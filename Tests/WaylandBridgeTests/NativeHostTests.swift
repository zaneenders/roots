import CEGLGLES
import DesktopTestSupport
import Foundation
import Roots
import Testing

@testable import WaylandBridge

@Test @MainActor func unconnectedHostRejectsNativeOperations() async {
  let host = NativeHost(configuration: .init())
  #expect(throws: NativeWindowError.waylandConnection) { try host.endFrame(continuously: true) }
  #expect(throws: NativeWindowError.rendering) { try host.setupRenderer(surfaceless: false) }
  await #expect(throws: NativeWindowError.waylandConnection) { try await host.dispatchAsync() }
}

@Test @MainActor func windowConfigurationFlowsIntoTheWaylandConnection() {
  let host = NativeHost(
    configuration: .init(
      title: "Config Test", appID: "org.shape-tree.test", minimumWidth: 320, minimumHeight: 240,
      layerNamespace: "test-namespace"))
  defer { host.cleanup() }
  let configuration = host.connection.configuration
  #expect(
    configuration.title == "Config Test" && configuration.appID == "org.shape-tree.test"
      && configuration.layerNamespace == "test-namespace"
      && configuration.minimumWidth == 320 && configuration.minimumHeight == 240)
}

@Test @MainActor func hostCleanupIsIdempotentAndTerminal() async {
  let host = NativeHost(configuration: .init())
  host.cleanup()
  host.cleanup()
  #expect(!host.running && !host.configured && !host.connection.frameReady)
  #expect(!host.input.pointerInside && !host.input.primaryDown)
  await #expect(throws: NativeWindowError.waylandConnection) { try await host.connect() }
  #expect(throws: NativeWindowError.waylandConnection) { try host.endFrame(continuously: true) }
  #expect(throws: NativeWindowError.rendering) { try host.setupRenderer(surfaceless: true) }
  await #expect(throws: NativeWindowError.waylandConnection) { try await host.dispatchAsync() }
  host.requestClose()
  _ = host.beginFrame()
  host.requestRedraw()
  #expect(!host.running && !host.canRender)
}

@Test @MainActor func failedRendererSetupClosesTheHost() async {
  let host = NativeHost(configuration: .init(width: 0))
  #expect(throws: NativeWindowError.invalidConfiguration) {
    try host.setupRenderer(surfaceless: true)
  }
  #expect(!host.running)
  await #expect(throws: NativeWindowError.waylandConnection) { try await host.connect() }
  host.cleanup()
}

extension NativeSessionTests {
  @Test func hostDeinitCleansRendererAndLeavesRetainedRendererInert() throws {
    var host: NativeHost? = NativeHost(configuration: .init(width: 16, height: 16))
    weak let reference = host
    let renderer = try #require(host).renderer
    try #require(host).setupRenderer(surfaceless: true)
    #expect(unsafe eglGetCurrentContext() != nil)
    host = nil
    #expect(reference == nil)
    #expect(unsafe eglGetCurrentContext() == nil)
    let draws: [DrawRect] = []
    renderer.render(draws.span)
    try NativeWindow.run(
      configuration: .init(width: 16, height: 16, maxFrames: 1), surfaceless: true
    ) { _, _ in }
  }

  @Test(.enabled("Wayland compositor is unavailable") { try await WaylandAvailability.compositor })
  func connectedHostRejectsDuplicateFramesAndClosesOnlyOnce() async throws {
    let host = NativeHost(configuration: .init())
    defer { host.cleanup() }
    try await host.connect()
    _ = host.beginFrame()
    try host.endFrame()
    #expect(!host.connection.frameReady && !host.connection.redrawRequested && !host.canRender)
    host.requestRedraw()
    #expect(!host.connection.frameReady && host.connection.redrawRequested && !host.canRender)
    #expect(throws: NativeWindowError.waylandConnection) { try host.endFrame(continuously: true) }
    await #expect(throws: NativeWindowError.waylandConnection) { try await host.connect() }
    host.cleanup()
    host.cleanup()
    #expect(throws: NativeWindowError.waylandConnection) { try host.endFrame(continuously: true) }
  }

  @Test(.enabled("Wayland compositor is unavailable") { try await WaylandAvailability.compositor })
  func hostCleanupCancelsSuspendedDispatchBeforeDisconnecting() async throws {
    let host = NativeHost(configuration: .init())
    defer { host.cleanup() }
    try await host.connect()
    _ = host.beginFrame()
    try host.endFrame(continuously: true)
    var finished = false
    let waiter = Task {
      defer { finished = true }
      do {
        while host.running { try await host.dispatchAsync() }
        #expect(!host.running)
      } catch {
        #expect(error is CancellationError || error as? NativeWindowError == .waylandConnection)
      }
    }
    defer { waiter.cancel() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(!finished)
    if !finished {
      await #expect(throws: NativeWindowError.waylandDispatchBusy) {
        try await host.dispatchAsync()
      }
    }
    host.cleanup()
    host.cleanup()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !finished, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(finished)
    if finished { await waiter.value }
  }

  @Test func rendererCannotBeInitializedTwiceOrReconnected() async throws {
    let host = NativeHost(configuration: .init(width: 16, height: 16))
    defer { host.cleanup() }
    try host.setupRenderer(surfaceless: true)
    #expect(throws: NativeWindowError.rendering) { try host.setupRenderer(surfaceless: true) }
    await #expect(throws: NativeWindowError.waylandConnection) { try await host.connect() }
    host.cleanup()
    host.cleanup()
    #expect(unsafe eglGetCurrentContext() == nil)
  }
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  func topBarRendersThenClosesWithoutClosingTheCompositor() async throws {
    var frames = 0
    let closer = Task {
      while frames == 0 { await Task.yield() }
      NativeWindow.requestClose()
    }
    defer { closer.cancel() }
    try await NativeWindow.runAsync(configuration: .init(height: 30, topBar: true)) { input, _ in
      #expect(input.height == 30 && input.width > 0)
      frames += 1
    }
    await closer.value
    #expect(frames > 0)
  }
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  func topBarHoverExtensionPreservesBaseConfiguration() async throws {
    var frames = 0
    let closer = Task {
      while frames == 0 { await Task.yield() }
      NativeWindow.requestClose()
    }
    defer { closer.cancel() }
    try await NativeWindow.runAsync(
      configuration: .init(height: 26, topBar: true, topBarOverlayHeight: 32)
    ) {
      input, _ in
      #expect(input.height == 58)
      frames += 1
    }
    await closer.value
    #expect(frames > 0)
  }
}

@Test @MainActor func invalidTopBarOverlayDimensionsFailBeforeConnecting() async {
  for height: Int32 in [-1, .max] {
    do {
      try await NativeWindow.runAsync(
        configuration: .init(height: 26, maxFrames: 1, topBar: true, topBarOverlayHeight: height),
        surfaceless: true
      ) { _, _ in
        Issue.record("Invalid configuration rendered")
      }
      Issue.record("Expected invalid configuration")
    } catch { #expect(error as? NativeWindowError == .invalidConfiguration) }
  }
}
