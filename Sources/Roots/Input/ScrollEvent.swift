public struct ScrollEvent: Sendable {
  public var deltaY: Float
  public var x: Float
  public var y: Float
  public var rect: Rect

  public init(deltaY: Float, x: Float, y: Float, rect: Rect) {
    self.deltaY = deltaY
    self.x = x
    self.y = y
    self.rect = rect
  }
}
