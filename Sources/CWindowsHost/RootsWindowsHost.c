#ifndef _WIN32
#error CWindowsHost requires Windows and the Windows SDK.
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif

#include <windows.h>
#include <windowsx.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "RootsWindowsHost.h"

#ifndef WM_DPICHANGED
#define WM_DPICHANGED 0x02E0
#endif

#define ROOTS_MAX_DIMENSION 8192
#define ROOTS_MAX_TEXT_BYTES ((size_t)16 * 1024 * 1024)
#define ROOTS_MAX_TITLE_BYTES ((size_t)65536)
#define ROOTS_EVENT_CAPACITY 512
#define ROOTS_MESSAGE_WAKE (WM_APP + 1)
#define ROOTS_WINDOW_CLASS L"Roots.NativeWindowHost.1"

struct RootsWindowsHost {
  SRWLOCK lock;
  HANDLE ready;
  HANDLE wake;
  HANDLE thread;
  HWND window;
  int close_requested;
  int present_requested;
  struct RootsClipboardRequest *clipboard_request;
  volatile LONG closed;
  volatile LONG error;
  wchar_t *title;
  int32_t initial_width;
  int32_t initial_height;
  int32_t client_width;
  int32_t client_height;
  RootsWindowsEvent events[ROOTS_EVENT_CAPACITY];
  size_t event_head;
  size_t event_count;
  uint8_t *frame;
  int32_t frame_width;
  int32_t frame_height;
  /* The remaining input state is only accessed by the UI thread. */
  int tracking_pointer;
  int pointer_pressed;
  uint16_t pending_high_surrogate;
  RootsWindowsEvent pending_text_event;
  uint32_t pending_text_repeat;
};

typedef struct RootsClipboardRequest {
  const char *input;
  size_t input_count;
  char *output;
  size_t output_count;
  uint32_t error;
  int write;
  HANDLE completed;
} RootsClipboardRequest;

static INIT_ONCE roots_class_once = INIT_ONCE_STATIC_INIT;
static DWORD roots_class_error;
static LRESULT CALLBACK roots_window_proc(HWND, UINT, WPARAM, LPARAM);

static DWORD roots_last_error_or(DWORD fallback) {
  DWORD error = GetLastError();
  return error ? error : fallback;
}

static void roots_record_error(RootsWindowsHost *host, DWORD error) {
  if (error) InterlockedCompareExchange(&host->error, (LONG)error, 0);
}

static RootsWindowsEvent roots_event(uint32_t type) {
  RootsWindowsEvent event;
  memset(&event, 0, sizeof(event));
  event.type = type;
  return event;
}

static void roots_append_event_locked(RootsWindowsHost *host,
                                       RootsWindowsEvent event) {
  size_t tail = (host->event_head + host->event_count) % ROOTS_EVENT_CAPACITY;
  host->events[tail] = event;
  host->event_count += 1;
}

static void roots_queue_event(RootsWindowsHost *host, RootsWindowsEvent event) {
  AcquireSRWLockExclusive(&host->lock);
  /* Coalesce only adjacent replaceable events, never across an input boundary. */
  if (host->event_count &&
      (event.type == ROOTS_WINDOWS_EVENT_POINTER_MOVE ||
       event.type == ROOTS_WINDOWS_EVENT_RESIZE ||
       event.type == ROOTS_WINDOWS_EVENT_REDRAW)) {
    size_t tail = (host->event_head + host->event_count - 1) % ROOTS_EVENT_CAPACITY;
    if (host->events[tail].type == event.type) {
      host->events[tail] = event;
      ReleaseSRWLockExclusive(&host->lock);
      return;
    }
  }
  if (host->event_count == ROOTS_EVENT_CAPACITY) {
    /* Bounded memory is essential while a client is busy rendering. Dropping
       isolated key-up/button-up events would leave input stuck. Reset the
       consumer's input state and restore the latest viewport before resuming. */
    RootsWindowsEvent reset = roots_event(ROOTS_WINDOWS_EVENT_FOCUS_LOST);
    RootsWindowsEvent resize = roots_event(ROOTS_WINDOWS_EVENT_RESIZE);
    resize.width = host->client_width;
    resize.height = host->client_height;
    host->event_head = 0;
    host->event_count = 0;
    roots_append_event_locked(host, reset);
    roots_append_event_locked(host, resize);
  }
  roots_append_event_locked(host, event);
  ReleaseSRWLockExclusive(&host->lock);
}

