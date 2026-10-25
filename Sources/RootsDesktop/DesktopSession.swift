import Roots

@MainActor
struct DesktopSession {
  let nodeCapacity: Int
  let scrollAcceleration: Float
  let scrollDeceleration: Float
  var start: (() -> Void)?
  var close: (() -> Void)?
  var frameCallbacks = DesktopFrameCallbacks()
  var keyHandler: ((KeyEvent) -> Bool)?

  var isValid: Bool {
    nodeCapacity >= 0 && scrollAcceleration.isFinite && scrollAcceleration >= 0
      && scrollDeceleration.isFinite && scrollDeceleration > 0
  }

  func run<Content: Block>(
    content: @escaping @MainActor (Viewport) -> Content, offscreen: Bool = false,
    backend: (any DesktopBackend)? = DesktopSystem.backend,
    present: (DesktopRuntime<Content>) async throws -> Void
  ) async throws {
    start?()
    defer { close?() }
    let runtime = makeRuntime(content: content, offscreen: offscreen, backend: backend)
    defer { runtime.stop() }
    try await present(runtime)
  }

  func makeRuntime<Content: Block>(
    content: @escaping @MainActor (Viewport) -> Content, offscreen: Bool = false,
    backend: (any DesktopBackend)? = DesktopSystem.backend,
    requestRedraw: (@MainActor () -> Void)? = nil
  ) -> DesktopRuntime<Content> {
    DesktopRuntime(
      content: content, primaryShortcut: backend?.primaryShortcut ?? .control, onKey: keyHandler,
      onCopy: { if !offscreen { _ = backend?.writeClipboard($0) } },
      requestRedraw: {
        if !offscreen {
          if let requestRedraw { requestRedraw() } else { backend?.requestRedraw() }
        }
      }, frameCallbacks: frameCallbacks,
      nodeCapacity: nodeCapacity, scrollAcceleration: scrollAcceleration,
      scrollDeceleration: scrollDeceleration)
  }
}
