import Foundation
import Roots
import RootsDesktop

@main struct Path3DApp: RootsApp {
  let model = Path3DModel(rendering: CommandLine.arguments.contains("--analytic") ? .analytic : .ribbon)

  var window: some Window {
    DesktopWindow(
      "3D Path · Roots", width: 1000, height: 800,
      maxFrames: CommandLine.arguments.contains("--offscreen") ? 3 : 0,
      screenshotPath: screenshotPath, offscreen: CommandLine.arguments.contains("--offscreen")
    ) { viewport in
      Path3DPage(model: model, bounds: viewport.bounds)
    }
    .onPrepareFrame { input, dt in
      if input.focusLost {
        model.playing = false
        model.orbiting = false
      }
      model.advance(dt)
    }
    .animationFrames { model.needsAnimation }
  }

  private var screenshotPath: String? {
    guard let index = CommandLine.arguments.firstIndex(of: "--screenshot"), index + 1 < CommandLine.arguments.count
    else {
      return nil
    }
    return CommandLine.arguments[index + 1]
  }
}

struct Path3DPage: Block {
  let model: Path3DModel
  let bounds: Region

  var body: some Block {
    Stack(in: bounds) {
      Column(gap: 12) {
        Text("3D Path").size(bounds.width < 600 ? 24 : 32)
        Row(gap: 8) {
          Button(key: 1, model.playing ? "Pause" : "Play", extent: max(0, min(100, (bounds.width - 56) / 3))) {
            model.playing.toggle()
          }
          Button(
            key: 2, model.orbiting ? "Stop orbit" : "Orbit", extent: max(0, min(140, (bounds.width - 56) / 3)),
            size: 16
          ) { model.orbiting.toggle() }
          Button(key: 3, "Reset", extent: max(0, min(100, (bounds.width - 56) / 3))) { model.reset() }
        }.frame(height: .fixed(36))
        Element(
          key: 4, extent: max(0, bounds.height - (bounds.width < 600 ? 134 : 145)), color: Color(0.025, 0.035, 0.05),
          onPointer: { model.pointer($0) }, onScroll: { model.zoom($0.deltaY) },
          paint: { model.paint(&$0) }
        )
        .frame(width: .fill, height: .fill)
      }
      .padding(20).frame(width: .fill, height: .fill)
    }.background(Color(0.05, 0.065, 0.085))
  }
}
