public struct Button: Block {
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
    size: Float = 20,
    textOverflow: TextOverflow = .clip, onClick: (() -> Void)? = nil
  ) {
    self.key = key
    self.title = title
    self.extent = extent
    self.color = color
    self.font = MonospaceFont(size: size)
    self.textOverflow = textOverflow
    self.onClick = onClick
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.button(
      key: key, title, extent: extent, color: color, font: font, textOverflow: textOverflow,
      onClick: onClick)
  }
}
