public final class PolylineStroke: Sendable {
  public static let maximumPointCount = 128
  public let points: [Coordinate]
  public let width: Float
  public let bounds: Region

  public init?(points: [Coordinate], width: Float) {
    guard !points.isEmpty, points.count <= Self.maximumPointCount, width > 0, width.isFinite,
      points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
    else { return nil }
    var low = points[0]
    var high = points[0]
    for point in points {
      low = Coordinate(x: min(low.x, point.x), y: min(low.y, point.y))
      high = Coordinate(x: max(high.x, point.x), y: max(high.y, point.y))
    }
    let padding = width / 2 + 1
    let bounds = Region(
      low.x - padding, low.y - padding, high.x - low.x + 2 * padding, high.y - low.y + 2 * padding)
    guard bounds.x.isFinite, bounds.y.isFinite, bounds.width.isFinite, bounds.height.isFinite,
      (bounds.x + bounds.width).isFinite, (bounds.y + bounds.height).isFinite,
      bounds.width > 0, bounds.height > 0
    else { return nil }
    let diagonal = bounds.width * bounds.width + bounds.height * bounds.height
    guard diagonal.isFinite else { return nil }
    self.points = points
    self.width = width
    self.bounds = bounds
  }

  public func distance(to point: Coordinate) -> Float {
    var minimum: Float = .greatestFiniteMagnitude
    var start = points[0]
    for end in points {
      let segment = end.vector - start.vector
      let delta = point.vector - start.vector
      let squaredLength = segment.x * segment.x + segment.y * segment.y
      let t =
        squaredLength > 0
        ? max(0, min(1, (delta.x * segment.x + delta.y * segment.y) / squaredLength)) : 0
      let nearest = delta - t * segment
      minimum = min(minimum, (nearest.x * nearest.x + nearest.y * nearest.y).squareRoot())
      start = end
    }
    return minimum - width / 2
  }
}
