public struct Paragraph: Block {
  public typealias Body = Never
  private let content: [Text]
  private var font = MonospaceFont()
  private var alignment = Alignment.topLeading
  private var key: UInt64?
  private var implicitIdentity: IdentityLocation?
  private var color: Color?

  public init(@ParagraphBuilder content: () -> [Text]) {
    self.content = content()
  }

  public func size(_ size: Float) -> Self {
    var result = self
    result.font = MonospaceFont(size: size)
    return result
  }

  public func color(_ color: Color) -> Self {
    var result = self
    result.color = color
    return result
  }

  public func alignment(_ alignment: Alignment) -> Self {
    var result = self
    result.alignment = alignment
    return result
  }

  public func selectable(
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column
  ) -> Self {
    var result = self
    result.key = nil
    result.implicitIdentity = IdentityLocation(file: file, line: line, column: column)
    return result
  }

  public func selectable(key: UInt64) -> Self {
    var result = self
    result.key = key
    result.implicitIdentity = nil
    return result
  }

  public borrowing func _build(into frame: inout UIFrame) {
    frame.paragraph(
      content.map { $0.paragraphRun(font: font, color: color) }, key: key, identity: implicitIdentity, font: font,
      alignment: alignment)
  }
}
