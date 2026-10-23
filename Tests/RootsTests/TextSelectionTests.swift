import Testing

@testable import Roots

struct TextSelectionTests {
  private let font = MonospaceFont(size: 20)

  @Test func draggingAcrossStyledLinesCopiesGraphemesAndLineBreaks() {
    var ui = UIStore()
    var copies: [String] = []
    func build(_ frame: inout UIFrame) {
      frame.beginColumn(in: Region(10, 20, 300, 120))
      frame.text(
        key: 1,
        lines: [
          TextLine([TextRun("café "), TextRun("👩‍💻", color: .accent)], y: 4, size: font.size),
          TextLine([TextRun("next")], y: 36, size: font.size)
        ], extent: 120)
      frame.end()
    }
    ui.frame(
      input: Input(x: 22 + font.advance, y: 26, pressed: true), build: build, present: { _ in })
    ui.frame(input: Input(x: 22 + 2 * font.advance, y: 60), build: build, present: { _ in })
    ui.frame(
      input: Input(x: 22 + 2 * font.advance, y: 60, released: true), build: build, present: { _ in }
    )
    #expect(ui.selectedText == "afé 👩‍💻\nne")
    ui.frame(
      input: Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]),
      onCopy: { copies.append($0) }, build: build, present: { _ in })
    #expect(copies == ["afé 👩‍💻\nne"])
    ui.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: build, present: { _ in })
    #expect(ui.selectedText == "café 👩‍💻\nnext")
    ui.frame(input: Input(keyEvents: [KeyEvent(.escape)]), build: build, present: { _ in })
    #expect(ui.selectedText == nil)
  }

  @Test func reverseDragAndKeyboardExtensionRespectSelectionBounds() {
    var ui = UIStore()
    func build(_ frame: inout UIFrame) {
      frame.beginColumn(in: Region(0, 0, 200, 40))
      frame.label(key: 1, "abcd", extent: 40, font: font)
      frame.end()
    }
    ui.frame(input: Input(x: 60, y: 20, pressed: true), build: build, present: { _ in })
    ui.frame(input: Input(x: 24, y: 20, released: true), build: build, present: { _ in })
    #expect(ui.selectedText == "bcd")
    ui.frame(
      input: Input(keyEvents: [KeyEvent(.left, modifiers: .shift)]), build: build, present: { _ in }
    )
    #expect(ui.selectedText == "abcd")
    ui.frame(input: Input(keyEvents: [KeyEvent(.right)]), build: build, present: { _ in })
    #expect(ui.selectedText == nil)
  }

  @Test func clippedTextUsesScrolledCoordinatesAndDoesNotRevealOnCopy() {
    var ui = UIStore()
    var offset: Float = 32
    func build(_ frame: inout UIFrame) {
      let scroll = frame.beginScrollColumn(key: 1, in: Region(0, 10, 200, 60), gap: 0)
      frame.text(
        key: 2,
        lines: (0..<10).map {
          TextLine([TextRun("line\($0)")], y: Float($0) * 32, size: font.size)
        }, extent: 320)
      frame.end()
      frame.scrollTo(offset, in: scroll)
    }
    ui.frame(
      input: Input(x: 12, y: 5, pressed: true, released: true), build: build, present: { _ in })
    #expect(ui.state(for: ui.handle(for: 2)!)?.focused == false)
    ui.frame(input: Input(x: 12, y: 15, pressed: true), build: build, present: { _ in })
    ui.frame(input: Input(x: 72, y: 15, released: true), build: build, present: { _ in })
    #expect(ui.selectedText == "line1")
    offset = 64
    ui.frame(
      input: Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]),
      build: build,
      present: { draws in
        for draw in draws where draw.glyphUV != nil {
          #expect(draw.clip == Region(0, 10, 200, 60))
        }
      })
    #expect(ui.selectedText == "line1")
    #expect(ui.state(for: ui.handle(for: 1)!)?.scrollOffset == 64)
  }

  @Test func dragBeyondViewportAutoscrollsAndKeepsCapture() {
    var ui = UIStore()
    func build(_ frame: inout UIFrame) {
      frame.beginScrollColumn(key: 1, in: Region(0, 0, 200, 64), gap: 0)
      frame.text(
        key: 2,
        lines: (0..<20).map {
          TextLine([TextRun("row\($0)")], y: Float($0) * 32, size: font.size)
        }, extent: 640)
      frame.end()
    }
    ui.frame(input: Input(x: 12, y: 5, pressed: true), build: build, present: { _ in })
    for _ in 0..<5 {
      ui.frame(input: Input(x: 72, y: 100), dt: 0.1, build: build, present: { _ in })
    }
    #expect(ui.state(for: ui.handle(for: 1)!)!.scrollOffset > 0)
    #expect(ui.needsAnimationFrame == true)
    #expect(ui.selectedText?.contains("row3") == true)
    ui.frame(input: Input(x: 72, y: 100, released: true), build: build, present: { _ in })
    #expect(ui.needsAnimationFrame == false)
    let selection = ui.selectedText
    ui.frame(input: Input(x: 12, y: 5), build: build, present: { _ in })
    #expect(ui.selectedText == selection)
  }

  @Test func textDoesNotAddTabStopsOrMakeButtonsAndCanvasesSelectable() {
    var ui = UIStore()
    var clicks = 0
    func build(_ frame: inout UIFrame) {
      frame.beginColumn(in: Region(0, 0, 200, 200), gap: 0)
      frame.button(key: 1, "Button", extent: 40, onClick: { clicks += 1 })
      frame.label(key: 2, "Selectable", extent: 40)
      frame.button(key: 3, "Next", extent: 40)
      frame.canvas(key: 4, extent: 40) { painter in
        painter.drawText("Button overlay", x: 12, y: 125)
      }
      frame.label(key: 5, "Opt out", extent: 40, selectable: false)
      frame.end()
    }
    ui.frame(
      input: Input(keyEvents: [KeyEvent(.tab), KeyEvent(.tab)]), build: build, present: { _ in })
    #expect(ui.state(for: ui.handle(for: 3)!)?.focused == true)
    ui.frame(input: Input(x: 12, y: 20, pressed: true), build: build, present: { _ in })
    ui.frame(
      input: Input(
        x: 60, y: 20, released: true,
        keyEvents: [KeyEvent(.character("a"), modifiers: .control)]), build: build,
      present: { _ in })
    #expect(clicks == 1)
    #expect(ui.selectedText == nil)
    for y: Float in [140, 180] {
      ui.frame(
        input: Input(
          x: 12, y: y, pressed: true, released: true,
          keyEvents: [KeyEvent(.character("a"), modifiers: .control)]), build: build,
        present: { _ in })
      #expect(ui.selectedText == nil)
    }
  }

  @Test func replacementRemovalAndReuseClearSelectionButStreamingAppendKeepsIt() {
    var ui = UIStore()
    var text = "hello"
    var shown = true
    func build(_ frame: inout UIFrame) {
      guard shown else { return }
      frame.beginColumn(in: Region(0, 0, 200, 40))
      frame.label(key: 1, text, extent: 40)
      frame.end()
    }
    ui.frame(
      input: Input(
        x: 12, y: 20, pressed: true, released: true,
        keyEvents: [KeyEvent(.character("a"), modifiers: .control)]), build: build,
      present: { _ in })
    #expect(ui.selectedText == "hello")
    text += " world"
    ui.frame(build: build, present: { _ in })
    #expect(ui.selectedText == "hello")
    text = "replacement"
    ui.frame(build: build, present: { _ in })
    #expect(ui.selectedText == nil)
    ui.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]), build: build,
      present: { _ in })
    shown = false
    ui.frame(build: build, present: { _ in })
    shown = true
    ui.frame(build: build, present: { _ in })
    #expect(ui.selectedText == nil)
  }

  @Test func retainedTextLinesReuseSelectionLayoutButRefreshMutations() throws {
    var storage = UIStorage(nodeCapacity: 1, drawCapacity: nil)
    var content = [TextLine([TextRun("hello", color: .text)], y: 0, size: font.size)]
    storage.epoch = 1
    let handle = storage.declare(
      key: 1, title: "", region: Region(0, 0, 200, 40), color: .panel, textLines: content)
    let initial = try #require(storage.nodes[handle.slot].textLayout)
    storage.focused = handle
    storage.nodes[handle.slot].selectionCursor = 5

    storage.epoch += 1
    _ = storage.declare(
      key: 1, title: "", region: Region(0, -20, 200, 40), color: .panel, textLines: content)
    let reused = try #require(storage.nodes[handle.slot].textLayout)
    #expect(reused.lines.isTriviallyIdentical(to: initial.lines))
    #expect(storage.selectedText == "hello")

    content[0].runs[0].color = .accent
    content[0].x = 20
    storage.epoch += 1
    _ = storage.declare(
      key: 1, title: "", region: Region(0, 0, 200, 40), color: .panel, textLines: content)
    let changed = try #require(storage.nodes[handle.slot].textLayout)
    #expect(!changed.lines.isTriviallyIdentical(to: initial.lines))
    #expect(changed.lines[0].content.runs[0].color == .accent)
    #expect(changed.lines[0].content.x == 20)
    #expect(storage.selectedText == "hello")
    #expect(initial.lines[0].content.runs[0].color == .text)

    content[0].runs[0].text += " world"
    storage.epoch += 1
    _ = storage.declare(
      key: 1, title: "", region: Region(0, 0, 200, 40), color: .panel, textLines: content)
    #expect(storage.nodes[handle.slot].textLayout?.text == "hello world")
    #expect(storage.selectedText == "hello")

    content[0].runs[0].text = "replacement"
    storage.epoch += 1
    _ = storage.declare(
      key: 1, title: "", region: Region(0, 0, 200, 40), color: .panel, textLines: content)
    #expect(storage.selectedText == nil)
    storage.epoch += 1
    _ = storage.declare(key: 1, title: "button", region: Region(0, 0, 200, 40), color: .panel)
    #expect(storage.nodes[handle.slot].textLayout == nil)
    #expect(storage.focused == nil)
  }

  @Test func elementsReceiveCapturedLocalPointerCoordinates() {
    var ui = UIStore()
    var events: [PointerEvent] = []
    func build(_ frame: inout UIFrame) {
      frame.beginColumn(in: Region(10, 20, 200, 40))
      frame.element(key: 1, extent: 40, onPointer: { events.append($0) }, paint: { _ in })
      frame.end()
    }
    ui.frame(input: Input(x: 30, y: 25, pressed: true), build: build, present: { _ in })
    ui.frame(input: Input(x: 300, y: 80), build: build, present: { _ in })
    ui.frame(input: Input(x: 300, y: 80, released: true), build: build, present: { _ in })
    ui.frame(input: Input(x: 50, y: 40), build: build, present: { _ in })
    #expect(events.map(\.phase) == [.pressed, .dragged, .released])
    #expect(events.map(\.x) == [20, 290, 290])
    #expect(events.map(\.y) == [5, 60, 60])
  }
}

