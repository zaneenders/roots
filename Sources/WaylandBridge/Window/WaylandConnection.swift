import SwiftWayland

@MainActor final class NativeHost {
  let configuration: NativeWindowConfiguration
  let connection: WaylandConnection
  let renderer = NativeRenderer()
  let backend: LinuxWindowBackend
  private let x11: X11Connection?
  private var applicationCloseRequested = false
  var closeRequested: Bool { applicationCloseRequested || connection.closeRequested }
  var timeSeconds: Double = 0
  private var connected = false
  private var rendererReady = false
  private var closed = false
  private var popupRenderer: NativeRenderer?
  private var popupRendererReady = false
  private var popupFrame: (@MainActor (NativeWindowInput, borrowing RenderFrame) -> Void)?
  private var popupDismissal: (@MainActor () -> Void)?

  var input: NativeWindowInput {
    var input = x11?.input ?? NativeWindowInput(connection.input)
    input.timeSeconds = timeSeconds
    return input
  }
  var running: Bool { x11?.running ?? connection.running }
  var configured: Bool { x11?.configured ?? connection.configured }
  var canRender: Bool { x11?.canRender ?? connection.canRender }

  init(configuration: NativeWindowConfiguration, backend: LinuxWindowBackend = .wayland) {
    precondition(backend != .auto)
    self.configuration = configuration
    self.backend = backend
    x11 = backend == .x11 ? X11Connection(configuration: configuration) : nil
    connection = WaylandConnection(
      configuration: .init(
        width: configuration.width, height: configuration.height, title: configuration.title,
        appID: configuration.appID, minimumWidth: configuration.minimumWidth,
        minimumHeight: configuration.minimumHeight, topBar: configuration.topBar,
        topBarOverlayHeight: configuration.topBarOverlayHeight,
        layerNamespace: configuration.layerNamespace))
  }

  isolated deinit { cleanup() }

  private func translate(_ operation: () throws -> Void) throws {
    do { try operation() } catch let error as WaylandError { throw NativeWindowError(error) }
  }

  func connect() async throws {
    guard !rendererReady else { throw NativeWindowError.waylandConnection }
    if let x11 {
      try x11.connect()
    } else {
      do { try await connection.connect() } catch let error as WaylandError {
        throw NativeWindowError(error)
      }
    }
    connected = true
  }

  func setupRenderer(surfaceless: Bool) throws {
    guard !closed, !rendererReady, running,
      surfaceless ? !connected : connected && (x11 != nil || configured)
    else {
      throw NativeWindowError.rendering
    }
    do {
      if let x11, !surfaceless {
        try renderer.setup(input: input, x11: x11)
      } else {
        try renderer.setup(input: input)
        if !surfaceless { renderer.enableDMABuf(connection: connection) }
      }
      rendererReady = true
    } catch {
      cleanup()
      throw error
    }
  }

  func dispatchAsync() async throws {
    if let x11 {
      try await x11.dispatchAsync()
      return
    }
    if connection.popupDismissed {
      dismissPopup()
      return
    }
    do { try await connection.dispatchAsync() } catch let error as WaylandError {
      throw NativeWindowError(error)
    }
    if connection.popupDismissed { dismissPopup() }
  }

  func drain() async throws {
    if closed || !connected || x11 != nil { return }
    do { try await connection.drain() } catch let error as WaylandError {
      throw NativeWindowError(error)
    }
  }

  func preparePresentation() throws -> Bool {
    try renderer.preparePresentation(
      width: input.width, height: input.height, bufferScale: input.bufferScale)
  }

  func beginFrame() -> NativeWindowInput {
    var input = x11?.beginFrame() ?? NativeWindowInput(connection.beginFrame())
    input.timeSeconds = timeSeconds
    return input
  }

  func endFrame(continuously: Bool = false) throws {
    if let x11 {
      try x11.endFrame(continuously: continuously)
    } else {
      try translate { try connection.endFrame(continuously: continuously) }
    }
  }

  func setIdleInhibited(_ enabled: Bool) -> Bool {
    x11 == nil && connection.setIdleInhibited(enabled)
  }

  func requestRedraw() {
    if let x11 { x11.requestRedraw() } else { connection.requestRedraw() }
  }
  func requestClose() {
    applicationCloseRequested = true
    if let x11 { x11.requestClose() } else { connection.requestClose() }
  }
  func readClipboard() async -> String? {
    if let x11 { return await x11.readClipboard() }
    return await connection.readClipboard()
  }
  func writeClipboard(_ text: String) -> Bool {
    if let x11 { return x11.writeClipboard(text) }
    return connection.writeClipboard(text)
  }

  func presentPopup(
    configuration: NativePopupConfiguration, grab: Bool = true,
    frame: @escaping @MainActor (NativeWindowInput, borrowing RenderFrame) -> Void,
    onDismiss: @escaping @MainActor () -> Void
  ) throws {
    guard x11 == nil else { throw NativeWindowError.invalidConfiguration }
    try translate {
      try connection.presentPopup(configuration: configuration, grab: grab)
    }
    popupRenderer = NativeRenderer()
    popupRendererReady = false
    popupFrame = frame
    popupDismissal = onDismiss
  }

  func requestPopupDismissal() { connection.requestPopupDismissal() }

  func dismissPopup() {
    popupRenderer?.cleanup()
    popupRenderer = nil
    popupRendererReady = false
    popupFrame = nil
    connection.dismissPopup()
    let onDismiss = popupDismissal
    popupDismissal = nil
    onDismiss?()
  }

  func renderPopup() {
    guard x11 == nil else { return }
    guard !connection.popupDismissed else {
      dismissPopup()
      return
    }
    guard let renderer = popupRenderer, let frame = popupFrame,
      let snapshot = connection.popupInput, connection.popupConfigured
    else { return }
    var input = NativeWindowInput(snapshot)
    input.timeSeconds = timeSeconds
    do {
      if !popupRendererReady {
        try renderer.setup(input: input, ownsDisplay: false)
        renderer.enableDMABuf(connection: connection, popup: true)
        popupRendererReady = true
      }
      try renderer.makeCurrent()
      guard
        try renderer.preparePresentation(
          width: input.width, height: input.height, bufferScale: input.bufferScale)
      else {
        try renderer.releaseCurrent()
        return
      }
      _ = connection.takePopupInput()
      try renderer.beginFrame(
        width: input.width, height: input.height, bufferScale: input.bufferScale, transparent: true)
      renderer.withFrame { frame(input, $0) }
      try renderer.endFrame(surfaceless: false)
      try renderer.swapBuffers()
      try renderer.releaseCurrent()
      if input.keyEvents.contains(where: { $0.key == .escape && $0.phase == .pressed }) {
        dismissPopup()
      }
    } catch {
      nativeLog("Popup rendering failed: \(error)")
      dismissPopup()
    }
  }

  func cleanup() {
    guard !closed else { return }
    closed = true
    dismissPopup()
    renderer.cleanup()
    x11?.cleanup()
    connection.cleanup()
  }
}

extension NativeWindowError {
  fileprivate init(_ error: WaylandError) {
    switch error {
    case .invalidConfiguration: self = .invalidConfiguration
    case .connection: self = .waylandConnection
    case .missingGlobals: self = .missingWaylandGlobals
    case .busy: self = .waylandDispatchBusy
    case .dispatch: self = .waylandDispatch
    }
  }
}
