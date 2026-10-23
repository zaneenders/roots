import DesktopTestSupport
import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import MacOSBridge

@Test @MainActor func invalidOffscreenConfigurationsDoNotInvokeFrames() async {
  for configuration in [
    WindowConfiguration(logicalSize: .init(0, 1), maxFrames: 1),
    WindowConfiguration(logicalSize: .init(.nan, 1), maxFrames: 1),
    WindowConfiguration(logicalSize: .init(8193, 1), maxFrames: 1),
    WindowConfiguration(maxFrames: 0), WindowConfiguration(maxFrames: -1)
  ] {
    do {
      try await MacOSWindow.renderOffscreen(configuration: configuration) { _, _ in
        Issue.record("Invalid configuration invoked a frame")
      }
      Issue.record("Invalid configuration succeeded")
    } catch {
      #expect(error as? MacOSWindowError == .invalidConfiguration)
    }
  }
}

@Test @MainActor func cancelledOffscreenSessionDoesNotInvokeFrames() async {
  let task = Task { @MainActor in
    try await MacOSWindow.renderOffscreen(configuration: .init(maxFrames: 1)) { _, _ in
      Issue.record("Cancelled session invoked a frame")
    }
  }
  task.cancel()
  do {
    try await task.value
    Issue.record("Cancelled session succeeded")
  } catch {
    #expect(error is CancellationError)
  }
}

