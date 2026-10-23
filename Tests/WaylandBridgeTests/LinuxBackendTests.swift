import Testing

@testable import WaylandBridge

@Test func linuxBackendSelectionIsExplicitAndStrict() throws {
  #expect(try LinuxWindowBackend(arguments: ["app"]) == .auto)
  for backend in LinuxWindowBackend.allCases {
    #expect(try LinuxWindowBackend(arguments: ["app", "--backend", backend.rawValue]) == backend)
  }
  for arguments in [
    ["app", "--backend"], ["app", "--backend", "invalid"],
    ["app", "--backend", "x11", "--backend", "wayland"],
  ] {
    #expect(throws: NativeWindowError.invalidConfiguration) {
      try LinuxWindowBackend(arguments: arguments)
    }
  }
}

@Test func automaticCandidatesPreserveWaylandOnlyFeatures() {
  #expect(LinuxWindowBackend.auto.candidates(environment: [:]) == [.wayland, .x11])
  #expect(LinuxWindowBackend.auto.candidates(environment: ["DISPLAY": ":1"]) == [.x11])
  #expect(
    LinuxWindowBackend.auto.candidates(environment: ["WAYLAND_DISPLAY": "wayland-1"]) == [.wayland])
  #expect(
    LinuxWindowBackend.auto.candidates(environment: [
      "WAYLAND_DISPLAY": "wayland-1", "DISPLAY": ":1",
    ])
      == [.wayland, .x11])
  #expect(
    LinuxWindowBackend.auto.candidates(environment: ["WAYLAND_SOCKET": "3", "DISPLAY": ":1"]) == [
      .wayland, .x11,
    ])
  #expect(
    LinuxWindowBackend.auto.candidates(topBar: true, environment: ["DISPLAY": ":1"]) == [.wayland])
  #expect(
    LinuxWindowBackend.x11.candidates(environment: ["WAYLAND_DISPLAY": "wayland-1"]) == [.x11])
  #expect(LinuxWindowBackend.wayland.candidates(environment: ["DISPLAY": ":1"]) == [.wayland])
}

@Test @MainActor func x11RejectsOffscreenAndLayerShellBeforeConnecting() async {
  await #expect(throws: NativeWindowError.invalidConfiguration) {
    try await NativeWindow.runAsync(
      configuration: .init(maxFrames: 1), surfaceless: true, backend: .x11
    ) { _, _ in }
  }
  await #expect(throws: NativeWindowError.invalidConfiguration) {
    try await NativeWindow.runAsync(configuration: .init(topBar: true), backend: .x11) { _, _ in }
  }
}

@Test @MainActor func cancellationBeforeStartupNeverSelectsAnotherBackend() async {
  let session = Task { @MainActor in
    try await NativeWindow.runAsync(backend: .auto) { _, _ in
      Issue.record("Cancelled startup must not deliver a frame")
    }
  }
  session.cancel()
  await #expect(throws: CancellationError.self) { try await session.value }
}

@Test @MainActor func closedStartupHostNeedsNoWaylandDrain() async throws {
  let host = NativeHost(configuration: .init())
  host.requestClose()
  host.cleanup()
  try await host.drain()
  #expect(!host.running)
}

@Test @MainActor func compositorCloseIntentReachesTheBackendFacadeAfterCleanup() {
  let host = NativeHost(configuration: .init())
  #expect(!host.closeRequested)
  host.connection.requestClose()
  host.cleanup()
  #expect(host.closeRequested && !host.running)

  let failed = NativeHost(configuration: .init())
  failed.cleanup()
  #expect(!failed.closeRequested && !failed.running)
}
