import Testing

@testable import Roots

struct TextLayoutPrefixTests {
  private let font = MonospaceFont(size: 20)

  @Test(arguments: [
    ["e", "\u{301}x"], ["👩", "\u{200D}", "💻x"], ["🇬", "🇧x"], ["👍", "🏽x"],
    ["1", "\u{FE0F}", "\u{20E3}x"],
  ])
  func crossRunGraphemesShareGlyphsBackgroundsAndSelection(parts: [String]) {
    let firstBackground = Color(0.3, 0.2, 0.1)
    let tailBackground = Color(0.1, 0.2, 0.3)
    var runs = [TextRun("", background: .panel)]
    for (index, part) in parts.enumerated() {
      runs.append(
        TextRun(
          part, color: index == 0 ? .accent : .text,
          background: index == 0 ? firstBackground : tailBackground))
      runs.append(TextRun("", background: .panel))
    }
    let text = parts.joined()
    let layout = TextLayout([TextLine(runs, y: 0, font: font)])
    let columns = MonospaceFont.columnWidth(of: text.first!)
    #expect(layout.lines[0].count == 2)
    #expect(layout.lines[0].column(at: 1) == columns)
    #expect(layout.offset(x: 12 + Float(columns) * font.advance, y: 1) == 1)
    var node = Node()
    node.rect = Rect(0, 0, 300, 100)
    node.selectionCursor = 1
    var painted = UIStorage(nodeCapacity: 0, drawCapacity: nil)
    painted.paintText(layout, node: node, selected: true)
    var reference = UIStorage(nodeCapacity: 0, drawCapacity: nil)
    reference.drawText(text, x: 12, y: 0, font: font, color: .text, clip: node.rect)
    var glyphs: [DrawRect] = []
    var backgrounds: [DrawRect] = []
    for draw in painted.draws {
      if draw.glyphUV != nil { glyphs.append(draw) } else { backgrounds.append(draw) }
    }
    #expect(glyphs.count == 2)
    #expect(glyphs.count == reference.draws.count)
    for (index, glyph) in glyphs.prefix(reference.draws.count).enumerated() {
      let expected = reference.draws[index]
      #expect(glyph.rect == expected.rect)
      #expect(glyph.glyphUV == expected.glyphUV)
      #expect(glyph.colorGlyph == expected.colorGlyph)
    }
    #expect(glyphs.first?.color == .accent)
    #expect(glyphs.last?.color == .text)
    let firstCell = Rect(12, 0, Float(columns) * font.advance, font.lineHeight)
    let tailCell = Rect(firstCell.x + firstCell.width, 0, font.advance, font.lineHeight)
    #expect(backgrounds.map(\.rect) == [firstCell, tailCell, firstCell])
    #expect(backgrounds.map(\.color) == [firstBackground, tailBackground, Color(0.28, 0.24, 0.42)])
  }

  @Test func alignedStylesKeepTheirRunStorage() {
    let content = [TextLine([TextRun("café "), TextRun("👩‍💻x", color: .accent)], y: 0)]
    let layout = TextLayout(content)
    #expect(layout.lines[0].paintRuns.isTriviallyIdentical(to: content[0].runs))
  }

  @Test func incrementalLayoutsRetainOffsetsAndMatchFreshLayout() {
    var content = [
      TextLine([TextRun("First message café")], y: 0, font: font),
      TextLine([], y: 32, font: font),
      TextLine(
        [
          TextRun("Second "), TextRun("e", color: .accent), TextRun("\u{301} 👩"),
          TextRun("\u{200D}💻"),
        ], y: 64,
        font: font),
      TextLine([TextRun("tail")], y: 96, font: font),
    ]
    var layout = TextLayout(content)
    let original = layout
    #expect(layout.lines[2].count == "Second e\u{301} 👩‍💻".count)
    #expect(layout.update(content).reusedLineCount == 4)
    #expect(layout.lines.isTriviallyIdentical(to: original.lines))
    for tail in ["tail continues", "tail replacement", "é", "e\u{301}", ""] {
      content[3].runs[0].text = tail
      #expect(layout.update(content).reusedLineCount == 3)
      expectFresh(layout, content: content)
      #expect(original.text == "First message café\n\nSecond e\u{301} 👩‍💻\ntail")
    }
    content.append(TextLine([TextRun("new message")], y: 128, font: font))
    #expect(layout.update(content).reusedLineCount == 4)
    expectFresh(layout, content: content)
    content.removeLast(2)
    #expect(layout.update(content).reusedLineCount == 3)
    expectFresh(layout, content: content)
    content[0].runs[0].text = "Earlier edit"
    #expect(layout.update(content).reusedLineCount == 0)
    expectFresh(layout, content: content)
    #expect(layout.update([]).reusedLineCount == 0)
    expectFresh(layout, content: [])
  }

