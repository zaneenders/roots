import Roots

struct MetalVertex: BitwiseCopyable, Sendable {
  var position: SIMD2<Float>
  var size: SIMD2<Float>
  var color: SIMD4<Float>
  var radius: Float
  var glyphUV: SIMD4<Float>
  var textured: Float
  var strokeWidth: Float
  var axis: SIMD2<Float>
}

struct MetalDrawRun {
  var firstVertex: Int
  var vertexCount: Int
  var scissor: MetalScissorRect?
  var polyline: DrawRect? = nil
  var image: ResolvedImageDraw? = nil
}

@MainActor struct MetalFrameState: ~Copyable {
  private(set) var vertices: [MetalVertex] = []
  private(set) var runs: [MetalDrawRun] = []
  private var logicalSize = SIMD2<Float>(repeating: 1)
  private var drawableSize = SIMD2<Int32>(repeating: 1)

  mutating func begin(logicalSize: SIMD2<Float>, drawableSize: SIMD2<Int32>) {
    self.logicalSize = logicalSize
    self.drawableSize = drawableSize
    vertices.removeAll(keepingCapacity: true)
    runs.removeAll(keepingCapacity: true)
  }

  mutating func withFrame(_ body: @MainActor (inout MetalRenderFrame) -> Void) {
    var frame = MetalRenderFrame(state: &self)
    body(&frame)
  }

  mutating func render(_ batch: borrowing UIDrawBatch) {
    for command in batch {
      switch command {
      case .rectangle(let draw): append(draw)
      case .image(let image):
        if let draw = image.resolve() { append(draw.rectangle, image: draw) }
      }
    }
  }

  mutating func render(_ draws: borrowing Span<DrawRect>) {
    for draw in draws { append(draw) }
  }

  private mutating func append(_ draw: DrawRect, image: ResolvedImageDraw? = nil) {
    guard Self.accepts(draw) else { return }
    let scissor = draw.clip.map {
      MetalScissorRect($0, logicalSize: logicalSize, drawableSize: drawableSize)
    }
    if scissor?.isEmpty == true { return }
    if draw.polyline != nil {
      runs.append(MetalDrawRun(firstVertex: 0, vertexCount: 0, scissor: scissor, polyline: draw))
      return
    }
    let first = vertices.count
    let uv = draw.glyphUV.map { SIMD4($0.x, $0.y, $0.width, $0.height) } ?? .zero
    vertices.append(
      MetalVertex(
        position: SIMD2(draw.region.x, draw.region.y),
        size: SIMD2(draw.region.width, draw.region.height),
        color: SIMD4(draw.color.r, draw.color.g, draw.color.b, draw.color.a), radius: draw.radius,
        glyphUV: uv,
        textured: image.map { $0.frame.format == .rgba8 ? 3 : ($0.frame.format == .nv12 ? 5 : 4) }
          ?? (draw.glyphUV == nil ? 0 : (draw.colorGlyph ? 2 : 1)),
        strokeWidth: draw.strokeWidth, axis: draw.axis))
    if image == nil, let last = runs.last, last.image == nil, last.polyline == nil,
      last.scissor == scissor
    {
      runs[runs.count - 1].vertexCount += 1
    } else {
      runs.append(MetalDrawRun(firstVertex: first, vertexCount: 1, scissor: scissor, image: image))
    }
  }

  static func accepts(_ draw: DrawRect) -> Bool {
    draw.isValid
  }
}