@Test func wideEmojiHitTestingAndHighlightUseColumnsNotGraphemeCounts() {
  let font = MonospaceFont(size: 20)
  let layout = TextLayout([TextLine([TextRun("A🙂B")], y: 0, size: font.size)])
  #expect(layout.lines[0].columns == [0, 1, 3, 4])
  #expect(layout.offset(x: 12 + 13, y: 4) == 1)
  #expect(layout.offset(x: 12 + 23, y: 4) == 1)
  #expect(layout.offset(x: 12 + 25, y: 4) == 2)
  #expect(layout.offset(x: 12 + 36, y: 4) == 2)
  #expect(layout.offset(x: 12 + 48, y: 4) == 3)
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 0, 200, 50))
    frame.text(key: 1, lines: [TextLine([TextRun("A🙂B")], y: 0, size: font.size)], extent: 50)
    frame.end()
  }
  ui.frame(input: Input(x: 24, y: 10, pressed: true), build: build, present: { _ in })
  ui.frame(input: Input(x: 48, y: 10, released: true), build: build) { draws in
    let highlights = (0..<draws.count).map { draws[$0] }.filter {
      $0.color == Color(0.28, 0.24, 0.42)
    }
    #expect(highlights.count == 1)
    #expect(highlights.first?.region == Region(24, 0, 24, font.lineHeight))
  }
  #expect(ui.selectedText == "🙂")
}
