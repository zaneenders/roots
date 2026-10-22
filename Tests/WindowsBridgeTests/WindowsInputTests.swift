import Roots
import Testing

@testable import WindowsBridge

struct WindowsInputTests {
  @Test func virtualKeysMapWithoutAssumingAUSKeyboardLayout() {
    #expect(WindowsKeyboard.key(virtualKey: 0x25) == .left)
    #expect(WindowsKeyboard.key(virtualKey: 0x2E) == .delete)
    #expect(WindowsKeyboard.key(virtualKey: 0x87) == .function(24))
    #expect(WindowsKeyboard.key(virtualKey: 0xA3) == .control)
    #expect(WindowsKeyboard.key(virtualKey: 0xA5) == .alt)
    #expect(WindowsKeyboard.key(virtualKey: 0x5B) == .super)
    #expect(WindowsKeyboard.key(virtualKey: 0x41) == nil)
    #expect(WindowsKeyboard.key(virtualKey: 0xBA) == nil)
    #expect(WindowsKeyboard.shortcut(virtualKey: 0x41, scalar: 0x51) == .character("q"))
    #expect(WindowsKeyboard.shortcut(virtualKey: 0x41, scalar: 0x8000_005E) == nil)
    #expect(WindowsKeyboard.text(0xD800) == nil)
    #expect(WindowsKeyboard.text(0x110000) == nil)
    #expect(WindowsKeyboard.text(0x0D) == nil)
    #expect(WindowsKeyboard.text(0x1F600) == "😀")
  }

