import CX11
import Roots

/// Resolve XKB keycodes directly: X11 has already applied the evdev offset.
@safe enum X11KeyResolver {
  // Hosts normalize their physical codes before entering this shared XKB translation.
  static func event(state: OpaquePointer?, keycode: UInt32, physicalCode: UInt32, phase: KeyPhase)
    -> KeyEvent
  {
    guard let state = unsafe state else {
      return KeyEvent(.symbol(0), phase: phase, physicalCode: physicalCode)
    }
    var modifiers: KeyModifiers = []
    for (name, flag): (String, KeyModifiers) in [
      ("Shift", .shift), ("Control", .control), ("Mod1", .alt), ("Mod4", .super),
      ("Mod5", .altGraph), ("Lock", .capsLock), ("Mod2", .numLock),
    ] {
      if unsafe xkb_state_mod_name_is_active(state, name, XKB_STATE_MODS_EFFECTIVE) > 0 {
        modifiers.insert(flag)
      }
    }
    let symbol = unsafe xkb_state_key_get_one_sym(state, keycode)
    return KeyEvent(
      Self.logicalKey(symbol), phase: phase, modifiers: modifiers, physicalCode: physicalCode)
  }

  private static func logicalKey(_ symbol: UInt32) -> Key {
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
