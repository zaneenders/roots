import Testing

@testable import SwiftWayland

@Test func pointerEdgesAccumulateUntilTheNextFrame() {
  var input = WaylandInput(width: 100, height: 80)
  input.pointerInside = true
  input.button(0x111, state: 1)
  #expect(!input.primaryDown)
  input.button(0x110, state: 1)
  input.button(0x110, state: 1)
  #expect(input.primaryPressed && input.primaryDown)
  input.resetEdges()
  #expect(!input.primaryPressed && input.primaryDown)
  input.leavePointer()
  #expect(!input.pointerInside && !input.primaryDown && input.primaryReleased)
  input.resetEdges()
  input.button(0x110, state: 1)
  input.button(0x110, state: 0)
  #expect(input.primaryPressed && input.primaryReleased && !input.primaryDown)
}

@Test func keyEventsAndScrollResetWithoutLosingPersistentInput() {
  var keyboard = Keyboard()
  var input = WaylandInput(width: 100, height: 80)
  keyboard.key(15, pressed: false, input: &input)
  #expect(input.keyEvents == [WaylandKeyEvent(.symbol(0), phase: .released, physicalCode: 15)])
  input.resetEdges()
  keyboard.key(15, pressed: true, input: &input)
  keyboard.key(57, pressed: true, input: &input)
  keyboard.key(1, pressed: true, input: &input)
  #expect(input.keyEvents.map(\.physicalCode) == [15, 57, 1])
  input.scrollX = -5
  input.scrollY = 15
  input.pointerX = 7
  input.pointerY = 8
  input.pointerInside = true
  input.resetEdges()
  #expect(input.keyEvents.isEmpty)
  #expect(input.scrollX == 0 && input.scrollY == 0)
  #expect(input.pointerInside && input.pointerX == 7 && input.pointerY == 8)
  #expect(input.width == 100 && input.height == 80)
  keyboard.key(28, pressed: true, input: &input)
  #expect(input.keyEvents == [WaylandKeyEvent(.symbol(0), physicalCode: 28)])
}

@Test func trackpadReleaseUsesProtocolTimeAndPublishesVelocityOnlyOnce() throws {
  var input = WaylandInput(width: 100, height: 80)
  input.axis(0, value: 5 * 256, time: 100)
  input.axisSource(1)
  input.pointerFrame()
  input.resetEdges()
  input.axisSource(1)
  input.axis(0, value: 4 * 256, time: 110)
  input.axis(1, value: -3 * 256, time: 110)
  input.pointerFrame()
  #expect(input.scrollY == 4 && input.scrollX == -3)
  #expect(input.scrollVelocityY == nil)
  input.resetEdges()
  input.axisStop(1, time: 110)
  input.pointerFrame()
  #expect(input.scrollVelocityY == nil)
  input.axisStop(0, time: 110)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 400)
  input.resetEdges()
  input.pointerFrame()
  #expect(input.scrollVelocityY == nil)
}
@Test func trackpadSamplesHandleTimestampWrapReversalAndSameFrameRelease() {
  var input = WaylandInput(width: 100, height: 80)
  input.axisSource(1)
  input.axis(0, value: 4 * 256, time: UInt32.max - 4)
  input.pointerFrame()
  input.axisSource(1)
  input.axis(0, value: 4 * 256, time: 5)
  input.pointerFrame()
  input.axisSource(1)
  input.axis(0, value: -3 * 256, time: 15)
  input.axisStop(0, time: 15)
  input.pointerFrame()
  #expect(input.scrollVelocityY == -300)
  input.axisSource(1)
  input.axis(0, value: 2 * 256, time: 25)
  input.pointerFrame()
  #expect(input.scrollVelocityY == nil)
  input.axisStop(0, time: 25)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}
@Test func trackpadPauseAndPointerLeaveDiscardOldVelocity() {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110] {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  input.axisStop(0, time: 300)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
  input.resetEdges()
  for time: UInt32 in [400, 410] {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  input.leavePointer()
  input.axisStop(0, time: 410)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}
@Test func trackpadVelocitySamplingIgnoresDuplicateTimeAndCapsExtremeSpeed() {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 100, 101] {
    input.axisSource(1)
    input.axis(0, value: .max, time: time)
    input.pointerFrame()
  }
  input.axisStop(0, time: 101)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 8_000)
}
@Test func longGapBetweenTrackpadSamplesCannotReuseTheOldSpeed() {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110, 300] {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  input.axisStop(0, time: 300)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}
@Test func zeroDistanceReleaseAfterAPauseDoesNotReviveOldVelocity() {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110] {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  input.axis(0, value: 0, time: 300)
  input.axisSource(1)
  input.axisStop(0, time: 300)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}
