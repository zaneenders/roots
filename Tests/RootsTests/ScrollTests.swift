import Testing

@_spi(Hosting) @testable import Roots

private let viewport = Rect(10, 20, 100, 60)

private func column(_ frame: inout UIFrame, keys: [UInt64] = [1, 2, 3], height: Float = 60) {
  frame.beginScrollColumn(key: 100, in: Rect(10, 20, 100, height), gap: 10)
  for key in keys { frame.button(key: key, "", extent: 30) }
  frame.end()
}

private func state(_ ui: borrowing UIStore, key: UInt64) throws -> NodeState {
  let handle = ui.handle(for: key)
  let required = try #require(handle)
  let value = ui.state(for: required)
  return try #require(value)
}

@Test func scrollingUsesFreshGeometryBeforePointerDispatch() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, pressed: true, released: true, scrollY: 40),
    build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 40)
  #expect(try state(ui, key: 1).rect == Rect(10, -20, 100, 30))
  #expect(try state(ui, key: 1).clicks == 0)
  #expect(try state(ui, key: 2).rect == Rect(10, 20, 100, 30))
  #expect(try state(ui, key: 2).clicks == 1)
  #expect(try state(ui, key: 2).hovered)
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 40)
  #expect(try state(ui, key: 2).clicks == 1)
}

@Test func scrollingClampsOnInputContentShrinkAndResize() throws {
  var ui = UIStore()
  ui.frame(input: Input(x: 20, y: 25, scrollY: 1000), build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 50)
  ui.frame(build: { column(&$0, height: 80) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 30)
  ui.frame(build: { column(&$0, keys: [1, 2]) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 10)
  ui.frame(input: Input(x: 20, y: 25, scrollY: -1000), build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 0)
  ui.frame(build: { column(&$0, keys: []) }, present: { #expect($0.count == 0) })
  #expect(try state(ui, key: 100).scrollOffset == 0)
}

@Test func scrollingPreservesFractionalDistanceAndIgnoresInvalidOrOutsideInput() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 0.5), dt: 0, build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 0.5)
  for input in [
    Input(x: 9, y: 25, scrollY: 40), Input(x: 20, y: 80, scrollY: 40),
    Input(x: 20, y: 25, scrollY: .nan), Input(x: 20, y: 25, scrollY: .infinity),
    Input(x: 20, y: 25, scrollX: 40),
  ] {
    ui.frame(input: input, build: { column(&$0) }, present: { _ in })
    #expect(try state(ui, key: 100).scrollOffset == 0.5)
  }
}

@Test func clippedRowsCannotReceiveClicksOrHoverOutsideViewport() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 90, pressed: true, released: true), build: { column(&$0) },
    present: { draws in
      #expect(draws.count == 2)
      for draw in draws { #expect(draw.clip == viewport) }
      #expect(draws[1].rect == Rect(10, 60, 100, 30))
      #expect(draws[1].radius == 7)
    })
  #expect(try state(ui, key: 2).clicks == 0)
  #expect(try state(ui, key: 2).hovered == false)
  ui.frame(
    input: Input(x: 20, y: 70, pressed: true, released: true), build: { column(&$0) },
    present: { _ in })
  #expect(try state(ui, key: 2).clicks == 1)
}

@Test func scrollingBetweenPressAndReleaseDoesNotActivateAnotherRow() throws {
  var ui = UIStore()
  ui.frame(input: Input(x: 20, y: 25, pressed: true), build: { column(&$0) }, present: { _ in })
  ui.frame(
    input: Input(x: 20, y: 25, released: true, scrollY: 40), build: { column(&$0) },
    present: { _ in })
  #expect(try state(ui, key: 1).clicks == 0)
  #expect(try state(ui, key: 2).clicks == 0)
}

