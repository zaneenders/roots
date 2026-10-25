import CEGLGLES
import DesktopTestSupport
import Foundation
import Glibc
import Testing

@testable import WaylandBridge

private enum AsyncTestFailure: Error { case timeout }

@MainActor private func eventually(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(condition())
  if !condition() { throw AsyncTestFailure.timeout }
}

@Test @MainActor func asyncInvalidConfigurationsFailBeforeOpeningNativeResources() async {
  do {
    try await NativeWindow.runAsync(configuration: .init(width: 0), surfaceless: true) { _, _ in
      Issue.record("Invalid configuration invoked a frame")
    }
    Issue.record("Expected invalidConfiguration")
  } catch {
    #expect(error as? NativeWindowError == .invalidConfiguration)
  }
}

@Suite(
  GraphicsTest(), .serialized,
  .enabled("Surfaceless EGL/OpenGL ES 3 is unavailable") { await EGLAvailability.isAvailable })
@MainActor struct NativeSessionTests {
  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    })
  func asyncWaylandSessionAllowsTimersToCloseAndCancelAnEventWait() async throws {
    var frames = 0
    var timerRan = false
    let closer = Task {
      while frames == 0 { await Task.yield() }
      try await Task.sleep(for: .milliseconds(40))
      timerRan = true
      NativeWindow.requestClose()
    }
    defer { closer.cancel() }
    try await NativeWindow.runAsync { _, _ in frames += 1 }
    try await closer.value
    #expect(timerRan && frames > 0)

    var started = false
    let session = Task {
      try await NativeWindow.runAsync { _, _ in started = true }
    }
    defer { session.cancel() }
    try await eventually { started }
    session.cancel()
    do {
      try await session.value
      Issue.record("Expected cancellation")
    } catch {
      #expect(error is CancellationError)
    }
    var reopenedFrames = 0
    try await NativeWindow.runAsync(configuration: .init(maxFrames: 2)) { _, _ in
      reopenedFrames += 1
    }
    #expect(reopenedFrames == 2)
  }

  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    })
  func idleSessionSleepsCoalescesRequestsAndWakesWithoutSocketInput() async throws {
    var frames = 0
    let driver = Task {
      try await eventually { frames > 0 }
      try await Task.sleep(for: .milliseconds(300))
      let settled = frames
      try await Task.sleep(for: .milliseconds(100))
      #expect(frames == settled)
      for _ in 0..<20 { NativeWindow.requestRedraw() }
      try await eventually { frames > settled }
      try await Task.sleep(for: .milliseconds(100))
      #expect(frames == settled + 1)
      NativeWindow.requestClose()
    }
    defer { driver.cancel() }
    try await NativeWindow.runAsync { _, _ in frames += 1 }
    try await driver.value
  }

  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    })
  func frameRequestsDuringBuildArePacedAndFrameLimitsUseFixedTime() async throws {
    var frames = 0
    try await NativeWindow.runAsync { _, _ in
      frames += 1
      if frames == 4 { NativeWindow.requestClose() } else { NativeWindow.requestRedraw() }
    }
    #expect(frames == 4)
    frames = 0
    try await NativeWindow.runAsync(configuration: .init(maxFrames: 4)) { input, _ in
      #expect(input.timeSeconds == Double(frames) / 60)
      frames += 1
    }
    #expect(frames == 4)
  }

  @Test func asyncSurfacelessSessionYieldsCancelsAndReopens() async throws {
    let configuration = NativeWindowConfiguration(width: 16, height: 16, maxFrames: 100_000)
    var frames = 0
    var started = false
    var cancelled = false
    var nestedAttempted = false
    let session = Task {
      do {
        try await NativeWindow.runAsync(configuration: configuration, surfaceless: true) {
          input, _ in
          #expect(unsafe eglGetCurrentContext() != nil)
          #expect(input.timeSeconds == Double(frames) / 60)
          frames += 1
          if !started {
            started = true
            Task { @MainActor in
              do {
                try await NativeWindow.runAsync(configuration: configuration, surfaceless: true) {
                  _, _ in
                }
                Issue.record("Nested async session was allowed")
              } catch {
                #expect(error as? NativeWindowError == .alreadyRunning)
              }
              #expect(unsafe eglGetCurrentContext() == nil)
              nestedAttempted = true
            }
          }
        }
        Issue.record("Expected cancellation")
      } catch {
        #expect(error is CancellationError)
        cancelled = true
      }
    }
    defer { session.cancel() }
    try await eventually { started && nestedAttempted }
    session.cancel()
    await session.value
    #expect(cancelled)
    #expect(frames > 0 && frames < 100_000)
    var closedFrames = 0
    try await NativeWindow.runAsync(configuration: configuration, surfaceless: true) { _, _ in
      closedFrames += 1
      NativeWindow.requestClose()
    }
    #expect(closedFrames == 1)
    var reopenedFrames = 0
    try await NativeWindow.runAsync(
      configuration: .init(width: 16, height: 16, maxFrames: 2), surfaceless: true
    ) {
      _, _ in
      reopenedFrames += 1
    }
    #expect(reopenedFrames == 2)
  }
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    })
  func waylandScreenshotMatchesTheNegotiatedBufferScale() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var lastInput: NativeWindowInput?
    try await NativeWindow.runAsync(configuration: .init(maxFrames: 3, screenshotPath: path.path)) {
      input, _ in
      #expect(input.width > 0 && input.height > 0 && input.bufferScale >= 1)
      lastInput = input
    }
    let input = try #require(lastInput)
    let size = try BufferSize(
      width: input.width, height: input.height, scale: input.bufferScale,
      fractionalScale120: input.fractionalScale120)
    let bytes = try Data(contentsOf: path)
    let header = Data("P6\n\(size.width) \(size.height)\n255\n".utf8)
    #expect(bytes.starts(with: header))
    #expect(bytes.count == header.count + Int(size.width) * Int(size.height) * 3)
  }
}
