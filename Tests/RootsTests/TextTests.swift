import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct TextTests {
  @Test func textDefaultsToContentSizeWithoutBackgroundOrSelection() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Text("AB").size(10)
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        for draw in batch { #expect(draw.glyphUV != nil) }
        #expect(batch[0].region == Region(0, 0, 10, 14))
        #expect(batch[1].region == Region(6, 0, 10, 14))
      })
    #expect(host.state(for: 1) == nil)
    host.frame(
      input: Input(mousePosition: .init(x: 5, y: 5), pressed: true),
      build: {
        Column(in: Region(0, 0, 100, 100)) { Text("AB").size(10) }
      }, present: { _ in })
    #expect(host.state(for: 1) == nil)
  }

  @Test func selectionUsesAlignedMultilineGeometryAndCopiesText() {
    var host = UIHost()
    var copied: String?
    func render(_ input: Input) {
      host.frame(
        input: input, onCopy: { copied = $0 },
        build: {
          ZStack(in: Region(0, 0, 100, 80)) {
            Text("AB\nC")
              .size(10)
              .alignment(.center)
              .selectable(key: 1)
              .frame(width: .fixed(40), height: .fixed(40))
          }
        }, present: { _ in })
    }
    render(Input(mousePosition: .init(x: 46, y: 48), pressed: true))
    render(Input(mousePosition: .init(x: 60, y: 48), released: true))
    #expect(host.selectedText == "C")
    render(Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    render(Input(keyEvents: [KeyEvent(.character("c"), modifiers: .control)]))
    #expect(copied == "AB\nC")
  }

  @Test func truncationUsesAvailableWidthAndSelectionCopiesDisplayedText() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Text("ABCDEF")
            .size(10)
            .selectable(key: 1)
            .overflow(.truncateTail)
            .frame(width: .fixed(22), height: .fixed(14))
        }
        FocusBlock(key: 1)
      },
      present: { batch in
        var glyphs: [DrawRect] = []
        for draw in batch where draw.glyphUV != nil { glyphs.append(draw) }
        #expect(glyphs.count == 3)
        #expect(glyphs.last?.glyphUV == FontAtlas.shared.glyphUV("…"))
        #expect(glyphs.last?.clip == Region(0, 0, 22, 14))
      })
    #expect(host.selectedText == "AB…")
  }

  @Test func selectableAndNonselectableTextHaveIdenticalGlyphs() {
    var host = UIHost()
    var expected: [DrawRect] = []
    for selectable in [false, true] {
      host.frame(
        build: {
          Column(in: Region(0, 0, 22, 50)) {
            let text = Text("ABCDEF\nZ")
              .size(10)
              .color(.accent)
              .alignment(.trailing)
              .overflow(.truncateTail)
            if selectable {
              text.selectable(key: 1)
            } else {
              text
            }
          }
        },
        present: { batch in
          var actual: [DrawRect] = []
          for draw in batch { actual.append(draw) }
          if !selectable {
            expected = actual
          } else {
            #expect(actual.count == expected.count)
            for index in actual.indices {
              #expect(actual[index].region == expected[index].region)
              #expect(actual[index].clip == expected[index].clip)
              #expect(actual[index].glyphUV == expected[index].glyphUV)
              #expect(actual[index].color == expected[index].color)
            }
          }
        })
    }
  }

  @Test func changingColorAndSizePreservesSelectionButDisablingClearsIt() {
    var host = UIHost()
    func render(selectable: Bool, size: Float, color: Color, input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 100, 100)) {
            let text = Text("ABC")
              .size(size)
              .color(color)
            if selectable {
              text.selectable(key: 1)
            } else {
              text
            }
          }
          if selectable { FocusBlock(key: 1) }
        }, present: { _ in })
    }
    render(
      selectable: true, size: 10, color: .text,
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    #expect(host.selectedText == "ABC")
    render(selectable: true, size: 12, color: .accent)
    #expect(host.selectedText == "ABC")
    render(selectable: false, size: 12, color: .accent)
    #expect(host.selectedText == nil)
    #expect(host.state(for: 1) == nil)
  }

  @Test func scrollingPreservesSelectionAndClipsText() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        ScrollColumn(key: 10, in: Region(0, 0, 100, 20), gap: 0) {
          Text("A\nB\nC").size(10).selectable(key: 1)
        }
        ScrollToBlock(16, in: 10)
        FocusBlock(key: 1)
      },
      present: { batch in
        for draw in batch { #expect(draw.clip == Region(0, 0, 10, 20)) }
      })
    #expect(host.selectedText == "A\nB\nC")
    #expect(host.state(for: 1)?.region == Region(0, -16, 10, 46))
  }

  @Test func multilineTruncationAndUnicodeSelectionUseDisplayedColumns() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 22, 80)) {
          Text("ABCDEF\n😀é")
            .size(10)
            .overflow(.truncateTail)
            .selectable(key: 1)
        }
        FocusBlock(key: 1)
      }, present: { _ in })
    #expect(host.selectedText == "AB…\n😀é")
  }

  @Test func horizontalPaddingLeavesTheFullGlyphHeightAvailable() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Text("A")
            .size(20)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(32))
            .background(.panel)
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].region == Region(0, 0, 100, 32))
        #expect(batch[1].region == Region(12, 0, 20, 28))
        #expect(batch[1].clip == Region(12, 0, 20, 28))
      })
  }

  @Test func truncatingASelectionDuringResizeClearsIt() {
    var host = UIHost()
    func render(width: Float, input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, width, 100)) {
            Text("ABCDEF")
              .size(10)
              .selectable(key: 1)
              .overflow(.truncateTail)
          }
          FocusBlock(key: 1)
        }, present: { _ in })
    }
    render(width: 100, input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    #expect(host.selectedText == "ABCDEF")
    render(width: 22)
    #expect(host.selectedText == nil)
    #expect(host.state(for: 1)?.focused == true)
  }

  @Test func selectableReturnsANewValueWithItsOwnKey() {
    let text = Text("A")
      .size(10)
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          text
          text.selectable(key: 0)
          text.selectable(key: 2)
        }
      }, present: { batch in #expect(batch.count == 3) })
    #expect(host.liveCount == 3)
    #expect(host.state(for: 0)?.region == Region(0, 22, 10, 14))
    #expect(host.state(for: 2)?.region == Region(0, 44, 10, 14))
  }

  @Test func changingSelectionKeyDoesNotTransferState() {
    var host = UIHost()
    for key: UInt64 in [1, 2] {
      host.frame(
        input: key == 1 ? Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]) : Input(),
        build: {
          Column(in: Region(0, 0, 100, 100)) {
            Text("ABC")
              .selectable(key: key)
          }
          FocusBlock(key: key)
        }, present: { _ in })
      #expect(host.selectedText == (key == 1 ? "ABC" : nil))
      #expect(host.state(for: key)?.focused == true)
    }
    #expect(host.state(for: 1) == nil)
  }
}
