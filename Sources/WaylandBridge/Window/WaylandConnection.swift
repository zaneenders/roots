import SwiftWayland

@MainActor final class NativeHost {
  let configuration: NativeWindowConfiguration
  let connection: WaylandConnection
  let renderer = NativeRenderer()
  var timeSeconds: Double = 0
  private var connected = false
  private var rendererReady = false
  private var closed = false
  private var popupRenderer: NativeRenderer?
  private var popupRendererReady = false
  private var popupFrame: (@MainActor (NativeWindowInput, borrowing RenderFrame) -> Void)?
  private var popupDismissal: (@MainActor () -> Void)?

  var input: NativeWindowInput {
    var input = NativeWindowInput(connection.input)
    input.timeSeconds = timeSeconds
    return input
  }
  var running: Bool { connection.running }
  var configured: Bool { connection.configured }
  var canRender: Bool { connection.canRender }

  init(configuration: NativeWindowConfiguration) {
    self.configuration = configuration
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
    do { try await connection.connect() } catch let error as WaylandError {
      throw NativeWindowError(error)
    }
    connected = true
  }

  func setupRenderer(surfaceless: Bool) throws {
    guard !closed, !rendererReady, running, surfaceless ? !connected : connected && configured
    else {
      throw NativeWindowError.rendering
    }
    do {
      try renderer.setup(input: input)
      if !surfaceless { renderer.enableDMABuf(connection: connection) }
      rendererReady = true
    } catch {
      cleanup()
      throw error
    }
  }

  func dispatchAsync() async throws {
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
    do { try await connection.drain() } catch let error as WaylandError {
      throw NativeWindowError(error)
    }
  }

  func preparePresentation() throws -> Bool {
    try renderer.preparePresentation(
      width: connection.input.width, height: connection.input.height,
      bufferScale: connection.input.bufferScale)
  }

  func beginFrame() -> NativeWindowInput {
    var input = NativeWindowInput(connection.beginFrame())
    input.timeSeconds = timeSeconds
    return input
  }

  func endFrame(continuously: Bool = false) throws {
    try translate { try connection.endFrame(continuously: continuously) }
  }

  func setIdleInhibited(_ enabled: Bool) -> Bool { connection.setIdleInhibited(enabled) }

  func requestRedraw() { connection.requestRedraw() }
  func requestClose() { connection.requestClose() }
  func readClipboard() async -> String? { await connection.readClipboard() }
  func writeClipboard(_ text: String) -> Bool { connection.writeClipboard(text) }

  func presentPopup(
    configuration: NativePopupConfiguration, grab: Bool = true,
    frame: @escaping @MainActor (NativeWindowInput, borrowing RenderFrame) -> Void,
    onDismiss: @escaping @MainActor () -> Void
  ) throws {
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
    connection.requestClose()
    dismissPopup()
    renderer.cleanup()
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
