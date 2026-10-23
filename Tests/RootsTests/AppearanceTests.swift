import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct AppearanceTests {
  @Test func backgroundUsesPaddedFrameAndPaintsBeforeContent() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(10, 20, 100, 80), gap: 0) {
          Text("A").selectable(key: 1).size(10).padding(5).frame(width: .fill)
            .background(.panel)
          Text("B").selectable(key: 2).size(10)
        }
      },
      present: { batch in
        #expect(batch.count == 3)
        #expect(batch[0].region == Region(10, 20, 100, 24))
        #expect(batch[0].color == .panel)
        #expect(batch[0].glyphUV == nil)
        #expect(batch[1].glyphUV != nil)
      })
    #expect(host.state(for: 1)?.region == Region(15, 25, 10, 14))
    #expect(host.state(for: 2)?.region == Region(10, 44, 10, 14))
  }

  @Test func backgroundDoesNotIncludeEarlierSiblingsWhenPromotingLayout() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 0) {
          Canvas(key: 1, extent: 20) { _ in }
          Text("A").size(10).background(.accent)
          Text("B").selectable(key: 2).size(10)
        }
      },
      present: { batch in
        #expect(batch[1].region == Region(0, 20, 10, 14))
      })
    #expect(host.state(for: 1)?.region == Region(0, 0, 100, 20))
    #expect(host.state(for: 2)?.region == Region(0, 34, 10, 14))
  }

  @Test func modifierOrderControlsBackgroundBounds() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 0) {
          Text("A").size(10).background(.accent).padding(5)
          Text("B").size(10).padding(5).background(.panel)
        }
      },
      present: { batch in
        #expect(batch.count == 4)
        #expect(batch[0].region == Region(5, 5, 10, 14))
        #expect(batch[2].region == Region(0, 24, 20, 24))
      })
  }

  @Test func backgroundSupportsExplicitRootBoundsAndEmptyContent() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(10, 20, 100, 80)) {
          Text("A").size(10)
        }.background(.panel)
        Column(in: Region(120, 20, 50, 30)) {}.background(.accent)
      },
      present: { batch in
        #expect(batch.count == 3)
        #expect(batch[0].region == Region(10, 20, 100, 80))
        #expect(batch[2].region == Region(120, 20, 50, 30))
      })
  }

  @Test func nestedBackgroundsKeepDeclarationOrderWithoutDuplicatingLayoutSlots() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 2) {
          Column(gap: 0) {
            Text("A").size(10).background(.accent)
            Text("B").size(10)
          }.padding(4).background(.panel)
          Text("C").selectable(key: 1).size(10)
        }
      },
      present: { batch in
        #expect(batch.count == 5)
        #expect(batch[0].region == Region(0, 0, 18, 36))
        #expect(batch[0].color == .panel)
        #expect(batch[1].region == Region(4, 4, 10, 14))
        #expect(batch[1].color == .accent)
      })
    #expect(host.state(for: 1)?.region == Region(0, 38, 10, 14))
  }

  @Test func backgroundPreservesScrollClippingAndDoesNotInterceptInput() {
    var host = UIHost()
    var clicks = 0
    for input in [Input(x: 10, y: 10, pressed: true), Input(x: 10, y: 10, released: true)] {
      host.frame(
        input: input, dt: 0,
        build: {
          ScrollColumn(key: 1, in: Region(0, 0, 100, 20), gap: 0) {
            Column(gap: 0) {
              Button(key: 2, "", extent: 40) { clicks += 1 }
            }.padding(3).frame(width: .fill).background(.accent)
          }
          ScrollToBlock(10, in: 1)
        },
        present: { batch in
          #expect(batch[0].region == Region(0, -10, 100, 46))
          #expect(batch[0].clip == Region(0, 0, 100, 20))
        })
    }
    #expect(clicks == 1)
    #expect(host.state(for: 2)?.focused == true)
  }

  @Test func colorInheritsThroughContainersAndRespectsLocalOverrides() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 0) {
          Column(gap: 0) {
            Text("A").size(10)
            Text("B").size(10).padding(0).color(.panel)
            Text("C").size(10).color(.text)
            Text("D").size(10).color(.panel).background(.text)
          }.color(.accent)
          Text("E").size(10)
        }
      },
      present: { batch in
        var glyphColors: [Color] = []
        for draw in batch where draw.glyphUV != nil { glyphColors.append(draw.color) }
        #expect(glyphColors == [.accent, .panel, .text, .panel, .text])
      })
  }

  @Test func colorWorksBeforeAndAfterFrameAndBackground() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 0) {
          Text("A").size(10).frame(width: .fill).background(.panel).color(.accent)
          Text("B").size(10).color(.accent).frame(width: .fill).background(.panel)
        }
      },
      present: { batch in
        #expect(batch.count == 4)
        #expect(batch[0].color == .panel)
        #expect(batch[1].color == .accent)
        #expect(batch[2].color == .panel)
        #expect(batch[3].color == .accent)
      })
  }

  @Test func colorStylesSelectableTextAndButtonsWithoutChangingTheirBackgrounds() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 150)) {
          Text("A")
            .size(10)
            .selectable(key: 1)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(32))
            .background(.panel)
          Text("B").selectable(key: 2)
            .size(10)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(32))
            .background(.panel)
          Button(key: 3, "C", size: 10)
        }.color(.accent)
      },
      present: { batch in
        var glyphColors: [Color] = []
        for draw in batch {
          if draw.glyphUV != nil { glyphColors.append(draw.color) } else { #expect(draw.color == .panel) }
        }
        #expect(glyphColors == [.accent, .accent, .accent])
      })
  }

  @Test func changingAppearanceDoesNotLeaveStaleBackgroundsOrColors() {
    var host = UIHost()
    for styled in [true, false, true, false] {
      host.frame(
        build: {
          Column(in: Region(0, 0, 100, 100)) {
            if styled {
              Text("A").selectable(key: 1).size(10).background(.panel).color(.accent)
            } else {
              Text("A").selectable(key: 1).size(10)
            }
          }
        },
        present: { batch in
          #expect(batch.count == (styled ? 2 : 1))
          #expect(batch[batch.count - 1].color == (styled ? .accent : .text))
        })
      #expect(host.liveCount == (styled ? 2 : 1))
    }
  }
}
