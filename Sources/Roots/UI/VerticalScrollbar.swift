public struct VerticalScrollbar {
  public let track: Rect
  public let thumb: Rect
  public let hitRect: Rect
  private let limit: Float
  private let offset: Float

  public init?(viewport: Rect, contentHeight: Float, offset: Float) {
    guard viewport.x.isFinite, viewport.y.isFinite, viewport.width.isFinite,
      viewport.height.isFinite,
      viewport.width >= 12, viewport.height > 8, contentHeight.isFinite,
      contentHeight > viewport.height, offset.isFinite
    else { return nil }
    limit = contentHeight - viewport.height
    self.offset = min(limit, max(0, offset))
    let height = viewport.height - 8
    let thumbHeight = max(min(24, height / 2), height * (viewport.height / contentHeight))
    track = Rect(viewport.x + viewport.width - 8, viewport.y + 4, 6, height)
    thumb = Rect(
      track.x, track.y + min(1, max(0, offset / limit)) * (height - thumbHeight), 6, thumbHeight)
    hitRect = Rect(viewport.x + viewport.width - 12, track.y, 12, height)
  }

  public func scrollOffset(at y: Float, grabOffset: Float) -> Float {
    guard y.isFinite, grabOffset.isFinite, track.height > thumb.height else { return 0 }
    if abs(y - grabOffset - thumb.y) < 0.001 { return offset }
    return min(1, max(0, (y - grabOffset - track.y) / (track.height - thumb.height))) * limit
  }

  public func draw(into painter: inout UIPaintContext, active: Bool = false) {
    painter.draw(DrawRect(track, Color(1, 1, 1, 0.08), radius: 3))
    painter.draw(DrawRect(thumb, Color(1, 1, 1, active ? 0.75 : 0.45), radius: 3))
  }
}