  @Test func styleGeometryAndRunChangesRefreshContentWithoutDiscardingValidSelections() {
    var content = [
      TextLine([TextRun("first")], y: 0, font: font),
      TextLine([TextRun("second")], y: 32, font: font),
    ]
    var layout = TextLayout(content)
    content[1].x = 24
    content[1].y = 40
    content[1].font = MonospaceFont(size: 24)
    content[1].background = .panel
    content[1].runs = [TextRun("sec", color: .accent, background: .panel), TextRun("ond")]
    let update = layout.update(content, selectionEnd: layout.text.count)
    #expect(update.reusedLineCount == 1)
    #expect(update.preservesSelection)
    expectFresh(layout, content: content)
    content[0].runs[0].text = "first!"
    #expect(!layout.update(content, selectionEnd: 8).preservesSelection)
    expectFresh(layout, content: content)
  }

  @Test func graphemeExtensionsAndCanonicalRewritesCannotRetainStaleSelectionOffsets() {
    for (before, after) in [("e", "e\u{301}"), ("👩", "👩‍💻"), ("🇬", "🇬🇧"), ("é", "e\u{301}")] {
      var content = [TextLine([TextRun("prefix")], y: 0), TextLine([TextRun(before)], y: 32)]
      var layout = TextLayout(content)
      let oldCount = layout.text.count
      content[1].runs = [TextRun(after)]
      let update = layout.update(content, selectionEnd: oldCount)
      #expect(update.reusedLineCount == 1)
      #expect(!update.preservesSelection)
      expectFresh(layout, content: content)
    }
  }

  @Test func carriageReturnAndLineSeparatorFormOneGraphemeAcrossTheBoundary() {
    var content = [TextLine([TextRun("a\r")], y: 0)]
    var layout = TextLayout(content)
    content.append(TextLine([TextRun("b")], y: 32))
    let update = layout.update(content, selectionEnd: 2)
    #expect(update.reusedLineCount == 0)
    #expect(!update.preservesSelection)
    #expect(layout.text == "a\r\nb")
    #expect(layout.lines[1].start == 2)
    #expect(layout.lines.last!.start + layout.lines.last!.count == layout.text.count)
    expectFresh(layout, content: content)
    content[1].runs[0].text += "c"
    #expect(layout.update(content, selectionEnd: 3).preservesSelection)
    expectFresh(layout, content: content)
    content.removeLast()
    #expect(!layout.update(content, selectionEnd: 3).preservesSelection)
    expectFresh(layout, content: content)
  }

  @Test func selectionAfterCRLFHighlightsOnlyItsOwnLineAndCopiesItsGrapheme() {
    var ui = UIStore()
    var copies: [String] = []
    var highlights: [Rect] = []
    func build(_ frame: inout UIFrame) {
      frame.beginColumn(in: Rect(0, 0, 300, 100))
      frame.text(
        key: 1,
        lines: [
          TextLine([TextRun("a\r")], y: 0, font: font),
          TextLine([TextRun("b")], y: 32, font: font),
        ], extent: 100)
      frame.end()
    }
    ui.frame(input: Input(x: 12, y: 33, pressed: true), build: build, present: { _ in })
    ui.frame(
      input: Input(
        x: 12 + font.advance, y: 33, released: true,
        keyEvents: [KeyEvent(.character("c"), modifiers: .control)]),
      onCopy: { copies.append($0) }, build: build,
      present: { draws in
        for draw in draws where draw.color == Color(0.28, 0.24, 0.42) && draw.glyphUV == nil {
          highlights.append(draw.rect)
        }
      })
    #expect(ui.selectedText == "b")
    #expect(copies == ["b"])
    #expect(highlights == [Rect(12, 32, font.advance, font.lineHeight)])
  }

