import Roots

/// Win32 virtual-key translation kept independent of the Windows SDK for tests.
enum WindowsKeyboard {
  static func key(virtualKey: UInt32) -> Key? {
    switch virtualKey {
    case 0x08: .backspace
    case 0x09: .tab
    case 0x0D: .enter
    case 0x10, 0xA0, 0xA1: .shift
    case 0x11, 0xA2, 0xA3: .control
    case 0x12, 0xA4, 0xA5: .alt
    case 0x14: .capsLock
    case 0x1B: .escape
    case 0x21: .pageUp
    case 0x22: .pageDown
    case 0x23: .end
    case 0x24: .home
    case 0x25: .left
    case 0x26: .up
    case 0x27: .right
    case 0x28: .down
    case 0x2E: .delete
    case 0x5B, 0x5C: .super
    case 0x70...0x87: .function(Int(virtualKey - 0x70 + 1))
    case 0x90: .numLock
    // Text arrives after keyboard-layout/dead-key/IME processing in WM_CHAR.
    case 0x20, 0x30...0x39, 0x41...0x5A, 0x60...0x6F,
      0xBA...0xC0, 0xDB...0xDF, 0xE2, 0xE5, 0xE7:
      nil
    default: .symbol(virtualKey)
    }
  }

  static func text(_ value: UInt32) -> UnicodeScalar? {
    guard value >= 0x20, value != 0x7F else { return nil }
    return UnicodeScalar(value)
  }

  static func shortcut(virtualKey: UInt32, scalar: UInt32) -> Key? {
    // MapVirtualKeyEx's result follows the current keyboard layout. Its high bit
    // marks dead keys, which must not become shortcut text.
    guard scalar & 0x8000_0000 == 0, let character = text(scalar) else { return nil }
    if (0x41...0x5A).contains(character.value) {
      return .character(UnicodeScalar(character.value + 0x20)!)
    }
    return .character(character)
  }
}
