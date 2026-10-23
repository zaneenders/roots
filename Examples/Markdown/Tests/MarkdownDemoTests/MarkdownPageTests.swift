@_spi(Hosting) import Roots
import Testing

@testable import MarkdownDemo

@MainActor
struct MarkdownPageTests {
  @Test func narrowerWindowsReflowAndScrollWithoutClippingTheDocument() throws {
    var host = UIHost()
    var wideHeight: Float = 0
    for width: Float in [940, 480] {
      host.frame(
        build: { MarkdownPage(bounds: Region(0, 0, width, 1080)) },
        present: { batch in
          #expect(batch.count > 100)
          #expect(batch[0].region == Region(0, 0, width, 1080))
          #expect(batch[0].color == Ink.page)
        })
      let introduction = try #require(host.state(for: 3)?.region)
      let code = try #require(host.state(for: 20)?.region)
      let footer = try #require(host.state(for: 21)?.region)
      #expect(introduction.width == width - 64)
      #expect(code.y + code.height < footer.y)
      if width == 940 { wideHeight = introduction.height } else { #expect(introduction.height > wideHeight) }
    }
  }

  @Test func selectAllCopiesTheDocumentWithoutVisualWrapBreaks() {
    var host = UIHost()
    var copied: String?
    host.frame(
      input: Input(keyEvents: [
        KeyEvent(.character("a"), modifiers: .control),
        KeyEvent(.character("c"), modifiers: .control)
      ]),
      onCopy: { copied = $0 },
      build: {
        MarkdownPage(bounds: Region(0, 0, 480, 800))
        FocusBlock(key: 3)
      }, present: { _ in })
    #expect(copied?.hasPrefix("ROOTS / TEXT PLAYGROUND\nA small document, made of text.\n") == true)
    #expect(copied?.contains("This page is composed with Paragraph and ordinary Text children.") == true)
    #expect(copied?.contains(MarkdownPage.code) == true)
    #expect(copied?.contains("Copy code") == false)
    #expect(copied?.contains("not implemented here.") == true)
  }

  @Test func draggingFromTheHeadingToTheFooterSelectsTheDocument() throws {
    var host = UIHost()
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          MarkdownPage(bounds: Region(0, 0, 940, 1080))
        }, present: { _ in })
    }
    render()
    let heading = try #require(host.state(for: 30)?.region)
    let footer = try #require(host.state(for: 21)?.region)
    render(Input(x: heading.x, y: heading.y + 2, pressed: true))
    render(Input(x: footer.x + footer.width, y: footer.y + footer.height - 2, released: true))
    #expect(host.selectedText?.hasPrefix("ROOTS / TEXT PLAYGROUND\n") == true)
    #expect(host.selectedText?.contains(MarkdownPage.code) == true)
    #expect(host.selectedText?.hasSuffix("not implemented here.") == true)
  }

  @Test func draggingWithinCodeKeepsIndentationAndNewlines() throws {
    var host = UIHost()
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          MarkdownPage(bounds: Region(0, 0, 940, 1080))
        }, present: { _ in })
    }
    render()
    let code = try #require(host.state(for: 20)?.region)
    render(Input(x: code.x, y: code.y + 2, pressed: true))
    render(Input(x: code.x + code.width, y: code.y + code.height - 2, released: true))
    #expect(host.selectedText == MarkdownPage.code)
  }

  @Test(arguments: [
    (UInt64(30), "ROOTS / TEXT PLAYGROUND"),
    (UInt64(31), "01 / Inline styling"),
    (UInt64(32), "02 / A short list"),
    (UInt64(33), "03 / Code, without Markdown parsing"),
    (UInt64(34), "SWIFT")
  ])
  func headingsAndCaptionsAreSelectable(key: UInt64, expected: String) {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        MarkdownPage(bounds: Region(0, 0, 940, 1080))
        FocusBlock(key: key, reveal: true)
      }, present: { _ in })
    #expect(host.selectedText?.hasPrefix("ROOTS / TEXT PLAYGROUND\n") == true)
    #expect(host.selectedText?.contains(expected) == true)
  }

  @Test func codeCopyButtonCopiesExactSourceAtNarrowAndWideWidths() throws {
    for width: Float in [480, 940] {
      var host = UIHost()
      var copied: [String] = []
      func render(_ input: Input = Input()) {
        host.frame(
          input: input, dt: 0,
          build: {
            MarkdownPage(bounds: Region(0, 0, width, 1080), copyCode: { copied.append($0) })
            FocusBlock(key: 35, reveal: true)
          }, present: { _ in })
      }
      render()
      let button = try #require(host.state(for: 35)?.region)
      let caption = try #require(host.state(for: 34)?.region)
      #expect(button.width == 108)
      #expect(caption.x + caption.width <= button.x)
      #expect(button.x + button.width <= width - 32)
      #expect(host.selectedText == nil)
      render(Input(x: button.center.x, y: button.center.y, pressed: true))
      render(Input(x: button.center.x, y: button.center.y, released: true))
      render(Input(keyEvents: [KeyEvent(.enter)]))
      #expect(copied.count == 2)
      #expect(copied.allSatisfy { $0.utf8.elementsEqual(MarkdownPage.code.utf8) })
    }
  }

}