static DWORD roots_notify(RootsWindowsHost *host) {
  DWORD error = ERROR_SUCCESS;
  /* Pointer-free window messages are serviced by native move/resize/menu modal
     loops, unlike an event-only outer message loop. Holding this lock until
     PostMessage returns prevents WM_NCDESTROY from publishing/removing the
     HWND and allowing reuse midway through the post. The event also handles
     the initialization interval before there is a window. */
  AcquireSRWLockShared(&host->lock);
  if (host->window && !roots_windows_host_is_closed(host) &&
      !PostMessageW(host->window, ROOTS_MESSAGE_WAKE, 0, 0))
    error = roots_last_error_or(ERROR_GEN_FAILURE);
  ReleaseSRWLockShared(&host->lock);
  if (!SetEvent(host->wake)) error = roots_last_error_or(ERROR_INVALID_HANDLE);
  return error;
}

static uint32_t roots_modifiers(void) {
  uint32_t value = 0;
  if (GetKeyState(VK_SHIFT) & 0x8000) value |= ROOTS_WINDOWS_MODIFIER_SHIFT;
  if (GetKeyState(VK_CONTROL) & 0x8000) value |= ROOTS_WINDOWS_MODIFIER_CONTROL;
  if (GetKeyState(VK_MENU) & 0x8000) value |= ROOTS_WINDOWS_MODIFIER_ALT;
  if ((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & 0x8000)
    value |= ROOTS_WINDOWS_MODIFIER_SUPER;
  if (GetKeyState(VK_CAPITAL) & 1) value |= ROOTS_WINDOWS_MODIFIER_CAPS_LOCK;
  if (GetKeyState(VK_NUMLOCK) & 1) value |= ROOTS_WINDOWS_MODIFIER_NUM_LOCK;
  /* Windows layouts generally implement AltGr as right Alt plus synthetic
     Control. Do not turn committed AltGr text into a Ctrl+Alt shortcut. */
  if ((GetKeyState(VK_RMENU) & 0x8000) && (value & ROOTS_WINDOWS_MODIFIER_CONTROL)) {
    value &= ~(ROOTS_WINDOWS_MODIFIER_CONTROL | ROOTS_WINDOWS_MODIFIER_ALT);
    value |= ROOTS_WINDOWS_MODIFIER_ALT_GRAPH;
  }
  return value;
}

static uint32_t roots_scan_code(LPARAM lparam) {
  return (uint32_t)(((UINT_PTR)lparam >> 16) & 0x1ff);
}

static uint32_t roots_key_phase(LPARAM lparam) {
  return ((UINT_PTR)lparam & ((UINT_PTR)1 << 30))
    ? ROOTS_WINDOWS_KEY_REPEATED : ROOTS_WINDOWS_KEY_PRESSED;
}

static void roots_emit_scalar(RootsWindowsHost *host, RootsWindowsEvent event,
                               uint32_t scalar) {
  if (scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff)) scalar = 0xfffd;
  event.text = scalar;
  roots_queue_event(host, event);
}

static uint32_t roots_repeat_count(LPARAM lparam) {
  uint32_t count = (uint32_t)((UINT_PTR)lparam & 0xffffu);
  return count ? count : 1;
}

static void roots_emit_repeated_scalar(RootsWindowsHost *host,
                                        RootsWindowsEvent event,
                                        uint32_t scalar, uint32_t count) {
  uint32_t index;
  /* The Win32 repeat field is 16 bits; the event queue remains bounded even
     for injected/coalesced messages with a large repeat count. */
  for (index = 0; index < count; ++index) {
    roots_emit_scalar(host, event, scalar);
    event.phase = ROOTS_WINDOWS_KEY_REPEATED;
  }
}

static void roots_emit_utf16(RootsWindowsHost *host, uint16_t unit, LPARAM lparam) {
  RootsWindowsEvent event = roots_event(ROOTS_WINDOWS_EVENT_TEXT);
  uint32_t repeats = roots_repeat_count(lparam);
  event.scan_code = roots_scan_code(lparam);
  event.modifiers = roots_modifiers();
  event.phase = roots_key_phase(lparam);
  if (host->pending_high_surrogate) {
    uint16_t high = host->pending_high_surrogate;
    uint32_t pending_repeats = host->pending_text_repeat;
    RootsWindowsEvent pending = host->pending_text_event;
    host->pending_high_surrogate = 0;
    if (unit >= 0xdc00 && unit <= 0xdfff) {
      uint32_t paired = repeats < pending_repeats ? repeats : pending_repeats;
      roots_emit_repeated_scalar(host, pending,
        0x10000u + (((uint32_t)high - 0xd800u) << 10) + unit - 0xdc00u, paired);
      if (pending_repeats > paired)
        roots_emit_repeated_scalar(host, pending, 0xfffd, pending_repeats - paired);
      if (repeats > paired)
        roots_emit_repeated_scalar(host, event, 0xfffd, repeats - paired);
      return;
    }
    roots_emit_repeated_scalar(host, pending, 0xfffd, pending_repeats);
  }
  if (unit >= 0xd800 && unit <= 0xdbff) {
    host->pending_high_surrogate = unit;
    host->pending_text_event = event;
    host->pending_text_repeat = repeats;
  } else {
    roots_emit_repeated_scalar(host, event, unit, repeats);
  }
}

