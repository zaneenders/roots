public struct LabelBlock: Block {
  public typealias Body = Never
  let key: UInt64
  let title: String
  let extent: Float
  let color: Color
  let font: MonospaceFont
  let textOverflow: TextOverflow
  let selectable: Bool
  public init(
    key: UInt64, _ title: String, extent: Float = 32, color: Color = .panel,
    font: MonospaceFont = MonospaceFont(),
    textOverflow: TextOverflow = .clip, selectable: Bool = true
  ) {
    self.key = key
    self.title = title
    self.extent = extent
    self.color = color
    self.font = font
    self.textOverflow = textOverflow
    self.selectable = selectable
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.label(
      key: key, title, extent: extent, color: color, font: font, textOverflow: textOverflow,
      selectable: selectable)
  }
}

public struct ButtonBlock: Block {
  public typealias Body = Never
  let key: UInt64
  let title: String
  let extent: Float
  let color: Color
  let font: MonospaceFont
  let textOverflow: TextOverflow
  let onClick: (() -> Void)?
  public init(
    key: UInt64, _ title: String, extent: Float = 44, color: Color = .panel,
    font: MonospaceFont = MonospaceFont(),
    textOverflow: TextOverflow = .clip, onClick: (() -> Void)? = nil
  ) {
    self.key = key
    self.title = title
    self.extent = extent
    self.color = color
    self.font = font
    self.textOverflow = textOverflow
    self.onClick = onClick
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.button(
      key: key, title, extent: extent, color: color, font: font, textOverflow: textOverflow,
      onClick: onClick)
  }
}

public struct TextBlock: Block {
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

public struct CanvasBlock: Block {
  public typealias Body = Never
  let key: UInt64
  let extent: Float
  let color: Color
  let paint: (inout UIPaintContext) -> Void
  public init(
    key: UInt64, extent: Float, color: Color = .panel,
    paint: @escaping (inout UIPaintContext) -> Void
  ) {
    self.key = key
    self.extent = extent
    self.color = color
    self.paint = paint
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.canvas(key: key, extent: extent, color: color, paint: paint)
  }
}

public struct ElementBlock: Block {
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
