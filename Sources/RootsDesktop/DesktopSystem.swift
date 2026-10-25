import Roots

/// Convenience access to the active desktop session (or the platform default when idle).
@MainActor
public enum DesktopSystem {
  private static var activeBackend: (any DesktopBackend)?
  static var popupSurface: (any DesktopSurface)?
  static var cursors = DesktopCursors()

  public static var backend: (any DesktopBackend)? { activeBackend ?? defaultBackend }
  public static var primaryShortcut: KeyModifiers { backend?.primaryShortcut ?? .control }

  public static func requestRedraw() { backend?.requestRedraw() }
  public static func requestClose() { backend?.requestClose() }
  public static func readClipboard() async -> String? { await backend?.readClipboard() }
  @discardableResult
  public static func writeClipboard(_ text: String) -> Bool {
    backend?.writeClipboard(text) ?? false
  }

  /// Overrides hit-tested cursor selection until cleared or the surface closes.
  /// False means unavailable; the override is retained for subsequent frames.
  @discardableResult
  public static func setCursor(_ shape: CursorShape?, popup: Bool = false) -> Bool {
    cursors.set(shape, popup: popup)
  }

  /// False means this surface does not currently support input-method sessions.
  @discardableResult
  public static func setTextInput(_ state: TextInputState?, popup: Bool = false) -> Bool {
    (surface(popup: popup) as? any DesktopTextInputSurface)?.setTextInput(state) ?? false
  }

  static func surface(popup: Bool) -> (any DesktopSurface)? {
    popup ? popupSurface : backend
  }

  static func withBackend(
    _ backend: any DesktopBackend, operation: () async throws -> Void
  ) async throws {
    guard activeBackend == nil else { throw DesktopBackendError.alreadyRunning }
    activeBackend = backend
    defer {
      activeBackend = nil
      popupSurface = nil
      cursors.reset(popup: false)
      cursors.reset(popup: true)
    }
    try await operation()
  }

  static func frame<Content: Block>(
    _ snapshot: BackendFrame, render: (borrowing UIDrawBatch) -> Void,
    runtime: DesktopRuntime<Content>, popup: Bool = false
  ) {
    runtime.frame(
      input: snapshot.input,
      viewport: Viewport(size: snapshot.logicalSize, scale: snapshot.scale),
      time: snapshot.timeSeconds, present: render)
    cursors.update(runtime.cursorStyle, popup: popup)
  }
}