static DWORD roots_utf8_to_wide(const char *text, size_t count, wchar_t **output) {
  int length;
  wchar_t *wide;
  *output = NULL;
  if ((!text && count) || count > ROOTS_MAX_TEXT_BYTES || count > INT_MAX)
    return ERROR_INVALID_PARAMETER;
  if (count && memchr(text, '\0', count)) return ERROR_INVALID_DATA;
  if (!count) {
    wide = (wchar_t *)calloc(1, sizeof(wchar_t));
    if (!wide) return ERROR_NOT_ENOUGH_MEMORY;
    *output = wide;
    return ERROR_SUCCESS;
  }
  length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)count, NULL, 0);
  if (!length) return roots_last_error_or(ERROR_NO_UNICODE_TRANSLATION);
  /* UTF-16 clipboard storage, including its terminator, is also bounded. */
  if ((size_t)length + 1 > ROOTS_MAX_TEXT_BYTES / sizeof(wchar_t))
    return ERROR_FILE_TOO_LARGE;
  wide = (wchar_t *)malloc(((size_t)length + 1) * sizeof(wchar_t));
  if (!wide) return ERROR_NOT_ENOUGH_MEMORY;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)count, wide, length)) {
    DWORD error = roots_last_error_or(ERROR_NO_UNICODE_TRANSLATION);
    free(wide);
    return error;
  }
  wide[length] = L'\0';
  *output = wide;
  return ERROR_SUCCESS;
}

static DWORD roots_clipboard_read(HWND window, RootsClipboardRequest *request) {
  HANDLE data;
  const wchar_t *wide = NULL;
  SIZE_T bytes;
  size_t capacity, length;
  int utf8_length;
  DWORD error = ERROR_SUCCESS;
  char *utf8 = NULL;
  if (!OpenClipboard(window)) return roots_last_error_or(ERROR_ACCESS_DENIED);
  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    error = ERROR_NOT_FOUND;
    goto done;
  }
  data = GetClipboardData(CF_UNICODETEXT);
  if (!data) { error = roots_last_error_or(ERROR_INVALID_DATA); goto done; }
  bytes = GlobalSize(data);
  if (bytes < sizeof(wchar_t) || bytes > ROOTS_MAX_TEXT_BYTES) {
    error = ERROR_INVALID_DATA;
    goto done;
  }
  wide = (const wchar_t *)GlobalLock(data);
  if (!wide) { error = roots_last_error_or(ERROR_INVALID_DATA); goto done; }
  capacity = bytes / sizeof(wchar_t);
  for (length = 0; length < capacity && wide[length] != L'\0'; ++length) {}
  if (length == capacity || length > INT_MAX) { error = ERROR_INVALID_DATA; goto unlock; }
  utf8_length = length
    ? WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, (int)length, NULL, 0, NULL, NULL)
    : 0;
  if (length && !utf8_length) { error = roots_last_error_or(ERROR_NO_UNICODE_TRANSLATION); goto unlock; }
  if ((size_t)utf8_length >= ROOTS_MAX_TEXT_BYTES) { error = ERROR_FILE_TOO_LARGE; goto unlock; }
  utf8 = (char *)malloc((size_t)utf8_length + 1);
  if (!utf8) { error = ERROR_NOT_ENOUGH_MEMORY; goto unlock; }
  if (utf8_length && !WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide,
                                        (int)length, utf8, utf8_length, NULL, NULL)) {
    error = roots_last_error_or(ERROR_NO_UNICODE_TRANSLATION);
    free(utf8);
    goto unlock;
  }
  utf8[utf8_length] = '\0';
  request->output = utf8;
  request->output_count = (size_t)utf8_length;
unlock:
  GlobalUnlock(data);
done:
  CloseClipboard();
  return error;
}

static DWORD roots_clipboard_write(HWND window, RootsClipboardRequest *request) {
  wchar_t *wide;
  size_t length;
  DWORD error = roots_utf8_to_wide(request->input, request->input_count, &wide);
  HGLOBAL storage;
  void *destination;
  if (error) return error;
  length = wcslen(wide);
  storage = GlobalAlloc(GMEM_MOVEABLE, (length + 1) * sizeof(wchar_t));
  if (!storage) { free(wide); return ERROR_NOT_ENOUGH_MEMORY; }
  destination = GlobalLock(storage);
  if (!destination) { free(wide); GlobalFree(storage); return roots_last_error_or(ERROR_NOT_ENOUGH_MEMORY); }
  memcpy(destination, wide, (length + 1) * sizeof(wchar_t));
  GlobalUnlock(storage);
  free(wide);
  if (!OpenClipboard(window)) { error = roots_last_error_or(ERROR_ACCESS_DENIED); goto done; }
  if (!EmptyClipboard()) {
    error = roots_last_error_or(ERROR_ACCESS_DENIED);
  } else if (!SetClipboardData(CF_UNICODETEXT, storage)) {
    error = roots_last_error_or(ERROR_ACCESS_DENIED);
  } else {
    storage = NULL; /* The operating system now owns the HGLOBAL. */
  }
  CloseClipboard();
done:
  if (storage) GlobalFree(storage);
  return error;
}

