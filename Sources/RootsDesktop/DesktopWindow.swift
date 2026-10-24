import Roots

public enum DesktopWindowError: Error, Equatable {
  case invalidConfiguration
}

@MainActor
public struct DesktopWindow<Content: Block>: Window {
  let title: String
  let size: SIMD2<Float>
  let maxFrames: Int32
  let screenshotPath: String?
  let offscreen: Bool
  let content: @MainActor (Viewport) -> Content
  private var session: DesktopSession

  public init(
    _ title: String, size: SIMD2<Float> = .init(900, 660), maxFrames: Int32 = 0,
    screenshotPath: String? = nil, offscreen: Bool = false,
    nodeCapacity: Int = 128, scrollAcceleration: Float = 0, scrollDeceleration: Float = 8,
    @BlockBuilder content: @escaping @MainActor (Viewport) -> Content
  ) {
    self.title = title
    self.size = size
    self.maxFrames = maxFrames
    self.screenshotPath = screenshotPath
    self.offscreen = offscreen
    self.content = content
    session = DesktopSession(
      nodeCapacity: nodeCapacity, scrollAcceleration: scrollAcceleration,
      scrollDeceleration: scrollDeceleration)
  }

  public func onKey(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> Self {
    var window = self
    window.session.keyHandler = handler
    return window
  }

  public func onPrepareFrame(_ action: @escaping @MainActor (inout Input, Float) -> Void) -> Self {
    var window = self
    window.session.frameCallbacks.prepare = action
    return window
  }

  public func onFrameUpdate(_ action: @escaping @MainActor (Input) -> DesktopFrameUpdate) -> Self {
    var window = self
    window.session.frameCallbacks.update = action
    return window
  }

  public func onFinishFrame(_ action: @escaping @MainActor (borrowing UIState) -> Void) -> Self {
    var window = self
    window.session.frameCallbacks.finish = action
    return window
  }

  public func animationFrames(while condition: @escaping @MainActor () -> Bool) -> Self {
    var window = self
    window.session.frameCallbacks.needsAnimationFrame = condition
    return window
  }

  public func onStart(_ action: @escaping @MainActor () -> Void) -> Self {
    var window = self
    window.session.start = action
    return window
  }

  public func onClose(_ action: @escaping @MainActor () -> Void) -> Self {
    var window = self
    window.session.close = action
    return window
  }

  public func run() async throws {
    try Task.checkCancellation()
    try validate()
    try await session.run(content: content, offscreen: offscreen) { runtime in
      try await DesktopSystem.run(self, runtime: runtime)
    }
  }

  func validate() throws {
    guard size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
      size.x <= 8192, size.y <= 8192, maxFrames >= (offscreen ? 1 : 0),
      session.isValid,
      screenshotPath == nil || maxFrames > 0
    else { throw DesktopWindowError.invalidConfiguration }
  }
}
