import Roots

public struct Viewport: Sendable, Equatable {
  public let bounds: Region
  public let scale: Float

  public init(size: Size, scale: Float = 1) {
    bounds = Region(0, 0, size.width, size.height)
    self.scale = scale
  }
}