static void roots_process_commands(RootsWindowsHost *host, HWND window) {
  RootsClipboardRequest *clipboard;
  int close_requested, present_requested;
  AcquireSRWLockExclusive(&host->lock);
  clipboard = host->clipboard_request;
  host->clipboard_request = NULL;
  close_requested = host->close_requested;
  present_requested = host->present_requested;
  host->present_requested = 0;
  ReleaseSRWLockExclusive(&host->lock);
  if (close_requested && !roots_windows_host_is_closed(host)) DestroyWindow(window);
  if (clipboard) {
    clipboard->error = roots_windows_host_is_closed(host)
      ? ERROR_INVALID_WINDOW_HANDLE
      : (clipboard->write ? roots_clipboard_write(window, clipboard)
                          : roots_clipboard_read(window, clipboard));
    SetEvent(clipboard->completed);
  }
  if (present_requested && !roots_windows_host_is_closed(host))
    InvalidateRect(window, NULL, FALSE);
}

static void roots_paint(RootsWindowsHost *host, HWND window) {
  PAINTSTRUCT paint;
  HDC dc = BeginPaint(window, &paint);
  RECT client = {0, 0, 0, 0};
  DWORD error = ERROR_SUCCESS;
  if (!dc) {
    roots_record_error(host, roots_last_error_or(ERROR_INVALID_HANDLE));
    roots_windows_host_request_close(host);
    return;
  }
  if (!GetClientRect(window, &client)) error = roots_last_error_or(ERROR_INVALID_HANDLE);
  FillRect(dc, &client, (HBRUSH)GetStockObject(BLACK_BRUSH));
  AcquireSRWLockShared(&host->lock);
  if (host->frame && client.right > 0 && client.bottom > 0) {
    BITMAPINFO info;
    int result;
    memset(&info, 0, sizeof(info));
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = host->frame_width;
    info.bmiHeader.biHeight = -host->frame_height; /* Top-down rows. */
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    result = StretchDIBits(dc, 0, 0, client.right, client.bottom,
                           0, 0, host->frame_width, host->frame_height,
                           host->frame, &info, DIB_RGB_COLORS, SRCCOPY);
    if (result == (int)GDI_ERROR) error = roots_last_error_or(ERROR_GEN_FAILURE);
  }
  ReleaseSRWLockShared(&host->lock);
  EndPaint(window, &paint);
  if (error) {
    roots_record_error(host, error);
    roots_windows_host_request_close(host);
  }
}

