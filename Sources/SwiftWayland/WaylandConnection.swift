import Foundation
import Glibc
import NIOCore

@MainActor public final class WaylandConnection {
  private enum Lifecycle { case idle, connecting, connected, closed }
  private var lifecycle = Lifecycle.idle
  private let objects = WaylandObjects()
  private var transport: WaylandTransport?
  private var reader: Task<Void, Never>?
  private var sender: Task<Void, Never>?
  public private(set) var protocolError: String?
  private var terminalError: (any Error)?
  private var dispatching = false
  private var waiting: CheckedContinuation<Void, any Error>?
  private var waitID: UInt64 = 0
  private var waitingForBuffer = false
  public let configuration: WaylandWindowConfiguration
  public internal(set) var input: WaylandInput
  public private(set) var running = true
  public private(set) var configured = false
  public private(set) var frameReady = true
  public private(set) var redrawRequested = true
  public var canRender: Bool {
    running && configured && frameReady && redrawRequested && !waitingForBuffer
  }
  private var registry: UInt32 = 0
  private var compositor: UInt32 = 0
  private var compositorVersion: UInt32 = 0
  private var shell: UInt32 = 0
  private var layerShell: UInt32 = 0
  private var idleManager: UInt32 = 0
  private var idleManagerName: UInt32?
  private var idleInhibitor: UInt32 = 0
  private var surface: UInt32 = 0
  private var xdgSurface: UInt32 = 0
  private var toplevel: UInt32 = 0
  private var pendingSize: SIMD2<Int32>?
  private var layerSurface: UInt32 = 0
  private var seat: UInt32 = 0
  private var seatVersion: UInt32 = 0
  private var seatName: UInt32?
  private var managerName: UInt32?
  private var dmabufName: UInt32?
  private var pointer: UInt32 = 0
  private var keyboard: UInt32 = 0
  private var outputs: [UInt32: WaylandOutput] = [:]
  private var preferredBufferScale: Int32?
  private var typing = Keyboard()
  private var popup: WaylandPopup?
  private var pointerInPopup = false
  private var keyboardInPopup = false
  private var pointerSerial: UInt32?
  private var frameCallback: UInt32 = 0
  private var callbacks: Set<UInt32> = []
  private lazy var clipboard = WaylandClipboard(objects: objects)
  private lazy var dmabuf = WaylandDMABuf(objects: objects)

  private var pointerInput: WaylandInput {
    get { pointerInPopup ? popup?.input ?? input : input }
    set { if pointerInPopup, let popup { popup.input = newValue } else { input = newValue } }
  }
  private var keyboardInput: WaylandInput {
    get { keyboardInPopup ? popup?.input ?? input : input }
    set { if keyboardInPopup, let popup { popup.input = newValue } else { input = newValue } }
  }

  public init(configuration: WaylandWindowConfiguration) {
    self.configuration = configuration
    input = WaylandInput(width: configuration.width, height: configuration.height)
  }
  isolated deinit { cleanup() }

  public func connect() async throws { try await connect(path: nil) }

