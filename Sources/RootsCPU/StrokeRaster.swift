import Roots

/// Triangle coverage matches the GPU ribbon shader, including shared-edge ownership.
struct StrokeRaster {
  private struct Vertex {
    let p: SIMD2<Float>
    let edge: SIMD2<Float>
    let color: SIMD4<Float>
  }

  static func render(
    _ draw: DrawRect, mesh: StrokeRibbon, width: Int, height: Int,
    bottomLeft: Bool, pixels: inout [UInt8]
  ) {
    let transform = draw.pathTransform
    let halfWidth = draw.polyline!.width * transform.scale / 2
    let radius = halfWidth + 1.5
    let bounds = draw.bounds.intersection(draw.clip ?? draw.bounds)
      .intersection(Region(0, 0, Float(width), Float(height)))
    guard !bounds.isEmpty else { return }
    func vertex(_ v: StrokeRibbon.Vertex) -> Vertex {
      let p = SIMD2(v.geometry.x, v.geometry.y) * transform.scale + SIMD2(v.geometry.z, v.geometry.w) * radius
      let position = transform.translation
      return Vertex(
        p: SIMD2(position.x, position.y) + transform.axis * p.x
          + SIMD2(-transform.axis.y, transform.axis.x) * p.y,
        edge: SIMD2(v.edge.x, v.edge.y) * radius, color: v.color)
    }
    func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
    func topLeft(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { b.y < a.y || (b.y == a.y && b.x > a.x) }
    for index in stride(from: 0, to: mesh.vertices.count, by: 3) {
      let a = vertex(mesh.vertices[index])
      var b = vertex(mesh.vertices[index + 1])
      var c = vertex(mesh.vertices[index + 2])
      var area = cross(b.p - a.p, c.p - a.p)
      guard area.isFinite, area != 0 else { continue }
      if area < 0 {
        swap(&b, &c)
        area = -area
      }
      let x0 = Int(max(bounds.x, min(a.p.x, b.p.x, c.p.x)).rounded(.down))
      let x1 = Int(min(bounds.x + bounds.width, max(a.p.x, b.p.x, c.p.x)).rounded(.up))
      let y0 = Int(max(bounds.y, min(a.p.y, b.p.y, c.p.y)).rounded(.down))
      let y1 = Int(min(bounds.y + bounds.height, max(a.p.y, b.p.y, c.p.y)).rounded(.up))
      guard x1 > x0, y1 > y0 else { continue }
      let cap = mesh.vertices[index].edge.z > 0.5
      func edge(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ p: SIMD2<Float>) -> Float {
        // Reversing a shared edge must produce the exact opposite sign.
        (a.y - b.y) * p.x + (b.x - a.x) * p.y + (a.x * b.y - a.y * b.x)
      }
      func weights(_ p: SIMD2<Float>) -> SIMD3<Float> {
        SIMD3(edge(b.p, c.p, p), edge(c.p, a.p, p), edge(a.p, b.p, p)) / area
      }
      func distance(_ p: SIMD2<Float>) -> Float {
        let w = weights(p)
        let edge = a.edge * w.x + b.edge * w.y + c.edge * w.z
        return (cap ? (edge * edge).sum().squareRoot() : abs(edge.x)) - halfWidth
      }
      for y in y0..<y1 {
        for x in x0..<x1 {
          let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
          guard bounds.contains(x: p.x, y: p.y) else { continue }
          let w = weights(p)
          guard w.x >= 0, w.y >= 0, w.z >= 0,
            w.x != 0 || topLeft(b.p, c.p), w.y != 0 || topLeft(c.p, a.p), w.z != 0 || topLeft(a.p, b.p)
          else { continue }
          let d = distance(p)
          let dx = distance(SIMD2(Float(x ^ 1) + 0.5, p.y)) - d
          let pairedY = bottomLeft ? height - 1 - ((height - 1 - y) ^ 1) : y ^ 1
          let dy = distance(SIMD2(p.x, Float(pairedY) + 0.5)) - d
          let edge = max((abs(dx) + abs(dy)) * 0.75, 0.0001)
          let t = max(0, min(1, (d + edge) / (2 * edge)))
          let color = a.color * w.x + b.color * w.y + c.color * w.z
          let alpha = max(0, min(1, color.w)) * max(0, min(1, draw.color.a)) * (1 - t * t * (3 - 2 * t))
          let rgb = SIMD3(color.x * draw.color.r, color.y * draw.color.g, color.z * draw.color.b)
          let offset = (y * width + x) * 3
          for channel in 0..<3 {
            let value = max(0, min(1, rgb[channel])) * 255 * alpha + Float(pixels[offset + channel]) * (1 - alpha)
            pixels[offset + channel] = UInt8(max(0, min(255, value)))
          }
        }
      }
    }
  }
}