  @Test func earlierSelectionsSurviveTailRewritesButTouchedOrOutOfBoundsSelectionsClear() throws {
    for reversed in [false, true] {
      var storage = UIStorage(nodeCapacity: 1, drawCapacity: nil)
      var content = [
        TextLine([TextRun("First")], y: 0, font: font),
        TextLine([TextRun("Second")], y: 32, font: font),
        TextLine([TextRun("tail")], y: 64, font: font),
        TextLine([], y: 96, font: font),
      ]
      func declare(_ storage: inout UIStorage) -> NodeHandle {
        storage.epoch += 1
        return storage.declare(
          key: 1, title: "", rect: Rect(0, 0, 300, 160), color: .panel, textLines: content)
      }
      let handle = declare(&storage)
      storage.focused = handle
      func select(_ storage: inout UIStorage, _ start: Int, _ end: Int) {
        storage.nodes[handle.slot].selectionAnchor = reversed ? end : start
        storage.nodes[handle.slot].selectionCursor = reversed ? start : end
      }
      select(&storage, 2, 8)
      #expect(storage.selectedText == "rst\nSe")
      content[2].runs[0].text = "rewritten later tail"
      _ = declare(&storage)
      #expect(storage.selectedText == "rst\nSe")
      content[2].runs[0].text = "short"
      _ = declare(&storage)
      #expect(storage.selectedText == "rst\nSe")
      select(&storage, 8, 15)
      content[2].runs[0].text = "changed"
      _ = declare(&storage)
      #expect(storage.selectedText == nil)
      select(&storage, 6, 8)
      content[0].runs[0].text = "Edit before selection"
      _ = declare(&storage)
      #expect(storage.selectedText == nil)
      let count = try #require(storage.nodes[handle.slot].textLayout?.text.count)
      select(&storage, count, count)
      content.removeLast(2)
      _ = declare(&storage)
      #expect(storage.nodes[handle.slot].selectionAnchor == 0)
      #expect(storage.nodes[handle.slot].selectionCursor == 0)
      select(&storage, 1, 3)
      content.removeAll()
      _ = declare(&storage)
      #expect(storage.nodes[handle.slot].textLayout == nil)
      #expect(storage.focused == nil)
      #expect(storage.selectedText == nil)
    }
  }

  private func expectFresh(_ actual: TextLayout, content: [TextLine]) {
    let fresh = TextLayout(content)
    #expect(actual.text.utf8.elementsEqual(fresh.text.utf8))
    #expect(actual.lines.count == fresh.lines.count)
    for (lhs, rhs) in zip(actual.lines, fresh.lines) {
      #expect(lhs.start == rhs.start && lhs.count == rhs.count && lhs.endUTF8 == rhs.endUTF8)
      #expect(
        lhs.content.x == rhs.content.x && lhs.content.y == rhs.content.y
          && lhs.content.font == rhs.content.font)
      #expect(lhs.content.background == rhs.content.background)
      #expect(
        lhs.paintRuns.elementsEqual(rhs.paintRuns) {
          $0.text.utf8.elementsEqual($1.text.utf8) && $0.color == $1.color
            && $0.background == $1.background
        })
      #expect(lhs.content.runs.count == rhs.content.runs.count)
      for (lhs, rhs) in zip(lhs.content.runs, rhs.content.runs) {
        #expect(lhs.text.utf8.elementsEqual(rhs.text.utf8))
        #expect(lhs.color == rhs.color && lhs.background == rhs.background)
      }
    }
    for line in fresh.lines {
      for column in [0, 1, line.count, line.count + 1] {
        let x = line.content.x + Float(column) * line.content.font.advance
        #expect(actual.offset(x: x, y: line.content.y) == fresh.offset(x: x, y: line.content.y))
      }
    }
  }
}
