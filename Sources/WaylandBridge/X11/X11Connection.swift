import CEGLGLES
import CX11
import Foundation
import Glibc

/// Owns the X connection and window; NativeRenderer owns their EGL surface/context.
@safe @MainActor final class X11Connection {
  let configuration: NativeWindowConfiguration
  private var connection: OpaquePointer?
  private var screen: xcb_screen_t?
  private var screenIndex: Int32 = 0
  private var window: UInt32 = 0
  private var colormap: UInt32 = 0
  private var protocols: UInt32 = 0
  private var deleteWindow: UInt32 = 0
  private var typing = X11Keyboard()
  private var clipboard: X11Clipboard?
  private(set) var input: NativeWindowInput
  private var readiness: DescriptorReadiness?
  private var frames = X11FrameSchedule()
  private var mapped = false
  private var focused = false
  private var closed = false
  private var dispatching = false
  private var eventsPending = false
  private var lastTimestamp: UInt32 = 0
  private(set) var running = true

  private var drawable: Bool { mapped && input.width > 0 && input.height > 0 }
  var configured: Bool { mapped }
  var canRender: Bool { running && drawable && frames.isReady() }

  init(configuration: NativeWindowConfiguration) {
    self.configuration = configuration
    input = NativeWindowInput(width: configuration.width, height: configuration.height)
  }

  isolated deinit { cleanup() }

  func connect() throws {
    guard !closed, unsafe connection == nil else { throw NativeWindowError.x11Connection }
    unsafe connection = xcb_connect(nil, &screenIndex)
    guard let connection = unsafe connection, unsafe xcb_connection_has_error(connection) == 0,
      let setup = unsafe xcb_get_setup(connection)
    else { throw NativeWindowError.x11Connection }
    var screens = unsafe xcb_setup_roots_iterator(setup)
    for _ in 0..<screenIndex { unsafe xcb_screen_next(&screens) }
    guard unsafe screens.rem > 0, let screen = unsafe screens.data else {
      throw NativeWindowError.x11Connection
    }
    self.screen = unsafe screen.pointee
    try unsafe typing.configure(connection: connection)
  }

  func makeEGLDisplay() throws -> EGLDisplay {
    guard let connection = unsafe connection,
      let extensionBytes = unsafe eglQueryString(nil, EGLint(EGL_EXTENSIONS))
    else { throw NativeWindowError.unsupportedEGLPlatform("XCB") }
    let extensions = unsafe String(cString: extensionBytes).split(separator: " ")
    guard extensions.contains("EGL_EXT_platform_xcb"), extensions.contains("EGL_EXT_platform_base"),
      let entry = unsafe eglGetProcAddress("eglGetPlatformDisplayEXT")
    else { throw NativeWindowError.unsupportedEGLPlatform("XCB") }
    let getPlatform = unsafe unsafeBitCast(entry, to: PFNEGLGETPLATFORMDISPLAYEXTPROC.self)
    let attributes: [EGLint] = [EGL_PLATFORM_XCB_SCREEN_EXT, screenIndex, EGL_NONE]
    guard
      let display = unsafe getPlatform(
        UInt32(EGL_PLATFORM_XCB_EXT), UnsafeMutableRawPointer(connection), attributes)
    else { throw NativeWindowError.egl(eglGetError()) }
    return unsafe display
  }

