public struct PointerEvent: Sendable {
  public enum Phase: Sendable {
    case pressed, dragged, released
    case cancelled
  }
  public var phase: Phase
  public var position: Coordinate
  public var region: Region

  public init(phase: Phase, position: Coordinate, region: Region) {
    self.phase = phase
    self.position = position
    self.region = region
  }
}
