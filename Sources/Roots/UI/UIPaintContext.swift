public struct UIPaintContext: ~Copyable, ~Escapable {
  private var storage: MutableRef<UIStorage>
  public private(set) var rect: Rect
  public private(set) var clip: Rect
  public private(set) var pointerPosition: SIMD2<Float>?
  public let focused: Bool
  private var frameClip: Rect
  private var origin = SIMD2<Float>.zero
  private var scale: Float = 1

  @_lifetime(&storage)
  init(storage: inout UIStorage, rect: Rect, clip: Rect?, focused: Bool) {
    let effectiveClip = clip.map { $0.intersection(rect) } ?? rect
    let pointer = storage.pointerPosition
    self.rect = rect
    self.clip = effectiveClip
    self.frameClip = effectiveClip
    self.pointerPosition = pointer.flatMap { effectiveClip.contains(x: $0.x, y: $0.y) ? $0 : nil }
    self.focused = focused
    self.storage = MutableRef(&storage)
  }

  public mutating func withOrigin(
    x: Float, y: Float, scale: Float = 1, _ body: (inout UIPaintContext) -> Void
  ) {
    precondition(x.isFinite && y.isFinite && scale > 0 && scale.isFinite)
    let previousOrigin = origin
    let previousScale = self.scale
    let previousRect = rect
    let previousPointer = pointerPosition
    let previousClip = clip
    origin += SIMD2(x, y) * self.scale
    self.scale *= scale
    precondition(origin.x.isFinite && origin.y.isFinite && self.scale > 0 && self.scale.isFinite)
    pointerPosition = pointerPosition.map { ($0 - SIMD2(x, y)) / scale }
    rect = Rect((rect.x - x) / scale, (rect.y - y) / scale, rect.width / scale, rect.height / scale)
    clip = Rect((clip.x - x) / scale, (clip.y - y) / scale, clip.width / scale, clip.height / scale)
    defer {
      origin = previousOrigin
      self.scale = previousScale
      rect = previousRect
      pointerPosition = previousPointer
      clip = previousClip
    }
    body(&self)
  }

  public mutating func withClip(_ requested: Rect, _ body: (inout UIPaintContext) -> Void) {
    let previousClip = clip
    let previousFrameClip = frameClip
    let previousPointer = pointerPosition
    let valid =
      requested.x.isFinite && requested.y.isFinite
      && requested.width.isFinite && requested.height.isFinite
    clip = valid ? clip.intersection(requested) : Rect(0, 0, 0, 0)
    frameClip = frameRect(clip).intersection(previousFrameClip)
    pointerPosition = pointerPosition.flatMap { clip.contains(x: $0.x, y: $0.y) ? $0 : nil }
    defer {
      clip = previousClip
      frameClip = previousFrameClip
      pointerPosition = previousPointer
    }
    body(&self)
  }

  public mutating func fillCircle(center: SIMD2<Float>, radius: Float, color: Color) {
    guard radius > 0 && radius.isFinite else { return }
    fillRect(
      Rect(center.x - radius, center.y - radius, 2 * radius, 2 * radius), color: color,
      radius: radius)
  }

  public mutating func strokeCircle(
    center: SIMD2<Float>, radius: Float, color: Color, width: Float = 1
  ) {
    guard radius > 0 && radius.isFinite else { return }
    strokeRect(
      Rect(center.x - radius, center.y - radius, 2 * radius, 2 * radius), color: color,
      radius: radius, width: width)
  }

  public mutating func strokePolyline(_ points: [SIMD2<Float>], color: Color, width: Float = 1) {
    guard !points.isEmpty, points.count <= PolylineStroke.maximumPointCount, width > 0,
      width.isFinite
    else { return }
    guard
      let stroke = PolylineStroke(points: points.map { origin + $0 * scale }, width: width * scale)
    else { return }
    storage.value.emit(DrawRect(polyline: stroke, color: color, clip: frameClip))
  }

  private func frameRect(_ rect: Rect) -> Rect {
    Rect(
      origin.x + rect.x * scale, origin.y + rect.y * scale, rect.width * scale, rect.height * scale)
  }

  public mutating func draw(_ draw: DrawRect) {
    var draw = draw
    if let stroke = draw.polyline {
      guard draw.isValid else { return }
      guard
        let transformed = PolylineStroke(
          points: stroke.points.map { origin + $0 * scale }, width: stroke.width * scale)
      else { return }
      draw = DrawRect(polyline: transformed, color: draw.color, clip: draw.clip)
    } else {
      draw.rect = frameRect(draw.rect)
    }
    draw.radius *= scale
    draw.strokeWidth *= scale
    draw.clip = draw.clip.map { frameRect($0).intersection(frameClip) } ?? frameClip
    storage.value.emit(draw)
  }

  public mutating func fillRect(_ rect: Rect, color: Color, radius: Float = 0) {
    draw(DrawRect(rect, color, radius: radius))
  }

  public mutating func strokeRect(_ rect: Rect, color: Color, radius: Float = 0, width: Float = 1) {
    guard width > 0 && width.isFinite else { return }
    draw(DrawRect(rect, color, radius: radius, strokeWidth: width))
  }

  public mutating func strokeLine(
    from start: SIMD2<Float>, to end: SIMD2<Float>, color: Color,
    width: Float = 1, cap: LineCap = .round
  ) {
    guard width > 0 && width.isFinite, start.x.isFinite, start.y.isFinite,
      end.x.isFinite, end.y.isFinite
    else { return }
    let delta = end - start
    let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
    guard length.isFinite, length > 0 || cap == .round else { return }
    let axis = length > 0 ? delta / length : SIMD2<Float>(1, 0)
    let half = width / 2
    let extensionLength = cap == .round ? half : 0
    let origin = start - axis * extensionLength - SIMD2(-axis.y, axis.x) * half
    draw(
      DrawRect(
        Rect(origin.x, origin.y, length + 2 * extensionLength, width), color,
        radius: cap == .round ? half : 0, axis: axis))
  }

  @discardableResult
  public mutating func drawText(
    _ text: String, x: Float, y: Float, font: MonospaceFont = MonospaceFont(), color: Color = .text
  ) -> Float {
    let end = storage.value.drawText(
      text, x: origin.x + x * scale, y: origin.y + y * scale,
      font: MonospaceFont(size: font.size * scale), color: color, clip: frameClip)
    return (end - origin.x) / scale
  }
}

public enum LineCap: Sendable {
  case butt, round
}
