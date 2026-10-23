public struct Element: Block {
  public typealias Body = Never
  let key: UInt64
  let extent: Float
  let color: Color
  let onKey: ((KeyEvent) -> Void)?
  let onPointer: ((PointerEvent) -> Void)?
  let onScroll: ((ScrollEvent) -> Void)?
  let focusable: Bool
  let paint: (inout UIPaintContext) -> Void
  public init(
    key: UInt64, extent: Float = 44, color: Color = .panel, onKey: ((KeyEvent) -> Void)? = nil,
    onPointer: ((PointerEvent) -> Void)? = nil, onScroll: ((ScrollEvent) -> Void)? = nil,
    focusable: Bool = true, paint: @escaping (inout UIPaintContext) -> Void
  ) {
    self.key = key
    self.extent = extent
    self.color = color
    self.onKey = onKey
    self.onPointer = onPointer
    self.onScroll = onScroll
    self.focusable = focusable
    self.paint = paint
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.element(
      key: key, extent: extent, color: color, onKey: onKey, onPointer: onPointer,
      onScroll: onScroll, focusable: focusable, paint: paint)
  }
}
