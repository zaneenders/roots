import Roots

/// AppKit/Metal implementation of the Roots desktop contract.
/// The native host currently supports one running window session at a time.
@MainActor
public final class MacOSBackend: DesktopBackend, DesktopCursorSurface {
  private var running = false
  private var onscreen = false

  public init() {}
  public var primaryShortcut: KeyModifiers { .super }

  public func run(
    configuration: BackendWindowConfiguration, frame: @escaping BackendFrameHandler
  ) async throws {
    try Task.checkCancellation()
    try configuration.validate()
    guard !running else { throw DesktopBackendError.alreadyRunning }
    running = true
    onscreen = !configuration.offscreen
    defer {
      running = false
      onscreen = false
    }
    let native = WindowConfiguration(
      logicalSize: .init(configuration.logicalSize.width, configuration.logicalSize.height),
      title: configuration.title, maxFrames: configuration.maxFrames,
      screenshotPath: configuration.screenshotPath,
      minimumSize: configuration.minimumSize.map { .init($0.width, $0.height) })
    let callback: @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void = {
      snapshot, renderer in
      frame(
        BackendFrame(
          input: snapshot.input,
          logicalSize: .init(width: snapshot.logicalSize.x, height: snapshot.logicalSize.y),
          scale: snapshot.logicalSize.x > 0
            ? Float(snapshot.drawableSize.x) / snapshot.logicalSize.x : 1,
          timeSeconds: snapshot.timeSeconds),
        { renderer.render($0) })
    }
    if configuration.offscreen {
      try await MacOSWindow.renderOffscreen(configuration: native, frame: callback)
    } else {
      try await MacOSWindow.runAsync(configuration: native, frame: callback)
    }
  }

  public func requestRedraw() { if onscreen { MacOSWindow.requestRedraw() } }
  public func requestClose() { if onscreen { MacOSWindow.requestClose() } }
  public func readClipboard() async -> String? { await MacOSWindow.readClipboard() }
  public func writeClipboard(_ text: String) -> Bool { MacOSWindow.writeClipboard(text) }
  public func setCursor(_ shape: CursorShape) -> Bool {
    onscreen && MacOSWindow.setCursor(shape)
  }
}
