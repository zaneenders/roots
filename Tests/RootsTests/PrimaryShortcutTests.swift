import Testing

@testable import Roots

@Test func readOnlySelectionUsesInjectedPrimaryShortcutWithoutRemappingInput() {
  var ui = UIStore()
  var copied: [String] = []
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Rect(0, 0, 200, 40))
    frame.label(key: 1, "Selectable text", extent: 40)
    frame.end()
  }
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true, released: true), build: build, present: { _ in })
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
    primaryShortcut: .super,
    build: build, present: { _ in })
  #expect(ui.selectedText == nil)
  ui.frame(
    input: Input(keyEvents: [
      KeyEvent(.character("a"), modifiers: .super), KeyEvent(.character("c"), modifiers: .super),
      KeyEvent(.character("c"), phase: .repeated, modifiers: .super)
    ]), primaryShortcut: .super, onCopy: { copied.append($0) }, build: build, present: { _ in })
  #expect(ui.selectedText == "Selectable text")
  #expect(copied == ["Selectable text"])
}
