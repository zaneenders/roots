public struct Region: Equatable, BitwiseCopyable, Sendable {
  public var x, y, width, height: Float
  public init(_ x: Float, _ y: Float, _ width: Float, _ height: Float) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
  public var center: Coordinate { Coordinate(x: x + width / 2, y: y + height / 2) }

  public func offsetBy(dx: Float, dy: Float) -> Region {
    Region(x + dx, y + dy, width, height)
  }

  public func insetBy(dx: Float, dy: Float) -> Region {
    let dx = min(dx, width / 2)
    let dy = min(dy, height / 2)
    return Region(x + dx, y + dy, width - 2 * dx, height - 2 * dy)
  }

  public var isEmpty: Bool { width <= 0 || height <= 0 }

  public func intersection(_ other: Region) -> Region {
    let x = max(x, other.x)
    let y = max(y, other.y)
    guard !isEmpty && !other.isEmpty else { return Region(x, y, 0, 0) }
    return Region(
      x, y, max(0, min(self.x + width, other.x + other.width) - x),
      max(0, min(self.y + height, other.y + other.height) - y))
  }

  public func contains(x: Float, y: Float) -> Bool {
    width > 0 && height > 0 && x >= self.x && y >= self.y && x < self.x + width
      && y < self.y + height
  }
}