@Test func tabAndActivationRevealOffscreenFocusAndClipAllDraws() throws {
  var ui = UIStore()
  for _ in 0..<3 {
    ui.frame(input: Input(keyEvents: [KeyEvent(.tab)]), build: { column(&$0) }, present: { _ in })
  }
  #expect(try state(ui, key: 3).focused)
  #expect(try state(ui, key: 3).rect == Rect(10, 50, 100, 30))
  #expect(try state(ui, key: 100).scrollOffset == 50)
  ui.frame(input: Input(x: 20, y: 25, scrollY: -50), build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 3).focused)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.enter)]), build: { column(&$0) },
    present: { draws in
      for draw in draws { #expect(draw.clip == viewport) }
    })
  #expect(try state(ui, key: 3).clicks == 1)
  #expect(try state(ui, key: 100).scrollOffset == 50)
  ui.frame(input: Input(keyEvents: [KeyEvent(.tab)]), build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 1).focused)
  #expect(try state(ui, key: 100).scrollOffset == 0)
}

@Test func offscreenTextDoesNotConsumeDrawBudgetAndStateSurvivesReorder() throws {
  var ui = UIStore(drawCapacity: 4)
  ui.frame(
    input: Input(x: 20, y: 25, pressed: true, released: true), build: { column(&$0) },
    present: { _ in })
  let handle = ui.handle(for: 1)
  ui.frame(build: { column(&$0, keys: [3, 2, 1]) }, present: { _ in })
  #expect(ui.handle(for: 1) == handle)
  #expect(try state(ui, key: 1).clicks == 1)
  #expect(ui.droppedDraws == 0)
  ui.frame(
    build: { frame in
      frame.beginScrollColumn(key: 100, in: viewport, gap: 10)
      frame.label(key: 3, "", extent: 60)
      frame.label(key: 2, "OFFSCREEN TEXT", extent: 30)
      frame.end()
    }, present: { #expect($0.count == 1) })
  #expect(ui.droppedDraws == 0)
}

@Test func removedScrollContainerResetsOffsetWhenSlotIsReused() throws {
  var ui = UIStore()
  ui.frame(input: Input(x: 20, y: 25, scrollY: 40), build: { column(&$0) }, present: { _ in })
  let old = ui.handle(for: 100)
  ui.frame(build: { _ in }, present: { _ in })
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(ui.handle(for: 100) != old)
  #expect(try state(ui, key: 100).scrollOffset == 0)
}

@Test func nestedViewportConsumesScrollOnceAndIntersectsAncestorClip() throws {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: viewport, gap: 0)
    frame.beginScrollColumn(key: 200, in: Rect(10, 60, 100, 60), gap: 0)
    for key: UInt64 in 1...3 { frame.button(key: key, "", extent: 30) }
    frame.end()
    frame.end()
  }
  ui.frame(input: Input(x: 20, y: 90, scrollY: 10), build: build, present: { _ in })
  #expect(try state(ui, key: 200).scrollOffset == 0)
  ui.frame(
    input: Input(x: 20, y: 65, scrollY: 10), build: build,
    present: { draws in
      #expect(draws.count == 2)
      #expect(draws[1].rect.y == 80)
      #expect(draws[0].clip == Rect(10, 60, 100, 20))
      #expect(draws[0].rect == Rect(10, 50, 100, 30))
    })
  #expect(try state(ui, key: 100).scrollOffset == 0)
  #expect(try state(ui, key: 200).scrollOffset == 10)
}

@Test func rectangleIntersectionTreatsTouchingAndEmptyRectsAsEmpty() {
  #expect(viewport.intersection(Rect(50, 60, 100, 100)) == Rect(50, 60, 60, 20))
  #expect(viewport.intersection(Rect(110, 20, 10, 10)).isEmpty)
  #expect(viewport.intersection(Rect(30, 30, -10, 20)).isEmpty)
}

@Test func viewportClipIncludesGlyphsAndIsClearedOnRedeclaration() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab)]),
    build: { frame in
      frame.beginScrollColumn(key: 100, in: viewport)
      frame.button(key: 1, "A", extent: 60)
      frame.end()
    },
    present: { draws in
      #expect(draws.count > 2)
      for draw in draws { #expect(draw.clip == viewport) }
    })
  let original = ui.handle(for: 1)
  ui.frame(
    build: { frame in
      frame.beginColumn(in: Rect(200, 200, 100, 60))
      frame.button(key: 1, "A", extent: 60)
      frame.end()
    },
    present: { draws in
      #expect(draws.count > 2)
      for draw in draws {
        #expect(draw.clip == (draw.color == .text ? Rect(200, 200, 100, 60) : nil))
      }
    })
  #expect(ui.handle(for: 1) == original)
  #expect(try state(ui, key: 1).rect == Rect(200, 200, 100, 60))
}

