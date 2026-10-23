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
      ScrollColumn(key: 9, in: viewport.bounds, gap: 12, showsScrollIndicator: true) {
        Text("Roots on Windows")
          .selectable(key: 1)
          .padding(horizontal: 12)
          .frame(width: .fill, height: .fixed(48), alignment: .leading)
          .background(.panel)
        Text("Count: \(model.count)")
          .selectable(key: 2)
          .padding(horizontal: 12)
          .frame(width: .fill, height: .fixed(32), alignment: .leading)
          .background(.panel)
        Button(key: 3, "Increment") { model.count += 1 }
        Text(model.lastKey)
          .selectable(key: 4)
          .padding(horizontal: 12)
          .frame(width: .fill, height: .fixed(32), alignment: .leading)
          .background(.panel)
        Button(key: 5, "Copy count") {
          model.clipboard =
            DesktopSystem.writeClipboard("Count: \(model.count)")
            ? "Copied count" : "Clipboard unavailable"
        }
        Button(key: 6, "Read clipboard") {
          Task { @MainActor in
            model.clipboard = await DesktopSystem.readClipboard() ?? "Clipboard unavailable"
          }
        }
        Text(model.clipboard)
          .selectable(key: 7)
          .padding(horizontal: 12)
          .frame(width: .fill, height: .fixed(32), alignment: .leading)
          .background(.panel)
        Canvas(key: 8, extent: 96) { context in
          context.fillRect(context.region, color: Color(0.08, 0.18, 0.3), radius: 12)
          context.fillRect(
            Region(
              context.region.x + 16, context.region.y + 16, 32 + Float(model.count % 12) * 24, 64),
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
