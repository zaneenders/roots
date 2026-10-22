#if os(Linux)
  import Roots
  import WaylandBridge

  public enum WaylandBarError: Error, Equatable {
    case invalidConfiguration
  }

  @MainActor
  public struct WaylandBar<Content: Block>: Window {
    let height: Int32
    let namespace: String
    let overlayHeight: Int32
    let maxFrames: Int32
    let screenshotPath: String?
    let content: @MainActor (Viewport) -> Content
    private var session: DesktopSession

    public init(
      height: Int32 = 26, namespace: String = "roots-bar", overlayHeight: Int32 = 0,
      maxFrames: Int32 = 0, screenshotPath: String? = nil,
      nodeCapacity: Int = 128, scrollAcceleration: Float = 0, scrollDeceleration: Float = 8,
      @BlockBuilder content: @escaping @MainActor (Viewport) -> Content
    ) {
      self.height = height
      self.namespace = namespace
      self.overlayHeight = overlayHeight
      self.maxFrames = maxFrames
      self.screenshotPath = screenshotPath
      self.content = content
      session = DesktopSession(
        nodeCapacity: nodeCapacity, scrollAcceleration: scrollAcceleration,
        scrollDeceleration: scrollDeceleration)
    }

    public func frameDelegate(_ delegate: any DesktopFrameDelegate) -> Self {
      var bar = self
      bar.session.delegate = delegate
      return bar
    }

    public func onStart(_ action: @escaping @MainActor () -> Void) -> Self {
      var bar = self
      bar.session.start = action
      return bar
    }

    public func onClose(_ action: @escaping @MainActor () -> Void) -> Self {
      var bar = self
      bar.session.close = action
      return bar
    }

    public func run() async throws {
      try Task.checkCancellation()
      try validate()
      try await session.run(content: content) { runtime in
        try await DesktopSystem.run(configuration: configuration, runtime: runtime)
      }
    }

    var configuration: NativeWindowConfiguration {
      .init(
        height: height, maxFrames: maxFrames, title: "Wayland bar", screenshotPath: screenshotPath,
        topBar: true,
        topBarOverlayHeight: overlayHeight, minimumWidth: 0, minimumHeight: 0,
        layerNamespace: namespace)
    }

    func validate() throws {
      guard height > 0, height <= 8192, overlayHeight >= 0, overlayHeight <= 8192 - height,
        !namespace.isEmpty, !namespace.utf8.contains(0), maxFrames >= 0,
        screenshotPath == nil || maxFrames > 0, session.isValid
      else { throw WaylandBarError.invalidConfiguration }
    }
  }
#endif
