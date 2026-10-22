import Foundation

public enum NativeWindowError: Error, Equatable, CustomStringConvertible {
  case invalidConfiguration
  case alreadyRunning
  case requiresAsyncSession
  case waylandConnection
  case missingWaylandGlobals
  case waylandDispatch
  case waylandDispatchBusy
  case egl(Int32)
  case shader(String)
  case rendering
  case dmabuf(String)

  public var description: String {
    switch self {
    case .invalidConfiguration: "Invalid dimensions or frame limit."
    case .requiresAsyncSession:
      "Wayland sessions require NativeWindow.runAsync; run is offscreen-only."
    case .alreadyRunning: "A native rendering session is already running."
    case .waylandConnection: "Cannot connect to Wayland. Check WAYLAND_DISPLAY and XDG_RUNTIME_DIR."
    case .missingWaylandGlobals:
      "Wayland compositor is missing wl_compositor or the requested surface-role protocol."
    case .waylandDispatch: "Wayland event dispatch failed."
    case .waylandDispatchBusy: "Wayland dispatch is already in progress on this connection."
    case .egl(let code): "EGL operation failed: 0x\(String(code, radix: 16))."
    case .shader(let log): "Shader compilation or linking failed: \(log)"
    case .rendering: "OpenGL rendering or readback failed."
    case .dmabuf(let reason): "Experimental dma-buf presentation failed: \(reason)"
    }
  }
}

@MainActor public enum NativeWindow {
  private static var host: NativeHost?

  public static func requestRedraw() { host?.requestRedraw() }

  public static func requestClose() { host?.requestClose() }

  @discardableResult
  public static func presentPopup(
    configuration: NativePopupConfiguration,
    frame: @escaping @MainActor (NativeWindowInput, borrowing RenderFrame) -> Void,
    onDismiss: @escaping @MainActor () -> Void
  ) -> Bool {
    guard let host else { return false }
    do {
      try host.presentPopup(configuration: configuration, frame: frame, onDismiss: onDismiss)
      return true
    } catch { return false }
  }

  @discardableResult
  public static func setIdleInhibited(_ enabled: Bool) -> Bool {
    host?.setIdleInhibited(enabled) ?? false
  }

  public static func dismissPopup() { host?.requestPopupDismissal() }

  public static func readClipboard() async -> String? {
    await host?.readClipboard()
  }

  @discardableResult
  public static func writeClipboard(_ text: String) -> Bool {
    host?.writeClipboard(text) ?? false
  }

  public static func run(
    configuration: NativeWindowConfiguration = .init(), surfaceless: Bool = false,
    frame: (NativeWindowInput, borrowing RenderFrame) -> Void
  ) throws {
    guard surfaceless else { throw NativeWindowError.requiresAsyncSession }
    let host = try start(configuration: configuration, surfaceless: true)
    defer { stop(host) }
    let started = ContinuousClock.now
    var frameCount: Int32 = 0
    while host.running {
      if try renderFrame(
        host, surfaceless: true, started: started, frameCount: &frameCount, frame: frame)
      {
        break
      }
    }
    logFrames(host, frameCount: frameCount, surfaceless: surfaceless)
  }

  public static func runAsync(
    configuration: NativeWindowConfiguration = .init(), surfaceless: Bool = false,
    frame: (NativeWindowInput, borrowing RenderFrame) -> Void
  ) async throws {
    try Task.checkCancellation()
    let host = try await startAsync(configuration: configuration, surfaceless: surfaceless)
    defer { stop(host) }
    let started = ContinuousClock.now
    var frameCount: Int32 = 0
    while host.running {
      try Task.checkCancellation()
      if surfaceless || host.canRender {
        let finished = try renderFrame(
          host, surfaceless: surfaceless, started: started, frameCount: &frameCount, frame: frame)
        try host.renderer.releaseCurrent()
        if finished { break }
      }
      if surfaceless {
        await Task.yield()
      } else {
        do {
          try await host.dispatchAsync()
        } catch is CancellationError {
          try Task.checkCancellation()
          if host.running { throw CancellationError() }
        }
      }
    }
    if !surfaceless { try await host.drain() }
    logFrames(host, frameCount: frameCount, surfaceless: surfaceless)
  }

  private static func start(configuration: NativeWindowConfiguration, surfaceless: Bool) throws
    -> NativeHost
  {
    guard configuration.width > 0, configuration.height > 0,
      configuration.maxFrames >= (surfaceless ? 1 : 0),
      configuration.topBarOverlayHeight >= 0,
      configuration.topBarOverlayHeight <= Int32.max - configuration.height
    else { throw NativeWindowError.invalidConfiguration }
    guard host == nil else { throw NativeWindowError.alreadyRunning }
    let host = NativeHost(configuration: configuration)
    self.host = host
    do {
      if host.running { try host.setupRenderer(surfaceless: true) }
      return host
    } catch {
      stop(host)
      throw error
    }
  }

  private static func startAsync(configuration: NativeWindowConfiguration, surfaceless: Bool)
    async throws -> NativeHost
  {
    if surfaceless { return try start(configuration: configuration, surfaceless: true) }
    guard configuration.width > 0, configuration.height > 0, configuration.maxFrames >= 0 else {
      throw NativeWindowError.invalidConfiguration
    }
    guard host == nil else { throw NativeWindowError.alreadyRunning }
    let host = NativeHost(configuration: configuration)
    self.host = host
    do {
      try await host.connect()
      if host.running { try host.setupRenderer(surfaceless: false) }
      return host
    } catch {
      stop(host)
      throw error
    }
  }

  private static func stop(_ host: NativeHost) {
    host.cleanup()
    self.host = nil
  }

  static func renderFrame(
    _ host: NativeHost, surfaceless: Bool, started: ContinuousClock.Instant,
    frameCount: inout Int32,
    frame: (NativeWindowInput, borrowing RenderFrame) -> Void
  ) throws -> Bool {
    if surfaceless || host.configuration.maxFrames > 0 {
      host.timeSeconds = Double(frameCount) / 60
    } else {
      let elapsed = started.duration(to: .now).components
      host.timeSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
    try host.renderer.makeCurrent()
    if !surfaceless, try !host.preparePresentation() { return false }
    let input = host.beginFrame()
    try host.renderer.beginFrame(
      width: input.width, height: input.height, bufferScale: input.bufferScale,
      transparent: host.configuration.topBar)
    host.renderer.withFrame { frame(input, $0) }
    try host.renderer.endFrame(surfaceless: surfaceless)
    frameCount += 1
    let lastFrame = host.configuration.maxFrames > 0 && frameCount >= host.configuration.maxFrames
    if lastFrame, let path = host.configuration.screenshotPath {
      try host.renderer.screenshot(to: path)
    }
    if !surfaceless {
      host.renderPopup()
      try host.renderer.makeCurrent()
      try host.endFrame(continuously: !lastFrame && host.configuration.maxFrames > 0)
      try host.renderer.swapBuffers()
    }
    return lastFrame || !host.running
  }

  private static func logFrames(_ host: NativeHost, frameCount: Int32, surfaceless: Bool) {
    let mode = surfaceless ? "EGL surfaceless" : "Wayland"
    nativeLog(
      "Rendered \(frameCount) \(mode) frames at \(host.input.width)x\(host.input.height), "
        + "\(host.input.bufferScale)x buffer scale.")
  }
}

func nativeLog(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}