  func createWindow(display: EGLDisplay, config: EGLConfig) throws -> EGLSurface {
    guard let connection = unsafe connection, let screen, window == 0,
      input.width > 0, input.height > 0, input.width <= Int32(UInt16.max),
      input.height <= Int32(UInt16.max)
    else { throw NativeWindowError.invalidConfiguration }
    var visual: EGLint = 0
    guard unsafe eglGetConfigAttrib(display, config, EGL_NATIVE_VISUAL_ID, &visual) != 0, visual > 0
    else {
      throw NativeWindowError.x11Visual
    }
    let visualID = UInt32(visual)
    guard let depth = depth(for: visualID) else { throw NativeWindowError.x11Visual }
    colormap = unsafe xcb_generate_id(connection)
    try check(
      unsafe xcb_create_colormap_checked(
        connection, UInt8(XCB_COLORMAP_ALLOC_NONE.rawValue), colormap, screen.root, visualID))
    window = unsafe xcb_generate_id(connection)
    let mask = UInt32(
      XCB_CW_BACK_PIXEL.rawValue | XCB_CW_BORDER_PIXEL.rawValue
        | XCB_CW_EVENT_MASK.rawValue | XCB_CW_COLORMAP.rawValue)
    let events = UInt32(
      XCB_EVENT_MASK_EXPOSURE.rawValue | XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue
        | XCB_EVENT_MASK_FOCUS_CHANGE.rawValue | XCB_EVENT_MASK_POINTER_MOTION.rawValue
        | XCB_EVENT_MASK_ENTER_WINDOW.rawValue | XCB_EVENT_MASK_LEAVE_WINDOW.rawValue
        | XCB_EVENT_MASK_BUTTON_PRESS.rawValue | XCB_EVENT_MASK_BUTTON_RELEASE.rawValue
        | XCB_EVENT_MASK_KEY_PRESS.rawValue | XCB_EVENT_MASK_KEY_RELEASE.rawValue
        | XCB_EVENT_MASK_KEYMAP_STATE.rawValue
        | XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue)
    let values: [UInt32] = [0, 0, events, colormap]
    try check(
      unsafe xcb_create_window_checked(
        connection, depth, window, screen.root, 0, 0, UInt16(input.width), UInt16(input.height), 0,
        UInt16(XCB_WINDOW_CLASS_INPUT_OUTPUT.rawValue), visualID, mask, values))
    protocols = try atom("WM_PROTOCOLS")
    deleteWindow = try atom("WM_DELETE_WINDOW")
    let utf8 = try atom("UTF8_STRING")
    try property(atom: protocols, type: UInt32(XCB_ATOM_ATOM.rawValue), words: [deleteWindow])
    try textProperty(atom: try atom("_NET_WM_NAME"), type: utf8, text: configuration.title)
    try textProperty(atom: UInt32(XCB_ATOM_WM_NAME.rawValue), type: utf8, text: configuration.title)
    try textProperty(
      atom: UInt32(XCB_ATOM_WM_CLASS.rawValue), type: UInt32(XCB_ATOM_STRING.rawValue),
      text: configuration.appID.replacingOccurrences(of: "\0", with: "") + "\0"
        + configuration.appID.replacingOccurrences(of: "\0", with: "") + "\0")
    try property(
      atom: try atom("_NET_WM_PID"), type: UInt32(XCB_ATOM_CARDINAL.rawValue),
      words: [UInt32(getpid())])
    // InputHint: normal focusable client. Size hints are a minimum, not a forced geometry.
    try property(
      atom: UInt32(XCB_ATOM_WM_HINTS.rawValue), type: UInt32(XCB_ATOM_WM_HINTS.rawValue),
      words: [1, 1, 0, 0, 0, 0, 0, 0, 0])
    var hints = [UInt32](repeating: 0, count: 18)
    hints[0] = 1 << 4
    hints[5] = UInt32(max(0, configuration.minimumWidth))
    hints[6] = UInt32(max(0, configuration.minimumHeight))
    try property(
      atom: UInt32(XCB_ATOM_WM_NORMAL_HINTS.rawValue),
      type: UInt32(XCB_ATOM_WM_SIZE_HINTS.rawValue),
      words: hints)
    clipboard = try unsafe X11Clipboard(connection: connection, window: window)
    guard let entry = unsafe eglGetProcAddress("eglCreatePlatformWindowSurfaceEXT") else {
      throw NativeWindowError.unsupportedEGLPlatform("XCB window surface")
    }
    let createSurface = unsafe unsafeBitCast(
      entry, to: PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC.self)
    guard let surface = unsafe createSurface(display, config, &window, nil) else {
      throw NativeWindowError.egl(eglGetError())
    }
    // Surface is adopted immediately by the caller. Mapping failure is reported from event dispatch.
    _ = unsafe xcb_map_window(connection, window)
    _ = unsafe xcb_flush(connection)
    return unsafe surface
  }

