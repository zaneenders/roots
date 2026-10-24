public struct Text: Block {
  public typealias Body = Never
  private let value: String
  private var key: UInt64?
  private var implicitIdentity: IdentityLocation?
  private var style = PlainTextStyle()
  private var hasExplicitSize = false
  private var inlineBackground: Color?

  public init(_ value: String) {
    self.value = value
  }

  public func size(_ size: Float) -> Self {
    var result = self
    result.style.font = MonospaceFont(size: size)
    result.hasExplicitSize = true
    return result
  }

  public func color(_ color: Color) -> Self {
    var result = self
    result.style.color = color
    return result
  }

  public func alignment(_ alignment: Alignment) -> Self {
    var result = self
    result.style.alignment = alignment
    return result
  }

  public func selectable(
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column
  ) -> Self {
    var result = self
    result.key = nil
    result.implicitIdentity = IdentityLocation(file: file, line: line, column: column)
    result.style.selectable = true
    return result
  }

  public func selectable(key: UInt64) -> Self {
    var result = self
    result.key = key
    result.implicitIdentity = nil
    result.style.selectable = true
    return result
  }

  public func overflow(_ overflow: TextOverflow) -> Self {
    var result = self
    result.style.overflow = overflow
    return result
  }

  func withInlineBackground(_ color: Color) -> Text {
    var result = self
    result.inlineBackground = color
    return result
  }

  func paragraphRun(font: MonospaceFont, color: Color?) -> ParagraphRun {
    precondition(!style.selectable, "Apply selection to the paragraph, not its inline text")
    return ParagraphRun(
      text: value, font: hasExplicitSize ? style.font : font,
      color: style.color ?? color, background: inlineBackground)
  }

  public borrowing func _build(into frame: inout UIFrame) {
    frame.plainText(value, key: key, identity: implicitIdentity, style: style)
  }
}

struct PlainTextStyle {
  var font = MonospaceFont()
  var color: Color?
  var alignment = Alignment.topLeading
  var selectable = false
  var overflow = TextOverflow.clip

  func lines(for text: String, in region: Region, color: Color) -> [TextLine] {
    let y = (region.height - font.height(of: text)) * alignment.y
    return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
      let displayed = overflow == .truncateTail ? font.truncating(String(line), to: region.width) : String(line)
      let x = (region.width - font.layoutWidth(of: displayed[...])) * alignment.x
      return TextLine(
        [TextRun(displayed, color: self.color ?? color)], x: x,
        y: y + Float(index) * font.lineHeight, size: font.size)
    }
  }

  func size(of text: String) -> SIMD2<Float> {
    let width =
      text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { font.layoutWidth(of: $0) }.max() ?? 0
    return SIMD2(width, font.height(of: text))
  }
}

extension MonospaceFont {
  func layoutWidth(of line: Substring) -> Float {
    guard let last = line.last else { return 0 }
    return width(of: line) + (Self.columnWidth(of: last) == 1 ? glyphWidth - advance : 0)
  }
}