@Test func keyboardFocusLossResetsHeldPointerAndQueuedInputWithoutPointerExit() {
  var input = WaylandInput(width: 100, height: 80)
  input.pointerInside = true
  input.pointerX = 7
  input.pointerY = 8
  input.button(0x110, state: 1)
  input.button(0x110, state: 0)
  input.button(0x110, state: 1)
  input.keyEvents = [WaylandKeyEvent(.enter)]
  input.scrollX = 5
  input.scrollY = 10
  input.scrollVelocityY = 500
  input.leaveKeyboard()
  #expect(input.focusLost)
  #expect(!input.primaryDown && !input.primaryPressed && !input.primaryReleased)
  #expect(input.keyEvents.isEmpty)
  #expect(input.scrollX == 0 && input.scrollY == 0 && input.scrollVelocityY == nil)
  #expect(input.pointerInside && input.pointerX == 7 && input.pointerY == 8)
  input.resetEdges()
  input.button(0x110, state: 1)
  #expect(input.primaryPressed && input.primaryDown)
  input.button(0x110, state: 0)
  #expect(input.primaryReleased && !input.primaryDown)
}

@Test(arguments: [UInt32(0), 2, 3, nil]) func nonFingerSourcesNeverGenerateMomentum(source: UInt32?) {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110] {
    if let source { input.axisSource(source) }
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  #expect(input.scrollY == 10)
  input.axisStop(0, time: 110)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}

@Test(arguments: [UInt32(0), nil]) func changingOrOmittingSourceDiscardsPriorFingerVelocity(
  source: UInt32?
) {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110] {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  if let source { input.axisSource(source) }
  input.axis(0, value: 5 * 256, time: 120)
  input.axisStop(0, time: 120)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}

@Test(arguments: [Float(1), -1]) func zeroDistanceAtFingerLiftPreservesReleaseVelocity(
  direction: Float
) {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110] {
    input.axis(0, value: Int32(direction * 5 * 256), time: time)
    input.axisSource(1)
    input.pointerFrame()
    input.resetEdges()
  }
  input.axis(0, value: 0, time: 120)
  input.axisSource(1)
  input.axisStop(0, time: 120)
  input.pointerFrame()
  #expect(input.scrollY == 0)
  #expect(input.scrollVelocityY == direction * 500)
}

@Test(arguments: [false, true]) func keyboardFocusLossDiscardsTrackpadMomentumHistory(
  newSample: Bool
) {
  var input = WaylandInput(width: 100, height: 80)
  for time: UInt32 in [100, 110] {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: time)
    input.pointerFrame()
  }
  input.leaveKeyboard()
  input.resetEdges()
  if newSample {
    input.axisSource(1)
    input.axis(0, value: 5 * 256, time: 120)
  }
  input.axisStop(0, time: 120)
  input.pointerFrame()
  #expect(input.scrollVelocityY == 0)
}

@Test func secondaryAndMiddleEdgesSurviveFramesAndCancelOnLeave() {
  var input = WaylandInput(width: 10, height: 10)
  input.button(0x111, state: 1)
  input.button(0x112, state: 1)
  input.button(0x111, state: 7)
  #expect(input.secondaryDown && input.middleDown)
  #expect(input.secondaryPressed && input.middlePressed)
  #expect(!input.primaryDown)
  input.resetEdges()
  #expect(input.secondaryDown && input.middleDown)
  #expect(!input.secondaryPressed && !input.middlePressed)
  input.leavePointer()
  #expect(input.secondaryReleased && input.middleReleased)
  #expect(!input.secondaryDown && !input.middleDown)
  input.button(0x111, state: 1)
  input.button(0x111, state: 0)
  #expect(input.secondaryPressed && input.secondaryReleased && !input.secondaryDown)
  input.button(0x112, state: 1)
  input.leaveKeyboard()
  #expect(!input.middleDown && !input.middlePressed && !input.middleReleased)
}

@Test func wheelStepsPreferValue120WithoutDoublingLogicalDistance() {
  var input = WaylandInput(width: 10, height: 10)
  input.axis(0, value: 2560, time: 1)
  input.axisSteps(0, value: 1, highResolution: false)
  input.axisSteps(0, value: 30, highResolution: true)
  input.axisSteps(0, value: 30, highResolution: true)
  input.axisSteps(1, value: -1, highResolution: false)
  input.axisDirection(0, inverted: true)
  input.pointerFrame()
  #expect(input.scrollY == 10 && input.scrollX == 0)
  #expect(input.scrollStepsY == 0.5 && input.scrollStepsX == -1)
  #expect(input.scrollInvertedY == true && input.scrollInvertedX == nil)
  input.pointerFrame()
  #expect(input.scrollStepsY == 0.5)
  input.resetEdges()
  input.axisSteps(0, value: -30, highResolution: true)
  input.pointerFrame()
  #expect(input.scrollStepsY == -0.25 && input.scrollStepsX == 0)
  #expect(input.scrollInvertedY == nil)
  input.axisSteps(0, value: 120, highResolution: true)
  input.leavePointer()
  input.resetEdges()
  input.pointerFrame()
  #expect(input.scrollStepsY == 0)
}
