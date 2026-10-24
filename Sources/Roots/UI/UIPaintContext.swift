public struct UIPaintContext: ~Copyable, ~Escapable {
  private var storage: MutableRef<UIStorage>
  public private(set) var region: Region
  public private(set) var clip: Region
  public private(set) var mousePosition: Coordinate?
  public let focused: Bool
  private var frameClip: Region
  private var origin = SIMD2<Float>.zero
  private var scale: Float = 1

  @_lifetime(&storage)
  init(storage: inout UIStorage, region: Region, clip: Region?, focused: Bool) {
    let effectiveClip = clip.map { $0.intersection(region) } ?? region
    let mousePosition = storage.mousePosition
    self.region = region
    self.clip = effectiveClip
    self.frameClip = effectiveClip
    self.mousePosition = mousePosition.flatMap { effectiveClip.contains(x: $0.x, y: $0.y) ? $0 : nil }
    self.focused = focused
    self.storage = MutableRef(&storage)
  }

  public mutating func withOrigin(
    x: Float, y: Float, scale: Float = 1, _ body: (inout UIPaintContext) -> Void
  ) {
    precondition(x.isFinite && y.isFinite && scale > 0 && scale.isFinite)
    let previousOrigin = origin
    let previousScale = self.scale
    let previousRegion = region
    let previousMousePosition = mousePosition
    let previousClip = clip
    origin += SIMD2(x, y) * self.scale
    self.scale *= scale
    precondition(origin.x.isFinite && origin.y.isFinite && self.scale > 0 && self.scale.isFinite)
    mousePosition = mousePosition.map { Coordinate(x: ($0.x - x) / scale, y: ($0.y - y) / scale) }
    region = Region((region.x - x) / scale, (region.y - y) / scale, region.width / scale, region.height / scale)
    clip = Region((clip.x - x) / scale, (clip.y - y) / scale, clip.width / scale, clip.height / scale)
    defer {
      origin = previousOrigin
      self.scale = previousScale
      region = previousRegion
      mousePosition = previousMousePosition
      clip = previousClip
    }
    body(&self)
  }

  public mutating func withClip(_ requested: Region, _ body: (inout UIPaintContext) -> Void) {
    let previousClip = clip
    let previousFrameClip = frameClip
    let previousMousePosition = mousePosition
    let valid =
      requested.x.isFinite && requested.y.isFinite
      && requested.width.isFinite && requested.height.isFinite
    clip = valid ? clip.intersection(requested) : Region(0, 0, 0, 0)
    frameClip = frameRegion(clip).intersection(previousFrameClip)
    mousePosition = mousePosition.flatMap { clip.contains(x: $0.x, y: $0.y) ? $0 : nil }
    defer {
      clip = previousClip
      frameClip = previousFrameClip
      mousePosition = previousMousePosition
    }
    body(&self)
  }

  public mutating func fillCircle(center: Coordinate, radius: Float, color: Color) {
    guard radius > 0 && radius.isFinite else { return }
    fillRect(
      Region(center.x - radius, center.y - radius, 2 * radius, 2 * radius), color: color,
      radius: radius)
  }

  public mutating func strokeCircle(
    center: Coordinate, radius: Float, color: Color, width: Float = 1
  ) {
    guard radius > 0 && radius.isFinite else { return }
    strokeRect(
      Region(center.x - radius, center.y - radius, 2 * radius, 2 * radius), color: color,
      radius: radius, width: width)
  }

  public mutating func strokePolyline(_ points: [Coordinate], color: Color, width: Float = 1) {
    guard !points.isEmpty, points.count <= PolylineStroke.maximumPointCount, width > 0,
      width.isFinite
    else { return }
    guard
      let stroke = PolylineStroke(
        points: points.map { Coordinate(origin + $0.vector * scale) }, width: width * scale)
    else { return }
    storage.value.emit(DrawRect(polyline: stroke, color: color, clip: frameClip))
  }

  private func frameRegion(_ region: Region) -> Region {
    Region(
      origin.x + region.x * scale, origin.y + region.y * scale, region.width * scale, region.height * scale)
  }

  public mutating func draw(_ draw: DrawRect) {
    var draw = draw
    if let stroke = draw.polyline {
      guard draw.isValid else { return }
      guard
        let transformed = PolylineStroke(
          points: stroke.points.map { Coordinate(origin + $0.vector * scale) }, width: stroke.width * scale)
      else { return }
      draw = DrawRect(polyline: transformed, color: draw.color, clip: draw.clip)
    } else {
      draw.region = frameRegion(draw.region)
    }
    draw.radius *= scale
    draw.strokeWidth *= scale
    draw.clip = draw.clip.map { frameRegion($0).intersection(frameClip) } ?? frameClip
    storage.value.emit(draw)
  }

  public mutating func fillRect(_ region: Region, color: Color, radius: Float = 0) {
    draw(DrawRect(region, color, radius: radius))
  }

  public mutating func strokeRect(_ region: Region, color: Color, radius: Float = 0, width: Float = 1) {
    guard width > 0 && width.isFinite else { return }
    draw(DrawRect(region, color, radius: radius, strokeWidth: width))
  }

  public mutating func strokeLine(
    from start: Coordinate, to end: Coordinate, color: Color,
    width: Float = 1, cap: LineCap = .round
  ) {
    guard width > 0 && width.isFinite, start.x.isFinite, start.y.isFinite,
      end.x.isFinite, end.y.isFinite
    else { return }
    let delta = end.vector - start.vector
    let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
    guard length.isFinite, length > 0 || cap == .round else { return }
    let axis = length > 0 ? delta / length : SIMD2<Float>(1, 0)
    let half = width / 2
    let extensionLength = cap == .round ? half : 0
    let origin = start.vector - axis * extensionLength - SIMD2(-axis.y, axis.x) * half
    draw(
      DrawRect(
        Region(origin.x, origin.y, length + 2 * extensionLength, width), color,
        radius: cap == .round ? half : 0, axis: axis))
  }

  @discardableResult
  public mutating func drawText(
    _ text: String, x: Float, y: Float, size: Float = 20, color: Color = .text
  ) -> Float {
    let font = MonospaceFont(size: size)
    let end = storage.value.drawText(
      text, x: origin.x + x * scale, y: origin.y + y * scale,
      font: MonospaceFont(size: font.size * scale), color: color, clip: frameClip)
    return (end - origin.x) / scale
  }
}

public enum LineCap: Sendable {
  case butt, round
}
