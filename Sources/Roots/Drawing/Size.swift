public struct Size: Equatable, BitwiseCopyable, Sendable {
  public var width, height: Float

  public init(width: Float, height: Float) {
    self.width = width
    self.height = height
  }
}
