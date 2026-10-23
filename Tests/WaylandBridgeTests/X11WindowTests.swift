import CEGLGLES
import DesktopTestSupport
import Foundation
@_spi(Hosting) import Roots
import Testing

@testable import WaylandBridge

/// Uses only an existing authenticated display. Does not start a server or alter access controls.
@Suite(
  GraphicsTest(), .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["ROOTS_X11_TESTS"] == "1"))
@MainActor struct X11WindowTests {
  @Test func asyncWindowYieldsReleasesContextAndClosesFromATimer() async throws {
    var frames = 0
    var timerRan = false
    let closer = Task {
      try await Task.sleep(for: .milliseconds(200))
      #expect(unsafe eglGetCurrentContext() == nil)
      timerRan = true
      NativeWindow.requestClose()
    }
    defer { closer.cancel() }
    try await NativeWindow.runAsync(
      configuration: .init(width: 320, height: 240, title: "Roots X11 lifecycle test"),
      backend: .x11
    ) { input, _ in
      #expect(unsafe eglGetCurrentContext() != nil)
      #expect(input.width > 0 && input.height > 0 && input.bufferScale == 1)
      frames += 1
    }
    try await closer.value
    #expect(timerRan && frames > 0)
    #expect(unsafe eglGetCurrentContext() == nil)
  }

  @Test func cancellationCleansUpAndAllowsReopening() async throws {
    var frames = 0
    let window = Task {
      try await NativeWindow.runAsync(configuration: .init(width: 320, height: 240), backend: .x11)
      { _, _ in
        frames += 1
      }
    }
    defer { window.cancel() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while frames == 0, .now < deadline { try await Task.sleep(for: .milliseconds(2)) }
    window.cancel()
    do {
      try await window.value
      Issue.record("Cancelled X11 session unexpectedly succeeded")
    } catch {
      #expect(error is CancellationError)
    }
    try #require(frames > 0)
    var reopened = 0
    try await NativeWindow.runAsync(
      configuration: .init(width: 320, height: 240, maxFrames: 2), backend: .x11
    ) {
      _, _ in reopened += 1
    }
    #expect(reopened == 2)
    #expect(unsafe eglGetCurrentContext() == nil)
  }

  @Test func idleWindowCoalescesRedrawsAndWakesWithoutSocketInput() async throws {
    var frames = 0
    let driver = Task {
      defer { NativeWindow.requestClose() }
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while frames == 0, .now < deadline { try await Task.sleep(for: .milliseconds(2)) }
      try #require(frames > 0)
      try await Task.sleep(for: .milliseconds(300))
      let settled = frames
      try await Task.sleep(for: .milliseconds(100))
      #expect(frames == settled)
      for _ in 0..<20 { NativeWindow.requestRedraw() }
      let redrawDeadline = ContinuousClock.now.advanced(by: .seconds(2))
      while frames == settled, .now < redrawDeadline { try await Task.sleep(for: .milliseconds(2)) }
      try await Task.sleep(for: .milliseconds(100))
      #expect(frames == settled + 1)
      NativeWindow.requestClose()
    }
    defer { driver.cancel() }
    try await NativeWindow.runAsync(configuration: .init(width: 320, height: 240), backend: .x11) {
      _, _ in
      frames += 1
    }
    try await driver.value
  }

  @Test func redrawInsideCallbackSurvivesAndFiniteFramesUseFixedTime() async throws {
    let watchdog = Task {
      try await Task.sleep(for: .seconds(5))
      NativeWindow.requestClose()
    }
    defer { watchdog.cancel() }
    var frames = 0
    try await NativeWindow.runAsync(configuration: .init(width: 320, height: 240), backend: .x11) {
      _, _ in
      frames += 1
      if frames == 4 { NativeWindow.requestClose() } else { NativeWindow.requestRedraw() }
    }
    #expect(frames == 4)
    frames = 0
    try await NativeWindow.runAsync(
      configuration: .init(width: 320, height: 240, maxFrames: 4), backend: .x11
    ) {
      input, _ in
      #expect(input.timeSeconds == Double(frames) / 60)
      frames += 1
    }
    #expect(frames == 4)
  }

  @Test func finiteWindowScreenshotMatchesItsDrawableAndPacingIsBounded() async throws {
    let watchdog = Task {
      try await Task.sleep(for: .seconds(5))
      NativeWindow.requestClose()
    }
    defer { watchdog.cancel() }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var last: NativeWindowInput?
    let start = ContinuousClock.now
    try await NativeWindow.runAsync(
      configuration: .init(width: 320, height: 240, maxFrames: 4, screenshotPath: path.path),
      backend: .x11
    ) { input, renderer in
      last = input
      let draws = [DrawRect(Rect(0, 0, Float(input.width), Float(input.height)), Color(1, 0, 0))]
      renderer.render(draws.span)
    }
    // Three intervals must elapse after the first frame; this is a no-busy-spin lower bound,
    // not a frame-rate performance claim about the compositor or driver.
    #expect(start.duration(to: .now) >= .milliseconds(45))
    let input = try #require(last)
    let size = SIMD2(input.width * input.bufferScale, input.height * input.bufferScale)
    let bytes = try Data(contentsOf: path)
    let header = Data("P6\n\(size.x) \(size.y)\n255\n".utf8)
    #expect(bytes.starts(with: header))
    #expect(bytes.count == header.count + Int(size.x) * Int(size.y) * 3)
    let center = header.count + (Int(size.y) / 2 * Int(size.x) + Int(size.x) / 2) * 3
    #expect(Array(bytes[center..<(center + 3)]) == [255, 0, 0])
  }
}

@Test @MainActor func closedX11HostRejectsOperationsWithoutOpeningADisplay() async {
  let host = X11Connection(configuration: .init())
  host.cleanup()
  host.cleanup()
  #expect(!host.running && !host.canRender)
  #expect(throws: NativeWindowError.x11Connection) { try host.connect() }
  #expect(throws: NativeWindowError.x11Connection) { try host.endFrame() }
  await #expect(throws: NativeWindowError.x11Connection) { try await host.dispatchAsync() }
  #expect(await host.readClipboard() == nil)
  #expect(!host.writeClipboard("closed"))
}
