import Roots
import Testing

@testable import WaylandBridge

struct X11KeyboardTests {
  @Test func detectableRepeatKeepsOnePhysicalIdentity() {
    var keyboard = X11Keyboard(detectableRepeat: true)
    var input = NativeWindowInput(width: 100, height: 100)
    keyboard.key(38, pressed: true, time: 10, input: &input)
    keyboard.key(38, pressed: true, time: 20, input: &input)
    keyboard.key(38, pressed: false, time: 30, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.pressed, .repeated, .released])
    #expect(input.keyEvents.allSatisfy { $0.physicalCode == 38 })
  }

  @Test func traditionalRepeatPairDoesNotBecomeFreshPress() {
    var keyboard = X11Keyboard()
    var input = NativeWindowInput(width: 100, height: 100)
    keyboard.key(36, pressed: true, time: 10, input: &input)
    keyboard.key(36, pressed: false, time: 20, input: &input)
    keyboard.key(36, pressed: true, time: 20, input: &input)
    keyboard.key(36, pressed: false, time: 30, input: &input)
    keyboard.flushRelease(input: &input)
    #expect(input.keyEvents.map(\.phase) == [.pressed, .repeated, .released])
  }

  @Test func unrelatedKeyPreservesRealReleaseOrdering() {
    var keyboard = X11Keyboard()
    var input = NativeWindowInput(width: 100, height: 100)
    keyboard.key(38, pressed: true, time: 10, input: &input)
    keyboard.key(38, pressed: false, time: 20, input: &input)
    keyboard.key(39, pressed: true, time: 21, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.pressed, .released, .pressed])
    #expect(input.keyEvents.map(\.physicalCode) == [38, 38, 39])
  }

  @Test func traditionalRepeatSplitAcrossCappedBatchIsStillRepeated() {
    var keyboard = X11Keyboard()
    var input = NativeWindowInput(width: 100, height: 100)
    keyboard.key(36, pressed: true, time: 10, input: &input)
    keyboard.key(36, pressed: false, time: 20, input: &input)
    keyboard.finishEventBatch(queueDrained: false, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.pressed])
    input.resetEdges()
    keyboard.key(36, pressed: true, time: 20, input: &input)
    keyboard.finishEventBatch(queueDrained: true, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.repeated])
  }

  @Test func focusLossClearsHeldAndPendingRelease() {
    var keyboard = X11Keyboard()
    var input = NativeWindowInput(width: 100, height: 100)
    keyboard.key(38, pressed: true, time: 10, input: &input)
    keyboard.key(38, pressed: false, time: 20, input: &input)
    keyboard.leave(input: &input)
    keyboard.key(38, pressed: true, time: 21, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.pressed])
  }

  @Test func heldKeyOnFocusReturnCannotBecomeAFreshShortcut() {
    var keyboard = X11Keyboard(detectableRepeat: true)
    var input = NativeWindowInput(width: 100, height: 100)
    var bitmap = [UInt8](repeating: 0, count: 31)
    bitmap[36 / 8 - 1] = 1 << (36 % 8)
    keyboard.restoreHeldKeys(bitmap)
    keyboard.key(36, pressed: true, time: 20, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.repeated])
    keyboard.leave(input: &input)
    keyboard.restoreHeldKeys([UInt8](repeating: 0, count: 31))
    keyboard.key(36, pressed: true, time: 30, input: &input)
    #expect(input.keyEvents.map(\.phase) == [.pressed])
  }
}
