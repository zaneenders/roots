import Foundation
import Roots
import RootsDesktop

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

@main
struct VideoPlayerApp: RootsApp {
  let player: Player

  static func main() async {
    do {
      let app = try Self()
      try await app.window.run()
    } catch {
      FileHandle.standardError.write(Data("VideoPlayer: \(error)\n".utf8))
      exit(1)
    }
  }

  init() throws {
    guard CommandLine.arguments.count == 2 else {
      throw DecodeError(description: "Usage: VideoPlayer /path/to/video.mp4")
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
      throw DecodeError(description: "Expected a regular local file: \(url.path)")
    }
    player = Player(path: url.path)
  }

  var window: some Window {
    DesktopWindow("Video · Roots", width: 960, height: 600) { viewport in
      Column(in: viewport.bounds, gap: 0) {
        Video(player.source, key: 1).frame(width: .fill, height: .fill)
        Text("\(player.status)   |   Space: pause   R: restart   Esc: close")
          .size(16).frame(width: .fill, height: .fixed(36)).background(.panel)
      }
    }
    .onStart { player.start() }
    .onClose { player.stop() }
    .onKey { event in
      guard event.phase == .pressed else { return false }
      switch event.key {
      case .character(" "):
        player.togglePause()
        return true
      case .character("r"), .character("R"):
        player.restart()
        return true
      case .escape:
        DesktopSystem.requestClose()
        return true
      default: return false
      }
    }
  }
}
