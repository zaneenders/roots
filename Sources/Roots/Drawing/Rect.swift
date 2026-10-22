public struct Rect: Equatable, BitwiseCopyable, Sendable {
  public var x, y, width, height: Float
  public init(_ x: Float, _ y: Float, _ width: Float, _ height: Float) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
  public var center: SIMD2<Float> { SIMD2(x + width / 2, y + height / 2) }

  public func offsetBy(dx: Float, dy: Float) -> Rect {
    Rect(x + dx, y + dy, width, height)
  }

  public func insetBy(dx: Float, dy: Float) -> Rect {
    let dx = min(dx, width / 2)
    let dy = min(dy, height / 2)
    return Rect(x + dx, y + dy, width - 2 * dx, height - 2 * dy)
  }

  public var isEmpty: Bool { width <= 0 || height <= 0 }

  public func intersection(_ other: Rect) -> Rect {
    let x = max(x, other.x)
    let y = max(y, other.y)
    guard !isEmpty && !other.isEmpty else { return Rect(x, y, 0, 0) }
    return Rect(
      x, y, max(0, min(self.x + width, other.x + other.width) - x),
      max(0, min(self.y + height, other.y + other.height) - y))
  }

  public func contains(x: Float, y: Float) -> Bool {
    width > 0 && height > 0 && x >= self.x && y >= self.y && x < self.x + width
      && y < self.y + height
  }
}
