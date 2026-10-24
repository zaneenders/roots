struct ParagraphRun {
  let text: String
  let font: MonospaceFont
  let color: Color?
  let background: Color?
}

struct ParagraphContent {
  let runs: [ParagraphRun]
  let font: MonospaceFont
  let alignment: Alignment
  let selectable: Bool

  struct Glyph {
    let character: Character
    let font: MonospaceFont
    let color: Color
    let background: Color?
    var advance: Float { Float(MonospaceFont.columnWidth(of: character)) * font.advance }
    var width: Float { MonospaceFont.columnWidth(of: character) == 2 ? advance : font.glyphWidth }
  }

  struct Line {
    let glyphs: Range<Int>
    let sourceStart: Int
    let sourceEnd: Int
    let width: Float
    let baseline: Float
    let height: Float
    let advance: Float
  }

  struct Layout {
    let text: String
    let glyphs: [Glyph]
    let lines: [Line]
    let size: SIMD2<Float>
  }

  func layout(width: Float, color: Color) -> Layout {
    var text = ""
    var ends: [Int] = []
    for run in runs {
      text += run.text
      ends.append(text.utf8.count)
    }
    var glyphs: [Glyph] = []
    var runIndex = 0
    var byteOffset = 0
    for character in text {
      while runIndex + 1 < runs.count, byteOffset >= ends[runIndex] { runIndex += 1 }
      let run = runs[runIndex]
      glyphs.append(Glyph(character: character, font: run.font, color: run.color ?? color, background: run.background))
      byteOffset += character.utf8.count
    }
    guard !glyphs.isEmpty else { return Layout(text: text, glyphs: [], lines: [], size: .zero) }
    var lines: [Line] = []
    func append(_ range: Range<Int>, sourceStart: Int, sourceEnd: Int) {
      var x: Float = 0
      var width: Float = 0
      var baseline: Float = range.isEmpty ? font.baseline : 0
      var descent: Float = range.isEmpty ? font.glyphHeight - font.baseline : 0
      var leading: Float = range.isEmpty ? font.lineHeight - font.glyphHeight : 0
      for index in range {
        let glyph = glyphs[index]
        width = max(width, x + glyph.width)
        x += glyph.advance
        baseline = max(baseline, glyph.font.baseline)
        descent = max(descent, glyph.font.glyphHeight - glyph.font.baseline)
        leading = max(leading, glyph.font.lineHeight - glyph.font.glyphHeight)
      }
      lines.append(
        Line(
          glyphs: range, sourceStart: sourceStart, sourceEnd: sourceEnd,
          width: width, baseline: baseline, height: baseline + descent,
          advance: baseline + descent + leading))
    }
    var start = 0
    var sourceStart = 0
    while start < glyphs.count {
      var end = start
      var advance: Float = 0
      var lineWidth: Float = 0
      var whitespace: Int?
      while end < glyphs.count {
        let glyph = glyphs[end]
        if glyph.character.isTextLineBreak { break }
        let nextWidth = max(lineWidth, advance + glyph.width)
        if nextWidth > width, end > start { break }
        if glyph.character.isWhitespace { whitespace = end }
        lineWidth = nextWidth
        advance += glyph.advance
        end += 1
      }
      if end == glyphs.count {
        append(start..<end, sourceStart: sourceStart, sourceEnd: end)
        break
      }
      let next = glyphs[end].character
      if next.isTextLineBreak {
        append(start..<end, sourceStart: sourceStart, sourceEnd: end)
        start = end + 1
        sourceStart = start
        if start == glyphs.count { append(start..<start, sourceStart: start, sourceEnd: start) }
      } else {
        var resume = end
        if !next.isWhitespace, let whitespace, whitespace > start {
          end = whitespace
          resume = whitespace
        }
        while resume < glyphs.count, glyphs[resume].character.isWhitespace,
          !glyphs[resume].character.isTextLineBreak
        { resume += 1 }
        append(start..<end, sourceStart: sourceStart, sourceEnd: resume)
        start = resume
        sourceStart = resume
      }
    }
    var height: Float = 0
    for (index, line) in lines.enumerated() { height += index == lines.count - 1 ? line.height : line.advance }
    return Layout(text: text, glyphs: glyphs, lines: lines, size: SIMD2(lines.map(\.width).max() ?? 0, height))
  }
}

extension ParagraphContent {
  func textLayout(_ layout: Layout, in region: Region) -> TextLayout {
    var fragments: [TextLayout.Fragment] = []
    var lines: [TextLayout.FlowLine] = []
    var y = max(0, region.height - layout.size.y) * alignment.y
    for line in layout.lines {
      var x = max(0, region.width - line.width) * alignment.x
      let lineX = x
      var stops = [x]
      for index in line.glyphs {
        let glyph = layout.glyphs[index]
        fragments.append(
          TextLayout.Fragment(
            text: String(glyph.character),
            region: Region(x, y + line.baseline - glyph.font.baseline, glyph.width, glyph.font.glyphHeight),
            font: glyph.font, color: glyph.color, background: glyph.background, advance: glyph.advance))
        x += glyph.advance
        stops.append(x)
      }
      while stops.count <= line.sourceEnd - line.sourceStart { stops.append(x) }
      lines.append(
        TextLayout.FlowLine(
          start: line.sourceStart, end: line.sourceEnd,
          region: Region(lineX, y, line.width, line.height), stops: stops))
      y += line.advance
    }
    return TextLayout(text: layout.text, fragments: fragments, flowLines: lines)
  }
}

extension UIStorage {
  mutating func updateParagraph(at index: Int) {
    guard let content = nodes[index].paragraph else { return }
    let previous = nodes[index].textLayout
    let result = content.layout(width: nodes[index].region.width, color: nodes[index].foregroundColor)
    let layout = content.textLayout(result, in: nodes[index].region)
    let selectionEnd = nodes[index].selection.upperBound
    let preservesSelection =
      previous.map {
        $0.text.prefix(selectionEnd).unicodeScalars.elementsEqual(layout.text.prefix(selectionEnd).unicodeScalars)
          && layout.text.count >= selectionEnd
      } ?? false
    if !preservesSelection {
      nodes[index].selectionAnchor = 0
      nodes[index].selectionCursor = 0
    }
    if !content.selectable {
      nodes[index].selectionAnchor = 0
      nodes[index].selectionCursor = 0
      if focused == handle(index) { focused = nil }
      if pressed == handle(index) { pressed = nil }
    }
    nodes[index].textLayout = layout
  }
}
