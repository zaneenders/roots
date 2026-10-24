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
    DesktopWindow("Example", width: 1180, height: 820) { viewport in
      Column(in: viewport.bounds) {
        Text("Hello")
          .size(20)
          .selectable(key: 1)
          .alignment(.leading)
          .padding(horizontal: 12)
          .frame(width: .fill, height: .fixed(32))
          .background(.panel)
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
      var window: some Window { DesktopWindow("Unused") { _ in BlockBuilder.buildBlock() } }
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) { try await FailingApp.main() }
  }

  @Test func invalidWindowDoesNotStartApplicationLifecycle() async {
    var events: [String] = []
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", nodeCapacity: -1) { _ in BlockBuilder.buildBlock() }
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
          _ in BlockBuilder.buildBlock()
        }.run()
      }
    }
  }

  @Test func viewportUsesLogicalBounds() {
    let viewport = Viewport(size: .init(width: 200, height: 100), scale: 2)
    #expect(viewport.bounds == Region(0, 0, 200, 100))
    #expect(viewport.scale == 2)
  }

  @Test func invalidConfigurationFailsBeforeBuildingContent() async {
    var builds = 0
    for size: Size in [
      Size(width: 0, height: 10), Size(width: -1, height: 10), Size(width: .nan, height: 10),
      Size(width: 10, height: .infinity), Size(width: 8193, height: 10)
    ] {
      let window = DesktopWindow("Invalid", width: size.width, height: size.height) { _ in
        builds += 1
        return BlockBuilder.buildBlock()
      }
      await #expect(throws: DesktopWindowError.invalidConfiguration) { try await window.run() }
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", offscreen: true) { _ in BlockBuilder.buildBlock() }.run()
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", maxFrames: -1) { _ in BlockBuilder.buildBlock() }.run()
    }
    await #expect(throws: DesktopWindowError.invalidConfiguration) {
      try await DesktopWindow("Invalid", screenshotPath: "/tmp/unused.ppm") { _ in BlockBuilder.buildBlock() }
        .run()
    }
    #expect(builds == 0)
  }

  @Test func cancellationIsCheckedBeforeOpeningAWindow() async {
    let task = Task { @MainActor in
      try await DesktopWindow("Cancelled") { _ in BlockBuilder.buildBlock() }.run()
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
        "Failed screenshot", width: 32, height: 32, maxFrames: 1,
        screenshotPath: directory.path, offscreen: true
      ) { _ in BlockBuilder.buildBlock() }
      .onStart { events.append("start") }
      .onClose { events.append("close") }
      .run()
    }
    #expect(events == ["start", "close"])
  }

  @Test func frameModifiersPreserveWindowValueSemanticsAndCallbackOrder() async throws {
    var events: [String] = []
    let original = DesktopWindow(
      "Callbacks", width: 32, height: 32, maxFrames: 1, offscreen: true
    ) { viewport in
      events.append("build")
      return Column(in: viewport.bounds) { Button(key: 1, "Action", onClick: {}) }
    }
    let configured =
      original
      .onPrepareFrame { _, _ in Issue.record("Replaced callback should not run") }
      .onPrepareFrame { input, dt in
        events.append("prepare")
        input.mousePosition = Coordinate(x: 7, y: -1)
        #expect(dt > 0)
      }
      .onFrameUpdate { input in
        events.append("update")
        #expect(input.mousePosition == Coordinate(x: 7, y: -1))
        return .rebuild(mousePosition: nil)
      }
      .onFinishFrame { state in
        events.append("finish")
        #expect(state.state(for: 1) != nil)
      }
      .animationFrames {
        events.append("animation")
        return false
      }

    try await original.run()
    #expect(events == ["build"])
    events.removeAll()
    try await configured.run()
    #expect(events == ["prepare", "build", "update", "build", "finish", "animation"])
  }

  @Test func offscreenWindowRebuildsContentAndWritesScreenshot() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var frames = 0
    var events: [String] = []
    try await DesktopWindow(
      "Offscreen", width: 64, height: 48, maxFrames: 3, screenshotPath: path.path, offscreen: true
    ) {
      viewport in
      #expect(events == ["start"])
      frames += 1
      #expect(viewport.bounds == Region(0, 0, 64, 48))
      return Column(in: viewport.bounds, gap: 0) {
        Canvas(key: 1, extent: 48) { context in
          context.fillRect(context.region, color: Color(1, 0, 0))
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
