import Roots
import Testing

@testable import WaylandBridge

struct X11InputTests {
  @Test func keyboardFocusLossPersistsUntilDeliveredEdgesAreReset() {
    var input = NativeWindowInput(width: 100, height: 80)
    input.primaryDown = true
    input.appendKeyEvent(KeyEvent(.enter))
    input.leaveKeyboard()
    #expect(input.focusLost)
    #expect(input.keyEvents.isEmpty)
    #expect(!input.primaryDown && input.primaryReleased)
    input.leavePointer()
    input.appendKeyEvent(KeyEvent(.tab))
    #expect(input.focusLost)
    let delivered = input
    input.resetEdges()
    #expect(delivered.focusLost && delivered.primaryReleased)
    #expect(!input.focusLost && !input.primaryReleased && input.keyEvents.isEmpty)
  }

  @Test func pointerLeavePreservesDragAndOutsideReleaseCoordinates() {
    var input = NativeWindowInput(width: 100, height: 80)
    input.primaryDown = true
    input.pointerInside = true
    input.pointerX = 120
    input.pointerY = -5
    input.leavePointer()
    #expect(!input.pointerInside && input.primaryDown)
    #expect(input.pointerX == 120 && input.pointerY == -5)
    input.releaseButtons()
    #expect(input.primaryReleased && !input.primaryDown)
    #expect(input.pointerX == 120 && input.pointerY == -5)
  }

  @Test func stalledInputQueueIsBoundedAndResetPreservesPersistentState() {
    var input = NativeWindowInput(width: 100, height: 80)
    for index in 0..<1_000 { input.appendKeyEvent(KeyEvent(.symbol(UInt32(index)))) }
    #expect(input.keyEvents.count == 256)
    #expect(input.keyEvents.first?.key == .symbol(744))
    input.pointerInside = true
    input.primaryDown = true
    input.primaryPressed = true
    input.scrollX = 20
    input.scrollY = 40
    input.scrollVelocityY = 100
    input.resetEdges()
    #expect(input.primaryDown && input.pointerInside && input.width == 100 && input.height == 80)
    #expect(!input.primaryPressed && input.keyEvents.isEmpty)
    #expect(input.scrollX == 0 && input.scrollY == 0 && input.scrollVelocityY == nil)
  }
}
