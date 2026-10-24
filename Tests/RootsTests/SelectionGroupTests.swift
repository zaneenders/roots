import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct SelectionGroupTests {
  private func content() -> some Block {
    Column(in: Region(0, 0, 100, 160), gap: 10) {
      Text("first")
        .size(10)
        .selectable(key: 1)
      Paragraph {
        Text("second ")
        Text("line")
          .color(.accent)
      }
      .size(10)
      .selectable(key: 2)
      Text("third")
        .size(10)
        .selectable(key: 3)
    }
    .textSelectionGroup(key: 100)
  }

  @Test func draggingAcrossTextAndParagraphPaintsAndCopiesTheWholeRange() {
    var host = UIHost()
    var copied: String?
    for input in [
      Input(mousePosition: .init(x: 6, y: 5), pressed: true),
      Input(mousePosition: .init(x: 12, y: 53), released: true)
    ] {
      host.frame(input: input, build: { content() }, present: { _ in })
    }
    #expect(host.selectedText == "irst\nsecond line\nth")
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]),
      onCopy: { copied = $0 }, build: { content() },
      present: { batch in
        var selections = 0
        for draw in batch where draw.color == Color(0.28, 0.24, 0.42) { selections += 1 }
        #expect(selections == 3)
      })
    #expect(copied == "irst\nsecond line\nth")
  }

  @Test func reverseDragUsesDocumentOrder() {
    var host = UIHost()
    host.frame(
      input: Input(mousePosition: .init(x: 12, y: 53), pressed: true), build: { content() },
      present: { _ in })
    host.frame(
      input: Input(mousePosition: .init(x: 6, y: 5), released: true), build: { content() },
      present: { _ in })
    #expect(host.selectedText == "irst\nsecond line\nth")
  }

  @Test func selectAllFromAnyMemberIncludesOnlyThatGroup() {
    var host = UIHost()
    for key: UInt64 in [1, 2, 3] {
      host.frame(
        input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
        build: {
          content()
          Column(in: Region(200, 0, 100, 100)) {
            Text("outside").selectable(key: 4)
          }
          Focus(key: key)
        }, present: { _ in })
      #expect(host.selectedText == "first\nsecond line\nthird")
    }
  }

  @Test func keyboardExtensionCrossesNodeBoundariesAndEscapeClearsEverything() {
    var host = UIHost()
    host.frame(
      input: Input(mousePosition: .init(x: 30, y: 5), pressed: true, released: true),
      build: { content() }, present: { _ in })
    host.frame(
      input: Input(keyEvents: [
        KeyEvent(.right, modifiers: .shift), KeyEvent(.right, modifiers: .shift)
      ]), build: { content() }, present: { _ in })
    #expect(host.selectedText == "\ns")
    host.frame(
      input: Input(keyEvents: [KeyEvent(.escape)]), build: { content() },
      present: { batch in
        for draw in batch { #expect(draw.color != Color(0.28, 0.24, 0.42)) }
      })
    #expect(host.selectedText == nil)
  }

  @Test func resizeAndStreamingAppendPreserveSelectedPrefix() {
    var host = UIHost()
    for (width, value): (Float, String) in [(100, "second line"), (34, "second line appended")] {
      host.frame(
        input: width == 100 ? Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]) : Input(),
        build: {
          Column(in: Region(0, 0, width, 200)) {
            Text("first").size(10).selectable(key: 1)
            Paragraph { Text(value) }.size(10).selectable(key: 2)
          }
          .textSelectionGroup(key: 100)
          Focus(key: 1)
        }, present: { _ in })
      #expect(host.selectedText == "first\nsecond line")
    }
  }

  @Test func changingSelectedTextOrRemovingGroupClearsTheSelection() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        content()
        Focus(key: 1)
      }, present: { _ in })
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Text("changed").selectable(key: 1)
        }.textSelectionGroup(key: 100)
      }, present: { _ in })
    #expect(host.selectedText == nil)
    host.frame(build: {}, present: { _ in })
    #expect(host.selectedText == nil)
  }

  @Test func buttonsAndUnselectableTextAreExcludedAndStillWork() {
    var host = UIHost()
    var clicks = 0
    func build() -> some Block {
      Column(in: Region(0, 0, 120, 200), gap: 0) {
        Text("first").size(10).selectable(key: 1)
        Button(key: 9, "Copy", extent: 40) { clicks += 1 }
        Text("not selectable").size(10)
        Text("last").size(10).selectable(key: 2)
      }.textSelectionGroup(key: 100)
    }
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        build()
        Focus(key: 1)
      }, present: { _ in })
    #expect(host.selectedText == "first\nlast")
    host.frame(
      input: Input(mousePosition: .init(x: 10, y: 25), pressed: true), build: { build() },
      present: { _ in })
    host.frame(
      input: Input(mousePosition: .init(x: 10, y: 25), released: true), build: { build() },
      present: { _ in })
    #expect(clicks == 1)
    #expect(host.selectedText == nil)
  }

  @Test func draggingBeyondTheViewportAutoscrollsAcrossMembers() {
    var host = UIHost()
    func build() -> some Block {
      Scroll(key: 50, in: Region(0, 0, 100, 40)) {
        Column(gap: 0) {
          Column(gap: 10) {
            ForEach(0..<10) { index in
              Text("row\(index)").size(10).selectable(key: UInt64(index + 1))
            }
          }.textSelectionGroup(key: 100)
        }
      }
    }
    host.frame(
      input: Input(mousePosition: .init(x: 0, y: 5), pressed: true), build: { build() },
      present: { _ in })
    for _ in 0..<5 {
      host.frame(
        input: Input(mousePosition: .init(x: 24, y: 80)), dt: 0.1, build: { build() },
        present: { _ in })
    }
    #expect(host.state(for: 50)!.scrollOffset > 0)
    #expect(host.selectedText?.contains("row3") == true)
  }

  @Test func nestedGroupsStayIndependent() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 100, 200)) {
          Text("outer").selectable(key: 1)
          TextSelectionGroup(key: 200) {
            Text("inner").selectable(key: 2)
          }
          Text("end").selectable(key: 3)
        }.textSelectionGroup(key: 100)
        Focus(key: 2)
      }, present: { _ in })
    #expect(host.selectedText == "inner")
  }
  @Test func removingTheScopeDoesNotLeaveALocalSelectionBehind() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        content()
        Focus(key: 1)
      }, present: { _ in })
    #expect(host.selectedText != nil)
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Text("first").size(10).selectable(key: 1)
        }
      }, present: { _ in })
    #expect(host.selectedText == nil)
  }

  @Test func platformShortcutCopiesUnicodeAndExplicitNewlines() {
    var host = UIHost()
    var copied: String?
    host.frame(
      input: Input(keyEvents: [
        KeyEvent(.character("a"), modifiers: .super),
        KeyEvent(.character("c"), modifiers: .super)
      ]), primaryShortcut: .super, onCopy: { copied = $0 },
      build: {
        TextSelectionGroup(key: 100) {
          Column(in: Region(0, 0, 100, 200)) {
            Text("café e\u{301}").size(10).selectable(key: 1)
            Paragraph { Text("👩‍💻\nlast") }.size(10).selectable(key: 2)
          }
        }
        Focus(key: 1)
      }, present: { _ in })
    #expect(copied?.utf8.elementsEqual("café e\u{301}\n👩‍💻\nlast".utf8) == true)
  }

}
