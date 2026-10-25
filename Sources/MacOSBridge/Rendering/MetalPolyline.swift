import Metal
import Roots

/// Immutable buffers; command buffers retain submitted resources until GPU completion.
@safe @MainActor struct MetalPolyline {
  let stroke: PolylineStroke
  let vertices: any MTLBuffer
  let chunks: any MTLBuffer
  let ribbon: (any MTLBuffer)?
  let ribbonCount: Int

  init(_ stroke: PolylineStroke, device: any MTLDevice) throws {
    self.stroke = stroke
    if let mesh = stroke.ribbon {
      guard let buffer = mesh.vertices.withUnsafeBytes({ bytes in
        unsafe device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
      }) else { throw MacOSWindowError.resourceAllocation }
      ribbon = buffer
      ribbonCount = mesh.vertices.count
    } else { ribbon = nil; ribbonCount = 0 }
    var data: [SIMD4<Float>] = []
    data.reserveCapacity(stroke.points.count * 2)
    for index in stroke.points.indices {
      let point = stroke.points[index]
      let color = stroke.colors.isEmpty ? Color(1, 1, 1) : stroke.colors[index]
      data.append(SIMD4(point.x, point.y, 0, 0))
      data.append(SIMD4(color.r, color.g, color.b, color.a))
    }
    let bounds = stroke.chunks.map { SIMD4($0.x, $0.y, $0.width, $0.height) }
    guard
      let vertices = data.withUnsafeBytes({ bytes in
        unsafe device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
      }),
      let chunks = bounds.withUnsafeBytes({ bytes in
        unsafe device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
      })
    else { throw MacOSWindowError.resourceAllocation }
    self.vertices = vertices
    self.chunks = chunks
  }
}