  func connect(
    path explicitPath: String?, environment: [String: String] = ProcessInfo.processInfo.environment
  ) async throws {
    guard lifecycle == .idle, running else { throw WaylandError.connection }
    guard configuration.width > 0, configuration.height > 0,
      configuration.minimumWidth >= 0, configuration.minimumHeight >= 0,
      configuration.topBarOverlayHeight >= 0,
      configuration.topBarOverlayHeight <= Int32.max - configuration.height
    else { throw WaylandError.invalidConfiguration }
    lifecycle = .connecting
    do {
      try Task.checkCancellation()
      let transport: WaylandTransport
      let stream: AsyncThrowingStream<WireMessage, any Error>
      if explicitPath == nil, let inherited = environment["WAYLAND_SOCKET"] {
        guard !inherited.isEmpty, inherited.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let fd = Int32(inherited)
        else { throw WaylandError.connection }
        let socket = WireDescriptor(taking: fd)
        _ = unsafe unsetenv("WAYLAND_SOCKET")
        let flags = fcntl(fd, F_GETFD)
        guard flags >= 0, fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0 else {
          throw WaylandError.connection
        }
        (transport, stream) = try await WaylandTransport.takingSocket(socket.take())
      } else {
        let name = explicitPath ?? environment["WAYLAND_DISPLAY"] ?? "wayland-0"
        let path: String
        if explicitPath != nil || name.hasPrefix("/") {
          path = name
        } else {
          guard let directory = environment["XDG_RUNTIME_DIR"] else {
            throw WaylandError.connection
          }
          path = directory + "/" + name
        }
        (transport, stream) = try await WaylandTransport.connect(path: path)
      }
      guard lifecycle != .closed else {
        await transport.close()
        throw CancellationError()
      }
      self.transport = transport
      installReader(stream, transport: transport)
      objects.requestQueued = { [weak self] in self?.scheduleSend() }
      registry = objects.create(1, 1, "wl_registry")
      try await synchronize()
      try await synchronize()
      guard compositor != 0, shell != 0, compositorVersion >= 3 else {
        throw WaylandError.missingGlobals
      }
      surface = objects.create(compositor, 0, "wl_surface")
      if configuration.topBar {
        guard layerShell != 0 else { throw WaylandError.missingGlobals }
        layerSurface = objects.create(
          layerShell, 0, "zwlr_layer_surface_v1",
          [.uint(surface), .uint(0), .uint(2), .string(configuration.layerNamespace)])
        objects.request(
          layerSurface, 0,
          [.uint(0), .uint(UInt32(configuration.height + configuration.topBarOverlayHeight))])
        objects.request(layerSurface, 1, [.uint(1 | 4 | 8)])
        objects.request(layerSurface, 2, [.int(configuration.height)])
        objects.request(layerSurface, 4, [.uint(0)])
      } else {
        xdgSurface = objects.create(shell, 2, "xdg_surface", [.uint(surface)])
        toplevel = objects.create(xdgSurface, 1, "xdg_toplevel")
        objects.request(toplevel, 2, [.string(configuration.title)])
        objects.request(toplevel, 3, [.string(configuration.appID)])
        objects.request(
          toplevel, 8, [.int(configuration.minimumWidth), .int(configuration.minimumHeight)])
      }
      objects.request(surface, 6)
      try await flushRequests()
      while !configured && running { try await waitForEvent() }
      try Task.checkCancellation()
      guard running, lifecycle != .closed else { throw WaylandError.connection }
      lifecycle = .connected
    } catch {
      cleanup()
      throw error
    }
  }

