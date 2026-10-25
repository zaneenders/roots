import Roots
import Testing

@testable import SwiftWayland
@testable import WaylandBridge

@Test(arguments: [nil, UInt32(150), 180, 210])
func waylandInputAdapterPreservesCoordinatesEdgesAndOrderedKeyEvents(fractionalScale120: UInt32?) {
  var source = WaylandInput(width: 120, height: 80)
  source.bufferScale = fractionalScale120 == nil ? 2 : 1
  source.fractionalScale120 = fractionalScale120
  source.pointerX = 12.5
  source.pointerY = 24.5
  source.pointerInside = true
  source.button(0x110, state: 1)
  source.axis(0, value: 3 * 256, time: 100)
  source.scrollVelocityY = 50
  source.focusLost = true
  source.keyEvents = [
    WaylandKeyEvent(.character("é"), modifiers: [.control, .shift], physicalCode: 16),
    WaylandKeyEvent(.function(12), phase: .repeated, modifiers: .altGraph, physicalCode: 88),
    WaylandKeyEvent(.symbol(0xFE51), phase: .released, physicalCode: 47)
  ]
  let input = NativeWindowInput(source)
  source.resetEdges()
  #expect(input.width == 120 && input.height == 80 && input.bufferScale == source.bufferScale)
  #expect(input.renderScale == fractionalScale120.map { Double($0) / 120 } ?? 2)
  #expect(input.fractionalScale120 == fractionalScale120)
  #expect(input.pointerX == 12.5 && input.pointerY == 24.5 && input.pointerInside)
  #expect(input.primaryDown && input.primaryPressed && !input.primaryReleased)
  #expect(input.scrollY == 3 && input.scrollVelocityY == 50 && input.focusLost)
  #expect(
    input.keyEvents == [
      KeyEvent(.character("é"), modifiers: [.control, .shift], physicalCode: 16),
      KeyEvent(.function(12), phase: .repeated, modifiers: .altGraph, physicalCode: 88),
      KeyEvent(.symbol(0xFE51), phase: .released, physicalCode: 47)
    ])
  #expect(source.keyEvents.isEmpty)
}

@Test func waylandInputAdapterMapsAllNamedKeys() {
  let sourceKeys: [WaylandKey] = [
    .escape, .tab, .enter, .backspace, .delete, .left, .right, .up, .down,
    .home, .end, .pageUp, .pageDown, .shift, .control, .alt, .altGraph,
    .super, .capsLock, .numLock
  ]
  let expected: [Key] = [
    .escape, .tab, .enter, .backspace, .delete, .left, .right, .up, .down,
    .home, .end, .pageUp, .pageDown, .shift, .control, .alt, .altGraph,
    .super, .capsLock, .numLock
  ]
  var source = WaylandInput(width: 1, height: 1)
  source.keyEvents = sourceKeys.map { WaylandKeyEvent($0) }
  #expect(NativeWindowInput(source).keyEvents.map(\.key) == expected)
}

@Test func desktopInputAdapterPreservesTextButtonsAndWheelMetadata() {
  var source = WaylandInput(width: 100, height: 80)
  source.button(0x111, state: 1)
  source.button(0x112, state: 1)
  source.axisSteps(0, value: 30, highResolution: true)
  source.axisDirection(0, inverted: true)
  source.pointerFrame()
  source.textEvents = [
    .init(
      committed: "é", preedit: .init(text: "日", cursorBegin: -1, cursorEnd: -1),
      deleteBefore: 2, deleteAfter: 0)
  ]
  let input = NativeWindowInput(source)
  #expect(input.secondaryDown && input.secondaryPressed && input.middleDown && input.middlePressed)
  #expect(input.scrollStepsY == 0.25 && input.scrollInvertedY == true)
  #expect(
    input.textEvents == [
      .init(
        committed: "é", preedit: .init(text: "日", cursorBegin: -1, cursorEnd: -1),
        deleteBefore: 2, deleteAfter: 0)
    ])
}