  private func depth(for visual: UInt32) -> UInt8? {
    // Walk the original setup: a copied fixed header has no variable-length depth list.
    guard let connection = unsafe connection, let setup = unsafe xcb_get_setup(connection) else {
      return nil
    }
    var screens = unsafe xcb_setup_roots_iterator(setup)
    for _ in 0..<screenIndex { unsafe xcb_screen_next(&screens) }
    guard let original = unsafe screens.data else { return nil }
    var depths = unsafe xcb_screen_allowed_depths_iterator(original)
    while unsafe depths.rem > 0 {
      guard let depth = unsafe depths.data else { break }
      var visuals = unsafe xcb_depth_visuals_iterator(depth)
      while unsafe visuals.rem > 0 {
        if let value = unsafe visuals.data, unsafe value.pointee.visual_id == visual {
          return unsafe depth.pointee.depth
        }
        unsafe xcb_visualtype_next(&visuals)
      }
      unsafe xcb_depth_next(&depths)
    }
    return nil
  }

  private func atom(_ name: String) throws -> UInt32 {
    guard let connection = unsafe connection else { throw NativeWindowError.x11Connection }
    let cookie = name.withCString { bytes in
      unsafe xcb_intern_atom(connection, 0, UInt16(name.utf8.count), bytes)
    }
    guard let reply = unsafe xcb_intern_atom_reply(connection, cookie, nil) else {
      throw NativeWindowError.x11Connection
    }
    defer { unsafe free(reply) }
    return unsafe reply.pointee.atom
  }

