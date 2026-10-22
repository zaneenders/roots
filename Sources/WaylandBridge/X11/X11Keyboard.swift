import CX11
import Glibc
import Roots

/// X11 supplies XKB keycodes directly; only the Wayland adapter adds the evdev offset.
@safe struct X11Keyboard: ~Copyable {
  private var context: OpaquePointer?
  private var keymap: OpaquePointer?
  private var state: OpaquePointer?
  private var device: Int32 = -1
  private(set) var eventBase: UInt8 = 0
  private(set) var detectableRepeat = false
  private var held = Set<UInt32>()
  private var pendingRelease: (key: UInt32, time: UInt32)?

  init(detectableRepeat: Bool = false) {
    self.detectableRepeat = detectableRepeat
    unsafe context = xkb_context_new(XKB_CONTEXT_NO_FLAGS)
    held.reserveCapacity(16)
  }

  deinit {
    if let state = unsafe state { unsafe xkb_state_unref(state) }
    if let keymap = unsafe keymap { unsafe xkb_keymap_unref(keymap) }
    if let context = unsafe context { unsafe xkb_context_unref(context) }
  }

  mutating func configure(connection: OpaquePointer) throws {
    guard
      unsafe xkb_x11_setup_xkb_extension(
        connection, UInt16(XKB_X11_MIN_MAJOR_XKB_VERSION), UInt16(XKB_X11_MIN_MINOR_XKB_VERSION),
        XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS, nil, nil, &eventBase, nil) != 0
    else { throw NativeWindowError.x11Connection }
    device = unsafe xkb_x11_get_core_keyboard_device_id(connection)
    guard device >= 0, device <= Int32(UInt16.max) else { throw NativeWindowError.x11Connection }
    let events = UInt16(
      XCB_XKB_EVENT_TYPE_NEW_KEYBOARD_NOTIFY.rawValue
        | XCB_XKB_EVENT_TYPE_MAP_NOTIFY.rawValue | XCB_XKB_EVENT_TYPE_STATE_NOTIFY.rawValue)
    let cookie = unsafe xcb_xkb_select_events_aux_checked(
      connection, UInt16(device), events, 0, events, 0xff, 0xff, nil)
    if let error = unsafe xcb_request_check(connection, cookie) {
      let code = unsafe error.pointee.error_code
      unsafe free(error)
      throw NativeWindowError.x11Protocol(code)
    }
    let repeatFlag = UInt32(XCB_XKB_PER_CLIENT_FLAG_DETECTABLE_AUTO_REPEAT.rawValue)
    let repeatCookie = unsafe xcb_xkb_per_client_flags(
      connection, UInt16(device), repeatFlag, repeatFlag, 0, 0, 0)
    if let reply = unsafe xcb_xkb_per_client_flags_reply(connection, repeatCookie, nil) {
      detectableRepeat = unsafe reply.pointee.value & repeatFlag != 0
      unsafe free(reply)
    }
    try unsafe reload(connection: connection)
  }

  mutating func reload(connection: OpaquePointer) throws {
    guard let context = unsafe context,
      let keymap = unsafe xkb_x11_keymap_new_from_device(
        context, connection, device, XKB_KEYMAP_COMPILE_NO_FLAGS)
    else { throw NativeWindowError.x11Connection }
    guard let state = unsafe xkb_x11_state_new_from_device(keymap, connection, device) else {
      unsafe xkb_keymap_unref(keymap)
      throw NativeWindowError.x11Connection
    }
    if let old = unsafe self.state { unsafe xkb_state_unref(old) }
    if let old = unsafe self.keymap { unsafe xkb_keymap_unref(old) }
    unsafe self.keymap = keymap
    unsafe self.state = state
  }

  mutating func restoreHeldKeys(_ bytes: [UInt8]) {
    held.removeAll(keepingCapacity: true)
    pendingRelease = nil
    // XCB KeymapNotify omits the unused byte for keycodes 0...7.
    for (index, byte) in bytes.prefix(31).enumerated() {
      for bit in 0..<8 where byte & (1 << bit) != 0 { held.insert(UInt32((index + 1) * 8 + bit)) }
    }
  }

  mutating func update(_ event: xcb_xkb_state_notify_event_t) {
    guard let state = unsafe state else { return }
    _ = unsafe xkb_state_update_mask(
      state, UInt32(event.baseMods), UInt32(event.latchedMods), UInt32(event.lockedMods),
      UInt32(bitPattern: Int32(event.baseGroup)), UInt32(bitPattern: Int32(event.latchedGroup)),
      UInt32(event.lockedGroup))
  }

  mutating func key(_ code: UInt32, pressed: Bool, time: UInt32, input: inout NativeWindowInput) {
    if !detectableRepeat, !pressed {
      flushRelease(input: &input)
      pendingRelease = (code, time)
      return
    }
    if let pending = pendingRelease, pressed, pending.key == code, pending.time == time {
      // Traditional X11 repeat is a release/press pair with the same timestamp.
      pendingRelease = nil
    } else {
      flushRelease(input: &input)
    }
    emit(code, pressed: pressed, input: &input)
  }

  mutating func flushRelease(input: inout NativeWindowInput) {
    guard let pending = pendingRelease else { return }
    pendingRelease = nil
    emit(pending.key, pressed: false, input: &input)
  }

  mutating func finishEventBatch(queueDrained: Bool, input: inout NativeWindowInput) {
    // A legacy repeat pair can straddle a bounded dispatch batch. Do not turn its
    // second half into a fresh press simply because rendering runs between batches.
    if queueDrained { flushRelease(input: &input) }
  }

  private mutating func emit(_ code: UInt32, pressed: Bool, input: inout NativeWindowInput) {
    let phase: KeyPhase = pressed ? (held.contains(code) ? .repeated : .pressed) : .released
    if pressed { held.insert(code) } else { held.remove(code) }
    input.appendKeyEvent(
      unsafe X11KeyResolver.event(state: state, keycode: code, physicalCode: code, phase: phase))
  }

  mutating func leave(input: inout NativeWindowInput) {
    held.removeAll(keepingCapacity: true)
    pendingRelease = nil
    input.leaveKeyboard()
  }
}
