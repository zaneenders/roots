import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct LineBreakTests {
  @Test(arguments: ["\n", "\r\n", "\r"])
  func measurementAndTruncationUseLogicalLines(separator: String) {
    let font = MonospaceFont(size: 10)
    let text = "AB\(separator)\(separator)C\(separator)"
    #expect(font.width(of: text) == 12)
    #expect(font.height(of: text) == 62)
    var style = PlainTextStyle()
    style.font = font
    #expect(style.size(of: text) == SIMD2(16, 62))
    let lines = style.lines(for: text, in: Region(0, 0, 100, 100), color: .text)
    #expect(lines.map { $0.runs[0].text } == ["AB", "", "C", ""])
    #expect(lines.map(\.y) == [0, 16, 32, 48])
    #expect(font.truncating("ABCDEF\(separator)GHIJK", to: 22) == "AB…\(separator)GH…")
  }

  @Test(arguments: ["AB\r\n\r\nC\r\n", "AB\r\rC\r", "AB\r\n\rC\n"])
  func textAndCanvasDrawTheSameGlyphsAsLF(text: String) {
    var host = UIHost()
    var expected: [Region] = []
    for mode in 0..<4 {
      var glyphs: [Region] = []
      host.frame(
        build: {
          Column(in: Region(0, 0, 100, 100), gap: 0) {
            if mode == 0 {
              Text("AB\n\nC\n").size(10)
            } else if mode == 1 {
              Text(text).size(10)
            } else if mode == 2 {
              Text(text).size(10).selectable(key: 1)
            } else {
              Canvas(key: 2, extent: 100) { painter in
                painter.drawText(text, x: 0, y: 0, size: 10, color: .text)
              }
            }
          }
        },
        present: { batch in
          for draw in batch.rectangles where draw.glyphUV != nil { glyphs.append(draw.region) }
        })
      if mode == 0 { expected = glyphs }
      #expect(glyphs == expected)
      #expect(glyphs.count == 3)
    }
  }

  @Test(arguments: ["\n", "\r\n", "\r"])
  func selectionAndCopyFollowDisplayedLines(separator: String) {
    var host = UIHost()
    var copied: String?
    func render(_ input: Input) {
      host.frame(
        input: input, onCopy: { copied = $0 },
        build: {
          Column(in: Region(0, 0, 200, 100)) {
            Text("AB\(separator)C").size(10).selectable(key: 1)
          }
        }, present: { _ in })
    }
    render(Input(mousePosition: .init(x: 0, y: 17), pressed: true))
    render(Input(mousePosition: .init(x: 6, y: 17), released: true))
    #expect(host.selectedText == "C")
    render(Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    render(Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]))
    #expect(copied == "AB\nC")
  }

  @Test(arguments: ["\n", "\r\n", "\r"])
  func selectableLabelsAndButtonsUseTheSameMultilineGeometry(separator: String) {
    var store = UIStore()
    var expected: [Region] = []
    for mode in 0..<3 {
      var glyphs: [Region] = []
      store.frame(
        build: { frame in
          frame.beginColumn(in: Region(0, 0, 100, 80))
          if mode == 2 {
            frame.label(key: 1, "AB\(separator)C", extent: 80, font: MonospaceFont(size: 10))
          } else {
            frame.button(
              key: 1, mode == 0 ? "AB\nC" : "AB\(separator)C", extent: 80,
              font: MonospaceFont(size: 10))
          }
          frame.end()
        },
        present: { batch in
          for draw in batch.rectangles where draw.glyphUV != nil { glyphs.append(draw.region) }
        })
      if mode == 0 { expected = glyphs }
      #expect(glyphs == expected)
      #expect(glyphs.count == 3)
    }
  }
}
