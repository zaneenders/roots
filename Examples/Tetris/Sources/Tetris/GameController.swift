import Observation
import Roots
import RootsDesktop
import TetrisCore

/// Roots tracks observed properties read while building and painting blocks.
/// The desktop frame clock drives gravity, so there is no timer or background task.
@MainActor @Observable
final class GameController: DesktopFrameDelegate {
  private(set) var game: Game
  @ObservationIgnored private var changedDuringInput = false

  init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
    game = Game(seed: seed)
  }

  var needsAnimationFrame: Bool { game.status == .playing }

  func prepareFrame(input: inout Input, dt: Float) {
    if input.focusLost {
      game.pause()
      // A key arriving with focus loss must not immediately unpause or restart the game.
      input.keyEvents.removeAll()
    } else {
      game.advance(by: Double(dt))
    }
    changedDuringInput = false
  }

  func frameUpdate(after input: Input) -> DesktopFrameUpdate {
    // Input is dispatched after blocks are built. Rebuild once to keep labels and
    // button titles in sync with the board in the very same presented frame.
    changedDuringInput ? .rebuild(pointer: .init(input.x, input.y)) : .present
  }

  func togglePause() {
    game.togglePause()
    changedDuringInput = true
  }

  func restart() {
    game.restart()
    changedDuringInput = true
  }

  /// Window-level shortcuts work even after clicking a button. Tab and Enter
  /// remain available for Roots' built-in button focus and keyboard activation.
  @discardableResult
  func handleKey(_ event: KeyEvent) -> Bool {
    guard event.phase != .released,
      event.modifiers.intersection([.control, .alt, .super, .altGraph]).isEmpty
    else { return false }

    switch event.key {
    case .left: game.move(-1)
    case .right: game.move(1)
    case .down: game.softDrop()
    case .up, .character("x"), .character("X"):
      if event.phase == .pressed { game.rotate() }
    case .character("z"), .character("Z"):
      if event.phase == .pressed { game.rotate(clockwise: false) }
    case .character(" "):
      if event.phase == .pressed { game.hardDrop() }
    case .escape, .character("p"), .character("P"):
      if event.phase == .pressed { game.togglePause() }
    case .character("r"), .character("R"):
      if event.phase == .pressed { game.restart() }
    default: return false
    }
    changedDuringInput = true
    return true
  }
}
