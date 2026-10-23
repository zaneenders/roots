import AppKit
import Roots
import Testing

@testable import MacOSBridge

@Test func macOSKeyboardPreservesModifierIdentityAndEditingKeys() {
  #expect(MacOSKeyboard.modifiers([.command, .option, .shift]) == [.super, .alt, .shift])
  #expect(MacOSKeyboard.modifiers(.control) == .control)
  #expect(MacOSKeyboard.key(code: 51, characters: "\u{7f}") == .backspace)
  #expect(MacOSKeyboard.key(code: 117, characters: nil) == .delete)
  #expect(MacOSKeyboard.key(code: 36, characters: "\r") == .enter)
  #expect(MacOSKeyboard.key(code: 76, characters: "\r") == .enter)
  #expect(MacOSKeyboard.key(code: 0, characters: "é") == .character("é"))
  #expect(MacOSKeyboard.key(code: 0, characters: "") == .symbol(0))
}

@Test @MainActor func nativeKeyboardUsesLayoutShortcutCharactersAndNativeRepeat() throws {
  let event = try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 0,
      windowNumber: 0, context: nil, characters: "\u{1}", charactersIgnoringModifiers: "a",
      isARepeat: true, keyCode: 0))
  let key = MacOSKeyboard.event(event)
  #expect(key.key == .character("a"))
  #expect(key.phase == .repeated)
  #expect(key.modifiers == [.super, .control])
  #expect(key.physicalCode == 0)
}

@Test func pointerCaptureSurvivesLeavingUntilReleaseAndEdgesAccumulate() {
  var state = MacOSInputState()
  state.pointer(x: 5, y: 6, inside: true)
  state.button(down: true)
  state.pointer(x: -20, y: 120, inside: false)
  #expect(state.primaryDown && state.input.pressed)
  #expect(state.input.x == -20 && state.input.y == 120)
  state.consumeEdges()
  #expect(state.primaryDown && !state.input.pressed)
  state.button(down: false)
  #expect(state.input.released && !state.primaryDown)
  #expect(state.input.x == -20 && state.input.y == 120)
  state.consumeEdges()
  #expect(state.input.x == -1 && state.input.y == -1)
  state.pointer(x: 5, y: 6, inside: true)
  state.button(down: true)
  state.button(down: false)
  #expect(state.input.pressed && state.input.released)
}

@Test func focusLossReleasesHeldStateClearsRepeatAndBoundsQueuedInput() {
  var state = MacOSInputState()
  state.pointer(x: 1, y: 2, inside: true)
  state.button(down: true)
  state.key(KeyEvent(.character("a"), modifiers: .super, physicalCode: 0))
  for _ in 0..<1000 {
    state.key(KeyEvent(.character("a"), phase: .repeated, modifiers: .super, physicalCode: 0))
  }
  #expect(state.input.keyEvents.count == MacOSInputState.keyLimit - 1)
  state.loseFocus()
  #expect(state.input.focusLost)
  #expect(state.input.released && !state.primaryDown && !state.input.pressed)
  #expect(state.modifiers.isEmpty)
  #expect(state.input.keyEvents == [KeyEvent(.character("a"), phase: .released, physicalCode: 0)])
  #expect(state.input.x == -1 && state.input.y == -1)
  state.consumeEdges()
  #expect(!state.input.focusLost)
}

@Test func nativeMomentumIsAccumulatedWithoutSyntheticVelocity() {
  var state = MacOSInputState()
  state.scroll(x: 1.25, y: 2.5)
  state.scroll(x: -0.25, y: 3.5)
  state.scroll(x: .nan, y: .infinity)
  #expect(state.input.scrollX == 1 && state.input.scrollY == 6)
  #expect(state.input.scrollVelocityY == nil)
  state.consumeEdges()
  #expect(state.input.scrollX == 0 && state.input.scrollY == 0)
}

