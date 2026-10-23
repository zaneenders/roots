import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct ContainerLayoutTests {
  @Test func nestedContainersOccupyOneParentSlot() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(10, 20, 200, 100), gap: 5) {
          RowBlock(gap: 4) {
            Text("A").selectable(key: 1).size(10)
            Text("BB").selectable(key: 2).size(10)
          }
          Text("C").selectable(key: 3).size(10)
        }
      }, present: { _ in })
    #expect(host.state(for: 1)?.region == Region(10, 20, 10, 14))
    #expect(host.state(for: 2)?.region == Region(24, 20, 16, 14))
    #expect(host.state(for: 3)?.region == Region(10, 39, 10, 14))
  }

  @Test func fillChildrenShareRemainingSpaceAndFixedChildrenDoNotShrink() {
    var host = UIHost()
    host.frame(
      build: {
        RowBlock(in: Region(0, 0, 110, 30), gap: 5) {
          Text("A").selectable(key: 1).size(10).frame(width: .fixed(30))
          Canvas(key: 2) { _ in }
          Canvas(key: 3) { _ in }
        }
      }, present: { _ in })
    #expect(host.state(for: 2)?.region == Region(35, 0, 35, 30))
    #expect(host.state(for: 3)?.region == Region(75, 0, 35, 30))
    host.frame(
      build: {
        RowBlock(in: Region(0, 0, 25, 30), gap: 5) {
          Canvas(key: 2, extent: 30) { _ in }
          Text("AAAA").selectable(key: 3).size(10)
        }
      }, present: { _ in })
    #expect(host.state(for: 2)?.region.width == 30)
    #expect(host.state(for: 3)?.region.width == 0)
  }

  @Test func growLevelsChildrenFromTheirIntrinsicSizes() {
    var host = UIHost()
    host.frame(
      build: {
        RowBlock(in: Region(0, 0, 100, 20), gap: 0) {
          Text("A").size(10).frame(width: .fill)
          Text("AAAAAAAAAA").size(10).frame(width: .fill)
        }
      },
      present: { batch in
        var glyphs: [DrawRect] = []
        for draw in batch { glyphs.append(draw) }
        #expect(glyphs.first?.region.x == 13)
        #expect(glyphs[1].region.x == 36)
      })
  }

  @Test func gridTreatsGroupsAsOneCellAndForEachAsSeparateCells() {
    var host = UIHost()
    host.frame(
      build: {
        Grid(in: Region(10, 20, 100, 100), columns: 2, gap: 4, alignment: .topLeading) {
          Column(gap: 0) {
            Text("A").selectable(key: 1).size(10)
            Text("B").selectable(key: 2).size(10)
          }
          ForEach([UInt64(3), 4]) { key in
            Text("C").selectable(key: key).size(10)
          }
        }
      }, present: { _ in })
    #expect(host.state(for: 1)?.region == Region(10, 20, 10, 14))
    #expect(host.state(for: 2)?.region == Region(10, 34, 10, 14))
    #expect(host.state(for: 3)?.region == Region(62, 20, 10, 14))
    #expect(host.state(for: 4)?.region == Region(10, 72, 10, 14))
  }

  @Test func stackCentersContentAndPaintsAndHitsInDeclarationOrder() {
    var host = UIHost()
    var bottomClicks = 0
    var topClicks = 0
    for input in [Input(), Input(x: 50, y: 50, pressed: true), Input(x: 50, y: 50, released: true)] {
      host.frame(
        input: input, dt: 0,
        build: {
          ZStack(in: Region(0, 0, 100, 100)) {
            Button(key: 1, "", extent: 100, color: .accent) { bottomClicks += 1 }
            Button(key: 2, "", extent: 40, color: .panel) { topClicks += 1 }
              .frame(width: .fixed(40), height: .fixed(40))
            Text("A").size(10)
          }
        },
        present: { batch in
          var draws: [DrawRect] = []
          for draw in batch { draws.append(draw) }
          #expect(draws[0].color == .accent)
          #expect(draws.last?.glyphUV != nil)
          #expect(draws.last?.region == Region(45, 43, 10, 14))
        })
    }
    #expect(host.state(for: 2)?.region == Region(30, 30, 40, 40))
    #expect(topClicks == 1 && bottomClicks == 0)
  }

  @Test func multilineTextUsesMetricsAlignmentAndClipping() {
    var host = UIHost()
    host.frame(
      build: {
        ZStack(in: Region(10, 20, 100, 80)) {
          Text("AB\nC").selectable(key: 1).size(10).color(.accent).alignment(.center)
            .frame(width: .fill, height: .fill)
        }
      },
      present: { batch in
        var draws: [DrawRect] = []
        for draw in batch { draws.append(draw) }
        #expect(draws.count == 3)
        #expect(draws[0].region == Region(52, 45, 10, 14))
        #expect(draws[1].region == Region(58, 45, 10, 14))
        #expect(draws[2].region == Region(55, 61, 10, 14))
        #expect(draws.allSatisfy { $0.color == .accent })
        #expect(draws[0].clip == Region(52, 45, 16, 30))
      })
  }

  @Test func paddingAndTrailingAlignmentRespectContainerBounds() {
    var host = UIHost()
    host.frame(
      build: {
        ZStack(in: Region(10, 20, 100, 80), alignment: .bottomTrailing) {
          Text("A").selectable(key: 1).size(10).padding(5)
        }
      }, present: { _ in })
    #expect(host.state(for: 1)?.region == Region(95, 81, 10, 14))
  }

  @Test func nestedLayoutInsideScrollUsesResolvedGeometry() {
    var host = UIHost()
    host.frame(
      build: {
        ScrollColumn(key: 10, in: Region(0, 0, 100, 20), gap: 0) {
          Column(gap: 2) {
            Text("A").selectable(key: 1).size(10)
            Text("B").selectable(key: 2).size(10)
          }
        }
        ScrollToBlock(10, in: 10)
      },
      present: { batch in
        var lastClip: Region?
        for draw in batch { lastClip = draw.clip }
        #expect(lastClip == Region(0, 6, 10, 14))
      })
    #expect(host.state(for: 10)?.scrollOffset == 10)
    #expect(host.state(for: 2)?.region == Region(0, 6, 10, 14))
  }

  @Test func scrollContentIncludesNestedPaddingAndSiblingContainers() {
    var host = UIHost()
    host.frame(
      build: {
        ScrollColumn(key: 10, in: Region(0, 0, 100, 20), gap: 5) {
          Column { Text("A").selectable(key: 1).size(10) }.padding(3)
          Column { Text("B").selectable(key: 2).size(10) }.padding(3)
        }
        ScrollToBlock(100, in: 10)
      }, present: { _ in })
    #expect(host.state(for: 10)?.scrollOffset == 25)
    #expect(host.state(for: 2)?.region == Region(3, 3, 10, 14))
  }

  @Test func pointerBlockingIsExplicitAndDoesNotTakeKeyboardFocus() {
    var host = UIHost()
    for blocked in [false, true] {
      var clicks = 0
      for input in [Input(x: 10, y: 10, pressed: true), Input(x: 10, y: 10, released: true)] {
        host.frame(
          input: input,
          build: {
            ZStack(in: Region(0, 0, 100, 100)) {
              Button(key: 1, "", extent: 100) { clicks += 1 }
              Canvas(key: 2, blocksPointer: blocked) { _ in }
            }
          }, present: { _ in })
      }
      #expect(clicks == (blocked ? 0 : 1))
      #expect(host.state(for: 2)?.focused == false)
    }
  }

  @Test func selectableTextUsesFinalNestedGeometry() {
    var host = UIHost()
    host.frame(
      build: {
        ZStack(in: Region(0, 0, 100, 80)) {
          Text("A").size(10).selectable(key: 1).alignment(.leading)
            .frame(width: .fixed(50), height: .fixed(40))
        }
      },
      present: { batch in
        var glyph: DrawRect?
        for draw in batch where draw.glyphUV != nil { glyph = draw }
        #expect(glyph?.region == Region(45, 33, 10, 14))
      })
    #expect(host.state(for: 1)?.region == Region(45, 33, 10, 14))
  }

  @Test func selectableTextKeepsSelectionAcrossLayoutAndFocusOnFirstFrame() {
    var host = UIHost()
    for input in [Input(), Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)])] {
      host.frame(
        input: input,
        build: {
          ZStack(in: Region(0, 0, 100, 80)) {
            Text("ABCDE").size(10).selectable(key: 1).overflow(.truncateTail).alignment(.leading)
              .frame(width: .fixed(60), height: .fixed(40))
          }
          FocusBlock(key: 1)
        }, present: { _ in })
      #expect(host.state(for: 1)?.focused == true)
    }
    #expect(host.selectedText == "ABCDE")
    host.frame(
      build: {
        ZStack(in: Region(0, 0, 100, 80)) {
          Text("ABCDE").size(10).selectable(key: 1).overflow(.truncateTail).alignment(.leading)
            .frame(width: .fixed(60), height: .fixed(40))
        }
      }, present: { _ in })
    #expect(host.selectedText == "ABCDE")
  }

  @Test func textMeasuresEmojiAndGridKeepsEmptyColumns() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Grid(columns: 3, gap: 2) {
            Text("A").selectable(key: 1).size(10)
            Text("B").selectable(key: 2).size(10)
          }
          Text("😀").selectable(key: 3).size(10)
        }
      }, present: { _ in })
    #expect(host.state(for: 1)?.region.width == 10)
    #expect(host.state(for: 2)?.region.x == 12)
    #expect(host.state(for: 3)?.region.width == 12)
  }

  @Test func framedGridReceivesSpaceBeforePlacingItsCells() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 120, 80)) {
          Grid(columns: 3, gap: 0) {
            ForEach([UInt64(1), 2, 3]) { key in Canvas(key: key) { _ in } }
          }.frame(width: .fill, height: .fixed(40))
        }
      }, present: { _ in })
    #expect(host.state(for: 1)?.region == Region(0, 0, 40, 40))
    #expect(host.state(for: 2)?.region == Region(40, 0, 40, 40))
    #expect(host.state(for: 3)?.region == Region(80, 0, 40, 40))
  }

  @Test func unkeyedTextCannotCollideWithExplicitKeysAndIsReleased() {
    var host = UIHost()
    for _ in 0..<3 {
      host.frame(
        build: {
          Column(in: Region(0, 0, 100, 100)) {
            Text("A")
            Text("B").selectable(key: 0)
          }
        }, present: { batch in #expect(batch.count == 2) })
      #expect(host.state(for: 0) != nil)
      #expect(host.liveCount == 2)
    }
    host.frame(
      build: {},
      present: { batch in
        let empty = batch.isEmpty
        #expect(empty)
      })
    #expect(host.liveCount == 0)
  }
}