  @Test func textComesOnlyFromCommittedCharactersAndKeepsReleaseIdentity() {
    var state = WindowsInputState()
    state.key(virtualKey: 0x41, scanCode: 30, phase: .pressed, modifiers: .shift)
    #expect(state.consume().keyEvents.isEmpty)
    state.text(scalar: 0x41, scanCode: 30, phase: .pressed, modifiers: .shift)
    state.text(scalar: 0x41, scanCode: 30, phase: .repeated, modifiers: .shift)
    state.key(virtualKey: 0x41, scanCode: 30, phase: .released, modifiers: [])
    #expect(
      state.consume().keyEvents == [
        KeyEvent(.character("A"), modifiers: .shift, physicalCode: 30),
        KeyEvent(.character("A"), phase: .repeated, modifiers: .shift, physicalCode: 30),
        KeyEvent(.character("A"), phase: .released, physicalCode: 30),
      ])
    #expect(state.consume().keyEvents.isEmpty)
  }

  @Test func controlShortcutsDoNotDuplicateCharacterMessages() {
    var state = WindowsInputState()
    state.key(virtualKey: 0x43, scanCode: 46, scalar: 0x43, phase: .pressed, modifiers: .control)
    state.text(scalar: 3, scanCode: 46, phase: .pressed, modifiers: .control)
    state.text(scalar: 0x63, scanCode: 46, phase: .pressed, modifiers: .control)
    state.key(virtualKey: 0x43, scanCode: 46, phase: .released, modifiers: .control)
    #expect(
      state.consume().keyEvents == [
        KeyEvent(.character("c"), modifiers: .control, physicalCode: 46),
        KeyEvent(.character("c"), phase: .released, modifiers: .control, physicalCode: 46),
      ])
  }

  @Test func nativeTextHintHandlesLayoutSpecificVirtualKeys() {
    var state = WindowsInputState()
    state.key(
      virtualKey: 0xC1, scanCode: 0x73, scalar: 0x2F, producesText: true,
      phase: .pressed, modifiers: [])
    state.text(scalar: 0x2F, scanCode: 0x73, phase: .pressed, modifiers: [])
    #expect(state.consume().keyEvents == [KeyEvent(.character("/"), physicalCode: 0x73)])
  }

  @Test func altGraphTextIsNotAControlAltShortcut() {
    var state = WindowsInputState()
    let modifiers: KeyModifiers = [.control, .alt, .altGraph]
    state.key(virtualKey: 0x45, scanCode: 18, scalar: 0x45, phase: .pressed, modifiers: modifiers)
    state.text(scalar: 0x20AC, scanCode: 18, phase: .pressed, modifiers: modifiers)
    #expect(
      state.consume().keyEvents == [
        KeyEvent(.character("€"), modifiers: .altGraph, physicalCode: 18)
      ])
  }

  @Test func rightAltIsOnlyAltGraphWhenTheLayoutReportsAltGraph() {
    var state = WindowsInputState()
    state.key(virtualKey: 0xA5, scanCode: 0x138, phase: .pressed, modifiers: .alt)
    state.key(virtualKey: 0xA5, scanCode: 0x138, phase: .released, modifiers: [])
    state.key(virtualKey: 0xA5, scanCode: 0x138, phase: .pressed, modifiers: .altGraph)
    state.key(virtualKey: 0xA5, scanCode: 0x138, phase: .released, modifiers: [])
    #expect(state.consume().keyEvents.map(\.key) == [.alt, .alt, .altGraph, .altGraph])
  }

  @Test func focusLossReleasesHeldInputAndClearsStaleEdges() {
    var state = WindowsInputState()
    state.pointer(x: 20, y: 30, inside: true)
    state.button(down: true)
    state.key(virtualKey: 0x25, scanCode: 0x14B, phase: .pressed, modifiers: [])
    state.text(scalar: 0x1F600, scanCode: 30, phase: .pressed, modifiers: [])
    state.scroll(x: 2, y: 4)
    _ = state.consume()
    state.loseFocus()
    let input = state.consume()
    #expect(input.focusLost)
    #expect(input.released)
    #expect(!input.pressed)
    #expect(input.x == -1 && input.y == -1)
    #expect(input.scrollX == 0 && input.scrollY == 0)
    #expect(
      input.keyEvents == [
        KeyEvent(.character("😀"), phase: .released, physicalCode: 30),
        KeyEvent(.left, phase: .released, physicalCode: 0x14B),
      ])
    #expect(!state.consume().focusLost)
    state.key(virtualKey: 0x25, scanCode: 0x14B, phase: .released, modifiers: [])
    #expect(state.consume().keyEvents.isEmpty)
  }

  @Test func pointerCaptureKeepsDragCoordinatesUntilRelease() {
    var state = WindowsInputState()
    state.pointer(x: 5, y: 6, inside: true)
    state.button(down: true)
    #expect(state.consume().pressed)
    state.pointer(x: -8, y: 7, inside: false)
    #expect(state.consume().x == -8)
    state.button(down: false)
    #expect(state.consume().released)
    #expect(state.consume().x == -1)
    state.button(down: false)
    #expect(!state.consume().released)
  }

  @Test func scrollAccumulationIsBoundedAndEdgesConsumeOnce() {
    var state = WindowsInputState()
    state.scroll(x: 0.25, y: 2)
    state.scroll(x: 0.5, y: 3)
    state.scroll(x: .nan, y: .infinity)
    let input = state.consume()
    #expect(input.scrollX == 0.75)
    #expect(input.scrollY == 5)
    #expect(state.consume().scrollY == 0)
    state.scroll(x: .greatestFiniteMagnitude, y: -.greatestFiniteMagnitude)
    #expect(state.consume().scrollX == 100_000)
  }

  @Test func overflowResetsHeldInputInsteadOfDroppingReleases() {
    var state = WindowsInputState()
    state.key(virtualKey: 0x25, scanCode: 0x14B, phase: .pressed, modifiers: [])
    for _ in 0..<WindowsInputState.keyLimit {
      state.key(virtualKey: 0x25, scanCode: 0x14B, phase: .repeated, modifiers: [])
    }
    let input = state.consume()
    #expect(input.focusLost)
    #expect(input.keyEvents == [KeyEvent(.left, phase: .released, physicalCode: 0x14B)])
    state.key(virtualKey: 0x25, scanCode: 0x14B, phase: .released, modifiers: [])
    #expect(state.consume().keyEvents.isEmpty)
  }
}