@Test func modifierTransitionsPublishEdgesWithoutRemappingCommand() {
  var state = MacOSInputState()
  state.flags(.super, code: 55, key: .super)
  state.flags([.super, .shift], code: 56, key: .shift)
  state.flags(.shift, code: 55, key: .super)
  #expect(state.input.keyEvents.map(\.key) == [.super, .shift, .super])
  #expect(state.input.keyEvents.map(\.phase) == [.pressed, .pressed, .released])
  #expect(state.modifiers == .shift)
}

@Test(arguments: [
  (Key.shift, KeyModifiers.shift, UInt32(56), UInt32(60)),
  (Key.control, KeyModifiers.control, UInt32(59), UInt32(62)),
  (Key.alt, KeyModifiers.alt, UInt32(58), UInt32(61)),
  (Key.super, KeyModifiers.super, UInt32(55), UInt32(54)),
])
func overlappingModifiersPreservePhysicalTransitions(
  key: Key, flag: KeyModifiers, left: UInt32, right: UInt32
) {
  var state = MacOSInputState()
  state.flags(flag, code: left, key: key)
  state.flags(flag, code: right, key: key)
  state.flags(flag, code: left, key: key)
  state.flags([], code: right, key: key)
  #expect(
    state.input.keyEvents == [
      KeyEvent(key, modifiers: flag, physicalCode: left),
      KeyEvent(key, modifiers: flag, physicalCode: right),
      KeyEvent(key, phase: .released, modifiers: flag, physicalCode: left),
      KeyEvent(key, phase: .released, physicalCode: right),
    ])
  state.loseFocus()
  #expect(
    state.input.keyEvents == [
      KeyEvent(key, phase: .released, modifiers: flag, physicalCode: left),
      KeyEvent(key, phase: .released, physicalCode: right),
    ])
}

@Test func focusLossReleasesBothPhysicalModifiersAndAllowsNewPresses() {
  var state = MacOSInputState()
  state.flags(.shift, code: 56, key: .shift)
  state.flags(.shift, code: 60, key: .shift)
  state.loseFocus()
  #expect(
    state.input.keyEvents == [
      KeyEvent(.shift, phase: .released, physicalCode: 56),
      KeyEvent(.shift, phase: .released, physicalCode: 60),
    ])
  state.consumeEdges()
  state.flags(.shift, code: 60, key: .shift)
  #expect(state.input.keyEvents == [KeyEvent(.shift, modifiers: .shift, physicalCode: 60)])
}

@Test func capsLockUsesTheToggleStateRatherThanPhysicalPresses() {
  var state = MacOSInputState()
  state.flags(.capsLock, code: 57, key: .capsLock)
  state.flags(.capsLock, code: 57, key: .capsLock)
  state.flags([], code: 57, key: .capsLock)
  state.flags([], code: 57, key: .capsLock)
  #expect(
    state.input.keyEvents == [
      KeyEvent(.capsLock, modifiers: .capsLock, physicalCode: 57),
      KeyEvent(.capsLock, phase: .released, physicalCode: 57),
    ])
}

@Test func focusLossPreservesQueuedReleasesAndDoesNotDuplicateRepressedKeys() {
  var state = MacOSInputState()
  let a = KeyEvent(.character("a"), physicalCode: 0)
  let b = KeyEvent(.character("b"), physicalCode: 11)
  let releaseA = KeyEvent(.character("a"), phase: .released, physicalCode: 0)
  let releaseB = KeyEvent(.character("b"), phase: .released, physicalCode: 11)
  state.key(a)
  state.key(b)
  state.consumeEdges()
  state.key(releaseA)
  state.key(a)
  state.loseFocus()
  #expect(state.input.keyEvents == [releaseA, releaseB])
  state.loseFocus()
  #expect(state.input.keyEvents == [releaseA, releaseB])
  state.consumeEdges()
  state.loseFocus()
  #expect(state.input.keyEvents.isEmpty)
}

