import Roots

public struct Viewport: Sendable, Equatable {
  public let bounds: Rect
  public let scale: Float

  public init(size: SIMD2<Float>, scale: Float = 1) {
    bounds = Rect(0, 0, size.x, size.y)
    self.scale = scale
  }
}
