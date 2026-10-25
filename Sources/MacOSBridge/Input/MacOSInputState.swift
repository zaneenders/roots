import Roots

struct MacOSInputState {
  enum Button { case primary, secondary, middle }
  private(set) var input = Input()
  private(set) var primaryDown = false
  private(set) var pointerInside = false
  private var heldKeys: [UInt32: KeyEvent] = [:]
  private var physicalModifiers: Set<UInt32> = []
  private(set) var modifiers: KeyModifiers = []
  static let keyLimit = 256

  mutating func pointer(x: Float, y: Float, inside: Bool) {
    pointerInside = inside
    input.mousePosition = inside || hasPointerCapture ? Coordinate(x: x, y: y) : nil
  }

  private var hasPointerCapture: Bool {
    primaryDown || input.secondaryDown || input.middleDown
      || input.pressed || input.released || input.secondaryPressed || input.secondaryReleased
      || input.middlePressed || input.middleReleased
  }

  mutating func button(_ button: Button = .primary, down: Bool) {
    switch button {
    case .primary:
      if down && !primaryDown { input.pressed = true }
      if !down && primaryDown { input.released = true }
      primaryDown = down
    case .secondary:
      if down && !input.secondaryDown { input.secondaryPressed = true }
      if !down && input.secondaryDown { input.secondaryReleased = true }
      input.secondaryDown = down
    case .middle:
      if down && !input.middleDown { input.middlePressed = true }
      if !down && input.middleDown { input.middleReleased = true }
      input.middleDown = down
    }
  }

  mutating func key(_ event: KeyEvent) {
    modifiers = event.modifiers
    // Reserve one queue slot for every accepted held key's eventual release.
    // Dropping a press or repeat is preferable to leaving a consumer's key stuck.
    var heldCount = heldKeys.count
    if let code = event.physicalCode {
      if event.phase == .released {
        if heldKeys[code] != nil { heldCount -= 1 }
      } else if heldKeys[code] == nil {
        heldCount += 1
      }
    }
    guard input.keyEvents.count + 1 + heldCount <= Self.keyLimit else { return }
    if let code = event.physicalCode {
      if event.phase == .released {
        heldKeys.removeValue(forKey: code)
      } else {
        heldKeys[code] = event
      }
    }
    input.keyEvents.append(event)
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
      // Modifier identity follows physical transitions even if the queue drops
      // the press. Accepted keys alone cannot disambiguate overlapping sides.
      let down = flags.contains(flag) && !physicalModifiers.contains(code)
      if down {
        if physicalModifiers.count < Self.keyLimit { physicalModifiers.insert(code) }
      } else {
        physicalModifiers.remove(code)
      }
      self.key(
        KeyEvent(key, phase: down ? .pressed : .released, modifiers: flags, physicalCode: code))
    }
    modifiers = flags
  }

  mutating func scroll(
    x: Float, y: Float, stepsX: Float = 0, stepsY: Float = 0, inverted: Bool? = nil
  ) {
    if x.isFinite { input.scrollX = max(-100_000, min(100_000, input.scrollX + x)) }
    if y.isFinite { input.scrollY = max(-100_000, min(100_000, input.scrollY + y)) }
    if stepsX.isFinite { input.scrollStepsX = max(-100_000, min(100_000, input.scrollStepsX + stepsX)) }
    if stepsY.isFinite { input.scrollStepsY = max(-100_000, min(100_000, input.scrollStepsY + stepsY)) }
    if (x.isFinite && x != 0) || (stepsX.isFinite && stepsX != 0) { input.scrollInvertedX = inverted }
    if (y.isFinite && y != 0) || (stepsY.isFinite && stepsY != 0) { input.scrollInvertedY = inverted }
  }

  mutating func consumeEdges() {
    input.focusLost = false
    input.pressed = false
    input.released = false
    input.secondaryPressed = false
    input.secondaryReleased = false
    input.middlePressed = false
    input.middleReleased = false
    input.scrollX = 0
    input.scrollY = 0
    input.scrollStepsX = 0
    input.scrollStepsY = 0
    input.scrollInvertedX = nil
    input.scrollInvertedY = nil
    input.textEvents.removeAll(keepingCapacity: true)
    input.keyEvents.removeAll(keepingCapacity: true)
    if !pointerInside && !hasPointerCapture {
      input.mousePosition = nil
    }
  }

  mutating func loseFocus() {
    input.focusLost = true
    input.keyEvents.removeAll { $0.phase != .released }
    var releasedCodes: Set<UInt32> = []
    input.keyEvents.removeAll { event in
      guard let code = event.physicalCode else { return false }
      return !releasedCodes.insert(code).inserted
    }
    for code in heldKeys.keys.sorted() where !releasedCodes.contains(code) {
      if let event = heldKeys[code] {
        input.keyEvents.append(KeyEvent(event.key, phase: .released, physicalCode: code))
      }
    }
    heldKeys.removeAll(keepingCapacity: true)
    physicalModifiers.removeAll(keepingCapacity: true)
    modifiers = []
    input.pressed = false
    input.released = input.released || primaryDown
    primaryDown = false
    input.secondaryPressed = false
    input.secondaryReleased = input.secondaryReleased || input.secondaryDown
    input.secondaryDown = false
    input.middlePressed = false
    input.middleReleased = input.middleReleased || input.middleDown
    input.middleDown = false
    pointerInside = false
    input.mousePosition = nil
    input.scrollX = 0
    input.scrollY = 0
    input.scrollStepsX = 0
    input.scrollStepsY = 0
    input.scrollInvertedX = nil
    input.scrollInvertedY = nil
    input.textEvents.removeAll(keepingCapacity: true)
  }
}
