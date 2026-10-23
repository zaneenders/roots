import Testing

@testable import Roots

@Test(arguments: [false, true]) func focusLossCancelsElementCaptureExactlyOnceWithoutReleasingIt(
  syntheticRelease: Bool
)
  throws
{
  var ui = UIStore()
  var phases: [PointerEvent.Phase] = []
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 0, 100, 40))
    frame.element(key: 1, extent: 40, onPointer: { phases.append($0.phase) }, paint: { _ in })
    frame.end()
  }
  ui.frame(input: Input(x: 10, y: 10, pressed: true), build: build, present: { _ in })
  let handle = ui.handle(for: 1)
  let element = try #require(handle)
  ui.frame(
    input: Input(x: 10, y: 10, released: syntheticRelease, focusLost: true), build: build,
    present: { _ in })
  ui.frame(input: Input(focusLost: true), build: build, present: { _ in })
  ui.frame(input: Input(x: 10, y: 10, released: true), build: build, present: { _ in })
  #expect(phases == [.pressed, .cancelled])
  #expect(ui.state(for: element)?.focused == true)
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true, released: true), build: build, present: { _ in })
  #expect(phases == [.pressed, .cancelled, .pressed, .released])
}

@Test(arguments: [false, true]) func focusLossPreservesReadOnlySelection(syntheticRelease: Bool) {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 0, 200, 40))
    frame.label(key: 1, "abcdef", extent: 40)
    frame.end()
  }
  ui.frame(input: Input(x: 24, y: 20, pressed: true), build: build, present: { _ in })
  ui.frame(input: Input(x: 60, y: 20), build: build, present: { _ in })
  #expect(ui.selectedText == "bcd")
  ui.frame(
    input: Input(released: syntheticRelease, focusLost: true), build: build, present: { _ in })
  #expect(ui.selectedText == "bcd")
  ui.frame(input: Input(x: 84, y: 20), build: build, present: { _ in })
  #expect(ui.selectedText == "bcd")
}

@Test(arguments: [false, true]) func focusLossCancelsScrollbarWithoutMovingContent(
  syntheticRelease: Bool
) throws {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 1, in: Region(0, 0, 100, 100), gap: 0, showsScrollIndicator: true)
    frame.label(key: 2, "", extent: 500)
    frame.end()
  }
  ui.frame(input: Input(x: 20, y: 50, scrollY: 120), build: build, present: { _ in })
  let declared = ui.handle(for: 1)
  let viewport = try #require(declared)
  let bar = try #require(
    VerticalScrollbar(viewport: Region(0, 0, 100, 100), contentHeight: 500, offset: 120))
  ui.frame(input: Input(x: 95, y: bar.thumb.y + 2, pressed: true), build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == 120)
  ui.frame(
    input: Input(released: syntheticRelease, focusLost: true), build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == 120)
  ui.frame(input: Input(x: 95, y: 80), build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == 120)
}

@Test func focusLossStopsMomentumAndResetsScrollAcceleration() throws {
  var ui = UIStore(scrollAcceleration: 1)
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 1, in: Region(0, 0, 100, 100), gap: 0)
    frame.label(key: 2, "", extent: 500)
    frame.end()
  }
  ui.frame(
    input: Input(x: 20, y: 50, scrollY: 60, scrollVelocityY: 200), build: build, present: { _ in })
  let declared = ui.handle(for: 1)
  let viewport = try #require(declared)
  ui.frame(input: Input(focusLost: true), dt: 0.1, build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == 60)
  #expect(ui.needsAnimationFrame == false)
  ui.frame(input: Input(x: 20, y: 50, scrollY: 6), dt: 0.01, build: build, present: { _ in })
  let beforeLoss = ui.state(for: viewport)?.scrollOffset
  ui.frame(input: Input(focusLost: true), dt: 0.01, build: build, present: { _ in })
  ui.frame(input: Input(x: 20, y: 50, scrollY: 6), dt: 0.01, build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == beforeLoss.map { $0 + 6 })
}

