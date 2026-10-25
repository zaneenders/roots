import Roots

public enum DesktopWindowError: Error, Equatable {
  case invalidConfiguration
}

@MainActor
public struct DesktopWindow<Content: Block>: Window {
  private let backend: (any DesktopBackend)?
  private let minimumSize: Size?
  let title: String
  let size: Size
  let maxFrames: Int32
  let screenshotPath: String?
  let offscreen: Bool
  let content: @MainActor (Viewport) -> Content
  private var session: DesktopSession

  public init(
    _ title: String, width: Float = 900, height: Float = 660, maxFrames: Int32 = 0,
    screenshotPath: String? = nil, offscreen: Bool = false,
    minimumSize: Size? = nil, backend: (any DesktopBackend)? = nil,
    nodeCapacity: Int = 128, scrollAcceleration: Float = 0, scrollDeceleration: Float = 8,
    @BlockBuilder content: @escaping @MainActor (Viewport) -> Content
  ) {
    self.backend = backend
    self.minimumSize = minimumSize
    self.title = title
    self.size = Size(width: width, height: height)
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
    guard let backend = backend ?? DesktopSystem.defaultBackend else {
      throw DesktopBackendError.unavailable
    }
    try await DesktopSystem.withBackend(backend) {
      try await session.run(content: content, offscreen: offscreen, backend: backend) { runtime in
        try await backend.run(configuration: configuration) { snapshot, render in
          DesktopSystem.frame(snapshot, render: render, runtime: runtime)
        }
      }
    }
  }

  var configuration: BackendWindowConfiguration {
    .init(
      title: title, logicalSize: size, minimumSize: minimumSize,
      maxFrames: maxFrames, screenshotPath: screenshotPath, offscreen: offscreen)
  }

  func validate() throws {
    do { try configuration.validate() } catch { throw DesktopWindowError.invalidConfiguration }
    guard session.isValid else { throw DesktopWindowError.invalidConfiguration }
  }
}