@Test func ordinaryRowsInsideViewportContributeToFreshContentBounds() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 1000),
    build: { frame in
      frame.beginScrollColumn(key: 100, in: viewport)
      frame.beginRow(in: Rect(10, 100, 100, 30), gap: 0)
      frame.button(key: 1, "", extent: 40)
      frame.button(key: 2, "", extent: 40)
      frame.end()
      frame.end()
    },
    present: { draws in
      #expect(draws.count == 2)
      for draw in draws { #expect(draw.clip == viewport) }
    })
  #expect(try state(ui, key: 100).scrollOffset == 50)
  #expect(try state(ui, key: 1).rect == Rect(10, 50, 40, 30))
  #expect(try state(ui, key: 2).rect == Rect(50, 50, 40, 30))
}

@Test func releaseMomentumDecaysOnItsOriginalViewportAndEventuallyStops() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 10, scrollVelocityY: 160),
    build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 10)
  ui.frame(dt: 1 / 60, build: { column(&$0) }, present: { _ in })
  let first = try state(ui, key: 100).scrollOffset
  #expect(first > 10)
  ui.frame(dt: 1 / 60, build: { column(&$0) }, present: { _ in })
  let second = try state(ui, key: 100).scrollOffset
  #expect(second > first)
  #expect(second - first < first - 10)
  for _ in 0..<120 { ui.frame(build: { column(&$0) }, present: { _ in }) }
  let settled = try state(ui, key: 100).scrollOffset
  #expect(settled < 30)
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == settled)
}

@Test func momentumTravelIsIndependentOfFrameRate() throws {
  var slow = UIStore()
  var fast = UIStore()
  let input = Input(x: 20, y: 25, scrollY: 10, scrollVelocityY: 160)
  slow.frame(input: input, build: { column(&$0) }, present: { _ in })
  fast.frame(input: input, build: { column(&$0) }, present: { _ in })
  for _ in 0..<6 { slow.frame(dt: 1 / 30, build: { column(&$0) }, present: { _ in }) }
  for _ in 0..<24 { fast.frame(dt: 1 / 120, build: { column(&$0) }, present: { _ in }) }
  #expect(abs(try state(slow, key: 100).scrollOffset - state(fast, key: 100).scrollOffset) < 0.0001)
  for _ in 0..<30 { slow.frame(dt: 1 / 30, build: { column(&$0) }, present: { _ in }) }
  for _ in 0..<120 { fast.frame(dt: 1 / 120, build: { column(&$0) }, present: { _ in }) }
  #expect(abs(try state(slow, key: 100).scrollOffset - state(fast, key: 100).scrollOffset) < 0.0001)
}

@Test func momentumUsesFreshGeometryForHitsAndDrawing() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 10, scrollVelocityY: 400),
    build: { column(&$0) }, present: { _ in })
  ui.frame(
    input: Input(x: 20, y: 25), dt: 0.1, build: { column(&$0) },
    present: { draws in
      for draw in draws { #expect(draw.clip == viewport) }
      #expect(draws[0].rect.y < 30)
    })
  #expect(try state(ui, key: 1).hovered == false)
  #expect(try state(ui, key: 2).hovered)
}

@Test(arguments: [
  Input(x: 20, y: 25, pressed: true), Input(keyEvents: [KeyEvent(.tab)]),
  Input(keyEvents: [KeyEvent(.enter)]),
  Input(x: 20, y: 25, scrollY: -2), Input(x: 200, y: 200, scrollY: 2), Input(scrollVelocityY: 0),
]) func explicitInteractionStopsMomentum(input: Input) throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 10, scrollVelocityY: 160),
    build: { column(&$0) }, present: { _ in })
  ui.frame(input: input, build: { column(&$0) }, present: { _ in })
  let offset = try state(ui, key: 100).scrollOffset
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == offset)
  if input.pressed { #expect(try state(ui, key: 1).focused) }
  if input.scrollVelocityY == 0 { #expect(offset == 10) }
}

@Test(arguments: [Float(0), -1, .nan, .infinity]) func invalidTimeDoesNotAdvanceMomentum(dt: Float)
  throws
{
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 10, scrollVelocityY: 160), dt: dt,
    build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 10)
  ui.frame(dt: dt, build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 10)
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset > 10)
}

