import AppKit
import Roots

struct MacOSKeyboard {
  static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
    var result: KeyModifiers = []
    if flags.contains(.shift) { result.insert(.shift) }
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.option) { result.insert(.alt) }
    if flags.contains(.command) { result.insert(.super) }
    if flags.contains(.capsLock) { result.insert(.capsLock) }
    return result
  }

  static func key(code: UInt16, characters: String?) -> Key {
    switch code {
    case 36, 76: return .enter
    case 48: return .tab
    case 51: return .backspace
    case 53: return .escape
    case 117: return .delete
    case 123: return .left
    case 124: return .right
    case 125: return .down
    case 126: return .up
    case 115: return .home
    case 119: return .end
    case 116: return .pageUp
    case 121: return .pageDown
    case 56, 60: return .shift
    case 59, 62: return .control
    case 58, 61: return .alt
    case 54, 55: return .super
    case 57: return .capsLock
    case 122: return .function(1)
    case 120: return .function(2)
    case 99: return .function(3)
    case 118: return .function(4)
    case 96: return .function(5)
    case 97: return .function(6)
    case 98: return .function(7)
    case 100: return .function(8)
    case 101: return .function(9)
    case 109: return .function(10)
    case 103: return .function(11)
    case 111: return .function(12)
    default:
      guard let characters, characters.unicodeScalars.count == 1,
        let scalar = characters.unicodeScalars.first
      else {
        return .symbol(UInt32(code))
      }
      return .character(scalar)
    }
  }

  static func event(_ event: NSEvent) -> KeyEvent {
    let flags = modifiers(event.modifierFlags)
    let characters =
      flags.intersection([.control, .super]).isEmpty
      ? event.characters : event.charactersIgnoringModifiers
    return KeyEvent(
      key(code: event.keyCode, characters: characters),
      phase: event.type == .keyUp ? .released : event.isARepeat ? .repeated : .pressed,
      modifiers: flags, physicalCode: UInt32(event.keyCode))
  }
}
