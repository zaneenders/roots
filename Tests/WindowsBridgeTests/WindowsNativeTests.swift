#if os(Windows)
  import Foundation
  import Testing
  import WindowsBridge

  // These tests open real windows. Opt in on an interactive Windows desktop;
  // portable input and offscreen tests always run, including in headless CI.
  @Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["ROOTS_WINDOWS_TEST_WINDOW"] == "1"))
  @MainActor struct WindowsNativeTests {
    @Test func closeAndReopenReleasesThePreviousNativeSession() async throws {
      for _ in 0..<2 {
        var frames = 0
        var finished = false
        let task = Task { @MainActor in
          defer { finished = true }
          try await WindowsWindow.runAsync(configuration: .init(size: .init(120, 80))) { _, _ in
            frames += 1
            WindowsWindow.requestClose()
          }
        }
        try await finish(task, when: { finished })
        #expect(frames >= 1)
      }
    }

    @Test func cancellationClosesAnIdleNativeWindow() async throws {
      var frames = 0
      var finished = false
      let task = Task { @MainActor in
        defer { finished = true }
        try await WindowsWindow.runAsync(configuration: .init(size: .init(120, 80))) { _, _ in
          frames += 1
        }
      }
      // Let the HWND initialize and the loop go idle before cancelling.
      try await started(task, when: { frames > 0 || finished })
      if finished {
        try await task.value
        Issue.record("The native window closed before cancellation could be tested")
        return
      }
      task.cancel()
      await #expect(throws: CancellationError.self) { try await task.value }
      try await WindowsWindow.runAsync(configuration: .init(size: .init(120, 80), maxFrames: 1)) {
        _, _ in
      }
    }

    @Test func observationRedrawAndAsyncWorkRunWhileWindowIsOpen() async throws {
      var frames = 0
      var finished = false
      var requestedRedraw = false
      let task = Task { @MainActor in
        defer { finished = true }
        try await WindowsWindow.runAsync(configuration: .init(size: .init(120, 80))) { _, _ in
          frames += 1
          if requestedRedraw { WindowsWindow.requestClose() }
        }
      }
      try await started(task, when: { frames > 0 || finished })
      if finished {
        try await task.value
        Issue.record("The native window closed before redraw could be tested")
        return
      }
      requestedRedraw = true
      WindowsWindow.requestRedraw()
      try await finish(task, when: { finished })
      #expect(frames >= 2)
    }

    private func started(_ task: Task<Void, any Error>, when ready: () -> Bool) async throws {
      for _ in 0..<500 {
        if ready() { return }
        try await Task.sleep(for: .milliseconds(10))
      }
      Issue.record("The native session did not reach its first frame within five seconds")
      task.cancel()
      try await task.value
    }

    private func finish(_ task: Task<Void, any Error>, when done: () -> Bool) async throws {
      for _ in 0..<500 {
        if done() { return try await task.value }
        try await Task.sleep(for: .milliseconds(10))
      }
      Issue.record("The native session did not close within five seconds")
      task.cancel()
      try await task.value
    }
  }
#endif