static LRESULT CALLBACK roots_window_proc(HWND window, UINT message,
                                          WPARAM wparam, LPARAM lparam) {
  RootsWindowsHost *host = (RootsWindowsHost *)GetWindowLongPtrW(window, GWLP_USERDATA);
  if (message == WM_NCCREATE) {
    const CREATESTRUCTW *creation = (const CREATESTRUCTW *)lparam;
    host = (RootsWindowsHost *)creation->lpCreateParams;
    SetLastError(ERROR_SUCCESS);
    if (!SetWindowLongPtrW(window, GWLP_USERDATA, (LONG_PTR)host) && GetLastError()) {
      roots_record_error(host, GetLastError());
      return FALSE;
    }
  }
  if (!host) return DefWindowProcW(window, message, wparam, lparam);
  switch (message) {
    case WM_SIZE: {
      RECT client;
      RootsWindowsEvent event = roots_event(ROOTS_WINDOWS_EVENT_RESIZE);
      if (wparam != SIZE_MINIMIZED && GetClientRect(window, &client)) {
        event.width = client.right;
        event.height = client.bottom;
      }
      if (event.width > ROOTS_MAX_DIMENSION || event.height > ROOTS_MAX_DIMENSION) {
        roots_record_error(host, ERROR_INVALID_PARAMETER);
        roots_windows_host_request_close(host);
        return 0;
      }
      AcquireSRWLockExclusive(&host->lock);
      host->client_width = event.width;
      host->client_height = event.height;
      ReleaseSRWLockExclusive(&host->lock);
      roots_queue_event(host, event);
      return 0;
    }
    case WM_GETMINMAXINFO: {
      MINMAXINFO *limits = (MINMAXINFO *)lparam;
      RECT border = {0, 0, ROOTS_MAX_DIMENSION, ROOTS_MAX_DIMENSION};
      AdjustWindowRectEx(&border, WS_OVERLAPPEDWINDOW, FALSE, 0);
      limits->ptMaxTrackSize.x = border.right - border.left;
      limits->ptMaxTrackSize.y = border.bottom - border.top;
      return 0;
    }
    case WM_DPICHANGED: {
      const RECT *suggested = (const RECT *)lparam;
      if (!SetWindowPos(window, NULL, suggested->left, suggested->top,
                        suggested->right - suggested->left, suggested->bottom - suggested->top,
                        SWP_NOACTIVATE | SWP_NOZORDER)) {
        roots_record_error(host, roots_last_error_or(ERROR_GEN_FAILURE));
        roots_windows_host_request_close(host);
      }
      roots_queue_event(host, roots_event(ROOTS_WINDOWS_EVENT_REDRAW));
      return 0;
    }
    case WM_PAINT:
      roots_paint(host, window);
      /* A present invalidates the window. Emitting REDRAW here would create
         a render/present/paint feedback loop. Exposes use the cached frame. */
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case ROOTS_MESSAGE_WAKE:
      roots_process_commands(host, window);
      return 0;
    case WM_MOUSEMOVE: {
      RootsWindowsEvent event = roots_event(ROOTS_WINDOWS_EVENT_POINTER_MOVE);
      if (!host->tracking_pointer) {
        TRACKMOUSEEVENT tracking;
        memset(&tracking, 0, sizeof(tracking));
        tracking.cbSize = sizeof(tracking);
        tracking.dwFlags = TME_LEAVE;
        tracking.hwndTrack = window;
        host->tracking_pointer = TrackMouseEvent(&tracking) ? 1 : 0;
      }
      event.x = GET_X_LPARAM(lparam);
      event.y = GET_Y_LPARAM(lparam);
      event.modifiers = roots_modifiers();
      roots_queue_event(host, event);
      return 0;
    }
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP: {
      RootsWindowsEvent event = roots_event(message == WM_LBUTTONDOWN
        ? ROOTS_WINDOWS_EVENT_POINTER_DOWN : ROOTS_WINDOWS_EVENT_POINTER_UP);
      event.x = GET_X_LPARAM(lparam);
      event.y = GET_Y_LPARAM(lparam);
      event.modifiers = roots_modifiers();
      if (message == WM_LBUTTONDOWN) {
        SetFocus(window);
        host->pointer_pressed = 1;
        SetCapture(window);
      } else {
        host->pointer_pressed = 0;
        if (GetCapture() == window) ReleaseCapture();
      }
      roots_queue_event(host, event);
      return 0;
    }
    case WM_MOUSELEAVE:
      host->tracking_pointer = 0;
      roots_queue_event(host, roots_event(ROOTS_WINDOWS_EVENT_POINTER_LEAVE));
      return 0;
    case WM_CAPTURECHANGED:
      if (host->pointer_pressed) {
        host->pointer_pressed = 0;
        roots_queue_event(host, roots_event(ROOTS_WINDOWS_EVENT_FOCUS_LOST));
      }
      return 0;
    case WM_CANCELMODE:
    case WM_KILLFOCUS:
      host->pointer_pressed = 0;
      host->pending_high_surrogate = 0;
      if (GetCapture() == window) ReleaseCapture();
      roots_queue_event(host, roots_event(ROOTS_WINDOWS_EVENT_FOCUS_LOST));
      return 0;
    case WM_MOUSEWHEEL:
    case WM_MOUSEHWHEEL: {
      RootsWindowsEvent event = roots_event(ROOTS_WINDOWS_EVENT_SCROLL);
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(window, &point);
      event.x = point.x;
      event.y = point.y;
      event.modifiers = roots_modifiers();
      if (message == WM_MOUSEWHEEL) event.delta_y = (double)GET_WHEEL_DELTA_WPARAM(wparam) / WHEEL_DELTA;
      else event.delta_x = (double)GET_WHEEL_DELTA_WPARAM(wparam) / WHEEL_DELTA;
      roots_queue_event(host, event);
      return 0;
    }
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP: {
      RootsWindowsEvent event = roots_event(ROOTS_WINDOWS_EVENT_KEY);
      UINT character = MapVirtualKeyExW((UINT)wparam, MAPVK_VK_TO_CHAR, GetKeyboardLayout(0));
      event.virtual_key = (uint32_t)wparam;
      event.scan_code = roots_scan_code(lparam);
      if (wparam == VK_SHIFT || wparam == VK_CONTROL || wparam == VK_MENU) {
        UINT scan = event.scan_code & 0xffu;
        UINT sided;
        if (event.scan_code & 0x100u) scan |= 0xe000u;
        sided = MapVirtualKeyExW(scan, MAPVK_VSC_TO_VK_EX, GetKeyboardLayout(0));
        if (sided) event.virtual_key = sided;
      }
      event.modifiers = roots_modifiers();
      event.phase = (message == WM_KEYUP || message == WM_SYSKEYUP)
        ? ROOTS_WINDOWS_KEY_RELEASED : roots_key_phase(lparam);
      event.text = character; /* Preserve bit 31 so consumers can reject dead-key shortcuts. */
      event.text_key = (character & 0x7fffffffu) >= 0x20 || wparam == VK_PACKET;
      {
        uint32_t count = event.phase == ROOTS_WINDOWS_KEY_RELEASED ? 1 : roots_repeat_count(lparam);
        uint32_t index;
        for (index = 0; index < count; ++index) {
          roots_queue_event(host, event);
          event.phase = ROOTS_WINDOWS_KEY_REPEATED;
        }
      }
      /* Preserve native system-key behavior, particularly Alt+F4. */
      if (message == WM_SYSKEYDOWN || message == WM_SYSKEYUP)
        return DefWindowProcW(window, message, wparam, lparam);
      return 0;
    }
    case WM_CHAR:
      roots_emit_utf16(host, (uint16_t)wparam, lparam);
      return 0;
    case WM_UNICHAR: {
      RootsWindowsEvent event;
      if (wparam == UNICODE_NOCHAR) return TRUE;
      event = roots_event(ROOTS_WINDOWS_EVENT_TEXT);
      event.scan_code = roots_scan_code(lparam);
      event.modifiers = roots_modifiers();
      event.phase = roots_key_phase(lparam);
      if (host->pending_high_surrogate) {
        roots_emit_repeated_scalar(host, host->pending_text_event, 0xfffd, host->pending_text_repeat);
        host->pending_high_surrogate = 0;
      }
      roots_emit_repeated_scalar(host, event, (uint32_t)wparam, roots_repeat_count(lparam));
      return 0;
    }
    case WM_CLOSE:
      DestroyWindow(window);
      return 0;
    case WM_DESTROY:
      InterlockedExchange(&host->closed, 1);
      roots_queue_event(host, roots_event(ROOTS_WINDOWS_EVENT_CLOSED));
      PostQuitMessage(0);
      return 0;
    case WM_NCDESTROY:
      AcquireSRWLockExclusive(&host->lock);
      host->window = NULL;
      ReleaseSRWLockExclusive(&host->lock);
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      return DefWindowProcW(window, message, wparam, lparam);
    default:
      return DefWindowProcW(window, message, wparam, lparam);
  }
}

