import Foundation

/// Immutable triangle geometry. Miter joins share edges; round caps use analytic coverage.
/// Crossings use source-over compositing, unlike the analytic path's single-coverage union.
public struct StrokeRibbon: Sendable {
  public struct Vertex: Sendable, BitwiseCopyable {
    /// Centerline position.xy and unit-width extrusion.zw.
    public let geometry: SIMD4<Float>
    public let color: SIMD4<Float>
    /// Signed edge coordinate.xy; z = 1 for a round cap, 0 for a ribbon side.
    public let edge: SIMD4<Float>
  }
  public let vertices: [Vertex]
  /// Smallest pixel-space scale before AA extrusion would fold a short inner corner.
  public let minimumScale: Float

  init?(points: borrowing [Coordinate], colors: borrowing [Color], width: Float) {
    guard points.count > 1 else { return nil }
    var directions: [SIMD2<Float>] = []
    var normals: [SIMD2<Float>] = []
    for index in 1..<points.count {
      let delta = points[index].vector - points[index - 1].vector
      let length = (delta * delta).sum().squareRoot()
      guard length > 0.000001 else { return nil }
      let direction = delta / length
      directions.append(direction)
      normals.append(SIMD2(-direction.y, direction.x))
    }
    var joins = [normals[0]]
    for index in 1..<(points.count - 1) {
      let sum = normals[index - 1] + normals[index]
      let denominator = (sum * normals[index]).sum()
      guard denominator > 0.5 else { return nil }  // sharp turns/reversals retain analytic coverage
      joins.append(sum / denominator)
    }
    joins.append(normals.last!)
    var minimumScale: Float = 0
    var vertices: [Vertex] = []
    vertices.reserveCapacity((points.count - 1) * 6 + 72)
    func color(_ index: Int) -> SIMD4<Float> {
      let c = colors.isEmpty ? Color(1, 1, 1) : colors[index]
      return SIMD4(c.r, c.g, c.b, c.a)
    }
    func vertex(_ index: Int, _ extrusion: SIMD2<Float>, _ edge: SIMD2<Float>, cap: Bool = false) -> Vertex {
      Vertex(
        geometry: SIMD4(points[index].x, points[index].y, extrusion.x, extrusion.y),
        color: color(index), edge: SIMD4(edge.x, edge.y, cap ? 1 : 0, 0))
    }
    for index in 0..<(points.count - 1) {
      let length = ((points[index + 1].vector - points[index].vector) * directions[index]).sum()
      let inset = abs((joins[index] * directions[index]).sum()) + abs((joins[index + 1] * directions[index]).sum())
      // Do not tessellate folded strips at very short, wide corners.
      let clearance = length - inset * width / 2
      guard clearance > 0 else { return nil }
      minimumScale = max(minimumScale, 1.51 * inset / clearance)
      let a = vertex(index, joins[index], SIMD2(1, 0))
      let b = vertex(index, -joins[index], SIMD2(-1, 0))
      let c = vertex(index + 1, joins[index + 1], SIMD2(1, 0))
      let d = vertex(index + 1, -joins[index + 1], SIMD2(-1, 0))
      vertices += [a, b, c, b, d, c]
    }
    for isStart in [true, false] {
      let index = isStart ? 0 : points.count - 1
      let direction = isStart ? -directions[0] : directions.last!
      let normal = SIMD2(-direction.y, direction.x)
      let steps = 12
      let expansion = 1 / cos(Float.pi / Float(steps) / 2)
      for step in 0..<steps {
        func radial(_ step: Int) -> SIMD2<Float> {
          let angle = -Float.pi / 2 + Float(step) * Float.pi / Float(steps)
          return (direction * cos(angle) + normal * sin(angle)) * expansion
        }
        let a = radial(step)
        let b = radial(step + 1)
        vertices += [
          vertex(index, .zero, .zero, cap: true),
          vertex(index, a, a, cap: true), vertex(index, b, b, cap: true)
        ]
      }
    }
    self.vertices = vertices
    self.minimumScale = minimumScale
  }
}
