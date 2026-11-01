import Roots

@MainActor
struct DesktopSession {
  let nodeCapacity: Int
  let drawCapacity: Int
  let scrollAcceleration: Float
  let scrollDeceleration: Float
  var start: (() -> Void)?
  var close: (() -> Void)?
  var frameCallbacks = DesktopFrameCallbacks()
  var keyHandler: ((KeyEvent) -> Bool)?

  init(
    nodeCapacity: Int = 128, drawCapacity: Int = 32_768,
    scrollAcceleration: Float = 0, scrollDeceleration: Float = 8
  ) {
    self.nodeCapacity = nodeCapacity
    self.drawCapacity = drawCapacity
    self.scrollAcceleration = scrollAcceleration
    self.scrollDeceleration = scrollDeceleration
  }

  var isValid: Bool {
    nodeCapacity >= 0 && drawCapacity >= 0
      && drawCapacity <= Int.max / MemoryLayout<DrawCommand>.stride
      && scrollAcceleration.isFinite && scrollAcceleration >= 0
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
      nodeCapacity: nodeCapacity, drawCapacity: drawCapacity, scrollAcceleration: scrollAcceleration,
      scrollDeceleration: scrollDeceleration)
  }
}
