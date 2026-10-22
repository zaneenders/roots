import Foundation
@_spi(Hosting) import Roots
import Testing

@testable import WindowsBridge

@MainActor struct WindowsRenderingTests {
  @Test func invalidConfigurationsFailBeforeRendering() async {
    for configuration in [
      WindowsWindowConfiguration(size: .init(.nan, 30), maxFrames: 1),
      WindowsWindowConfiguration(size: .init(30, .infinity), maxFrames: 1),
      WindowsWindowConfiguration(size: .init(8193, 30), maxFrames: 1),
      WindowsWindowConfiguration(size: .init(0, 30), maxFrames: 1),
      WindowsWindowConfiguration(maxFrames: 0),
      WindowsWindowConfiguration(title: "bad\0title", maxFrames: 1),
    ] {
      await #expect(throws: WindowsWindowError.invalidConfiguration) {
        try await WindowsWindow.renderOffscreen(configuration: configuration) { _, _ in
          Issue.record("Invalid configuration reached the renderer")
        }
      }
    }
  }

  @Test func cpuFramesUsePublicBlocksAndWriteDeterministicScreenshots() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var host = UIHost()
    var times: [Double] = []
    try await WindowsWindow.renderOffscreen(
      configuration: .init(size: .init(32.2, 24.5), maxFrames: 3, screenshotPath: path.path)
    ) { snapshot, renderer in
      times.append(snapshot.timeSeconds)
      #expect(snapshot.size == SIMD2<Float>(33, 25))
      host.frame(input: snapshot.input, dt: 1 / 60) {
        ColumnBlock(in: Rect(0, 0, snapshot.size.x, snapshot.size.y), gap: 0) {
          CanvasBlock(key: 1, extent: snapshot.size.y) { context in
            context.fillRect(context.rect, color: Color(1, 0, 0))
          }
        }
      } present: {
        renderer.render($0)
      }
    }
    #expect(times == [0, 1 / 60, 2 / 60])
    let image = try Data(contentsOf: path)
    #expect(String(decoding: image.prefix(13), as: UTF8.self) == "P6\n33 25\n255\n")
    #expect(image.count == 13 + 33 * 25 * 3)
    let center = 13 + (12 * 33 + 16) * 3
    #expect(Array(image[center..<center + 3]) == [255, 0, 0])
  }

  @Test func screenshotWriteErrorsPropagate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: (any Error).self) {
      try await WindowsWindow.renderOffscreen(
        configuration: .init(size: .init(2, 2), maxFrames: 1, screenshotPath: directory.path)
      ) { _, _ in }
    }
  }

  @Test func cancelledOffscreenTaskDoesNotBuildContent() async {
    let task = Task { @MainActor in
      try await WindowsWindow.renderOffscreen(configuration: .init(maxFrames: 1)) { _, _ in
        Issue.record("Cancelled window reached the renderer")
      }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
