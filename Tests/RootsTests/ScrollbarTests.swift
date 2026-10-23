import Testing

@testable import Roots

private let scrollbarViewport = Region(10, 20, 100, 100)

private func scrollbarColumn(_ frame: inout UIFrame, height: Float = 400, visible: Bool = true) {
  frame.beginScrollColumn(key: 100, in: scrollbarViewport, gap: 0, showsScrollIndicator: visible)
  frame.button(key: 1, "", extent: height)
  frame.end()
}

private func scrollbarState(_ ui: borrowing UIStore, key: UInt64 = 100) throws -> NodeState {
  let value = ui.handle(for: key)
  let handle = try #require(value)
  let state = ui.state(for: handle)
  return try #require(state)
}

@Test func scrollbarDragPreservesGrabPointCapturesOutsideAndDoesNotActivateContent() throws {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) { scrollbarColumn(&frame) }
  ui.frame(input: Input(keyEvents: [KeyEvent(.tab)]), build: build, present: { _ in })
  ui.frame(input: Input(x: 20, y: 30, scrollY: -1000), build: build, present: { _ in })
  let bar = try #require(
    VerticalScrollbar(viewport: scrollbarViewport, contentHeight: 400, offset: 0))
  let x = bar.hitRegion.x + 1
  let y = bar.thumb.y + 3
  ui.frame(input: Input(x: x, y: y, pressed: true), build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 0)
  #expect(try scrollbarState(ui, key: 1).focused)
  ui.frame(input: Input(x: -100, y: y + 20), build: build, present: { _ in })
  let middle = try scrollbarState(ui).scrollOffset
  #expect(abs(middle - 300 * 20 / (bar.track.height - bar.thumb.height)) < 0.001)
  ui.frame(input: Input(x: -100, y: 1000, released: true), build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 300)
  ui.frame(input: Input(x: x, y: y), build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 300)
  #expect(try scrollbarState(ui, key: 1).clicks == 0)
}

@Test func scrollbarTrackClickJumpsAndPaintsAboveContent() throws {
  var ui = UIStore()
  let bar = try #require(
    VerticalScrollbar(viewport: scrollbarViewport, contentHeight: 400, offset: 0))
  let y = bar.track.y + bar.track.height / 2
  ui.frame(
    input: Input(x: bar.thumb.x + 2, y: y, pressed: true, released: true),
    build: { scrollbarColumn(&$0) },
    present: { draws in
      #expect(draws.count == 3)
      #expect(draws[0].region.height == 400)
      #expect(draws[1].region == bar.track)
      #expect(draws[2].region.width == 6)
      #expect(draws[2].clip == scrollbarViewport)
    })
  #expect(abs(try scrollbarState(ui).scrollOffset - 150) < 0.001)
  #expect(!(try scrollbarState(ui, key: 1).focused))
  #expect(try scrollbarState(ui, key: 1).clicks == 0)
}

@Test func scrollbarDragStopsMomentumAndClampsAfterContentChanges() throws {
  var ui = UIStore()
  var height: Float = 400
  func build(_ frame: inout UIFrame) { scrollbarColumn(&frame, height: height) }
  ui.frame(
    input: Input(x: 20, y: 30, scrollY: 50, scrollVelocityY: 160), build: build, present: { _ in })
  let bar = try #require(
    VerticalScrollbar(viewport: scrollbarViewport, contentHeight: height, offset: 50))
  ui.frame(
    input: Input(x: bar.thumb.x + 2, y: bar.thumb.y + 3, pressed: true), build: build,
    present: { _ in })
  ui.frame(
    input: Input(x: bar.thumb.x + 2, y: 1000, released: true), build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 300)
  height = 500
  ui.frame(build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 300)
  height = 150
  ui.frame(build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 50)
}

@Test func hiddenAndRemovedScrollbarsCancelCapture() throws {
  var ui = UIStore()
  var height: Float = 400
  var visible = true
  func build(_ frame: inout UIFrame) { scrollbarColumn(&frame, height: height, visible: visible) }
  ui.frame(input: Input(x: 105, y: 27, pressed: true), build: build, present: { _ in })
  visible = false
  ui.frame(input: Input(x: 105, y: 100), build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 0)
  visible = true
  ui.frame(input: Input(x: 105, y: 27, pressed: true), build: build, present: { _ in })
  height = 50
  ui.frame(
    input: Input(x: 105, y: 100), build: build, present: { draws in #expect(draws.count == 1) })
  #expect(try scrollbarState(ui).scrollOffset == 0)
  height = 400
  ui.frame(input: Input(x: 105, y: 27, pressed: true), build: build, present: { _ in })
  ui.frame(build: { _ in }, present: { _ in })
  ui.frame(input: Input(x: 105, y: 100), build: build, present: { _ in })
  #expect(try scrollbarState(ui).scrollOffset == 0)
}

@Test func nestedScrollbarsRespectClippingAndLaterOverlays() throws {
  var ui = UIStore()
  var overlay = false
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: scrollbarViewport, gap: 0, showsScrollIndicator: true)
    frame.beginScrollColumn(key: 200, in: Region(20, 80, 70, 100), gap: 0, showsScrollIndicator: true)
    frame.button(key: 1, "", extent: 400)
    frame.end()
    frame.end()
    if overlay {
      frame.beginColumn(in: scrollbarViewport)
      frame.button(key: 2, "", extent: 100)
      frame.end()
    }
  }
  ui.frame(
    input: Input(x: 85, y: 140, pressed: true, released: true), build: build, present: { _ in })
  #expect(try scrollbarState(ui, key: 200).scrollOffset == 0)
  ui.frame(input: Input(x: 85, y: 90, pressed: true), build: build, present: { _ in })
  ui.frame(input: Input(x: 85, y: 110, released: true), build: build, present: { _ in })
  #expect(try scrollbarState(ui, key: 200).scrollOffset > 0)
  #expect(try scrollbarState(ui).scrollOffset == 0)
  overlay = true
  ui.frame(
    input: Input(x: 105, y: 100, pressed: true, released: true), build: build,
    present: { draws in
      let background = draws[draws.count - 2]
      let outline = draws[draws.count - 1]
      #expect(background.region == scrollbarViewport)
      #expect(outline.color == .accent && outline.strokeWidth == 2)
      #expect(
        outline.region
          == Region(
            scrollbarViewport.x + 1, scrollbarViewport.y + 1,
            scrollbarViewport.width - 2, scrollbarViewport.height - 2))
    })
  #expect(try scrollbarState(ui, key: 2).clicks == 1)
  #expect(try scrollbarState(ui).scrollOffset == 0)
}

@Test func scrollbarGeometryHidesWithoutOverflowAndFitsTinyViewports() throws {
  #expect(VerticalScrollbar(viewport: scrollbarViewport, contentHeight: 100, offset: 0) == nil)
  #expect(
    VerticalScrollbar(viewport: scrollbarViewport, contentHeight: .infinity, offset: 0) == nil)
  #expect(VerticalScrollbar(viewport: Region(0, 0, 10, 100), contentHeight: 400, offset: 0) == nil)
  let bar = try #require(
    VerticalScrollbar(viewport: Region(0, 0, 12, 12), contentHeight: 1000, offset: 500))
  #expect(bar.thumb.height >= 2)
  #expect(bar.thumb.y >= bar.track.y)
  #expect(bar.thumb.y + bar.thumb.height <= bar.track.y + bar.track.height)
  #expect(bar.scrollOffset(at: -1000, grabOffset: 1) == 0)
  #expect(bar.scrollOffset(at: 1000, grabOffset: 1) == 988)
}
