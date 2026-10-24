import Roots
import RootsDesktop

@main
struct TetrisApp: RootsApp {
  let controller = GameController()

  var window: some Window {
    DesktopWindow("Tetris · Roots", width: 900, height: 800) { viewport in
      GameBlock(controller: controller, bounds: viewport.bounds)
    }
    .onKey { controller.handleKey($0) }
    .onPrepareFrame { controller.prepareFrame(input: &$0, dt: $1) }
    .onFrameUpdate { controller.frameUpdate(after: $0) }
    .animationFrames { controller.needsAnimationFrame }
  }
}
