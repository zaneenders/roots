#if os(Linux)
  import Roots
  import Testing

  @testable import RootsDesktop

  // Applications can choose a backend using RootsDesktop alone, without importing WaylandBridge.
  private struct LinuxBackendApp: RootsApp {
    var window: some Window {
      DesktopWindow("X11") { _ in EmptyBlock() }
        .linuxBackend(.x11)
        .onKey { $0.key == .escape }
    }
  }

  @MainActor
  struct LinuxDesktopWindowTests {
    @Test func backendModifierPreservesTheOriginalWindowAndComposesWithLifecycle() throws {
      let original = DesktopWindow("Linux", size: .init(100, 80)) { _ in EmptyBlock() }
      let configured = original.linuxBackend(.x11).onStart {}.onClose {}
      #expect(original.backend == .auto)
      #expect(configured.backend == .x11)
      #expect(configured.title == original.title)
      #expect(configured.size == original.size)
      #expect(configured.linuxBackend(.wayland).backend == .wayland)
      #expect(configured.linuxBackend(.auto).backend == .auto)
      try configured.validate()
      _ = LinuxBackendApp().window
    }

    @Test func invalidOffscreenBackendDoesNotStartLifecycle() async {
      var started = false
      var closed = false
      let window = DesktopWindow("Invalid", maxFrames: 1, offscreen: true) { _ in EmptyBlock() }
        .linuxBackend(.x11)
        .onStart { started = true }
        .onClose { closed = true }
      await #expect(throws: DesktopWindowError.invalidConfiguration) { try await window.run() }
      #expect(!started && !closed)
    }

    @Test func publicBackendValuesRoundTrip() {
      #expect(LinuxWindowBackend.allCases.map(\.rawValue) == ["auto", "wayland", "x11"])
      #expect(LinuxWindowBackend(rawValue: "x11") == .x11)
      #expect(LinuxWindowBackend(rawValue: "X11") == nil)
    }
  }
#endif
