import Foundation

/// A similarity transform: translation + rotation + positive uniform scale.
/// Stroke widths and hit-test distances scale uniformly; clipping remains in screen coordinates.
public struct PathTransform: Equatable, Sendable {
  public let translation: Coordinate
  public let scale: Float
  public let axis: SIMD2<Float>
  public static let identity = PathTransform()

  public init(translation: Coordinate = .zero, scale: Float = 1, rotation: Float = 0) {
    self.translation = translation
    self.scale = scale
    self.axis = SIMD2(cos(rotation), sin(rotation))
  }

  private init(translation: Coordinate, scale: Float, axis: SIMD2<Float>) {
    self.translation = translation
    self.scale = scale
    self.axis = axis
  }

  public var isValid: Bool {
    translation.x.isFinite && translation.y.isFinite && scale.isFinite && scale > 0
      && axis.x.isFinite && axis.y.isFinite
      && abs(axis.x * axis.x + axis.y * axis.y - 1) < 0.0001
  }

  public func apply(_ point: Coordinate) -> Coordinate {
    let p = point.vector * scale
    return Coordinate(translation.vector + axis * p.x + SIMD2(-axis.y, axis.x) * p.y)
  }

  public func unapply(_ point: Coordinate) -> Coordinate {
    let p = (point.vector - translation.vector) / scale
    return Coordinate(x: p.x * axis.x + p.y * axis.y, y: -p.x * axis.y + p.y * axis.x)
  }

  /// `outer.concatenating(inner).apply(p) == outer.apply(inner.apply(p))`
  public func concatenating(_ inner: PathTransform) -> PathTransform {
    PathTransform(
      translation: apply(inner.translation), scale: scale * inner.scale,
      axis: SIMD2(axis.x * inner.axis.x - axis.y * inner.axis.y, axis.y * inner.axis.x + axis.x * inner.axis.y))
  }

  public func bounds(of region: Region) -> Region {
    let origin = apply(Coordinate(x: region.x, y: region.y))
    let dx = axis * (region.width * scale)
    let dy = SIMD2(-axis.y, axis.x) * (region.height * scale)
    return Region(
      origin.x + min(0, dx.x) + min(0, dy.x), origin.y + min(0, dx.y) + min(0, dy.y),
      abs(dx.x) + abs(dy.x), abs(dx.y) + abs(dy.y))
  }
}