static BOOL CALLBACK roots_register_class(PINIT_ONCE once, PVOID parameter,
                                          PVOID *context) {
  WNDCLASSEXW window_class;
  (void)once; (void)parameter; (void)context;
  memset(&window_class, 0, sizeof(window_class));
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = roots_window_proc;
  window_class.hInstance = GetModuleHandleW(NULL);
  window_class.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
  window_class.lpszClassName = ROOTS_WINDOW_CLASS;
  if (!RegisterClassExW(&window_class)) roots_class_error = roots_last_error_or(ERROR_GEN_FAILURE);
  return TRUE;
}

static void roots_set_thread_dpi_awareness(void) {
  /* Dynamic lookup avoids a hard Windows 10 loader dependency and never changes
     the embedding process's DPI policy. -4 is PER_MONITOR_AWARE_V2, -3 is
     PER_MONITOR_AWARE. Earlier Windows versions retain their inherited policy. */
  typedef HANDLE (WINAPI *SetThreadAwareness)(HANDLE);
  HMODULE user32 = GetModuleHandleW(L"user32.dll");
  SetThreadAwareness set_awareness = user32
    ? (SetThreadAwareness)GetProcAddress(user32, "SetThreadDpiAwarenessContext") : NULL;
  if (set_awareness && !set_awareness((HANDLE)(INT_PTR)-4))
    set_awareness((HANDLE)(INT_PTR)-3);
}

