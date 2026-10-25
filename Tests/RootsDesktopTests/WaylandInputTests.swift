#if os(Linux)
import Roots
import Testing

@testable import RootsDesktop
@testable import SwiftWayland
@testable import WaylandBridge

@MainActor
struct WaylandInputTests {
  @Test func backendFramePreservesFractionalScaleBeforeBufferRounding() {
    var snapshot = NativeWindowInput(width: 101, height: 79)
    snapshot.fractionalScale120 = 150
    snapshot.timeSeconds = 2.5
    snapshot.secondaryPressed = true
    snapshot.pointerX = 15
    snapshot.pointerY = 20
    let frame = snapshot.backendFrame
    #expect(frame.logicalSize == Size(width: 101, height: 79))
    #expect(frame.scale == 1.25 && frame.timeSeconds == 2.5)
    #expect(frame.input.secondaryPressed && !frame.input.pressed)
    #expect(frame.input.mousePosition == Coordinate(x: 15, y: 20))
  }

  @Test(arguments: [false, true])
  func capturedReleaseKeepsCoordinatesUnlessFocusWasLost(focusLost: Bool) {
    var source = WaylandInput(width: 100, height: 100)
    source.pointerInside = true
    source.pointerX = 20
    source.pointerY = 20
    source.button(0x110, state: 1)
    var events: [PointerEvent] = []
    let runtime = DesktopRuntime(
      content: { viewport in
        Column(in: viewport.bounds) {
          Element(key: 1, extent: 100, onPointer: { events.append($0) }) { _ in }
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {})
    defer { runtime.stop() }
    let viewport = Viewport(size: .init(width: 100, height: 100))
    runtime.frame(
      input: NativeWindowInput(source).input, viewport: viewport, dt: 0,
      present: { _ in })
    source.resetEdges()
    source.pointerX = 150
    source.pointerY = 50
    source.button(0x110, state: 0)
    source.leavePointer()
    source.focusLost = focusLost
    runtime.frame(
      input: NativeWindowInput(source).input, viewport: viewport, dt: 0,
      present: { _ in })
    #expect(events.map(\.phase) == [.pressed, focusLost ? .cancelled : .released])
    #expect(events.last?.position.x == 150 && events.last?.position.y == 50)
    source.resetEdges()
    let idle = NativeWindowInput(source).input
    #expect(idle.mousePosition == nil)
  }

  @Test func desktopEventsReachFrameCallbacksWithoutBecomingPrimaryClicks() {
    var source = WaylandInput(width: 100, height: 100)
    source.pointerX = 20
    source.pointerY = 20
    source.button(0x111, state: 1)
    source.button(0x112, state: 1)
    source.axisSteps(0, value: 30, highResolution: true)
    source.axisDirection(0, inverted: true)
    source.pointerFrame()
    source.textEvents = [
      .init(committed: "é", preedit: .init(text: "日", cursorBegin: 0, cursorEnd: 3))
    ]
    let input = NativeWindowInput(source).input
    #expect(input.mousePosition == Coordinate(x: 20, y: 20))
    #expect(input.secondaryPressed && input.middlePressed && !input.pressed)
    #expect(input.scrollStepsY == 0.25 && input.scrollInvertedY == true)
    var observed: Input?
    let runtime = DesktopRuntime(
      content: { viewport in Column(in: viewport.bounds) {} },
      primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {},
      frameCallbacks: .init(prepare: { snapshot, _ in observed = snapshot }))
    defer { runtime.stop() }
    runtime.frame(
      input: input, viewport: .init(size: .init(width: 100, height: 100)), dt: 0,
      present: { _ in })
    #expect(observed?.textEvents == input.textEvents)
    #expect(observed?.secondaryPressed == true && observed?.middlePressed == true)
  }

  @Test func outsideButtonEdgesKeepCoordinates() {
    var source = WaylandInput(width: 100, height: 100)
    source.pointerX = 150
    source.pointerY = 50
    for phase in 0..<3 {
      source.primaryDown = phase == 0
      source.primaryPressed = phase == 1
      source.primaryReleased = phase == 2
      let input = NativeWindowInput(source).input
      #expect(input.mousePosition == Coordinate(x: 150, y: 50))
    }
  }
}
#endif
