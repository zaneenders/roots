public struct DrawRect: Sendable {
  public private(set) var polyline: PolylineStroke?
  public var rect: Rect
  public var color: Color
  public var radius: Float
  public var strokeWidth: Float
  public var axis: SIMD2<Float>
  public var clip: Rect?
  public var glyphUV: Rect?
  public var colorGlyph: Bool
  public init(
    _ rect: Rect, _ color: Color, radius: Float = 0, strokeWidth: Float = 0,
    axis: SIMD2<Float> = SIMD2(1, 0), clip: Rect? = nil, glyphUV: Rect? = nil,
    colorGlyph: Bool = false
  ) {
    self.polyline = nil
    self.rect = rect
    self.color = color
    self.radius = radius
    self.strokeWidth = strokeWidth
    self.axis = axis
    self.clip = clip
    self.glyphUV = glyphUV
    self.colorGlyph = colorGlyph
  }

  public init(polyline: PolylineStroke, color: Color, clip: Rect? = nil) {
    self.init(polyline.bounds, color, clip: clip)
    self.polyline = polyline
  }

  @inlinable
  public var isValid: Bool {
    if let polyline {
      return rect == polyline.bounds && axis == SIMD2(1, 0) && radius == 0 && strokeWidth == 0
        && glyphUV == nil
        && color.r.isFinite && color.g.isFinite && color.b.isFinite && color.a.isFinite
    }
    guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
      rect.width > 0, rect.height > 0,
      color.r.isFinite, color.g.isFinite, color.b.isFinite, color.a.isFinite,
      radius.isFinite, strokeWidth.isFinite, strokeWidth >= 0,
      axis == SIMD2(1, 0)
        || (axis.x.isFinite && axis.y.isFinite
          && abs(axis.x * axis.x + axis.y * axis.y - 1) < 0.0001)
    else { return false }
    if axis == SIMD2(1, 0) {
      guard (rect.x + rect.width + edgePadding).isFinite,
        (rect.y + rect.height + edgePadding).isFinite
      else {
        return false
      }
    } else {
      let b = bounds
      guard b.x.isFinite, b.y.isFinite, b.width.isFinite, b.height.isFinite,
        (b.x + b.width).isFinite, (b.y + b.height).isFinite
      else { return false }
    }
    guard let uv = glyphUV else { return true }
    return strokeWidth == 0 && uv.x.isFinite && uv.y.isFinite && uv.width.isFinite
      && uv.height.isFinite
      && uv.x >= 0 && uv.y >= 0 && uv.width > 0 && uv.height > 0
      && uv.x + uv.width <= 1 && uv.y + uv.height <= 1
  }

  @inlinable
  public var edgePadding: Float { glyphUV == nil ? 1 : 0 }

  @inlinable
  public func position(at local: SIMD2<Float>) -> SIMD2<Float> {
    if axis == SIMD2(1, 0) { return SIMD2(rect.x, rect.y) + local }
    return SIMD2(rect.x, rect.y) + axis * local.x + SIMD2(-axis.y, axis.x) * local.y
  }

  @inlinable
  public func localPosition(at point: SIMD2<Float>) -> SIMD2<Float> {
    let delta = point - SIMD2(rect.x, rect.y)
    if axis == SIMD2(1, 0) { return delta }
    return SIMD2(delta.x * axis.x + delta.y * axis.y, -delta.x * axis.y + delta.y * axis.x)
  }

  @inlinable
  public var bounds: Rect {
    if let polyline { return polyline.bounds }
    let padding = edgePadding
    if axis == SIMD2(1, 0) {
      return Rect(
        rect.x - padding, rect.y - padding, rect.width + 2 * padding, rect.height + 2 * padding)
    }
    let origin = position(at: SIMD2(-padding, -padding))
    let dx = axis * (rect.width + 2 * padding)
    let dy = SIMD2(-axis.y, axis.x) * (rect.height + 2 * padding)
    return Rect(
      origin.x + min(0, dx.x) + min(0, dy.x), origin.y + min(0, dx.y) + min(0, dy.y),
      abs(dx.x) + abs(dy.x), abs(dx.y) + abs(dy.y))
  }
}