static DWORD WINAPI roots_ui_thread(void *parameter) {
  RootsWindowsHost *host = (RootsWindowsHost *)parameter;
  HWND window = NULL;
  RECT bounds = {0, 0, host->initial_width, host->initial_height};
  MSG message;
  int running = 1;
  roots_set_thread_dpi_awareness();
  InitOnceExecuteOnce(&roots_class_once, roots_register_class, NULL, NULL);
  if (roots_class_error) { roots_record_error(host, roots_class_error); goto finished; }
  if (!AdjustWindowRectEx(&bounds, WS_OVERLAPPEDWINDOW, FALSE, 0)) {
    roots_record_error(host, roots_last_error_or(ERROR_GEN_FAILURE));
    goto finished;
  }
  window = CreateWindowExW(0, ROOTS_WINDOW_CLASS, host->title, WS_OVERLAPPEDWINDOW,
                           CW_USEDEFAULT, CW_USEDEFAULT, bounds.right - bounds.left,
                           bounds.bottom - bounds.top, NULL, NULL, GetModuleHandleW(NULL), host);
  if (!window) { roots_record_error(host, roots_last_error_or(ERROR_GEN_FAILURE)); goto finished; }
  AcquireSRWLockExclusive(&host->lock);
  host->window = window;
  ReleaseSRWLockExclusive(&host->lock);
  ShowWindow(window, SW_SHOWNORMAL);
  SetEvent(host->ready);
  while (running) {
    DWORD result = MsgWaitForMultipleObjectsEx(1, &host->wake, INFINITE,
                                               QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    if (result == WAIT_FAILED) {
      roots_record_error(host, roots_last_error_or(ERROR_GEN_FAILURE));
      break;
    }
    if (result == WAIT_OBJECT_0) roots_process_commands(host, window);
    /* Bound each drain so continuous mouse input cannot starve commands. */
    {
      unsigned int count;
      for (count = 0; count < 256 && PeekMessageW(&message, NULL, 0, 0, PM_REMOVE); ++count) {
        if (message.message == WM_QUIT) { running = 0; break; }
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
  }
  if (!roots_windows_host_is_closed(host)) DestroyWindow(window);
finished:
  InterlockedExchange(&host->closed, 1);
  SetEvent(host->ready); /* Also releases create() on every initialization failure. */
  return 0;
}

RootsWindowsHost *roots_windows_host_create(const char *title_utf8,
                                            int32_t width, int32_t height,
                                            uint32_t *error_code) {
  RootsWindowsHost *host;
  size_t title_count;
  DWORD error;
  if (error_code) *error_code = ERROR_SUCCESS;
  if (!title_utf8 || width < 1 || width > ROOTS_MAX_DIMENSION ||
      height < 1 || height > ROOTS_MAX_DIMENSION) {
    if (error_code) *error_code = ERROR_INVALID_PARAMETER;
    return NULL;
  }
  for (title_count = 0; title_count <= ROOTS_MAX_TITLE_BYTES && title_utf8[title_count]; ++title_count) {}
  if (title_count > ROOTS_MAX_TITLE_BYTES) {
    if (error_code) *error_code = ERROR_FILE_TOO_LARGE;
    return NULL;
  }
  host = (RootsWindowsHost *)calloc(1, sizeof(RootsWindowsHost));
  if (!host) { if (error_code) *error_code = ERROR_NOT_ENOUGH_MEMORY; return NULL; }
  InitializeSRWLock(&host->lock);
  error = roots_utf8_to_wide(title_utf8, title_count, &host->title);
  if (error) goto failed;
  host->initial_width = width;
  host->initial_height = height;
  host->ready = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!host->ready) { error = roots_last_error_or(ERROR_NOT_ENOUGH_MEMORY); goto failed; }
  host->wake = CreateEventW(NULL, FALSE, FALSE, NULL);
  if (!host->wake) { error = roots_last_error_or(ERROR_NOT_ENOUGH_MEMORY); goto failed; }
  host->thread = CreateThread(NULL, 0, roots_ui_thread, host, 0, NULL);
  if (!host->thread) { error = roots_last_error_or(ERROR_NOT_ENOUGH_MEMORY); goto failed; }
  if (WaitForSingleObject(host->ready, INFINITE) != WAIT_OBJECT_0) {
    error = roots_last_error_or(ERROR_GEN_FAILURE);
    roots_windows_host_request_close(host);
    WaitForSingleObject(host->thread, INFINITE);
    goto failed;
  }
  error = roots_windows_host_error_code(host);
  if (error || roots_windows_host_is_closed(host)) {
    if (!error) error = ERROR_INVALID_WINDOW_HANDLE;
    roots_windows_host_request_close(host);
    WaitForSingleObject(host->thread, INFINITE);
    goto failed;
  }
  return host;
failed:
  if (error_code) *error_code = error;
  if (host->thread) CloseHandle(host->thread);
  if (host->ready) CloseHandle(host->ready);
  if (host->wake) CloseHandle(host->wake);
  free(host->frame);
  free(host->title);
  free(host);
  return NULL;
}

int32_t roots_windows_host_poll_event(RootsWindowsHost *host,
                                     RootsWindowsEvent *event) {
  int32_t available = 0;
  if (!host || !event) return 0;
  AcquireSRWLockExclusive(&host->lock);
  if (host->event_count) {
    *event = host->events[host->event_head];
    host->event_head = (host->event_head + 1) % ROOTS_EVENT_CAPACITY;
    host->event_count -= 1;
    available = 1;
  }
  ReleaseSRWLockExclusive(&host->lock);
  return available;
}

uint32_t roots_windows_host_present_rgb(RootsWindowsHost *host,
                                       const uint8_t *pixels, size_t count,
                                       int32_t width, int32_t height) {
  size_t pixel_count, index;
  uint8_t *frame, *previous;
  if (!host || !pixels || width < 1 || width > ROOTS_MAX_DIMENSION ||
      height < 1 || height > ROOTS_MAX_DIMENSION) return ERROR_INVALID_PARAMETER;
  if (roots_windows_host_is_closed(host)) return ERROR_INVALID_WINDOW_HANDLE;
  pixel_count = (size_t)width * (size_t)height;
  if (count != pixel_count * 3) return ERROR_INVALID_PARAMETER;
  frame = (uint8_t *)malloc(pixel_count * 4);
  if (!frame) return ERROR_NOT_ENOUGH_MEMORY;
  for (index = 0; index < pixel_count; ++index) {
    frame[index * 4] = pixels[index * 3 + 2];
    frame[index * 4 + 1] = pixels[index * 3 + 1];
    frame[index * 4 + 2] = pixels[index * 3];
    frame[index * 4 + 3] = 0;
  }
  AcquireSRWLockExclusive(&host->lock);
  previous = host->frame;
  host->frame = frame;
  host->frame_width = width;
  host->frame_height = height;
  host->present_requested = 1;
  ReleaseSRWLockExclusive(&host->lock);
  free(previous);
  return roots_notify(host);
}

void roots_windows_host_request_close(RootsWindowsHost *host) {
  if (!host || roots_windows_host_is_closed(host)) return;
  AcquireSRWLockExclusive(&host->lock);
  host->close_requested = 1;
  ReleaseSRWLockExclusive(&host->lock);
  roots_record_error(host, roots_notify(host));
}

void roots_windows_host_destroy(RootsWindowsHost *host) {
  if (!host) return;
  roots_windows_host_request_close(host);
  WaitForSingleObject(host->thread, INFINITE);
  CloseHandle(host->thread);
  CloseHandle(host->ready);
  CloseHandle(host->wake);
  free(host->frame);
  free(host->title);
  free(host);
}

int32_t roots_windows_host_is_closed(RootsWindowsHost *host) {
  return !host || InterlockedCompareExchange(&host->closed, 0, 0) != 0;
}

uint32_t roots_windows_host_error_code(RootsWindowsHost *host) {
  return host ? (uint32_t)InterlockedCompareExchange(&host->error, 0, 0) : ERROR_INVALID_PARAMETER;
}

static uint32_t roots_dispatch_clipboard(RootsWindowsHost *host,
                                          RootsClipboardRequest *request) {
  HANDLE waits[2];
  DWORD result;
  request->error = ERROR_INVALID_WINDOW_HANDLE;
  request->completed = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!request->completed) return roots_last_error_or(ERROR_NOT_ENOUGH_MEMORY);
  AcquireSRWLockExclusive(&host->lock);
  if (roots_windows_host_is_closed(host)) {
    ReleaseSRWLockExclusive(&host->lock);
    CloseHandle(request->completed);
    return ERROR_INVALID_WINDOW_HANDLE;
  }
  host->clipboard_request = request;
  ReleaseSRWLockExclusive(&host->lock);
  roots_record_error(host, roots_notify(host));
  waits[0] = request->completed;
  waits[1] = host->thread;
  /* The stack request remains live until the UI thread completes it or exits.
     Never send a pointer to an HWND that another thread may already destroy. */
  result = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
  if (result == WAIT_FAILED) {
    DWORD error = roots_last_error_or(ERROR_GEN_FAILURE);
    roots_windows_host_request_close(host);
    WaitForSingleObject(host->thread, INFINITE);
    request->error = error;
  }
  CloseHandle(request->completed);
  return request->error;
}

uint32_t roots_windows_host_clipboard_read_utf8(RootsWindowsHost *host,
                                               char **text, size_t *count) {
  RootsClipboardRequest request;
  uint32_t error;
  if (text) *text = NULL;
  if (count) *count = 0;
  if (!host || !text || !count) return ERROR_INVALID_PARAMETER;
  memset(&request, 0, sizeof(request));
  error = roots_dispatch_clipboard(host, &request);
  if (error) {
    free(request.output);
    return error;
  }
  *text = request.output;
  *count = request.output_count;
  return error;
}

uint32_t roots_windows_host_clipboard_write_utf8(RootsWindowsHost *host,
                                                const char *text, size_t count) {
  RootsClipboardRequest request;
  if (!host || (!text && count) || count > ROOTS_MAX_TEXT_BYTES) return ERROR_INVALID_PARAMETER;
  memset(&request, 0, sizeof(request));
  request.input = text;
  request.input_count = count;
  request.write = 1;
  return roots_dispatch_clipboard(host, &request);
}

void roots_windows_host_free(void *buffer) {
  free(buffer);
}
