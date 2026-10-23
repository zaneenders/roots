import Roots
import RootsDesktop

@main
struct TetrisApp: RootsApp {
  let controller = GameController()

  var window: some Window {
    DesktopWindow("Tetris · Roots", size: .init(900, 800)) { viewport in
      GameBlock(controller: controller, bounds: viewport.bounds)
    }
    .onKey { controller.handleKey($0) }
    .frameDelegate(controller)
  }
}
