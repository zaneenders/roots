import Roots

struct WindowsInputState {
  static let keyLimit = 256
  private(set) var input = Input()
  private(set) var primaryDown = false
  private var pointerInside = false
  private var heldKeys: [UInt32: Key] = [:]

  mutating func pointer(x: Float, y: Float, inside: Bool) {
    guard x.isFinite, y.isFinite else { return }
    pointerInside = inside
    input.x = inside || primaryDown ? x : -1
    input.y = inside || primaryDown ? y : -1
  }

  mutating func button(down: Bool) {
    if down && !primaryDown { input.pressed = true }
    if !down && primaryDown { input.released = true }
    primaryDown = down
  }

  mutating func scroll(x: Float, y: Float) {
    if x.isFinite { input.scrollX = max(-100_000, min(100_000, input.scrollX + x)) }
    if y.isFinite { input.scrollY = max(-100_000, min(100_000, input.scrollY + y)) }
  }

  mutating func key(
    virtualKey: UInt32, scanCode: UInt32, scalar: UInt32 = 0, producesText: Bool = false,
    phase: KeyPhase, modifiers: KeyModifiers
  ) {
    if phase == .released {
      // Preserve the key pressed, even if Shift or the keyboard layout changed.
      guard let key = heldKeys.removeValue(forKey: scanCode) else { return }
      append(KeyEvent(key, phase: .released, modifiers: modifiers, physicalCode: scanCode))
      return
    }
    let shortcut =
      !modifiers.intersection([.control, .alt, .super]).isEmpty
      && !modifiers.contains(.altGraph)
    var mapped = WindowsKeyboard.key(virtualKey: virtualKey)
    if virtualKey == 0xA5 && modifiers.contains(.altGraph) { mapped = .altGraph }
    if producesText, case .symbol = mapped { mapped = nil }
    guard
      let key = mapped
        ?? (shortcut ? WindowsKeyboard.shortcut(virtualKey: virtualKey, scalar: scalar) : nil)
    else { return }
    record(key, scanCode: scanCode, phase: phase, modifiers: modifiers)
  }

  mutating func text(
    scalar: UInt32, scanCode: UInt32, phase: KeyPhase, modifiers: KeyModifiers
  ) {
    guard let character = WindowsKeyboard.text(scalar),
      modifiers.intersection([.control, .alt, .super]).isEmpty || modifiers.contains(.altGraph)
    else { return }
    var textModifiers = modifiers
    if modifiers.contains(.altGraph) { textModifiers.subtract([.control, .alt]) }
    record(.character(character), scanCode: scanCode, phase: phase, modifiers: textModifiers)
  }

  private mutating func record(
    _ key: Key, scanCode: UInt32, phase: KeyPhase, modifiers: KeyModifiers
  ) {
    if scanCode != 0 {
      if heldKeys.count >= Self.keyLimit && heldKeys[scanCode] == nil {
        loseFocus()
        return
      }
      heldKeys[scanCode] = key
    }
    append(
      KeyEvent(
        key, phase: phase, modifiers: modifiers, physicalCode: scanCode == 0 ? nil : scanCode))
  }

  private mutating func append(_ event: KeyEvent) {
    guard input.keyEvents.count < Self.keyLimit else {
      // Dropping a release could leave application/game controls stuck.
      loseFocus()
      return
    }
    input.keyEvents.append(event)
  }

  mutating func loseFocus() {
    input.focusLost = true
    input.keyEvents = heldKeys.keys.sorted().compactMap { code in
      heldKeys[code].map { KeyEvent($0, phase: .released, physicalCode: code) }
    }
    heldKeys.removeAll(keepingCapacity: true)
    input.pressed = false
    input.released = primaryDown
    primaryDown = false
    pointerInside = false
    input.x = -1
    input.y = -1
    input.scrollX = 0
    input.scrollY = 0
  }

  mutating func consume() -> Input {
    let result = input
    input.pressed = false
    input.released = false
    input.focusLost = false
    input.scrollX = 0
    input.scrollY = 0
    input.keyEvents.removeAll(keepingCapacity: true)
    if !primaryDown && !pointerInside {
      input.x = -1
      input.y = -1
    }
    return result
  }
}
