public struct Canvas: Block {
  public typealias Body = Never
  let key: UInt64
  let extent: Float?
  let color: Color
  let blocksPointer: Bool
  let paint: (inout UIPaintContext) -> Void
  public init(
    key: UInt64, extent: Float? = nil, color: Color = .panel, blocksPointer: Bool = false,
    paint: @escaping (inout UIPaintContext) -> Void
  ) {
    self.key = key
    self.extent = extent
    self.color = color
    self.blocksPointer = blocksPointer
    self.paint = paint
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.canvas(key: key, extent: extent, color: color, blocksPointer: blocksPointer, paint: paint)
  }
}
