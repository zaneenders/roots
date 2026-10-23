#ifndef ROOTS_WINDOWS_HOST_H
#define ROOTS_WINDOWS_HOST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* This header intentionally exposes no Windows SDK types. */
typedef struct RootsWindowsHost RootsWindowsHost;

enum RootsWindowsEventType {
  ROOTS_WINDOWS_EVENT_NONE = 0,
  ROOTS_WINDOWS_EVENT_RESIZE = 1,
  ROOTS_WINDOWS_EVENT_POINTER_MOVE = 2,
  ROOTS_WINDOWS_EVENT_POINTER_DOWN = 3,
  ROOTS_WINDOWS_EVENT_POINTER_UP = 4,
  ROOTS_WINDOWS_EVENT_POINTER_LEAVE = 5,
  ROOTS_WINDOWS_EVENT_SCROLL = 6,
  ROOTS_WINDOWS_EVENT_KEY = 7,
  ROOTS_WINDOWS_EVENT_TEXT = 8,
  ROOTS_WINDOWS_EVENT_FOCUS_LOST = 9,
  ROOTS_WINDOWS_EVENT_REDRAW = 10,
  ROOTS_WINDOWS_EVENT_CLOSED = 11
};

enum RootsWindowsKeyPhase {
  ROOTS_WINDOWS_KEY_PRESSED = 0,
  ROOTS_WINDOWS_KEY_REPEATED = 1,
  ROOTS_WINDOWS_KEY_RELEASED = 2
};

enum RootsWindowsModifiers {
  ROOTS_WINDOWS_MODIFIER_SHIFT = 1 << 0,
  ROOTS_WINDOWS_MODIFIER_CONTROL = 1 << 1,
  ROOTS_WINDOWS_MODIFIER_ALT = 1 << 2,
  ROOTS_WINDOWS_MODIFIER_SUPER = 1 << 3,
  ROOTS_WINDOWS_MODIFIER_ALT_GRAPH = 1 << 4,
  ROOTS_WINDOWS_MODIFIER_CAPS_LOCK = 1 << 5,
  ROOTS_WINDOWS_MODIFIER_NUM_LOCK = 1 << 6
};

typedef struct RootsWindowsEvent {
  uint32_t type;
  int32_t width;
  int32_t height;
  double x;
  double y;
  /* Scroll deltas are wheel detents, not pixels. Positive y scrolls up;
     positive x scrolls right. Fractional/high-resolution detents are preserved. */
  double delta_x;
  double delta_y;
  uint32_t virtual_key;
  /* Physical Set-1 scan code; bit 8 is the extended-key flag. */
  uint32_t scan_code;
  uint32_t modifiers;
  uint32_t phase;
  /* TEXT events contain one committed Unicode scalar, never a UTF-16 surrogate.
     KEY events contain the current-layout MapVirtualKey value (bit 31 marks
     a dead key), useful for shortcut mapping. Basic IME commits use WM_CHAR;
     composition/preedit is not exposed. TEXT phases report repeat state. */
  uint32_t text;
  /* KEY hint: this key normally produces text. Committed text is separate;
     consumers should not synthesize duplicate text from ordinary key-downs. */
  uint32_t text_key;
} RootsWindowsEvent;

/* Public calls must be serialized by the owner (for example, Swift MainActor).
   The host owns a separate Win32 UI thread. destroy() joins it and invalidates
   the pointer; do not call destroy() concurrently with any other API call.
   Dimensions are physical client pixels, 1...8192. No process-wide DPI setting
   is changed. A supported OS uses per-monitor thread DPI awareness; clients
   currently treat those pixels as logical units (viewport scale 1).
   Nonzero errors are Win32 error codes. */
RootsWindowsHost *roots_windows_host_create(const char *title_utf8,
                                            int32_t width, int32_t height,
                                            uint32_t *error_code);
int32_t roots_windows_host_poll_event(RootsWindowsHost *host,
                                     RootsWindowsEvent *event);
/* Input must contain exactly width * height * 3 bytes in RGB row-major order.
   The data is copied synchronously and can be released immediately on return. */
uint32_t roots_windows_host_present_rgb(RootsWindowsHost *host,
                                       const uint8_t *pixels, size_t count,
                                       int32_t width, int32_t height);
void roots_windows_host_request_close(RootsWindowsHost *host);
void roots_windows_host_destroy(RootsWindowsHost *host);
int32_t roots_windows_host_is_closed(RootsWindowsHost *host);
uint32_t roots_windows_host_error_code(RootsWindowsHost *host);
/* Clipboard calls execute on the window thread. UTF-8 is validated; read output
   is NUL terminated with count excluding the terminator. Data is bounded to
   16 MiB and ownership of read output passes to the caller. Embedded NULs in
   write input are rejected. No clipboard format is treated as executable. */
uint32_t roots_windows_host_clipboard_read_utf8(RootsWindowsHost *host,
                                               char **text, size_t *count);
uint32_t roots_windows_host_clipboard_write_utf8(RootsWindowsHost *host,
                                                const char *text, size_t count);
void roots_windows_host_free(void *buffer);

#ifdef __cplusplus
}
#endif
#endif
