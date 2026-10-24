import Testing

@testable import Roots

private func idleButton(_ frame: inout UIFrame) {
  frame.beginColumn(in: Region(0, 0, 100, 40))
  frame.button(key: 1, "Button")
  frame.end()
}

@Test func hoverAndFlashSettleExactlyAndWakeAgain() throws {
  var ui = UIStore()
  ui.frame(build: idleButton, present: { _ in })
  #expect(ui.needsAnimationFrame == false)
  let hover = Input(mousePosition: .init(x: 10, y: 10))
  ui.frame(input: hover, build: idleButton, present: { _ in })
  #expect(ui.needsAnimationFrame == true)
  for _ in 0..<90 { ui.frame(input: hover, build: idleButton, present: { _ in }) }
  let declared = ui.handle(for: 1)
  let handle = try #require(declared)
  #expect(ui.state(for: handle)?.hoverAnimation == 1)
  #expect(ui.needsAnimationFrame == false)
  ui.frame(
    input: Input(mousePosition: .init(x: 10, y: 10), pressed: true), build: idleButton,
    present: { _ in })
  ui.frame(
    input: Input(mousePosition: .init(x: 10, y: 10), released: true), build: idleButton,
    present: { _ in })
  #expect(ui.needsAnimationFrame == true)
  #expect(ui.state(for: handle)?.clicks == 1)
  for _ in 0..<90 { ui.frame(build: idleButton, present: { _ in }) }
  #expect(ui.state(for: handle)?.hoverAnimation == 0)
  #expect(ui.needsAnimationFrame == false)
}

@Test func momentumRequestsFramesOnlyUntilItSettlesOrIsInterrupted() {
  var ui = UIStore()
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 1, in: Region(0, 0, 100, 100))
    frame.label(key: 2, "Content", extent: 2000)
    frame.end()
  }
  let fling = Input(mousePosition: .init(x: 10, y: 10), scrollY: 10, scrollVelocityY: 160)
  ui.frame(input: fling, build: build, present: { _ in })
  #expect(ui.needsAnimationFrame == true)
  for _ in 0..<120 { ui.frame(build: build, present: { _ in }) }
  #expect(ui.needsAnimationFrame == false)
  ui.frame(input: fling, build: build, present: { _ in })
  #expect(ui.needsAnimationFrame == true)
  ui.frame(input: Input(keyEvents: [KeyEvent(.escape)]), build: build, present: { _ in })
  #expect(ui.needsAnimationFrame == false)
}
