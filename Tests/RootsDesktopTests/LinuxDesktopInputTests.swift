#if os(Linux)
  import Roots
  import Testing

  @testable import RootsDesktop
  @testable import WaylandBridge

  @MainActor
  struct LinuxDesktopInputTests {
    @Test func pointerExitOnlyHidesCoordinatesWhenNoGestureIsCaptured() {
      var snapshot = NativeWindowInput(width: 100, height: 80)
      snapshot.pointerX = 120
      snapshot.pointerY = 90
      #expect(DesktopSystem.input(snapshot).x == -1)
      #expect(DesktopSystem.input(snapshot).y == -1)
      snapshot.pointerInside = true
      #expect(DesktopSystem.input(snapshot).x == 120)
      #expect(DesktopSystem.input(snapshot).y == 90)
      snapshot.pointerInside = false
      snapshot.primaryDown = true
      #expect(DesktopSystem.input(snapshot).x == 120)
      #expect(DesktopSystem.input(snapshot).y == 90)
      snapshot.primaryDown = false
      snapshot.primaryPressed = true
      #expect(DesktopSystem.input(snapshot).x == 120)
      #expect(DesktopSystem.input(snapshot).y == 90)
      snapshot.primaryPressed = false
      snapshot.primaryReleased = true
      #expect(DesktopSystem.input(snapshot).x == 120)
      #expect(DesktopSystem.input(snapshot).y == 90)
      #expect(DesktopSystem.input(snapshot).released)
    }

    @Test func inputMappingPreservesKeysScrollAndFocusLoss() {
      var snapshot = NativeWindowInput(width: 100, height: 80)
      snapshot.primaryPressed = true
      snapshot.scrollX = 2
      snapshot.scrollY = 3
      snapshot.scrollVelocityY = 120
      snapshot.keyEvents = [KeyEvent(.character("q"), modifiers: .control)]
      snapshot.focusLost = true
      let input = DesktopSystem.input(snapshot)
      #expect(input.pressed)
      #expect(input.scrollX == 2 && input.scrollY == 3 && input.scrollVelocityY == 120)
      #expect(input.keyEvents == snapshot.keyEvents)
      #expect(input.focusLost)
    }

    @Test func capturedOutsideDragAndReleaseReachTheRuntimeAndFocusLossCancels() {
      var events: [PointerEvent] = []
      let runtime = DesktopRuntime(
        content: { viewport in
          ColumnBlock(in: viewport.bounds, gap: 0) {
            ElementBlock(key: 1, extent: 80, onPointer: { events.append($0) }) { _ in }
          }
        }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {})
      defer { runtime.stop() }
      let viewport = Viewport(size: .init(100, 80))
      var snapshot = NativeWindowInput(width: 100, height: 80)
      snapshot.pointerInside = true
      snapshot.pointerX = 10
      snapshot.pointerY = 10
      snapshot.primaryPressed = true
      snapshot.primaryDown = true
      runtime.frame(
        input: DesktopSystem.input(snapshot), viewport: viewport, dt: 0, present: { _ in })
      snapshot.pointerInside = false
      snapshot.pointerX = 120
      snapshot.pointerY = 90
      snapshot.primaryPressed = false
      runtime.frame(
        input: DesktopSystem.input(snapshot), viewport: viewport, dt: 0, present: { _ in })
      #expect(events.map(\.phase) == [.pressed, .dragged])
      #expect(events.last?.x == 120 && events.last?.y == 90)
      snapshot.primaryDown = false
      snapshot.primaryReleased = true
      runtime.frame(
        input: DesktopSystem.input(snapshot), viewport: viewport, dt: 0, present: { _ in })
      #expect(events.map(\.phase) == [.pressed, .dragged, .released])
      #expect(events.last?.x == 120 && events.last?.y == 90)
      snapshot.pointerInside = true
      snapshot.pointerX = 10
      snapshot.pointerY = 10
      snapshot.primaryReleased = false
      snapshot.primaryPressed = true
      snapshot.primaryDown = true
      runtime.frame(
        input: DesktopSystem.input(snapshot), viewport: viewport, dt: 0, present: { _ in })
      snapshot.pointerInside = false
      snapshot.primaryPressed = false
      snapshot.primaryDown = false
      snapshot.focusLost = true
      runtime.frame(
        input: DesktopSystem.input(snapshot), viewport: viewport, dt: 0, present: { _ in })
      #expect(events.map(\.phase) == [.pressed, .dragged, .released, .pressed, .cancelled])
      snapshot.focusLost = false
      runtime.frame(
        input: DesktopSystem.input(snapshot), viewport: viewport, dt: 0, present: { _ in })
      #expect(events.count == 5)
    }
  }
#endif
