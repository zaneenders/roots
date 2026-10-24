public struct PointerEvent: Sendable {
  public enum Phase: Sendable {
    case pressed, dragged, released
    case cancelled
  }
  public var phase: Phase
  /// Coordinates relative to the element's origin. Cancellation uses the last available position.
  public var position: Coordinate
  public var region: Region

  public init(phase: Phase, position: Coordinate, region: Region) {
    self.phase = phase
    self.position = position
    self.region = region
  }
}
