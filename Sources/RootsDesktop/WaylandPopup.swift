#if os(Linux)
  import Roots
  import WaylandBridge

  @MainActor
  public struct WaylandPopup<Content: Block> {
    let configuration: NativePopupConfiguration
    let content: @MainActor (Viewport) -> Content
    private var session: DesktopSession

    public init(
      configuration: NativePopupConfiguration,
      nodeCapacity: Int = 128, scrollAcceleration: Float = 0, scrollDeceleration: Float = 8,
      @BlockBuilder content: @escaping @MainActor (Viewport) -> Content
    ) {
      self.configuration = configuration
      self.content = content
      session = DesktopSession(
        nodeCapacity: nodeCapacity, scrollAcceleration: scrollAcceleration,
        scrollDeceleration: scrollDeceleration)
    }

    public func onKey(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> Self {
      var popup = self
      popup.session.keyHandler = handler
      return popup
    }

    public func frameDelegate(_ delegate: any DesktopFrameDelegate) -> Self {
      var popup = self
      popup.session.delegate = delegate
      return popup
    }

    public func onClose(_ action: @escaping @MainActor () -> Void) -> Self {
      var popup = self
      popup.session.close = action
      return popup
    }

    @discardableResult
    public func present() -> Bool {
      guard configuration.width > 0, configuration.height > 0,
        configuration.anchorWidth > 0, configuration.anchorHeight > 0, session.isValid
      else { return false }
      let runtime = session.makeRuntime(content: content)
      let close = session.close
      let presented = NativeWindow.presentPopup(
        configuration: configuration,
        frame: { snapshot, renderer in
          DesktopSystem.frame(snapshot, renderer: renderer, runtime: runtime)
        },
        onDismiss: {
          runtime.stop()
          close?()
        })
      if !presented { runtime.stop() }
      return presented
    }
  }
#endif
