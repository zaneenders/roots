public struct Coordinate: Equatable, BitwiseCopyable, Sendable {
  public static let zero = Coordinate(x: 0, y: 0)
  public var x, y: Float

  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }

  @inlinable
  package init(_ vector: SIMD2<Float>) {
    self.init(x: vector.x, y: vector.y)
  }

  @inlinable
  package var vector: SIMD2<Float> { SIMD2(x, y) }
}
