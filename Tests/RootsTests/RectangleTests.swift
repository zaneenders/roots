import Testing

@_spi(Hosting) import Roots

@MainActor
struct RectangleTests {
  @Test func aliasFillsAvailableSpaceWithSquareCorners() {
    let rectangle: Rectangle = Rect()
    let bounds = Region(10, 20, 100, 80)
    var host = UIHost()
    host.frame(
      build: { ZStack(in: bounds) { rectangle } },
      present: { batch in
        #expect(batch.count == 1)
        #expect(batch[0].region == bounds)
        #expect(batch[0].color == .text)
        #expect(batch[0].radius == 0)
        #expect(batch[0].strokeWidth == 0)
        #expect(batch[0].glyphUV == nil)
      })
    #expect(host.liveCount == 1)
  }

  @Test func framePaddingAndBackgroundCompose() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(10, 20, 100, 80)) {
          Rect()
            .color(.accent)
            .frame(width: .fixed(24), height: .fixed(16))
            .padding(2)
            .background(.panel)
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].region == Region(10, 20, 28, 20))
        #expect(batch[0].color == .panel)
        #expect(batch[1].region == Region(12, 22, 24, 16))
        #expect(batch[1].color == .accent)
        #expect(batch[1].radius == 0)
      })
  }

  @Test func colorsInheritAndLocalOverridesStayScoped() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 0) {
          Column(gap: 0) {
            Rectangle().frame(width: .fill, height: .fixed(10))
            Rectangle().color(.panel).frame(width: .fill, height: .fixed(10))
            Rectangle().frame(width: .fill, height: .fixed(10)).color(.text)
          }.frame(width: .fill).color(.accent)
          Rectangle().frame(width: .fill, height: .fixed(10))
        }
      },
      present: { batch in
        #expect(batch.count == 4)
        #expect(batch[0].color == .accent)
        #expect(batch[1].color == .panel)
        #expect(batch[2].color == .text)
        #expect(batch[3].color == .text)
      })
  }

  @Test func flexibleRectangleTakesRemainingRowSpace() {
    var host = UIHost()
    host.frame(
      build: {
        RowBlock(in: Region(0, 0, 100, 30), gap: 4) {
          Rectangle().frame(width: .fixed(20), height: .fill)
          Rect()
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].region == Region(0, 0, 20, 30))
        #expect(batch[1].region == Region(24, 0, 76, 30))
      })
  }

  @Test func rectanglePreservesEarlierSiblingsWhenPromotingLayout() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100), gap: 2) {
          Canvas(key: 1, extent: 10) { _ in }
          Rectangle()
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].region == Region(0, 0, 100, 10))
        #expect(batch[1].region == Region(0, 12, 100, 88))
      })
  }

  @Test func rectangleScrollsAndClipsToViewport() {
    var host = UIHost()
    host.frame(
      build: {
        ScrollColumn(key: 1, in: Region(0, 0, 20, 20), gap: 0) {
          Rectangle().frame(width: .fixed(20), height: .fixed(40))
        }
        ScrollToBlock(10, in: 1)
      },
      present: { batch in
        #expect(batch.count == 1)
        #expect(batch[0].region == Region(0, -10, 20, 40))
        #expect(batch[0].clip == Region(0, 0, 20, 20))
      })
    #expect(host.state(for: 1)?.scrollOffset == 10)
  }

  @Test(arguments: [false, true])
  func rectangleDoesNotInterceptPointerOrKeyboardFocus(outline: Bool) {
    var host = UIHost()
    var clicks = 0
    host.frame(
      input: Input(
        x: 20, y: 20, pressed: true, released: true, keyEvents: [KeyEvent(.tab)]),
      dt: 0,
      build: {
        ZStack(in: Region(0, 0, 100, 40)) {
          Button(key: 1, "") { clicks += 1 }
          if outline { Rect().radius(3).stroke() } else { Rect() }
        }
      }, present: { _ in })
    #expect(clicks == 1)
    #expect(host.state(for: 1)?.focused == true)
    #expect(host.state(for: 1)?.hovered == true)
  }

  @Test func roundedFillAndStrokeUseTheSameBoundsAndInheritedColor() {
    let bounds = Region(10, 20, 100, 80)
    var host = UIHost()
    host.frame(
      build: {
        ZStack(in: bounds) {
          Rect().radius(3)
          Rect().radius(7).stroke(width: 1.5)
        }.color(.accent)
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].region == bounds)
        #expect(batch[0].radius == 3)
        #expect(batch[0].strokeWidth == 0)
        #expect(batch[0].color == .accent)
        #expect(batch[1].region == bounds)
        #expect(batch[1].radius == 7)
        #expect(batch[1].strokeWidth == 1.5)
        #expect(batch[1].color == .accent)
      })
  }

  @Test func radiusModifierPreservesValuesAndComposesWithStroke() {
    let original = Rectangle().radius(3)
    var host = UIHost()
    host.frame(
      build: {
        ZStack(in: Region(0, 0, 20, 20)) {
          original
          original.radius(7).stroke(width: 2)
          original.radius(7).radius(0)
          Rect().stroke(width: 2).radius(5)
        }
      },
      present: { batch in
        #expect(batch.count == 4)
        for index in 0..<batch.count {
          #expect(batch[index].radius == [Float(3), 7, 0, 5][index])
          #expect(batch[index].strokeWidth == [Float(0), 2, 0, 2][index])
        }
      })
  }

  @Test func zeroWidthStrokeDoesNotBecomeAFill() {
    var host = UIHost()
    host.frame(
      build: { ZStack(in: Region(0, 0, 20, 20)) { Rect().radius(3).stroke(width: 0) } },
      present: { batch in
        #expect(batch.count == 0)
      })
  }

  @Test func roundedStrokeClipsWithoutChangingLayout() {
    var host = UIHost()
    host.frame(
      build: {
        ScrollColumn(key: 1, in: Region(0, 0, 20, 20), gap: 0) {
          Rect().radius(3).stroke().color(.accent)
            .frame(width: .fixed(20), height: .fixed(40))
        }
        ScrollToBlock(10, in: 1)
      },
      present: { batch in
        #expect(batch.count == 1)
        #expect(batch[0].region == Region(0, -10, 20, 40))
        #expect(batch[0].clip == Region(0, 0, 20, 20))
        #expect(batch[0].radius == 3)
        #expect(batch[0].strokeWidth == 1)
        #expect(batch[0].color == .accent)
      })
  }

  @Test func strokeModifierHasValueSemanticsAndDoesNotLeakAcrossFrames() {
    let fill = Rect().radius(3)
    let stroke = fill.stroke(width: 2)
    var host = UIHost(nodeCapacity: 2)
    host.frame(
      build: { ZStack(in: Region(0, 0, 20, 20)) { stroke; fill } },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].strokeWidth == 2)
        #expect(batch[1].strokeWidth == 0)
      })
    host.frame(build: {}, present: { _ in })
    host.frame(
      build: { ZStack(in: Region(0, 0, 20, 20)) { Rect() } },
      present: { batch in
        #expect(batch.count == 1)
        #expect(batch[0].radius == 0)
        #expect(batch[0].strokeWidth == 0)
      })
  }

  @Test func removedRectangleDoesNotChangeReusedCanvasPainting() {
    var host = UIHost(nodeCapacity: 1)
    host.frame(
      build: { ZStack(in: Region(0, 0, 20, 20)) { Rect() } }, present: { _ in })
    host.frame(build: {}, present: { _ in })
    host.frame(
      build: {
        ZStack(in: Region(0, 0, 20, 20)) {
          Canvas(key: 1) { context in
            context.fillRect(context.region, color: .accent)
          }
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[0].radius == 7)
        #expect(batch[1].color == .accent)
      })
  }
}