  private func property(atom: UInt32, type: UInt32, words: [UInt32]) throws {
    guard let connection = unsafe connection else { throw NativeWindowError.x11Connection }
    try check(
      unsafe xcb_change_property_checked(
        connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), window, atom, type, 32,
        UInt32(words.count), words))
  }

  private func textProperty(atom: UInt32, type: UInt32, text: String) throws {
    guard let connection = unsafe connection else { throw NativeWindowError.x11Connection }
    let bytes = Array(text.utf8)
    try check(
      unsafe xcb_change_property_checked(
        connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), window, atom, type, 8,
        UInt32(bytes.count), bytes))
  }

  private func check(_ cookie: xcb_void_cookie_t) throws {
    guard let connection = unsafe connection else { throw NativeWindowError.x11Connection }
    if let error = unsafe xcb_request_check(connection, cookie) {
      let code = unsafe error.pointee.error_code
      unsafe free(error)
      throw NativeWindowError.x11Protocol(code)
    }
  }

  func beginFrame() -> NativeWindowInput {
    typing.finishEventBatch(queueDrained: !eventsPending, input: &input)
    // Consume before calling application code: a redraw requested by that code
    // belongs to the next frame, and focus loss survives until this delivery.
    frames.beginFrame()
    let snapshot = input
    input.resetEdges()
    return snapshot
  }

  func endFrame(continuously: Bool = false) throws {
    guard !closed else { throw NativeWindowError.x11Connection }
    frames.endFrame(continuously: continuously)
  }

  func requestRedraw() {
    guard !closed, running else { return }
    frames.requestRedraw()
    readiness?.wake()
  }

  func dispatchAsync() async throws {
    try Task.checkCancellation()
    guard !dispatching, let connection = unsafe connection, !closed else {
      throw NativeWindowError.x11Connection
    }
    dispatching = true
    defer { dispatching = false }
    try drainEvents()
    if eventsPending {
      await Task.yield()
      return
    }
    if canRender || !running { return }
    guard unsafe xcb_flush(connection) > 0, unsafe xcb_connection_has_error(connection) == 0 else {
      throw NativeWindowError.x11Dispatch
    }
    let wait = DescriptorReadiness(unsafe xcb_get_file_descriptor(connection))
    readiness = wait
    defer { readiness = nil }
    let deadline = frames.waitDeadline(
      drawable: drawable, clipboardDeadline: clipboard?.nextDeadline)
    try await wait.wait(until: deadline)
    try Task.checkCancellation()
    if running { try drainEvents() }
  }

  private func drainEvents() throws {
    guard let connection = unsafe connection else { throw NativeWindowError.x11Connection }
    clipboard?.poll()
    // Bound an input flood so frame/close/application tasks cannot be starved.
    var count = 0
    while count < 4096, let event = unsafe xcb_poll_for_event(connection) {
      defer { unsafe free(event) }
      try unsafe handle(event)
      count += 1
      if !running { break }
    }
    eventsPending = count == 4096
    guard unsafe xcb_connection_has_error(connection) == 0 else {
      throw NativeWindowError.x11Dispatch
    }
  }

  private func handle(_ event: UnsafePointer<xcb_generic_event_t>) throws {
    if unsafe clipboard?.handle(event) == true { return }
    let type = unsafe event.pointee.response_type & 0x7f
    if type == typing.eventBase {
      let xkb: xcb_xkb_state_notify_event_t = unsafe eventValue(event)
      switch Int32(xkb.xkbType) {
      case XCB_XKB_NEW_KEYBOARD_NOTIFY, XCB_XKB_MAP_NOTIFY:
        if let connection = unsafe connection { try unsafe typing.reload(connection: connection) }
      case XCB_XKB_STATE_NOTIFY: typing.update(xkb)
      default: break
      }
      return
    }
    switch Int32(type) {
    case XCB_CONFIGURE_NOTIFY:
      let e: xcb_configure_notify_event_t = unsafe eventValue(event)
      guard e.window == window else { return }
      input.width = Int32(e.width)
      input.height = Int32(e.height)
      requestRedraw()
    case XCB_MAP_NOTIFY:
      let e: xcb_map_notify_event_t = unsafe eventValue(event)
      if e.window == window {
        mapped = true
        frames.mapped()
        requestRedraw()
      }
    case XCB_UNMAP_NOTIFY:
      let e: xcb_unmap_notify_event_t = unsafe eventValue(event)
      if e.window == window {
        mapped = false
        focused = false
        typing.leave(input: &input)
        input.leavePointer()
        requestRedraw()
      }
    case XCB_EXPOSE:
      let e: xcb_expose_event_t = unsafe eventValue(event)
      if e.window == window { requestRedraw() }
    case XCB_DESTROY_NOTIFY:
      let e: xcb_destroy_notify_event_t = unsafe eventValue(event)
      if e.window == window {
        window = 0
        requestClose()
      }
    case XCB_CLIENT_MESSAGE:
      let e = unsafe UnsafeRawPointer(event).assumingMemoryBound(
        to: xcb_client_message_event_t.self
      ).pointee
      if e.window == window, e.format == 32, e.type == protocols,
        unsafe e.data.data32.0 == deleteWindow
      {
        requestClose()
      }
    case XCB_FOCUS_IN:
      let e: xcb_focus_in_event_t = unsafe eventValue(event)
      if e.event == window {
        focused = true
        requestRedraw()
        // XKB state notifications remain selected while unfocused. Keep their
        // event ordering instead of querying a newer state ahead of queued keys.
      }
    case XCB_FOCUS_OUT:
      let e: xcb_focus_out_event_t = unsafe eventValue(event)
      if e.event == window {
        focused = false
        typing.leave(input: &input)
        requestRedraw()
      }
    case XCB_KEYMAP_NOTIFY:
      // The server sends this immediately after FocusIn/EnterNotify. It reflects
      // that event's keyboard state, unlike a later round trip that can overtake keys.
      guard focused else { return }
      let e: xcb_keymap_notify_event_t = unsafe eventValue(event)
      withUnsafeBytes(of: e.keys) { bytes in
        typing.restoreHeldKeys(unsafe Array(bytes))
      }
    case XCB_MOTION_NOTIFY:
      let e: xcb_motion_notify_event_t = unsafe eventValue(event)
      if e.event == window {
        input.pointerX = Float(e.event_x)
        input.pointerY = Float(e.event_y)
        lastTimestamp = e.time
        requestRedraw()
      }
    case XCB_ENTER_NOTIFY, XCB_LEAVE_NOTIFY:
      let e: xcb_enter_notify_event_t = unsafe eventValue(event)
      if e.event == window {
        if Int32(type) == XCB_ENTER_NOTIFY {
          input.pointerInside = true
        } else {
          input.leavePointer()
        }
        input.pointerX = Float(e.event_x)
        input.pointerY = Float(e.event_y)
        lastTimestamp = e.time
        requestRedraw()
      }
    case XCB_BUTTON_PRESS, XCB_BUTTON_RELEASE:
      let e: xcb_button_press_event_t = unsafe eventValue(event)
      guard e.event == window else { return }
      lastTimestamp = e.time
      input.pointerX = Float(e.event_x)
      input.pointerY = Float(e.event_y)
      requestRedraw()
      let pressed = Int32(type) == XCB_BUTTON_PRESS
      if e.detail == 1 {
        input.primaryPressed = input.primaryPressed || (pressed && !input.primaryDown)
        input.primaryReleased = input.primaryReleased || (!pressed && input.primaryDown)
        input.primaryDown = pressed
      } else if pressed {
        switch e.detail {
        case 4: input.scrollY -= 40
        case 5: input.scrollY += 40
        case 6: input.scrollX -= 40
        case 7: input.scrollX += 40
        default: break
        }
      }
    case XCB_KEY_PRESS, XCB_KEY_RELEASE:
      let e: xcb_key_press_event_t = unsafe eventValue(event)
      guard e.event == window, focused else { return }
      lastTimestamp = e.time
      typing.key(
        UInt32(e.detail), pressed: Int32(type) == XCB_KEY_PRESS, time: e.time, input: &input)
      requestRedraw()
    case 0:
      let e: xcb_generic_error_t = unsafe eventValue(event)
      throw NativeWindowError.x11Protocol(e.error_code)
    default: break
    }
  }

  func requestClose() {
    running = false
    readiness?.wake()
  }

  func readClipboard() async -> String? {
    // The transfer adds a deadline while dispatch may already be waiting without
    // one. Wake it so it can include the new deadline even when no X event arrives.
    readiness?.wake()
    return await clipboard?.read()
  }

  func writeClipboard(_ text: String) -> Bool {
    guard focused else { return false }
    let queued = clipboard?.write(text, timestamp: lastTimestamp) ?? false
    if queued { readiness?.wake() }
    return queued
  }

  func cleanup() {
    guard !closed else { return }
    closed = true
    requestClose()
    clipboard?.close()
    clipboard = nil
    typing.leave(input: &input)
    if let connection = unsafe connection {
      if window != 0 { _ = unsafe xcb_destroy_window(connection, window) }
      if colormap != 0 { _ = unsafe xcb_free_colormap(connection, colormap) }
      _ = unsafe xcb_flush(connection)
      unsafe xcb_disconnect(connection)
    }
    unsafe connection = nil
    window = 0
    colormap = 0
    screen = nil
  }
}

/// XCB owns an aligned event allocation until the dispatch callback returns.
@unsafe private func eventValue<Event: BitwiseCopyable>(_ event: UnsafePointer<xcb_generic_event_t>)
  -> Event
{
  precondition(MemoryLayout<Event>.size <= MemoryLayout<xcb_generic_event_t>.size)
  return unsafe UnsafeRawPointer(event).load(as: Event.self)
}
