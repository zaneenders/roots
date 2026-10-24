import CXKBCommon
import Glibc

@safe struct Keyboard: ~Copyable {
  static let maximumKeymapSize: UInt32 = 16 * 1024 * 1024

  private var context: OpaquePointer?
  private var keymap: OpaquePointer?
  private var state: OpaquePointer?
  private var rate: Int32 = 0
  private var delay: Int32 = 0
  private var held: Repeat?

  var isRepeating: Bool { held != nil }
  var repeatDeadline: ContinuousClock.Instant? { held?.next }

  init() { unsafe context = xkb_context_new(XKB_CONTEXT_NO_FLAGS) }

  deinit {
    if let state = unsafe state { unsafe xkb_state_unref(state) }
    if let keymap = unsafe keymap { unsafe xkb_keymap_unref(keymap) }
    if let context = unsafe context { unsafe xkb_context_unref(context) }
  }

  mutating func load(format: UInt32, fd: Int32, size: UInt32) {
    clear()
    guard format == WaylandKeyboardKeymapFormat.xkbV1.rawValue,
      fd >= 0, size > 0, size <= Self.maximumKeymapSize
    else { return }
    var bytes = [UInt8](repeating: 0, count: Int(size))
    let complete = bytes.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return false }
      var offset = 0
      while offset < buffer.count {
        let count = unsafe pread(
          fd, address.advanced(by: offset), buffer.count - offset, off_t(offset))
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { return false }
        offset += count
      }
      return true
    }
    guard complete else { return }
    compile(bytes.span)
  }

  mutating func load(keymap source: String) {
    clear()
    compile(source.utf8Span.span)
  }

  private mutating func compile(_ bytes: borrowing Span<UInt8>) {
    guard let context = unsafe context else { return }
    unsafe keymap = bytes.withUnsafeBufferPointer { buffer in
      unsafe buffer.withMemoryRebound(to: CChar.self) {
        unsafe xkb_keymap_new_from_buffer(
          context, $0.baseAddress, $0.count, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS)
      }
    }
    if let keymap = unsafe keymap { unsafe state = xkb_state_new(keymap) }
  }

  private mutating func clear() {
    cancelRepeat()
    if let state = unsafe state { unsafe xkb_state_unref(state) }
    if let keymap = unsafe keymap { unsafe xkb_keymap_unref(keymap) }
    unsafe state = nil
    unsafe keymap = nil
  }

  mutating func modifiers(depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) {
    if let state = unsafe state {
      _ = unsafe xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group)
    }
  }

  mutating func repeatInfo(rate: Int32, delay: Int32) {
    self.rate = min(100, max(0, rate))
    self.delay = max(0, delay)
    if rate <= 0 { cancelRepeat() }
  }

  private mutating func cancelRepeat() {
    held = nil
  }

  mutating func leave(input: inout WaylandInput) {
    cancelRepeat()
    input.leaveKeyboard()
  }

  mutating func key(
    _ key: UInt32, pressed: Bool, input: inout WaylandInput, now: ContinuousClock.Instant = .now
  ) {
    let event = event(for: key, phase: pressed ? .pressed : .released)
    input.keyEvents.append(event)
    guard pressed else {
      if held?.key == key { cancelRepeat() }
      return
    }
    guard !event.key.isModifier else { return }
    cancelRepeat()
    if rate > 0, key <= UInt32.max - 8, let keymap = unsafe keymap,
      unsafe xkb_keymap_key_repeats(keymap, key + 8) != 0
    {
      held = Repeat(key: key, next: now.advanced(by: .milliseconds(delay)))
    }
  }

  mutating func repeatKeys(input: inout WaylandInput, now: ContinuousClock.Instant = .now) {
    guard var held, rate > 0 else { return }
    let interval = Duration.nanoseconds(1_000_000_000 / Int64(rate))
    var count = 0
    while now >= held.next && count < 32 {
      input.keyEvents.append(event(for: held.key, phase: .repeated))
      held.next = held.next.advanced(by: interval)
      count += 1
    }
    if now >= held.next { held.next = now.advanced(by: interval) }
    self.held = held
  }

  private func event(for key: UInt32, phase: WaylandKeyPhase) -> WaylandKeyEvent {
    guard key <= UInt32.max - 8, let state = unsafe state else {
      return WaylandKeyEvent(.symbol(0), phase: phase, physicalCode: key)
    }
    var modifiers: WaylandKeyModifiers = []
    for (name, flag): (String, WaylandKeyModifiers) in [
      ("Shift", .shift), ("Control", .control), ("Mod1", .alt), ("Mod4", .super),
      ("Mod5", .altGraph), ("Lock", .capsLock), ("Mod2", .numLock)
    ] {
      if unsafe xkb_state_mod_name_is_active(state, name, XKB_STATE_MODS_EFFECTIVE) > 0 {
        modifiers.insert(flag)
      }
    }
    let symbol = unsafe xkb_state_key_get_one_sym(state, key + 8)
    return WaylandKeyEvent(
      Self.logicalKey(symbol), phase: phase, modifiers: modifiers, physicalCode: key)
  }

  private static func logicalKey(_ symbol: UInt32) -> WaylandKey {
    switch symbol {
    case UInt32(XKB_KEY_Escape): return .escape
    case UInt32(XKB_KEY_Tab), UInt32(XKB_KEY_ISO_Left_Tab): return .tab
    case UInt32(XKB_KEY_Return), UInt32(XKB_KEY_KP_Enter): return .enter
    case UInt32(XKB_KEY_BackSpace): return .backspace
    case UInt32(XKB_KEY_Delete), UInt32(XKB_KEY_KP_Delete): return .delete
    case UInt32(XKB_KEY_Left), UInt32(XKB_KEY_KP_Left): return .left
    case UInt32(XKB_KEY_Right), UInt32(XKB_KEY_KP_Right): return .right
    case UInt32(XKB_KEY_Up), UInt32(XKB_KEY_KP_Up): return .up
    case UInt32(XKB_KEY_Down), UInt32(XKB_KEY_KP_Down): return .down
    case UInt32(XKB_KEY_Home), UInt32(XKB_KEY_KP_Home): return .home
    case UInt32(XKB_KEY_End), UInt32(XKB_KEY_KP_End): return .end
    case UInt32(XKB_KEY_Page_Up), UInt32(XKB_KEY_KP_Page_Up): return .pageUp
    case UInt32(XKB_KEY_Page_Down), UInt32(XKB_KEY_KP_Page_Down): return .pageDown
    case UInt32(XKB_KEY_Shift_L), UInt32(XKB_KEY_Shift_R): return .shift
    case UInt32(XKB_KEY_Control_L), UInt32(XKB_KEY_Control_R): return .control
    case UInt32(XKB_KEY_Alt_L), UInt32(XKB_KEY_Alt_R): return .alt
    case UInt32(XKB_KEY_ISO_Level3_Shift), UInt32(XKB_KEY_Mode_switch): return .altGraph
    case UInt32(XKB_KEY_Super_L), UInt32(XKB_KEY_Super_R): return .super
    case UInt32(XKB_KEY_Caps_Lock): return .capsLock
    case UInt32(XKB_KEY_Num_Lock): return .numLock
    case UInt32(XKB_KEY_F1)...UInt32(XKB_KEY_F35):
      return .function(Int(symbol - UInt32(XKB_KEY_F1)) + 1)
    default:
      let value = xkb_keysym_to_utf32(symbol)
      if value >= 32, value != 127, let scalar = UnicodeScalar(value) { return .character(scalar) }
      return .symbol(symbol)
    }
  }
}
