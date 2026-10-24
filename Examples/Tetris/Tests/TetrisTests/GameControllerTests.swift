import Roots
import RootsDesktop
import Testing

@testable import Tetris

@MainActor
struct GameControllerTests {
  @Test func releasesAndShortcutModifiedKeysDoNotChangeTheGame() {
    let controller = GameController(seed: 42)
    let initial = controller.game.active
    #expect(!controller.handleKey(KeyEvent(.left, phase: .released)))
    for modifier: KeyModifiers in [.control, .alt, .super, .altGraph] {
      #expect(!controller.handleKey(KeyEvent(.left, modifiers: modifier)))
    }
    #expect(controller.game.active == initial)
  }

  @Test func onlyMovementAndSoftDropRepeat() {
    let controller = GameController(seed: 42)
    #expect(controller.handleKey(KeyEvent(.left, phase: .repeated)))
    #expect(controller.game.active?.origin.x == 2)
    #expect(controller.handleKey(KeyEvent(.down, phase: .repeated)))
    #expect(controller.game.score == 1)
    let moved = controller.game.active
    for key: Key in [
      .up, .character("x"), .character("z"), .character(" "), .character("p"), .escape,
      .character("r")
    ] {
      #expect(controller.handleKey(KeyEvent(key, phase: .repeated)))
      #expect(controller.game.active == moved)
      #expect(controller.game.status == .playing && controller.game.score == 1)
    }
  }

  @Test func tabEnterAndUnrecognizedKeysRemainAvailableToRoots() {
    let controller = GameController(seed: 42)
    for key: Key in [.tab, .enter, .character("q")] {
      #expect(!controller.handleKey(KeyEvent(key)))
    }
  }

  @Test func focusLossPausesBeforeGravityAndSuppressesSimultaneousKeys() {
    let controller = GameController(seed: 42)
    let initial = controller.game.active
    var input = Input(
      keyEvents: [KeyEvent(.character("p")), KeyEvent(.character("r"))], focusLost: true)
    controller.prepareFrame(input: &input, dt: 1)
    #expect(controller.game.status == .paused && controller.game.active == initial)
    #expect(input.keyEvents.isEmpty && !controller.needsAnimationFrame)
    input = Input()
    controller.prepareFrame(input: &input, dt: 30)
    #expect(controller.game.active == initial && controller.game.status == .paused)
    controller.handleKey(KeyEvent(.character("p")))
    controller.prepareFrame(input: &input, dt: 0.2)
    #expect(controller.game.active == initial && controller.game.status == .playing)
  }

  @Test func pauseAndRestartButtonsShareKeyboardBehavior() {
    let controller = GameController(seed: 42)
    #expect(controller.needsAnimationFrame)
    controller.handleKey(KeyEvent(.character("p")))
    #expect(controller.game.status == .paused && !controller.needsAnimationFrame)
    controller.togglePause()
    #expect(controller.game.status == .playing && controller.needsAnimationFrame)
    controller.handleKey(KeyEvent(.character(" ")))
    #expect(controller.game.board.contains { $0 != nil })
    controller.restart()
    #expect(controller.game.board.allSatisfy { $0 == nil } && controller.game.score == 0)
  }

  @Test func dispatchedCommandsRebuildLabelsInTheSameFrame() {
    let controller = GameController(seed: 42)
    var input = Input(x: 30, y: 40)
    controller.prepareFrame(input: &input, dt: 0)
    guard case .present = controller.frameUpdate(after: input) else {
      Issue.record("No input change should need a second build")
      return
    }
    controller.togglePause()
    guard case .rebuild(let mousePosition) = controller.frameUpdate(after: input) else {
      Issue.record("A button action should rebuild the same frame")
      return
    }
    #expect(mousePosition == Coordinate(x: 30, y: 40))
    controller.prepareFrame(input: &input, dt: 0)
    guard case .present = controller.frameUpdate(after: input) else {
      Issue.record("The rebuild flag should reset on the next frame")
      return
    }
  }
}