@Test func queueOverflowReservesReleasesForPreviouslyDeliveredKeys() {
  var state = MacOSInputState()
  let a = KeyEvent(.character("a"), physicalCode: 0)
  let b = KeyEvent(.character("b"), physicalCode: 11)
  state.key(a)
  state.key(b)
  state.consumeEdges()
  for _ in 0..<1000 {
    state.key(KeyEvent(.character("a"), phase: .repeated, physicalCode: 0))
  }
  #expect(state.input.keyEvents.count == MacOSInputState.keyLimit - 2)
  state.key(KeyEvent(.character("c"), physicalCode: 8))
  let releaseA = KeyEvent(.character("a"), phase: .released, physicalCode: 0)
  let releaseB = KeyEvent(.character("b"), phase: .released, physicalCode: 11)
  state.key(releaseA)
  state.key(releaseB)
  #expect(state.input.keyEvents.count == MacOSInputState.keyLimit)
  #expect(Array(state.input.keyEvents.suffix(2)) == [releaseA, releaseB])
  state.loseFocus()
  #expect(state.input.keyEvents == [releaseA, releaseB])
}

@Test func queuedReleasesStayBoundedAcrossRepeatedPressCycles() {
  var state = MacOSInputState()
  for _ in 0..<1000 {
    state.key(KeyEvent(.character("a"), physicalCode: 0))
    state.key(KeyEvent(.character("a"), phase: .released, physicalCode: 0))
  }
  #expect(state.input.keyEvents.count == MacOSInputState.keyLimit)
  state.loseFocus()
  #expect(state.input.keyEvents == [KeyEvent(.character("a"), phase: .released, physicalCode: 0)])
}

@Test func codeLessEventsCannotUseReservedReleaseSlots() {
  var state = MacOSInputState()
  state.key(KeyEvent(.shift, physicalCode: 56))
  state.consumeEdges()
  for _ in 0..<1000 { state.key(KeyEvent(.character("x"))) }
  state.flags([], code: 56, key: .shift)
  #expect(state.input.keyEvents.count == MacOSInputState.keyLimit)
  #expect(state.input.keyEvents.last == KeyEvent(.shift, phase: .released, physicalCode: 56))
  state.consumeEdges()
  state.loseFocus()
  #expect(state.input.keyEvents.isEmpty)
}

@Test func focusLossRetainsAReleaseQueuedAfterThePressWasConsumed() {
  var state = MacOSInputState()
  state.key(KeyEvent(.character("a"), physicalCode: 0))
  state.consumeEdges()
  let release = KeyEvent(.character("a"), phase: .released, physicalCode: 0)
  state.key(release)
  state.loseFocus()
  #expect(state.input.keyEvents == [release])
}

@Test func manyHeldKeysReserveSpaceAcrossFrames() {
  var state = MacOSInputState()
  for code in 0..<UInt32(MacOSInputState.keyLimit) {
    state.key(KeyEvent(.symbol(code), physicalCode: code))
    state.consumeEdges()
  }
  state.loseFocus()
  #expect(state.input.keyEvents.count == MacOSInputState.keyLimit - 1)
  #expect(
    Set(state.input.keyEvents.compactMap(\.physicalCode)).count == state.input.keyEvents.count)
  #expect(state.input.keyEvents.allSatisfy { $0.phase == .released })
  state.consumeEdges()
  state.key(KeyEvent(.symbol(256), phase: .repeated, physicalCode: 256))
  #expect(state.input.keyEvents == [KeyEvent(.symbol(256), phase: .repeated, physicalCode: 256)])
  state.loseFocus()
  #expect(state.input.keyEvents == [KeyEvent(.symbol(256), phase: .released, physicalCode: 256)])
}

@Test func droppedModifierPressDoesNotTurnItsReleaseIntoAPress() {
  var state = MacOSInputState()
  state.flags(.shift, code: 56, key: .shift)
  state.consumeEdges()
  for _ in 0..<1000 { state.key(KeyEvent(.character("x"))) }
  state.flags(.shift, code: 60, key: .shift)
  #expect(!state.input.keyEvents.contains { $0.physicalCode == 60 })
  state.consumeEdges()
  state.flags(.shift, code: 60, key: .shift)
  state.flags([], code: 56, key: .shift)
  #expect(
    state.input.keyEvents == [
      KeyEvent(.shift, phase: .released, modifiers: .shift, physicalCode: 60),
      KeyEvent(.shift, phase: .released, physicalCode: 56),
    ])
}
