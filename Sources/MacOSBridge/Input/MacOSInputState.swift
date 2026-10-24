import Roots

struct MacOSInputState {
  private(set) var input = Input()
  private(set) var primaryDown = false
  private(set) var pointerInside = false
  private var heldKeys: [UInt32: KeyEvent] = [:]
  private(set) var modifiers: KeyModifiers = []
  static let keyLimit = 256

  mutating func pointer(x: Float, y: Float, inside: Bool) {
    pointerInside = inside
    input.mousePosition = inside || primaryDown ? Coordinate(x: x, y: y) : nil
  }

  mutating func button(down: Bool) {
    if down && !primaryDown { input.pressed = true }
    if !down && primaryDown { input.released = true }
    primaryDown = down
  }

  mutating func key(_ event: KeyEvent) {
    modifiers = event.modifiers
    if let code = event.physicalCode {
      if event.phase == .released {
        heldKeys.removeValue(forKey: code)
      } else if heldKeys.count < Self.keyLimit {
        heldKeys[code] = event
      }
    }
    if input.keyEvents.count < Self.keyLimit { input.keyEvents.append(event) }
  }

  mutating func flags(_ flags: KeyModifiers, code: UInt32, key: Key) {
    let previous = modifiers
    let flag: KeyModifiers
    switch key {
    case .shift: flag = .shift
    case .control: flag = .control
    case .alt: flag = .alt
    case .super: flag = .super
    case .capsLock: flag = .capsLock
    default:
      modifiers = flags
      return
    }
    if key == .capsLock {
      if previous.contains(flag) != flags.contains(flag) {
        self.key(
          KeyEvent(
            key, phase: flags.contains(flag) ? .pressed : .released, modifiers: flags,
            physicalCode: code))
      }
    } else {
      let down = flags.contains(flag) && heldKeys[code] == nil
      self.key(
        KeyEvent(key, phase: down ? .pressed : .released, modifiers: flags, physicalCode: code))
    }
    modifiers = flags
  }

  mutating func scroll(x: Float, y: Float) {
    if x.isFinite { input.scrollX = max(-100_000, min(100_000, input.scrollX + x)) }
    if y.isFinite { input.scrollY = max(-100_000, min(100_000, input.scrollY + y)) }
  }

  mutating func consumeEdges() {
    input.focusLost = false
    input.pressed = false
    input.released = false
    input.scrollX = 0
    input.scrollY = 0
    input.keyEvents.removeAll(keepingCapacity: true)
    if !pointerInside && !primaryDown {
      input.mousePosition = nil
    }
  }

  mutating func loseFocus() {
    input.focusLost = true
    input.keyEvents.removeAll(keepingCapacity: true)
    for code in heldKeys.keys.sorted() {
      if let event = heldKeys[code] {
        input.keyEvents.append(KeyEvent(event.key, phase: .released, physicalCode: code))
      }
    }
    heldKeys.removeAll(keepingCapacity: true)
    modifiers = []
    input.pressed = false
    input.released = primaryDown
    primaryDown = false
    pointerInside = false
    input.mousePosition = nil
    input.scrollX = 0
    input.scrollY = 0
  }
}
