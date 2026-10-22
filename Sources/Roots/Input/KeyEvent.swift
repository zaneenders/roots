public struct KeyEvent: Equatable, Sendable {
  public var key: Key
  public var phase: KeyPhase
  public var modifiers: KeyModifiers
  public var physicalCode: UInt32?

  public init(
    _ key: Key, phase: KeyPhase = .pressed, modifiers: KeyModifiers = [],
    physicalCode: UInt32? = nil
  ) {
    self.key = key
    self.phase = phase
    self.modifiers = modifiers
    self.physicalCode = physicalCode
  }
}