@Test func invalidOrUnownedReleaseVelocityCannotStartMomentum() throws {
  var ui = UIStore()
  ui.frame(input: Input(scrollVelocityY: 160), build: { column(&$0) }, present: { _ in })
  for velocity: Float in [.nan, .infinity, -.infinity] {
    ui.frame(
      input: Input(x: 20, y: 25, scrollY: 0.5, scrollVelocityY: velocity),
      build: { column(&$0) }, present: { _ in })
    let offset = try state(ui, key: 100).scrollOffset
    ui.frame(build: { column(&$0) }, present: { _ in })
    #expect(try state(ui, key: 100).scrollOffset == offset)
  }
}

@Test(arguments: [Float(0), 160, .greatestFiniteMagnitude])
func momentumStopsAtBoundsAndDoesNotReturnAfterGrowth(
  velocity: Float
) throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 40, scrollVelocityY: velocity),
    build: { column(&$0) }, present: { _ in })
  ui.frame(dt: 1, build: { column(&$0) }, present: { _ in })
  let offset = try state(ui, key: 100).scrollOffset
  #expect(offset == (velocity == 0 ? 40 : 50))
  ui.frame(build: { column(&$0, keys: [1, 2, 3, 4]) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == offset)
}

@Test func contentShrinkAndSlotReuseDiscardMomentum() throws {
  var ui = UIStore()
  let input = Input(x: 20, y: 25, scrollY: 40, scrollVelocityY: 160)
  ui.frame(input: input, build: { column(&$0) }, present: { _ in })
  ui.frame(build: { column(&$0, height: 80) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 30)
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 30)
  ui.frame(input: input, build: { column(&$0) }, present: { _ in })
  ui.frame(build: { _ in }, present: { _ in })
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 0)
}

@Test func nestedMomentumStaysWithTheChildEvenWhenThePointerMovesToItsParent() throws {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: viewport, gap: 0)
    frame.beginScrollColumn(key: 200, in: Rect(10, 60, 100, 60), gap: 0)
    for key: UInt64 in 1...3 { frame.button(key: key, "", extent: 30) }
    frame.end()
    frame.end()
  }
  ui.frame(
    input: Input(x: 20, y: 65, scrollY: 10, scrollVelocityY: 80), build: build, present: { _ in })
  ui.frame(input: Input(x: 20, y: 25), build: build, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 0)
  #expect(try state(ui, key: 200).scrollOffset > 10)
}

@Test func releaseOnALaterFrameStartsMomentumWithoutRepeatingTheDistance() throws {
  var ui = UIStore()
  ui.frame(input: Input(x: 20, y: 25, scrollY: 40), build: { column(&$0) }, present: { _ in })
  ui.frame(input: Input(scrollVelocityY: -160), build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 40)
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset < 40)
  ui.frame(dt: 1, build: { column(&$0) }, present: { _ in })
  #expect(abs(try state(ui, key: 100).scrollOffset - 20.625) < 0.0001)
}

@Test func outwardReleaseAtEitherBoundaryCannotSurviveContentGrowth() throws {
  var ui = UIStore()
  for input in [
    Input(x: 20, y: 25, scrollY: 1000, scrollVelocityY: 160),
    Input(x: 20, y: 25, scrollY: -1000, scrollVelocityY: -160),
  ] {
    ui.frame(input: input, build: { column(&$0) }, present: { _ in })
    let offset = try state(ui, key: 100).scrollOffset
    ui.frame(build: { column(&$0, keys: [1, 2, 3, 4]) }, present: { _ in })
    #expect(try state(ui, key: 100).scrollOffset == offset)
  }
}

