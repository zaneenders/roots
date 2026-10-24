import Observation
import Roots
import RootsDesktop
import TetrisCore

@MainActor @Observable
final class GameController {
  private(set) var game: Game
  @ObservationIgnored private var changedDuringInput = false

  init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
    game = Game(seed: seed)
  }

  var needsAnimationFrame: Bool { game.status == .playing }

  func prepareFrame(input: inout Input, dt: Float) {
    if input.focusLost {
      game.pause()
      input.keyEvents.removeAll()
    } else {
      game.advance(by: Double(dt))
    }
    changedDuringInput = false
  }

  func frameUpdate(after input: Input) -> DesktopFrameUpdate {
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
