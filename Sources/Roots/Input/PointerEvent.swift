public struct PointerEvent: Sendable {
  public enum Phase: Sendable {
    case pressed, dragged, released
    case cancelled
  }
  public var phase: Phase
  public var x: Float
  public var y: Float
  public var rect: Rect

  public init(phase: Phase, x: Float, y: Float, rect: Rect) {
    self.phase = phase
    self.x = x
    self.y = y
    self.rect = rect
  }
}