@Test func changingViewportToOrdinaryNodeDiscardsMomentum() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 20, y: 25, scrollY: 10, scrollVelocityY: 160),
    build: { column(&$0) }, present: { _ in })
  ui.frame(
    build: { frame in
      frame.beginColumn(in: viewport)
      frame.label(key: 100, "", extent: 60)
      frame.end()
    }, present: { _ in })
  ui.frame(build: { column(&$0) }, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == 0)
}

@Test func requestedFocusRevealsFreshGeometryAndLeavesRoomForTheOutline() throws {
  var ui = UIStore()
  var requestsReveal = true
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: Rect(0, 0, 120, 60), gap: 0)
    frame.beginColumn(in: Rect(4, 4, 112, 200), gap: 4)
    for key: UInt64 in 1...5 {
      let handle = frame.button(key: key, "", extent: 30)
      if key == 5 { frame.focus(handle, reveal: requestsReveal) }
    }
    frame.label(key: 6, "", extent: 4, selectable: false)
    frame.end()
    frame.end()
  }
  ui.frame(build: build, present: { _ in })
  let last = try state(ui, key: 5)
  #expect(last.focused)
  #expect(last.rect.y >= 2 && last.rect.y + last.rect.height <= 58)
  let offset = try state(ui, key: 100).scrollOffset
  #expect(offset > 0)
  requestsReveal = false
  ui.frame(input: Input(x: 20, y: 20, scrollY: -20), build: build, present: { _ in })
  #expect(try state(ui, key: 100).scrollOffset == offset - 20)
}

@Test func optionalScrollIndicatorTracksOverflowAndOffsetWithoutTakingFocus() throws {
  var ui = UIStore()
  let viewport = Rect(10, 20, 100, 60)
  var contentHeight: Float = 240
  var showsIndicator = true
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: viewport, showsScrollIndicator: showsIndicator)
    frame.canvas(key: 1, extent: contentHeight, color: .panel) { _ in }
    frame.end()
  }
  var thumb: Rect?
  func present(_ draws: borrowing UIDrawBatch) {
    thumb = nil
    for draw in draws where draw.color == Color(1, 1, 1, 0.45) {
      thumb = draw.rect
      #expect(draw.clip == viewport)
    }
  }
  ui.frame(build: build, present: present)
  let top = try #require(thumb)
  #expect(top.y == viewport.y + 4)
  ui.frame(input: Input(x: 20, y: 30, scrollY: 1000), build: build, present: present)
  let bottom = try #require(thumb)
  #expect(bottom.height == top.height)
  #expect(bottom.y + bottom.height == viewport.y + viewport.height - 4)
  #expect(!(try state(ui, key: 100).focused))
  showsIndicator = false
  ui.frame(build: build, present: present)
  #expect(thumb == nil)
  showsIndicator = true
  contentHeight = 30
  ui.frame(build: build, present: present)
  #expect(thumb == nil)
}

@MainActor
@Test(arguments: [false, true])
func unrelatedInteractiveOverlayBlocksScroll(withHandler: Bool) {
  var host = UIHost()
  var received: [Float] = []
  host.frame(
    input: Input(x: 10, y: 10, scrollY: 40),
    build: {
      ScrollColumnBlock(key: 1, in: Rect(0, 0, 100, 100), gap: 0) {
        CanvasBlock(key: 2, extent: 400) { _ in }
      }
      ColumnBlock(in: Rect(0, 0, 100, 100)) {
        ElementBlock(
          key: 3, extent: 100, onScroll: withHandler ? { received.append($0.deltaY) } : nil,
          focusable: false
        ) { _ in }
      }
    }, present: { _ in })
  #expect(host.state(for: 1)?.scrollOffset == 0)
  #expect(received == (withHandler ? [40] : []))
}

@MainActor
@Test func scrollBubblesThroughTheHitElementsOwnAncestors() {
  var host = UIHost()
  host.frame(
    input: Input(x: 10, y: 10, scrollY: 40),
    build: {
      ScrollColumnBlock(key: 1, in: Rect(0, 0, 100, 100), gap: 0) {
        ElementBlock(key: 2, extent: 400) { _ in }
      }
    }, present: { _ in })
  #expect(host.state(for: 1)?.scrollOffset == 40)
}
