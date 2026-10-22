#if os(Linux)
  import DesktopTestSupport
  import Foundation
  import Observation
  import Roots
  import RootsCPU
  import Testing

  @testable import RootsDesktop

  private struct BarApp: RootsApp {
    var window: some Window {
      WaylandBar(height: 26, namespace: "org.example.bar") { viewport in
        RowBlock(in: viewport.bounds) {
          LabelBlock(key: 1, "Status")
        }
      }
    }
  }

  @MainActor @Observable
  private final class BarModel {
    var red: Float = 0
  }

  @MainActor
  struct WaylandBarTests {
    @Test func configurationSelectsPassiveLayerRoleWithoutToplevelConstraints() throws {
      _ = BarApp().window
      let bar = WaylandBar(
        height: 26, namespace: "org.example.bar", overlayHeight: 32, maxFrames: 2,
        screenshotPath: "bar.ppm"
      ) { _ in EmptyBlock() }
      try bar.validate()
      let configuration = bar.configuration
      #expect(configuration.topBar)
      #expect(configuration.height == 26)
      #expect(configuration.topBarOverlayHeight == 32)
      #expect(configuration.layerNamespace == "org.example.bar")
      #expect(configuration.minimumWidth == 0 && configuration.minimumHeight == 0)
      #expect(configuration.maxFrames == 2 && configuration.screenshotPath == "bar.ppm")
    }

    @Test func invalidConfigurationNeverStartsLifecycleOrBuildsContent() async {
      let configurations: [WaylandBar<EmptyBlock>] = [
        .init(height: 0) { _ in EmptyBlock() },
        .init(height: -1) { _ in EmptyBlock() },
        .init(height: 8193) { _ in EmptyBlock() },
        .init(height: .max) { _ in EmptyBlock() },
        .init(namespace: "") { _ in EmptyBlock() },
        .init(namespace: "invalid\0namespace") { _ in EmptyBlock() },
        .init(overlayHeight: -1) { _ in EmptyBlock() },
        .init(overlayHeight: .max) { _ in EmptyBlock() },
        .init(height: 8192, overlayHeight: 1) { _ in EmptyBlock() },
        .init(maxFrames: -1) { _ in EmptyBlock() },
        .init(screenshotPath: "bar.ppm") { _ in EmptyBlock() },
        .init(nodeCapacity: -1) { _ in EmptyBlock() },
        .init(scrollAcceleration: -.infinity) { _ in EmptyBlock() },
        .init(scrollAcceleration: .nan) { _ in EmptyBlock() },
        .init(scrollDeceleration: 0) { _ in EmptyBlock() },
        .init(scrollDeceleration: .infinity) { _ in EmptyBlock() },
      ]
      var events: [String] = []
      for bar in configurations {
        await #expect(throws: WaylandBarError.invalidConfiguration) {
          try await bar.onStart { events.append("start") }.onClose { events.append("close") }.run()
        }
      }
      var builds = 0
      await #expect(throws: WaylandBarError.invalidConfiguration) {
        try await WaylandBar(height: 0) { _ in
          builds += 1
          return EmptyBlock()
        }.run()
      }
      #expect(events.isEmpty && builds == 0)
    }

    @Test func cancellationBeforeStartSkipsLifecycleAndContent() async {
      var events: [String] = []
      let task = Task { @MainActor in
        try await WaylandBar { _ in
          events.append("content")
          return EmptyBlock()
        }
        .onStart { events.append("start") }
        .onClose { events.append("close") }
        .run()
      }
      task.cancel()
      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(events.isEmpty)
    }

    @Test func cancellationAfterStartClosesLifecycleWithoutConnecting() async {
      var events: [String] = []
      var session: Task<Void, any Error>?
      let task = Task { @MainActor in
        try await WaylandBar { _ in
          events.append("content")
          return EmptyBlock()
        }
        .onStart {
          events.append("start")
          session?.cancel()
        }
        .onClose { events.append("close") }
        .run()
      }
      session = task
      await #expect(throws: CancellationError.self) { try await task.value }
      session = nil
      #expect(events == ["start", "close"])
    }

    @Test func barContentUsesObservedRuntimeAndLogicalViewport() async throws {
      let model = BarModel()
      var builds = 0
      let bar = WaylandBar(overlayHeight: 32) { viewport in
        builds += 1
        #expect(viewport.bounds == Rect(0, 0, 100, 58))
        #expect(viewport.scale == 2)
        return RowBlock(in: viewport.bounds) {
          CanvasBlock(key: 1, extent: 100) { context in
            context.fillRect(context.rect, color: Color(model.red, 0, 0))
          }
        }
      }
      #expect(builds == 0)
      let (redraws, signal) = AsyncStream<Void>.makeStream()
      var iterator = redraws.makeAsyncIterator()
      let runtime = DesktopRuntime(
        content: bar.content, primaryShortcut: .control, onCopy: { _ in },
        requestRedraw: { signal.yield() })
      defer {
        runtime.stop()
        signal.finish()
      }
      let renderer = CPURenderer(width: 100, height: 58)
      let viewport = Viewport(size: .init(100, 58), scale: 2)
      runtime.frame(input: Input(), viewport: viewport, time: 0, present: { renderer.render($0) })
      model.red = 1
      #expect(await iterator.next() != nil)
      runtime.frame(input: Input(), viewport: viewport, time: 1, present: { renderer.render($0) })
      #expect(builds == 2)
      #expect(Array(renderer.pixels.suffix(3)) == [255, 0, 0])
    }
  }

  @Suite(
    GraphicsTest(), .serialized,
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  @MainActor
  struct WaylandBarRenderingTests {
    @Test func configuredBarPresentsClosesAndReopensAsAnOrdinaryWindow() async throws {
      var frames = 0
      var events: [String] = []
      try await WaylandBar(height: 26, namespace: "roots-test-bar", overlayHeight: 32, maxFrames: 2)
      {
        viewport in
        #expect(viewport.bounds.width > 0 && viewport.bounds.height == 58 && viewport.scale >= 1)
        frames += 1
        return RowBlock(in: Rect(0, 0, viewport.bounds.width, 26)) {
          CanvasBlock(key: 1, extent: viewport.bounds.width) { context in
            context.fillRect(context.rect, color: Color(0.2, 0.3, 0.4))
          }
        }
      }
      .onStart { events.append("start") }
      .onClose { events.append("close") }
      .run()
      #expect(frames == 2 && events == ["start", "close"])
      frames = 0
      try await DesktopWindow("After bar", size: .init(100, 100), maxFrames: 1) { _ in
        frames += 1
        return EmptyBlock()
      }.run()
      #expect(frames == 1)
    }
  }
#endif
