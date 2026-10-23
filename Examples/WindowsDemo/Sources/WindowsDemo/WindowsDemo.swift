import Observation
import Roots
import RootsDesktop

@MainActor @Observable
final class DemoModel {
  var count = 0
  var lastKey = "Press a key"
  var clipboard = "Clipboard: not read yet"
}

@main
struct WindowsDemo: RootsApp {
  let model = DemoModel()

  var window: some Window {
    let offscreen = CommandLine.arguments.contains("--offscreen")
    return DesktopWindow(
      "Roots • Windows", size: .init(640, 480), maxFrames: offscreen ? 1 : 0,
      screenshotPath: offscreen ? "windows-demo.ppm" : nil, offscreen: offscreen
    ) { viewport in
      ScrollColumnBlock(key: 9, in: viewport.bounds, gap: 12, showsScrollIndicator: true) {
        LabelBlock(key: 1, "Roots on Windows", extent: 48)
        LabelBlock(key: 2, "Count: \(model.count)")
        ButtonBlock(key: 3, "Increment") { model.count += 1 }
        LabelBlock(key: 4, model.lastKey)
        ButtonBlock(key: 5, "Copy count") {
          model.clipboard =
            DesktopSystem.writeClipboard("Count: \(model.count)")
            ? "Copied count" : "Clipboard unavailable"
        }
        ButtonBlock(key: 6, "Read clipboard") {
          Task { @MainActor in
            model.clipboard = await DesktopSystem.readClipboard() ?? "Clipboard unavailable"
          }
        }
        LabelBlock(key: 7, model.clipboard)
        CanvasBlock(key: 8, extent: 96) { context in
          context.fillRect(context.rect, color: Color(0.08, 0.18, 0.3), radius: 12)
          context.fillRect(
            Rect(context.rect.x + 16, context.rect.y + 16, 32 + Float(model.count % 12) * 24, 64),
            color: .accent, radius: 8)
        }
      }
    }.onKey { event in
      if event.phase == .pressed {
        model.lastKey = "Key: \(event.key)"
        if event.key == .escape {
          DesktopSystem.requestClose()
          return true
        }
      }
      return false
    }
  }
}