@Suite(GraphicsTest(), .enabled("Metal is unavailable") { await GraphicsAvailability.offscreen })
@MainActor struct MetalRenderingTests {
  @Test @MainActor func offscreenFramesHaveDeterministicTimeAndOwnedScreenshots() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("capture.ppm")
    var frames = 0
    try await MacOSWindow.renderOffscreen(
      configuration: .init(logicalSize: .init(17, 13), maxFrames: 2, screenshotPath: path.path)
    ) { snapshot, frame in
      #expect(snapshot.timeSeconds == Double(frames) / 60)
      #expect(snapshot.drawableSize == .init(17, 13))
      frames += 1
      let draws = [DrawRect(Rect(0, 0, 17, 13), Color(1, 0, 0))]
      frame.render(draws.span)
    }
    #expect(frames == 2)
    let image = try Data(contentsOf: path)
    let header = Data("P6\n17 13\n255\n".utf8)
    #expect(image.starts(with: header))
    #expect(image.count == header.count + 17 * 13 * 3)
    #expect(pixel(image, width: 17, height: 13, x: 8, y: 6) == [255, 0, 0])
  }

  @Test @MainActor func renderingPreservesOrderClipsOrientationAndReusesCompletedStorage()
    async throws
  {
    let renderer = try MetalRenderer(logicalSize: .init(17, 13), drawableSize: .init(34, 26))
    for count in [1025, 3, 2049] {
      var draws = [DrawRect](repeating: DrawRect(Rect(0, 0, 17, 13), Color(1, 0, 0)), count: count)
      draws.append(DrawRect(Rect(0, 0, 17, 13), Color(0, 1, 0), clip: Rect(0, 0, 8, 6)))
      draws.append(DrawRect(Rect(0, 0, 17, 13), Color(0, 0, 1), clip: Rect(0, 0, 0, 1)))
      draws.append(DrawRect(Rect(0, 0, 17, 13), .text, clip: Rect(.nan, 0, 1, 1)))
      draws.append(DrawRect(Rect(12, 9, 5, 4), Color(0, 0, 1)))
      draws.append(DrawRect(Rect(8, 0, 9, 6), Color(0, 0, 1, 0.5)))
      let image = try #require(await renderer.render(readback: true) { $0.render(draws.span) })
      #expect(pixel(image, width: 34, height: 26, x: 4, y: 4) == [0, 255, 0])
      #expect(pixel(image, width: 34, height: 26, x: 20, y: 16) == [255, 0, 0])
      #expect(pixel(image, width: 34, height: 26, x: 30, y: 22) == [0, 0, 255])
      let blended = pixel(image, width: 34, height: 26, x: 20, y: 4)
      #expect(abs(Int(blended[0]) - 128) <= 1 && blended[1] == 0 && abs(Int(blended[2]) - 128) <= 1)
    }
    let empty = try #require(await renderer.render(readback: true) { _ in })
    #expect(pixel(empty, width: 34, height: 26, x: 4, y: 4) == [10, 13, 18])
  }

  @Test @MainActor func glyphMipSamplingMatchesCPUWithinRoundingTolerance() async throws {
    let renderer = try MetalRenderer(logicalSize: .init(40, 56), drawableSize: .init(40, 56))
    let draws = [
      DrawRect(Rect(0, 0, 40, 56), Color(0, 0, 0)),
      DrawRect(Rect(0, 0, 20, 28), Color(1, 1, 1), glyphUV: FontAtlas.shared.glyphUV("A")),
      DrawRect(Rect(20, 28, 10, 14), Color(1, 1, 1), glyphUV: FontAtlas.shared.glyphUV("B"))
    ]
    let cpu = CPURenderer(width: 40, height: 56)
    cpu.render(draws.span)
    let image = try #require(await renderer.render(readback: true) { $0.render(draws.span) })
    let headerCount = Data("P6\n40 56\n255\n".utf8).count
    let pixels = Array(image.dropFirst(headerCount))
    #expect(pixels.max()! > 200)
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max()!
    #expect(maximumError <= 3)
  }

  @Test @MainActor func roundedEdgesKeepCenterOpaqueAndCornersClear() async throws {
    let renderer = try MetalRenderer(logicalSize: .init(20, 20), drawableSize: .init(40, 40))
    let draws = [
      DrawRect(Rect(0, 0, 20, 20), Color(0, 0, 0)),
      DrawRect(Rect(2, 2, 16, 16), Color(1, 1, 1), radius: 8)
    ]
    let image = try #require(await renderer.render(readback: true) { $0.render(draws.span) })
    #expect(pixel(image, width: 40, height: 40, x: 20, y: 20) == [255, 255, 255])
    #expect(pixel(image, width: 40, height: 40, x: 4, y: 4) == [0, 0, 0])
    #expect(pixel(image, width: 40, height: 40, x: 2, y: 20) == [0, 0, 0])
  }

  @Test @MainActor func analyticLinesAndInsideStrokesMatchCPU() async throws {
    let renderer = try MetalRenderer(logicalSize: .init(64, 48), drawableSize: .init(64, 48))
    var ui = UIHost()
    var draws: [DrawRect] = []
    ui.frame(
      build: {
        RowBlock(in: Rect(0, 0, 64, 48)) {
          CanvasBlock(key: 1, extent: 64) { context in
            context.fillRect(context.rect, color: Color(0, 0, 0))
            context.strokeRect(Rect(4, 4, 24, 24), color: Color(0, 1, 0, 0.7), radius: 6, width: 2)
            context.strokeLine(
              from: .init(32, 6), to: .init(56, 24), color: Color(1, 1, 1, 0.6), width: 3)
            context.strokeLine(
              from: .init(56, 30), to: .init(32, 42), color: Color(1, 0, 0), width: 2, cap: .butt)
          }
        }
      },
      present: { span in
        for draw in span { draws.append(draw) }
      })
    let cpu = CPURenderer(width: 64, height: 48)
    cpu.render(draws.span)
    let image = try #require(await renderer.render(readback: true) { $0.render(draws.span) })
    let pixels = Array(image.dropFirst(Data("P6\n64 48\n255\n".utf8).count))
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(pixels.count == cpu.pixels.count)
    #expect(maximumError <= 4)
  }

  @Test @MainActor func joinedStrokesBlendOnceAndPreserveOrderAroundInstancedRectangles()
    async throws
  {
    let renderer = try MetalRenderer(logicalSize: .init(48, 40), drawableSize: .init(48, 40))
    let stroke = try #require(
      PolylineStroke(points: [.init(8, 8), .init(32, 28), .init(8, 28), .init(32, 8)], width: 4))
    let draws = [
      DrawRect(Rect(0, 0, 48, 40), Color(0, 0, 0)),
      DrawRect(polyline: stroke, color: Color(1, 1, 1, 0.5), clip: Rect(4, 4, 32, 28)),
      DrawRect(Rect(40, 30, 4, 4), Color(1, 0, 0))
    ]
    let cpu = CPURenderer(width: 48, height: 40)
    cpu.render(draws.span)
    let image = try #require(await renderer.render(readback: true) { $0.render(draws.span) })
    let pixels = Array(image.dropFirst(Data("P6\n48 40\n255\n".utf8).count))
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(pixels.count == cpu.pixels.count)
    #expect(maximumError <= 4)
    _ = try #require(await renderer.render(readback: true) { $0.render([draws[1]].span) })
  }

  @Test @MainActor func cancellationDrainsSubmittedWorkBeforeAllowingReuse() async throws {
    let renderer = try MetalRenderer(logicalSize: .init(8, 8), drawableSize: .init(8, 8))
    var task: Task<Data?, any Error>?
    task = Task { @MainActor in
      try await renderer.render(readback: true) { frame in
        let draws = [DrawRect(Rect(0, 0, 8, 8), Color(1, 0, 0))]
        frame.render(draws.span)
        task?.cancel()
      }
    }
    do {
      _ = try await task!.value
      Issue.record("Cancelled rendering succeeded")
    } catch {
      #expect(error is CancellationError)
    }
    let image = try #require(
      await renderer.render(readback: true) { frame in
        let draws = [DrawRect(Rect(0, 0, 8, 8), Color(0, 1, 0))]
        frame.render(draws.span)
      })
    #expect(pixel(image, width: 8, height: 8, x: 4, y: 4) == [0, 255, 0])
  }

  @Test @MainActor func failedScreenshotWriteDoesNotPreventAnotherSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
      try await MacOSWindow.renderOffscreen(
        configuration: .init(logicalSize: .init(8, 8), maxFrames: 1, screenshotPath: directory.path)
      ) { _, _ in }
      Issue.record("Writing a screenshot to a directory succeeded")
    } catch {
      #expect(error is CocoaError)
    }
    let path = directory.appendingPathComponent("recovered.ppm")
    try await MacOSWindow.renderOffscreen(
      configuration: .init(logicalSize: .init(8, 8), maxFrames: 1, screenshotPath: path.path)
    ) { _, frame in
      let draws = [DrawRect(Rect(0, 0, 8, 8), Color(0, 0, 1))]
      frame.render(draws.span)
    }
    let image = try Data(contentsOf: path)
    #expect(pixel(image, width: 8, height: 8, x: 4, y: 4) == [0, 0, 255])
  }

  private func pixel(_ image: Data, width: Int, height: Int, x: Int, y: Int) -> [UInt8] {
    let header = Data("P6\n\(width) \(height)\n255\n".utf8).count
    let offset = header + (y * width + x) * 3
    return Array(image[offset..<offset + 3])
  }
}
