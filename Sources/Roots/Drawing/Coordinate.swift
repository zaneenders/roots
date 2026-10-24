public struct Coordinate: Equatable, BitwiseCopyable, Sendable {
  public var x, y: Float

  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }
}
