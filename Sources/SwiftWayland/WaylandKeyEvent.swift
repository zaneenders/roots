public struct WaylandKeyEvent: Equatable, Sendable {
  public var key: WaylandKey
  public var phase: WaylandKeyPhase
  public var modifiers: WaylandKeyModifiers
  public var physicalCode: UInt32?

  public init(
    _ key: WaylandKey, phase: WaylandKeyPhase = .pressed, modifiers: WaylandKeyModifiers = [],
    physicalCode: UInt32? = nil
  ) {
    self.key = key
    self.phase = phase
    self.modifiers = modifiers
    self.physicalCode = physicalCode
  }
}