@Test func focusLossDiscardsPendingPointerAndScrollInput() {
  var ui = UIStore()
  var pointers = 0
  var scrolls = 0
  var keys = 0
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 0, 100, 40))
    let element = frame.element(
      key: 1, extent: 40, onKey: { _ in keys += 1 },
      onPointer: { _ in pointers += 1 }, onScroll: { _ in scrolls += 1 }, paint: { _ in })
    frame.focus(element)
    frame.end()
  }
  ui.frame(
    input: Input(
      x: 10, y: 10, pressed: true, released: true, scrollY: 30,
      scrollVelocityY: 200, keyEvents: [KeyEvent(.shift, phase: .released)], focusLost: true),
    build: build, present: { _ in })
  #expect(pointers == 0)
  #expect(scrolls == 0)
  #expect(keys == 1)
  ui.frame(input: Input(x: 10, y: 10), build: build, present: { _ in })
  #expect(pointers == 0)
}

@Test func latestFocusRequestReplacesPendingReveal() throws {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginScrollColumn(key: 1, in: Region(0, 0, 100, 80), gap: 0)
      let first = frame.button(key: 2, "", extent: 40)
      frame.label(key: 3, "", extent: 160)
      let last = frame.button(key: 4, "", extent: 40)
      frame.focus(last, reveal: true)
      frame.focus(first)
      frame.end()
    }, present: { _ in })
  let declared = ui.handle(for: 1)
  let viewport = try #require(declared)
  let first = ui.handle(for: 2)
  let focused = try #require(first)
  #expect(ui.state(for: viewport)?.scrollOffset == 0)
  #expect(ui.state(for: focused)?.focused == true)
}

@Test(arguments: [false, true]) func focusLossCancelsButtonActivation(syntheticRelease: Bool) {
  var ui = UIStore()
  var clicks = 0
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 0, 100, 40))
    frame.button(key: 1, "", extent: 40, onClick: { clicks += 1 })
    frame.end()
  }
  ui.frame(input: Input(x: 10, y: 10, pressed: true), build: build, present: { _ in })
  ui.frame(
    input: Input(x: 10, y: 10, released: syntheticRelease, focusLost: true), build: build,
    present: { _ in })
  ui.frame(input: Input(x: 10, y: 10, released: true), build: build, present: { _ in })
  #expect(clicks == 0)
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true, released: true), build: build, present: { _ in })
  #expect(clicks == 1)
}

@Test func focusLossStopsSelectionAutoscroll() throws {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 1, in: Region(0, 0, 200, 64), gap: 0)
    frame.text(
      key: 2,
      lines: (0..<20).map {
        TextLine([TextRun("row\($0)")], y: Float($0) * 32)
      }, extent: 640)
    frame.end()
  }
  ui.frame(input: Input(x: 12, y: 5, pressed: true), build: build, present: { _ in })
  ui.frame(input: Input(x: 72, y: 100), dt: 0.1, build: build, present: { _ in })
  let declared = ui.handle(for: 1)
  let viewport = try #require(declared)
  let offset = ui.state(for: viewport)?.scrollOffset
  let selected = ui.selectedText
  #expect(ui.needsAnimationFrame == true)
  ui.frame(input: Input(focusLost: true), dt: 0.1, build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == offset)
  #expect(ui.selectedText == selected)
  #expect(ui.needsAnimationFrame == false)
  ui.frame(input: Input(x: 72, y: 100), dt: 0.1, build: build, present: { _ in })
  #expect(ui.state(for: viewport)?.scrollOffset == offset)
  #expect(ui.selectedText == selected)
  #expect(ui.needsAnimationFrame == false)
}

@Test func focusLossDoesNotCancelRemovedElements() {
  var ui = UIStore()
  var visible = true
  var phases: [PointerEvent.Phase] = []
  func build(_ frame: inout UIFrame) {
    guard visible else { return }
    frame.beginColumn(in: Region(0, 0, 100, 40))
    frame.element(key: 1, extent: 40, onPointer: { phases.append($0.phase) }, paint: { _ in })
    frame.end()
  }
  ui.frame(input: Input(x: 10, y: 10, pressed: true), build: build, present: { _ in })
  visible = false
  ui.frame(input: Input(focusLost: true), build: build, present: { _ in })
  #expect(phases == [.pressed])
  #expect(ui.handle(for: 1) == nil)
}