  private func installReader(
    _ stream: AsyncThrowingStream<WireMessage, any Error>, transport: WaylandTransport
  ) {
    reader = Task { @MainActor [weak self] in
      do {
        for try await message in stream {
          guard let self, self.lifecycle != .closed else { return }
          try self.receive(message)
          self.signal()
          try await self.flushRequests()
          try await transport.acknowledged(objects: [:])
        }
      } catch {
        guard let self, self.lifecycle != .closed else { return }
        self.terminalError = error
        self.running = false
        self.signal()
      }
    }
  }
  private func scheduleSend() {
    guard sender == nil, transport != nil, lifecycle != .closed else { return }
    sender = Task { @MainActor [weak self] in
      guard let self else { return }
      self.sender = nil
      do { try await self.flushRequests() } catch {
        self.terminalError = error
        self.running = false
        self.signal()
      }
    }
  }
  private func flushRequests() async throws {
    guard let transport else { throw WaylandError.connection }
    let (requests, registrations) = try objects.takeRequests()
    try await transport.send(requests, objects: registrations)
  }
  private func synchronize() async throws {
    let callback = objects.create(1, 0, "wl_callback")
    callbacks.insert(callback)
    try await flushRequests()
    while callbacks.contains(callback), running { try await waitForEvent() }
  }
  private func signal() {
    let waiter = waiting
    waiting = nil
    if let terminalError { waiter?.resume(throwing: terminalError) } else { waiter?.resume() }
  }
  private func waitForEvent() async throws {
    try Task.checkCancellation()
    if let terminalError { throw terminalError }
    guard lifecycle != .closed else { throw WaylandError.connection }
    waitID &+= 1
    let id = waitID
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        precondition(waiting == nil)
        waiting = continuation
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard self?.waitID == id else { return }
        let waiting = self?.waiting
        self?.waiting = nil
        waiting?.resume(throwing: CancellationError())
      }
    }
    try Task.checkCancellation()
    if let terminalError { throw terminalError }
  }

  public func drain(timeout: Duration = .milliseconds(250)) async throws {
    guard lifecycle == .connected else { throw WaylandError.connection }
    guard !dispatching else { throw WaylandError.busy }
    dispatching = true
    defer { dispatching = false }
    try Task.checkCancellation()
    if let terminalError { throw terminalError }
    let callback = objects.create(1, 0, "wl_callback")
    callbacks.insert(callback)
    var expired = false
    let deadline = Task { @MainActor in
      try await Task.sleep(for: timeout)
      expired = true
      signal()
    }
    defer {
      deadline.cancel()
      if callbacks.remove(callback) != nil { objects.retire(callback) }
    }
    try await flushRequests()
    while callbacks.contains(callback), !expired { try await waitForEvent() }
    try Task.checkCancellation()
    if let terminalError { throw terminalError }
  }

  public func dispatchAsync() async throws {
    guard lifecycle == .connected else { throw WaylandError.connection }
    guard !dispatching else { throw WaylandError.busy }
    dispatching = true
    defer { dispatching = false }
    if let terminalError { throw terminalError }
    if canRender || !running { return }
    try await waitForEvent()
  }
  public func requestRedraw() {
    guard running else { return }
    redrawRequested = true
    signal()
  }
  public func requestClose() {
    running = false
    signal()
  }

  func receive(_ message: WireMessage) throws {
    let id = message.object
    let opcode = message.opcode
    let a = message.arguments
    guard let interface = objects.interfaces[id] else { throw WaylandError.dispatch }
    if !objects.isLive(id) {
      if interface == "wl_data_device", opcode == 0 { clipboard.event(message) }
      if interface == "zwp_linux_buffer_params_v1", opcode == 0 { dmabuf.event(message) }
      return
    }
    switch interface {
    case "wl_display":
      if opcode == 0 {
        protocolError = a[2].text
        throw WaylandError.dispatch
      }
      objects.deleted(a[0].word)
    case "wl_registry":
      if opcode == 0 {
        bind(name: a[0].word, interface: a[1].text ?? "", version: a[2].word)
      } else {
        removeGlobal(a[0].word)
      }
    case "wl_callback":
      objects.retire(id)
      callbacks.remove(id)
      if frameCallback == id {
        frameCallback = 0
        frameReady = true
      }
    case "xdg_wm_base": objects.request(id, 3, [.uint(a[0].word)])
    case "xdg_surface":
      guard id == xdgSurface || id == popup?.xdgSurface else { return }
      objects.request(id, 4, [.uint(a[0].word)])
      if id == xdgSurface {
        if let pendingSize {
          if pendingSize.x > 0 { input.width = pendingSize.x }
          if pendingSize.y > 0 { input.height = pendingSize.y }
          self.pendingSize = nil
        }
        configured = true
      } else if let popup {
        if let size = popup.pendingSize {
          if size.x > 0 { popup.input.width = size.x }
          if size.y > 0 { popup.input.height = size.y }
          popup.pendingSize = nil
        }
        popup.configured = true
      }
      requestRedraw()
    case "xdg_toplevel":
      if opcode == 0 {
        pendingSize = SIMD2(a[0].signed, a[1].signed)
      } else if opcode == 1 {
        requestClose()
      }
    case "zwlr_layer_surface_v1":
      if opcode == 0 {
        objects.request(id, 6, [.uint(a[0].word)])
        configureLayer(width: a[1].word, height: a[2].word)
      } else {
        requestClose()
      }
    case "xdg_popup":
      guard id == popup?.popup else { return }
      if opcode == 0 {
        popup?.pendingSize = SIMD2(a[2].signed, a[3].signed)
      } else if opcode == 1 {
        requestPopupDismissal()
      }
    case "wl_surface":
      if id == surface {
        if opcode <= 1 {
          for name in outputs.keys where outputs[name]?.id == a[0].word {
            outputs[name]?.entered = opcode == 0
          }
          updateBufferScale()
        } else if opcode == 2, a[0].signed > 0 {
          preferredBufferScale = a[0].signed
          updateBufferScale()
        }
      }
    case "wl_output":
      if opcode == 3, a[0].signed > 0 {
        for name in outputs.keys where outputs[name]?.id == id {
          outputs[name]?.scale = a[0].signed
        }
      } else if opcode == 2 {
        updateBufferScale()
      }
    case "wl_seat": if opcode == 0 { updateCapabilities(a[0].word) }
    case "wl_pointer": pointerEvent(opcode, a)
    case "wl_keyboard": keyboardEvent(opcode, a)
    case "wl_data_device", "wl_data_offer", "wl_data_source": clipboard.event(message)
    case "zwp_linux_dmabuf_v1", "zwp_linux_buffer_params_v1", "wl_buffer": dmabuf.event(message)
    default: break
    }
  }

  private func bind(name: UInt32, interface: String, version: UInt32) {
    switch interface {
    case "wl_compositor" where compositor == 0:
      compositorVersion = min(version, 6)
      compositor = objects.bind(registry, name, interface, compositorVersion)
    case "xdg_wm_base" where shell == 0: shell = objects.bind(registry, name, interface, 1)
    case "zwlr_layer_shell_v1" where configuration.topBar && layerShell == 0:
      layerShell = objects.bind(registry, name, interface, 1)
    case "zwp_idle_inhibit_manager_v1" where idleManager == 0 && version >= 1:
      idleManager = objects.bind(registry, name, interface, 1)
      idleManagerName = name
    case "wl_output" where version >= 2:
      outputs[name] = WaylandOutput(
        id: objects.bind(registry, name, interface, min(version, 3)), version: min(version, 3))
    case "wl_seat" where seat == 0 && version >= 4:
      seatVersion = min(version, 5)
      seat = objects.bind(registry, name, interface, seatVersion)
      seatName = name
    case "wl_data_device_manager" where clipboard.manager == 0:
      clipboard.manager = objects.bind(registry, name, interface, 1)
      managerName = name
    case "zwp_linux_dmabuf_v1" where dmabuf.factory == 0 && version >= 3:
      dmabuf.factory = objects.bind(registry, name, interface, 3)
      dmabufName = name
    default: break
    }
    if seat != 0 { clipboard.attach(seat: seat) }
  }
  private func removeGlobal(_ name: UInt32) {
    if idleManagerName == name {
      _ = setIdleInhibited(false)
      objects.request(idleManager, 0)
      idleManager = 0
      idleManagerName = nil
    }
    if let output = outputs.removeValue(forKey: name) {
      if output.version >= 3 { objects.request(output.id, 0) } else { objects.retire(output.id) }
      updateBufferScale()
    }
    if dmabufName == name {
      objects.request(dmabuf.factory, 0)
      dmabuf.factory = 0
      dmabufName = nil
    }
    if managerName == name {
      clipboard.close()
      managerName = nil
    }
    if seatName == name {
      updateCapabilities(0)
      clipboard.detachSeat()
      if seatVersion >= 5 { objects.request(seat, 3) } else { objects.retire(seat) }
      seat = 0
      seatName = nil
    }
  }
  private func updateCapabilities(_ capabilities: UInt32) {
    if capabilities & 1 != 0 {
      if pointer == 0 { pointer = objects.create(seat, 0, "wl_pointer") }
    } else if pointer != 0 {
      objects.request(pointer, 1)
      pointer = 0
      pointerInput.leavePointer()
      pointerSerial = nil
      if popup != nil { requestPopupDismissal() }
      requestRedraw()
    }
    if capabilities & 2 != 0 {
      if keyboard == 0 { keyboard = objects.create(seat, 1, "wl_keyboard") }
    } else if keyboard != 0 {
      objects.request(keyboard, 0)
      keyboard = 0
      clipboard.focused = false
      typing.leave(input: &keyboardInput)
      if popup != nil { requestPopupDismissal() }
      requestRedraw()
    }
  }
  private func pointerEvent(_ opcode: UInt16, _ a: [WireValue]) {
    switch opcode {
    case 0:
      pointerInPopup = a[1].word == popup?.surface
      pointerInput.pointerInside = true
      pointerInput.pointerX = Float(a[2].signed) / 256
      pointerInput.pointerY = Float(a[3].signed) / 256
    case 1: pointerInput.leavePointer()
    case 2:
      pointerInput.pointerX = Float(a[1].signed) / 256
      pointerInput.pointerY = Float(a[2].signed) / 256
    case 3:
      clipboard.serial = a[0].word
      if a[2].word == 0x110 && a[3].word == 1 { pointerSerial = a[0].word }
      pointerInput.button(a[2].word, state: a[3].word)
    case 4: pointerInput.axis(a[1].word, value: a[2].signed, time: a[0].word)
    case 5:
      let previous = pointerInput.scrollVelocityY
      pointerInput.pointerFrame()
      if pointerInput.scrollVelocityY == previous { return }
    case 6:
      pointerInput.axisSource(a[0].word)
      return
    case 7: pointerInput.axisStop(a[1].word, time: a[0].word)
    default: return
    }
    requestRedraw()
  }
  private func keyboardEvent(_ opcode: UInt16, _ a: [WireValue]) {
    switch opcode {
    case 0:
      guard case .fd(let fd) = a[1] else { return }
      fd.borrow { typing.load(format: a[0].word, fd: $0, size: a[2].word) }
      fd.close()
    case 1:
      clipboard.serial = a[0].word
      clipboard.focused = true
      keyboardInPopup = a[1].word == popup?.surface
    case 2:
      clipboard.focused = false
      typing.leave(input: &keyboardInput)
    case 3:
      clipboard.serial = a[0].word
      typing.key(a[2].word, pressed: a[3].word == 1, input: &keyboardInput)
    case 4:
      typing.modifiers(
        depressed: a[1].word, latched: a[2].word, locked: a[3].word, group: a[4].word)
      return
    case 5:
      typing.repeatInfo(rate: a[0].signed, delay: a[1].signed)
      return
    default: return
    }
    requestRedraw()
  }
  func configureLayer(width: UInt32, height: UInt32) {
    guard width <= UInt32(Int32.max), height <= UInt32(Int32.max) else {
      requestClose()
      return
    }
    if width > 0 { input.width = Int32(width) }
    if height > 0 { input.height = Int32(height) }
    if compositor != 0, surface != 0 {
      let region = objects.create(compositor, 1, "wl_region")
      objects.request(region, 1, [.int(0), .int(0), .int(input.width), .int(configuration.height)])
      objects.request(surface, 5, [.uint(region)])
      objects.request(region, 0)
    }
    configured = true
    requestRedraw()
  }
  private func updateBufferScale() {
    let scale = preferredBufferScale ?? outputs.values.filter(\.entered).map(\.scale).max() ?? 1
    guard scale != input.bufferScale, surface != 0 else { return }
    input.bufferScale = scale
    objects.request(surface, 8, [.int(scale)])
    if let popup {
      popup.input.bufferScale = scale
      objects.request(popup.surface, 8, [.int(scale)])
    }
    requestRedraw()
  }

  public func beginFrame() -> WaylandInput {
    redrawRequested = false
    if lifecycle != .closed { typing.repeatKeys(input: &keyboardInput) }
    let snapshot = input
    input.resetEdges()
    return snapshot
  }
  public func endFrame(continuously: Bool = false) throws {
    guard lifecycle == .connected else { throw WaylandError.connection }
    guard running else { return }
    guard frameCallback == 0 else { throw WaylandError.connection }
    frameCallback = objects.create(surface, 3, "wl_callback")
    frameReady = false
    redrawRequested = redrawRequested || continuously || typing.isRepeating
  }
  public func presentPopup(
    configuration: WaylandPopupConfiguration, grab: Bool = true,
    onDismiss: @escaping @MainActor () -> Void = {}
  ) throws {
    guard lifecycle == .connected, configuration.isValid, running, popup == nil,
      !grab
        || (seat != 0 && pointerSerial != nil && input.primaryDown && input.pointerInside
          && !pointerInPopup)
    else { throw WaylandError.invalidConfiguration }
    popup = WaylandPopup(
      configuration: configuration, scale: input.bufferScale, compositor: compositor, shell: shell,
      parent: xdgSurface, layerParent: layerSurface, seat: grab ? seat : 0, serial: pointerSerial,
      objects: objects,
      onDismiss: onDismiss)
    pointerSerial = nil
    requestRedraw()
  }
  public func requestPopupDismissal() {
    popup?.dismissed = true
    requestRedraw()
  }
  public func dismissPopup() {
    guard let child = popup else { return }
    popup = nil
    waitingForBuffer = false
    pointerInPopup = false
    if keyboardInPopup { typing.leave(input: &child.input) }
    keyboardInPopup = false
    child.close()
    requestRedraw()
  }
  public var popupInput: WaylandInput? { popup?.input }
  public var popupConfigured: Bool { popup?.configured ?? false }
  public var popupDismissed: Bool { popup?.dismissed ?? false }
  public func takePopupInput() -> WaylandInput? {
    guard let popup, popup.configured, !popup.dismissed else { return nil }
    let snapshot = popup.input
    popup.input.resetEdges()
    return snapshot
  }
  public func importDMABuf(
    width: Int32, height: Int32, format: UInt32, modifier: UInt64,
    planes: borrowing Span<WaylandDMABufPlane>
  ) throws -> WaylandDMABufBuffer {
    guard lifecycle == .connected, running else { throw WaylandError.connection }
    return try dmabuf.importBuffer(
      width: width, height: height, format: format, modifier: modifier, planes: planes,
      changed: { [weak self] in
        guard let self, self.waitingForBuffer else { return }
        self.waitingForBuffer = false
        self.requestRedraw()
      })
  }
  public func waitForDMABufBuffer() { waitingForBuffer = true }
  public func presentDMABuf(_ buffer: WaylandDMABufBuffer, popup: Bool = false) throws {
    guard lifecycle == .connected, dmabuf.owns(buffer) else { throw WaylandError.connection }
    let target = popup ? self.popup?.surface ?? 0 : surface
    guard target != 0 else { throw WaylandError.connection }
    try buffer.present(on: target)
  }
  public func readClipboard() async -> String? {
    guard running, let fd = clipboard.beginRead() else { return nil }
    let transfer = Task.detached(executorPreference: BlockingIOExecutor.shared) {
      ClipboardTransfer.read(from: fd)
    }
    return await withTaskCancellationHandler {
      await transfer.value
    } onCancel: {
      transfer.cancel()
    }
  }
  @discardableResult public func writeClipboard(_ text: String) -> Bool {
    running && clipboard.write(text)
  }

  @discardableResult public func setIdleInhibited(_ enabled: Bool) -> Bool {
    guard lifecycle == .connected, running else { return false }
    if enabled {
      guard idleManager != 0, surface != 0 else { return false }
      if idleInhibitor == 0 {
        idleInhibitor = objects.create(idleManager, 1, "zwp_idle_inhibitor_v1", [.uint(surface)])
      }
    } else if idleInhibitor != 0 {
      objects.request(idleInhibitor, 0)
      idleInhibitor = 0
    }
    return true
  }

  public func cleanup() {
    guard lifecycle != .closed else { return }
    lifecycle = .closed
    running = false
    configured = false
    frameReady = false
    reader?.cancel()
    reader = nil
    sender?.cancel()
    sender = nil
    dismissPopup()
    dmabuf.close()
    clipboard.close()
    typing.leave(input: &input)
    input.leavePointer()
    idleInhibitor = 0
    idleManager = 0
    idleManagerName = nil
    objects.discard()
    let transport = self.transport
    self.transport = nil
    if let transport { Task { await transport.close() } }
    signal()
  }
}
