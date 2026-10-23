import DesktopTestSupport
import Foundation
import Roots
import RootsDesktop
import Testing

@MainActor
private final class AppLifetime {
  static var initialized = 0
  static var released = 0
  init() { Self.initialized += 1 }
  isolated deinit { Self.released += 1 }
}

private struct TestApp: RootsApp {
  static var runs = 0
  let model = AppLifetime()
  var window: some Window { TestWindow() }

  private struct TestWindow: Window {
    func run() async throws {
      #expect(AppLifetime.initialized == 1)
      #expect(AppLifetime.released == 0)
      await Task.yield()
      #expect(AppLifetime.released == 0)
      TestApp.runs += 1
    }
  }
}

private struct ExampleApp: RootsApp {
  var window: some Window {
    DesktopWindow("Example", size: .init(1180, 820)) { viewport in
      ColumnBlock(in: viewport.bounds) {
        LabelBlock(key: 1, "Hello")
      }
    }.onKey { $0.key == .escape }
  }
}

@MainActor
struct DesktopWindowTests {
  @Test func defaultMainCreatesOneAppAndKeepsItAliveUntilWindowReturns() async throws {
    try await TestApp.main()
    #expect(TestApp.runs == 1)
    #expect(AppLifetime.released == 1)
    _ = ExampleApp().window
  }

  @Test func defaultMainPropagatesWindowErrors() async {
    struct FailingApp: RootsApp {
      var window: some Window { FailingWindow() }
    }
    struct FailingWindow: Window {
      func run() async throws { throw DesktopWindowError.invalidConfiguration }
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) { try await FailingApp.main() }
  }

  @Test func defaultMainPropagatesInitializationErrors() async {
    struct FailingApp: RootsApp {
      init() throws { throw DesktopWindowError.invalidConfiguration }
      var window: some Window { DesktopWindow("Unused") { _ in EmptyBlock() } }
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) { try await FailingApp.main() }
  }

  @Test func invalidWindowDoesNotStartApplicationLifecycle() async {
    var events: [String] = []
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", nodeCapacity: -1) { _ in EmptyBlock() }
        .onStart { events.append("start") }
        .onClose { events.append("close") }
        .run()
    }
    #expect(events.isEmpty)
    for (acceleration, deceleration): (Float, Float) in [
      (-1, 4), (.nan, 4), (1, 0), (1, .infinity)
    ] {
      await #expect(throws: DesktopWindowError.invalidConfiguration) {
        try await DesktopWindow(
          "Invalid", scrollAcceleration: acceleration, scrollDeceleration: deceleration
        ) {
          _ in EmptyBlock()
        }.run()
      }
    }
  }

  @Test func viewportUsesLogicalBounds() {
    let viewport = Viewport(size: .init(200, 100), scale: 2)
    #expect(viewport.bounds == Rect(0, 0, 200, 100))
    #expect(viewport.scale == 2)
  }

  @Test func invalidConfigurationFailsBeforeBuildingContent() async {
    var builds = 0
    for size: SIMD2<Float> in [
      .init(0, 10), .init(-1, 10), .init(.nan, 10), .init(10, .infinity), .init(8193, 10)
    ] {
      let window = DesktopWindow("Invalid", size: size) { _ in
        builds += 1
        return EmptyBlock()
      }
      await #expect(throws: DesktopWindowError.invalidConfiguration) { try await window.run() }
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", offscreen: true) { _ in EmptyBlock() }.run()
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", maxFrames: -1) { _ in EmptyBlock() }.run()
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", screenshotPath: "/tmp/unused.ppm") { _ in EmptyBlock() }
        .run()
    }
    #expect(builds == 0)
  }

  @Test func cancellationIsCheckedBeforeOpeningAWindow() async {
    let task = Task { @MainActor in
      try await DesktopWindow("Cancelled") { _ in EmptyBlock() }.run()
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}

@Suite(
  GraphicsTest(), .serialized,
  .enabled("Metal or surfaceless EGL/OpenGL ES 3 is unavailable") {
    await GraphicsAvailability.offscreen
  })
@MainActor
struct DesktopWindowRenderingTests {
  @Test func backendFailureStillClosesApplicationLifecycle() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var events: [String] = []
    await #expect(throws: (any Error).self) {
      try await DesktopWindow(
        "Failed screenshot", size: .init(32, 32), maxFrames: 1,
        screenshotPath: directory.path, offscreen: true
      ) { _ in EmptyBlock() }
      .onStart { events.append("start") }
      .onClose { events.append("close") }
      .run()
    }
    #expect(events == ["start", "close"])
  }

  @Test func offscreenWindowRebuildsContentAndWritesScreenshot() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var frames = 0
    var events: [String] = []
    try await DesktopWindow(
      "Offscreen", size: .init(64, 48), maxFrames: 3, screenshotPath: path.path, offscreen: true
    ) {
      viewport in
      #expect(events == ["start"])
      frames += 1
      #expect(viewport.bounds == Rect(0, 0, 64, 48))
      return ColumnBlock(in: viewport.bounds, gap: 0) {
        CanvasBlock(key: 1, extent: 48) { context in
          context.fillRect(context.rect, color: Color(1, 0, 0))
        }
      }
    }
    .onStart { events.append("start") }
    .onClose { events.append("close") }
    .run()
    #expect(events == ["start", "close"])
    #expect(frames == 3)
    let image = try Data(contentsOf: path)
    #expect(String(decoding: image.prefix(13), as: UTF8.self) == "P6\n64 48\n255\n")
    #expect(Array(image.suffix(3)) == [255, 0, 0])
  }
}
