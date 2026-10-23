import Foundation
import Roots
import RootsDesktop

/// Run `swift run Tetris`, or render one deterministic frame without a window:
/// `swift run Tetris --screenshot /tmp/tetris.ppm`.
@main
struct TetrisApp: RootsApp {
  let controller: GameController
  let screenshotPath: String?

  init() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty {
      screenshotPath = nil
    } else if arguments.count == 2, arguments[0] == "--screenshot", !arguments[1].isEmpty {
      screenshotPath = arguments[1]
    } else {
      throw LaunchError.usage
    }
    controller = GameController(seed: screenshotPath == nil ? UInt64.random(in: .min ... .max) : 42)
  }

  var window: some Window {
    DesktopWindow(
      "Tetris · Roots", size: .init(900, 800),
      maxFrames: screenshotPath == nil ? 0 : 1,
      screenshotPath: screenshotPath, offscreen: screenshotPath != nil
    ) { viewport in
      GameBlock(controller: controller, bounds: viewport.bounds)
    }
    .onKey { controller.handleKey($0) }
    .frameDelegate(controller)
  }
}

private enum LaunchError: Error, CustomStringConvertible {
  case usage
  var description: String { "Usage: Tetris [--screenshot /path/to/tetris.ppm]" }
}
