import Observation
import Synchronization
import Testing

@_spi(Hosting) @testable import Roots

@MainActor @Observable
private final class ParagraphModel { var text = "before" }

@MainActor
struct ParagraphTests {
  @Test func wrapsAcrossRunsAndSizesFollowingSiblings() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 34, 100), gap: 3) {
          Paragraph {
            Text("hello ")
            Text("world").color(.accent)
          }
          .size(10)
          .selectable(key: 1)
          Canvas(key: 2, extent: 10) { _ in }
        }
      },
      present: { batch in
        #expect(batch[0].region == Region(0, 0, 10, 14))
        #expect(batch[5].region == Region(0, 16, 10, 14))
        #expect(batch[5].color == .accent)
      })
    #expect(host.state(for: 1)?.region == Region(0, 0, 34, 30))
    #expect(host.state(for: 2)?.region == Region(0, 33, 34, 10))
  }

  @Test func wordsCrossStyleBoundariesAndLongWordsSplit() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 34, 100), gap: 0) {
          Paragraph {
            Text("ab ")
            Text("cd").color(.accent)
            Text("ef")
          }.size(10).selectable(key: 1)
        }
      },
      present: { batch in
        #expect(batch[2].region == Region(0, 16, 10, 14))
        #expect(batch[2].color == .accent)
      })
    #expect(host.state(for: 1)?.region.height == 30)
  }

  @Test func selectionCopiesOriginalTextAcrossSoftWrapsAndResize() {
    var host = UIHost()
    func render(width: Float, input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, width, 200)) {
            Paragraph {
              Text("hello ")
              Text("world").color(.accent)
            }.size(10).selectable(key: 1)
          }
          FocusBlock(key: 1)
        }, present: { _ in })
    }
    render(width: 34, input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    #expect(host.selectedText == "hello world")
    render(width: 100)
    #expect(host.selectedText == "hello world")
    #expect(host.state(for: 1)?.region.height == 14)
    var copied: String?
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]),
      onCopy: { copied = $0 },
      build: {
        Column(in: Region(0, 0, 34, 100)) {
          Paragraph { Text("hello world") }.size(10).selectable(key: 1)
        }
        FocusBlock(key: 1)
      }, present: { _ in })
    #expect(copied == "hello world")
  }

  @Test func mixedSizesShareTheAtlasBaselineAndInheritedColor() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Paragraph {
            Text("A")
            Text("B").size(20).color(.panel)
          }.size(10).color(.accent).selectable(key: 1)
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(abs(batch[0].region.y + MonospaceFont(size: 10).baseline - MonospaceFont(size: 20).baseline) < 0.001)
        #expect(batch[1].region.y == 0)
        #expect(batch[0].color == .accent)
        #expect(batch[1].color == .panel)
      })
    #expect(host.state(for: 1)?.region.height == 28)
  }

  @Test func explicitBreaksWhitespaceAndGraphemesSurvive() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 1, 300)) {
          Paragraph {
            Text("e")
            Text("\u{301}👩‍")
            Text("💻\r")
            Text("\nA\n\n")
          }.size(10).selectable(key: 1)
        }
        FocusBlock(key: 1)
      }, present: { _ in })
    #expect(host.selectedText == "e\u{301}👩‍💻\r\nA\n\n")
    #expect(host.state(for: 1)?.region.height == 78)
  }

  @Test func paddingBackgroundAndScrollUseWrappedHeight() {
    var host = UIHost()
    host.frame(
      build: {
        ScrollColumn(key: 10, in: Region(0, 0, 44, 20), gap: 0) {
          Paragraph { Text("hello world") }
            .size(10)
            .selectable(key: 1)
            .padding(5)
            .frame(width: .fill)
            .background(.panel)
        }
        ScrollToBlock(20, in: 10)
      },
      present: { batch in
        #expect(batch[0].region == Region(0, -20, 44, 40))
        #expect(batch[0].clip == Region(0, 0, 44, 20))
      })
    #expect(host.state(for: 1)?.region == Region(5, -15, 34, 30))
    #expect(host.state(for: 10)?.scrollOffset == 20)
  }

  @Test func defaultParagraphDoesNotInterceptPointerInput() {
    var host = UIHost()
    var clicks = 0
    for input in [Input(x: 5, y: 5, pressed: true), Input(x: 5, y: 5, released: true)] {
      host.frame(
        input: input,
        build: {
          ZStack(in: Region(0, 0, 100, 40), alignment: .topLeading) {
            Button(key: 1, "", extent: 40) { clicks += 1 }
            Paragraph { Text("hello") }.size(10)
          }
        }, present: { _ in })
    }
    #expect(clicks == 1)
  }

  @Test func builderSupportsBranchesLoopsAndEmptyContent() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Paragraph {
            if true { Text("A") }
            if false { Text("wrong") } else { Text("B") }
            for value in ["C", "D"] { Text(value) }
          }.size(10).selectable(key: 1)
          Paragraph {}.selectable(key: 2)
        }
        FocusBlock(key: 1)
      }, present: { _ in })
    #expect(host.selectedText == "ABCD")
    #expect(host.state(for: 2)?.region.height == 0)
  }

  @Test func rightAlignmentUsesEachWrappedLinesWidth() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 40, 100)) {
          Paragraph { Text("hello x") }.size(10).alignment(.trailing)
        }
      },
      present: { batch in
        #expect(batch[0].region.x == 6)
        #expect(batch[5].region.x == 30)
        #expect(batch[5].region.y == 16)
      })
  }
  @Test func pointerSelectionCrossesRunsAndSoftWraps() {
    var host = UIHost()
    var copied: String?
    func render(_ input: Input) {
      host.frame(
        input: input, onCopy: { copied = $0 },
        build: {
          Column(in: Region(0, 0, 34, 100)) {
            Paragraph {
              Text("hello ")
              Text("world").color(.accent)
            }.size(10).selectable(key: 1)
          }
        }, present: { _ in })
    }
    render(Input(x: 0, y: 5, pressed: true))
    render(Input(x: 12, y: 21, released: true))
    #expect(host.selectedText == "hello wo")
    render(Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]))
    #expect(copied == "hello wo")
  }

  @Test func heightChangesWithinRowsAndGridsWithoutMovingIndependentRoots() {
    var host = UIHost()
    for width: Float in [34, 100, 34] {
      host.frame(
        build: {
          Column(in: Region(0, 0, width, 120), gap: 4) {
            RowBlock(gap: 0) {
              Paragraph { Text("hello world") }.size(10).selectable(key: 1)
            }.frame(width: .fill)
            Canvas(key: 2, extent: 10) { _ in }
          }
          Grid(in: Region(200, 0, width * 2, 100), columns: 2, gap: 0) {
            Paragraph { Text("hello world") }.size(10).selectable(key: 3)
            Text("other")
          }
        }, present: { _ in })
      let expected: Float = width == 34 ? 30 : 14
      #expect(host.state(for: 1)?.region.height == expected)
      #expect(host.state(for: 2)?.region.y == expected + 4)
      #expect(host.state(for: 3)?.region.height == expected)
    }
  }

  @Test func reusingAKeyBetweenParagraphAndTextReplacesItsLayout() {
    var host = UIHost()
    for paragraph in [true, false, true] {
      host.frame(
        input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
        build: {
          Column(in: Region(0, 0, 34, 100)) {
            if paragraph {
              Paragraph { Text("hello world") }.size(10).selectable(key: 1)
            } else {
              Text("new").size(10).selectable(key: 1)
            }
          }
          FocusBlock(key: 1)
        }, present: { _ in })
      #expect(host.selectedText == (paragraph ? "hello world" : "new"))
    }
  }

  @Test func childExpressionsStayInsideObservationTracking() {
    let model = ParagraphModel()
    let changes = Mutex(0)
    var host = UIHost()
    withObservationTracking {
      host.frame(
        build: {
          Column(in: Region(0, 0, 100, 100)) {
            Paragraph { Text(model.text) }.size(10)
          }
        }, present: { _ in })
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    model.text = "after"
    #expect(changes.withLock { $0 } == 1)
  }

  @Test func emptyRunsAndTrailingSpacesTerminateAtZeroWidth() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 0, 100)) {
          Paragraph {
            Text("")
            Text("a   ")
            Text("")
          }.size(10).selectable(key: 1)
        }
        FocusBlock(key: 1)
      }, present: { _ in })
    #expect(host.selectedText == "a   ")
    #expect(host.state(for: 1)?.region.height == 14)
  }

  @Test func inlineBackgroundStaysAttachedAcrossWrapping() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 22, 100)) {
          Paragraph {
            Text("abc").color(.accent).background(.panel)
          }.size(10)
        }
      },
      present: { batch in
        var backgrounds: [DrawRect] = []
        var glyphs: [DrawRect] = []
        for draw in batch {
          if draw.glyphUV == nil { backgrounds.append(draw) } else { glyphs.append(draw) }
        }
        #expect(backgrounds.count == 3)
        #expect(backgrounds[2].region == Region(12, 0, 6, 14))
        #expect(glyphs.allSatisfy { $0.color == .accent })
      })
  }

  @Test func streamingAppendPreservesExistingSelection() {
    var host = UIHost()
    func render(_ value: String, input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 34, 100)) {
            Paragraph { Text(value) }.size(10).selectable(key: 1)
          }
          FocusBlock(key: 1)
        }, present: { _ in })
    }
    render("hello", input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    #expect(host.selectedText == "hello")
    render("hello world")
    #expect(host.selectedText == "hello")
    render("other world")
    #expect(host.selectedText == nil)
  }

  @Test func whitespaceJustBeyondTheEdgeDoesNotSplitAFittingWord() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Paragraph { Text("aa bb cc") }.size(10).selectable(key: 1)
            .frame(width: .fixed(34))
        }
      },
      present: { batch in
        #expect(batch[2].region == Region(18, 0, 10, 14))
        #expect(batch[3].region == Region(24, 0, 10, 14))
        #expect(batch[4].region == Region(0, 16, 10, 14))
      })
    #expect(host.state(for: 1)?.region.height == 30)
  }

}
