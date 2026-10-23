public struct RichText: Block {
  public typealias Body = Never
  let key: UInt64
  let lines: [TextLine]
  let extent: Float
  let color: Color
  let paint: ((inout UIPaintContext) -> Void)?
  public init(
    key: UInt64, lines: [TextLine], extent: Float, color: Color = .panel,
    paint: ((inout UIPaintContext) -> Void)? = nil
  ) {
    self.key = key
    self.lines = lines
    self.extent = extent
    self.color = color
    self.paint = paint
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.text(key: key, lines: lines, extent: extent, color: color, paint: paint)
  }
}
