/// Immutable geometry shared by retained draw commands and renderer caches.
public final class PolylineStroke: Sendable {
  /// Resource guard, not a shader uniform limit. Clients need not split paths.
  public static let maximumPointCount = 65_536
  public let points: [Coordinate]
  public let colors: [Color]
  public enum Rendering: Sendable {
    /// Opaque, well-conditioned strokes use ribbons; transparency retains analytic union coverage.
    case automatic
    case analytic
    /// Opt into source-over crossings. Unsupported sharp/degenerate geometry falls back to analytic.
    case ribbon
  }
  public let rendering: Rendering
  public let ribbon: StrokeRibbon?
  /// `scale` includes physical pixel scale when evaluating the antialias extrusion bound.
  public func usesRibbon(tint: Color, scale: Float = 1) -> Bool {
    ribbon.map { scale.isFinite && scale > $0.minimumScale && (rendering == .ribbon || tint.a >= 1) } ?? false
  }
  public let width: Float
  public let bounds: Region
  /// Local-space bounds for groups of 64 segments, used by all backends.
  public let chunks: [Region]
  public static let segmentsPerChunk = 64

  public init?(points: [Coordinate], width: Float, colors: [Color] = [], rendering: Rendering = .automatic) {
    guard !points.isEmpty, points.count <= Self.maximumPointCount, width > 0, width.isFinite,
      points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
      colors.isEmpty || colors.count == points.count,
      colors.allSatisfy({ $0.r.isFinite && $0.g.isFinite && $0.b.isFinite && $0.a.isFinite })
    else { return nil }
    let padding = width / 2 + 1
    func bounds(_ range: ClosedRange<Int>) -> Region {
      var low = points[range.lowerBound]
      var high = low
      for index in range {
        let point = points[index]
        low = Coordinate(x: min(low.x, point.x), y: min(low.y, point.y))
        high = Coordinate(x: max(high.x, point.x), y: max(high.y, point.y))
      }
      return Region(low.x - padding, low.y - padding, high.x - low.x + 2 * padding, high.y - low.y + 2 * padding)
    }
    let extent = bounds(0...(points.count - 1))
    guard extent.x.isFinite, extent.y.isFinite, extent.width.isFinite, extent.height.isFinite,
      (extent.x + extent.width).isFinite, (extent.y + extent.height).isFinite,
      extent.width > 0, extent.height > 0,
      (extent.width * extent.width + extent.height * extent.height).isFinite
    else { return nil }
    self.rendering = rendering
    self.ribbon =
      rendering == .analytic || (rendering == .automatic && colors.contains { $0.a < 1 })
      ? nil : StrokeRibbon(points: points, colors: colors, width: width)
    self.points = points
    self.colors = colors
    self.width = width
    self.bounds = extent
    chunks = stride(from: 0, to: max(1, points.count - 1), by: Self.segmentsPerChunk).map {
      bounds($0...min($0 + Self.segmentsPerChunk, points.count - 1))
    }
  }

  public struct Hit: Sendable {
    public let segmentIndex: Int
    public let fraction: Float
    /// Distance to the centerline in the caller's coordinates (not the stroke edge).
    public let distance: Float
    public let position: Coordinate
  }

  /// Earliest segment wins ties at crossings; duplicate points and single-point paths are supported.
  public func hitTest(
    _ point: Coordinate, transform: PathTransform = .identity, tolerance: Float = 8, clip: Region? = nil
  ) -> Hit? {
    guard transform.isValid, point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0,
      clip.map({ $0.contains(x: point.x, y: point.y) }) ?? true
    else { return nil }
    let local = transform.unapply(point)
    guard local.x.isFinite, local.y.isFinite else { return nil }
    let hit = nearest(to: local, maximumDistance: tolerance / transform.scale)
    guard let hit else { return nil }
    let distance = hit.distance * transform.scale
    let position = transform.apply(hit.position)
    guard distance.isFinite, distance <= tolerance, position.x.isFinite, position.y.isFinite else { return nil }
    return Hit(segmentIndex: hit.segmentIndex, fraction: hit.fraction, distance: distance, position: position)
  }

  public func color(at hit: Hit) -> Color {
    guard !colors.isEmpty else { return Color(1, 1, 1) }
    let index = min(max(0, hit.segmentIndex), colors.count - 1)
    let a = colors[index]
    let b = colors[min(index + 1, colors.count - 1)]
    let t = hit.fraction
    return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  public func distance(to point: Coordinate) -> Float {
    (nearest(to: point)?.distance ?? .greatestFiniteMagnitude) - width / 2
  }

  private func nearest(to point: Coordinate, maximumDistance: Float = .greatestFiniteMagnitude) -> Hit? {
    var best: Hit?
    var minimum = maximumDistance
    func lowerBound(_ bounds: Region) -> Float {
      let dx = max(bounds.x - point.x, 0, point.x - bounds.x - bounds.width)
      let dy = max(bounds.y - point.y, 0, point.y - bounds.y - bounds.height)
      return dx * dx + dy * dy
    }
    // Seed with the nearest chunk, not the first source segment. This keeps CPU
    // fallback and picking from walking far-away segments before finding a bound.
    var nearestChunk = 0
    var nearestBound = Float.greatestFiniteMagnitude
    for index in chunks.indices {
      let bound = lowerBound(chunks[index])
      if bound < nearestBound {
        nearestBound = bound
        nearestChunk = index
      }
    }
    for pass in 0...chunks.count {
      let chunkIndex = pass == 0 ? nearestChunk : pass - 1
      if pass > 0 && chunkIndex == nearestChunk { continue }
      if lowerBound(chunks[chunkIndex]) > minimum * minimum { continue }
      let first = chunkIndex * Self.segmentsPerChunk
      let end = min(first + Self.segmentsPerChunk, max(1, points.count - 1))
      for index in first..<end {
        let start = points[index]
        let segment = points[min(index + 1, points.count - 1)].vector - start.vector
        let delta = point.vector - start.vector
        let squaredLength = segment.x * segment.x + segment.y * segment.y
        let t = squaredLength > 0 ? max(0, min(1, (delta.x * segment.x + delta.y * segment.y) / squaredLength)) : 0
        let nearest = start.vector + t * segment
        let d = point.vector - nearest
        let distance = (d.x * d.x + d.y * d.y).squareRoot()
        if distance <= minimum, best == nil || distance < minimum || index < best!.segmentIndex {
          minimum = distance
          best = Hit(segmentIndex: index, fraction: t, distance: distance, position: Coordinate(nearest))
        }
      }
    }
    return best
  }
}
