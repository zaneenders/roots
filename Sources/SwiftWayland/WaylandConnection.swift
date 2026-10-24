import Foundation
import Glibc
import NIOCore

@MainActor public final class WaylandConnection {
  private enum Lifecycle { case idle, connecting, connected, closed }
  private var lifecycle = Lifecycle.idle
  private let objects = WaylandObjects()
  private var io: Task<Void, Never>?
  private var writes: AsyncStream<Void>.Continuation?
  private var clipboardShutdown: Task<Void, Never>?
  private var decoder = WireDecoder()
  public private(set) var protocolError: String?
  private var terminalError: (any Error)?
  private var dispatching = false
  private var waiting: CheckedContinuation<Void, any Error>?
  private var waitID: UInt64 = 0
  private let frame = SurfaceFrameState()
  public let configuration: WaylandWindowConfiguration
  public internal(set) var input: WaylandInput
  public private(set) var running = true
  public var configured: Bool { frame.configured }
  public var frameReady: Bool { lifecycle != .closed && frame.frameReady }
  public var redrawRequested: Bool { frame.redrawRequested }
  public var canRender: Bool { running && frame.canRender }
  public var canRenderPopup: Bool {
    running && popup?.dismissed == false && popup?.frame.canRender == true
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
  private let scale = SurfaceScale()
  private var fractionalManager: UInt32 = 0
  private var fractionalManagerName: UInt32?
  private var viewporter: UInt32 = 0
  private var viewporterName: UInt32?
  private var typing = Keyboard()
  private var repeatTask: Task<Void, Never>?
  private var repeatDeadline: ContinuousClock.Instant?
  private var popup: WaylandPopup?
  private var pointerInPopup = false
  private var keyboardInPopup = false
  private var pointerSerial: UInt32?
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
        transport = try await WaylandTransport.takingSocket(socket.take())
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
        transport = try await WaylandTransport.connect(path: path)
      }
      guard lifecycle != .closed else {
        try? await transport.channel.close().get()
        throw CancellationError()
      }
      installIO(transport)
      registry = objects.create(1, 1, "wl_registry")
      try await synchronize()
      try await synchronize()
      guard compositor != 0, shell != 0, compositorVersion >= 3 else {
        throw WaylandError.missingGlobals
      }
      surface = objects.create(compositor, 0, "wl_surface")
      setupSurfaceScales()
      dmabuf.watch(surface: surface)
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
      while running && (!configured || !dmabuf.ready(surface: surface)) {
        try await waitForEvent()
      }
      try Task.checkCancellation()
      guard running, lifecycle != .closed else { throw WaylandError.connection }
      lifecycle = .connected
    } catch {
      await close()
      throw error
    }
  }

  private func installIO(_ transport: WaylandTransport) {
    let (writes, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.writes = signal
    objects.requestQueued = { signal.yield(()) }
    let receive: @MainActor @Sendable (inout WireChunk) throws -> Void = { [weak self] chunk in
      try self?.receive(&chunk)
    }
    let requests: @MainActor @Sendable () throws -> [WirePacket] = { [weak self] in
      try self?.objects.takeRequests() ?? []
    }
    io = Task { @MainActor [weak self] in
      do {
        try await transport.executeThenClose { inbound, outbound in
          try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
              group.addTask { try await Self.read(inbound, receive: receive) }
              group.addTask {
                do {
                  try await Self.write(writes, outbound: outbound, requests: requests)
                } catch {
                  // Let the reader drain buffered events before reporting a write failure.
                  transport.channel.pipeline.fireErrorCaught(error)
                  transport.channel.close(promise: nil)
                }
              }
              defer {
                transport.channel.close(promise: nil)
                group.cancelAll()
              }
              while try await group.next() != nil {}
            }
          } onCancel: {
            // A write waiting for writability must be unblocked before joining the writer.
            transport.channel.close(promise: nil)
          }
        }
      } catch {
        guard let self, self.lifecycle != .closed else { return }
        self.terminalError = error
        self.running = false
        self.scheduleKeyRepeat()
        self.decoder = WireDecoder()
        self.objects.discard()
        self.signal()
      }
    }
  }

  private static func read(
    _ inbound: NIOAsyncChannelInboundStream<WireChunk>,
    receive: @MainActor @Sendable (inout WireChunk) throws -> Void
  ) async throws {
    for try await var chunk in inbound {
      try Task.checkCancellation()
      try receive(&chunk)
    }
    throw WaylandError.connection
  }

  private static func write(
    _ writes: AsyncStream<Void>, outbound: NIOAsyncChannelOutboundWriter<WireBatch>,
    requests: @MainActor @Sendable () throws -> [WirePacket]
  ) async throws {
    for await _ in writes {
      try Task.checkCancellation()
      let batch = try requests()
      if !batch.isEmpty { try await outbound.write(WireBatch(batch)) }
    }
  }

  func receive(_ chunk: inout WireChunk) throws {
    guard lifecycle != .closed else { return }
    try decoder.append(&chunk.bytes, descriptors: chunk.descriptors)
    while let message = try decoder.next(interfaces: objects.interfaces) {
      try receive(message)
    }
    signal()
  }

  private func synchronize() async throws {
    let callback = objects.create(1, 0, "wl_callback")
    callbacks.insert(callback)
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
    if canRender || canRenderPopup || popupDismissed || !running { return }
    try await waitForEvent()
  }
  public func requestRedraw() {
    guard running else { return }
    frame.redrawRequested = true
    signal()
  }
  public func requestPopupRedraw() {
    guard running, let popup, !popup.dismissed else { return }
    popup.frame.redrawRequested = true
    signal()
  }
  public func requestClose() {
    running = false
    scheduleKeyRepeat()
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
      frame.complete(id)
      popup?.frame.complete(id)
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
        frame.configured = true
      } else if let popup {
        if let size = popup.pendingSize {
          if size.x > 0 { popup.input.width = size.x }
          if size.y > 0 { popup.input.height = size.y }
          popup.pendingSize = nil
        }
        popup.frame.configured = true
      }
      if id == xdgSurface { requestRedraw() } else { requestPopupRedraw() }
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
      guard let scale = id == surface ? scale : (id == popup?.surface ? popup?.scale : nil)
      else { return }
      if opcode <= 1 {
        if opcode == 0 { scale.outputs.insert(a[0].word) } else { scale.outputs.remove(a[0].word) }
      } else if opcode == 2, a[0].signed > 0 {
        scale.preferredBufferScale = a[0].signed
      }
      updateBufferScale()
    case "wp_fractional_scale_v1":
      guard a[0].word > 0,
        let scale = id == scale.fractional
          ? scale : (id == popup?.scale.fractional ? popup?.scale : nil)
      else { return }
      scale.preferredFractionalScale = a[0].word
      updateBufferScale()
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
    case "zwp_linux_dmabuf_feedback_v1":
      if try dmabuf.feedbackEvent(message) {
        requestRedraw()
        requestPopupRedraw()
      }
    case "zwp_linux_dmabuf_v1", "zwp_linux_buffer_params_v1", "wl_buffer": dmabuf.event(message)
    default: break
    }
  }

  private func bind(name: UInt32, interface: String, version: UInt32) {
    switch interface {
    case "wl_compositor" where compositor == 0:
      compositorVersion = min(version, 6)
      compositor = objects.bind(registry, name, interface, compositorVersion)
    case "wp_fractional_scale_manager_v1" where fractionalManager == 0 && version >= 1:
      fractionalManager = objects.bind(registry, name, interface, 1)
      fractionalManagerName = name
      setupSurfaceScales()
    case "wp_viewporter" where viewporter == 0 && version >= 1:
      viewporter = objects.bind(registry, name, interface, 1)
      viewporterName = name
      setupSurfaceScales()
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
      dmabuf.version = min(version, 4)
      dmabuf.factory = objects.bind(registry, name, interface, dmabuf.version)
      dmabuf.watch()
      dmabufName = name
    default: break
    }
    if seat != 0 { clipboard.attach(seat: seat) }
  }
  private func removeGlobal(_ name: UInt32) {
    if fractionalManagerName == name {
      objects.request(fractionalManager, 0)
      fractionalManager = 0
      fractionalManagerName = nil
    }
    if viewporterName == name {
      objects.request(viewporter, 0)
      viewporter = 0
      viewporterName = nil
    }
    if idleManagerName == name {
      _ = setIdleInhibited(false)
      objects.request(idleManager, 0)
      idleManager = 0
      idleManagerName = nil
    }
    if let output = outputs.removeValue(forKey: name) {
      if output.version >= 3 { objects.request(output.id, 0) } else { objects.retire(output.id) }
      scale.outputs.remove(output.id)
      popup?.scale.outputs.remove(output.id)
      updateBufferScale()
    }
    if dmabufName == name {
      objects.request(dmabuf.factory, 0)
      dmabuf.close()
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
    defer { scheduleKeyRepeat() }
    if capabilities & 1 != 0 {
      if pointer == 0 { pointer = objects.create(seat, 0, "wl_pointer") }
    } else if pointer != 0 {
      objects.request(pointer, 1)
      pointer = 0
      pointerInput.leavePointer()
      pointerSerial = nil
      if popup != nil { requestPopupDismissal() }
      if pointerInPopup { requestPopupRedraw() } else { requestRedraw() }
    }
    if capabilities & 2 != 0 {
      if keyboard == 0 { keyboard = objects.create(seat, 1, "wl_keyboard") }
    } else if keyboard != 0 {
      objects.request(keyboard, 0)
      keyboard = 0
      clipboard.focused = false
      typing.leave(input: &keyboardInput)
      if popup != nil { requestPopupDismissal() }
      if keyboardInPopup { requestPopupRedraw() } else { requestRedraw() }
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
    if pointerInPopup { requestPopupRedraw() } else { requestRedraw() }
  }
  private func keyboardEvent(_ opcode: UInt16, _ a: [WireValue]) {
    defer { scheduleKeyRepeat() }
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
    if keyboardInPopup { requestPopupRedraw() } else { requestRedraw() }
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
    frame.configured = true
    requestRedraw()
  }
  private func setupSurfaceScales() {
    scale.setup(
      surface: surface, manager: fractionalManager, viewporter: viewporter, objects: objects)
    if let popup {
      popup.scale.setup(
        surface: popup.surface, manager: fractionalManager, viewporter: viewporter, objects: objects
      )
    }
  }

  private func updateBufferScale() {
    func fallback(_ scale: SurfaceScale, otherwise: Int32 = 1) -> Int32 {
      outputs.values.filter { scale.outputs.contains($0.id) }.map(\.scale).max() ?? otherwise
    }
    if scale.update(input: &input, surface: surface, fallback: fallback(scale), objects: objects) {
      requestRedraw()
    }
    if let popup,
      popup.scale.update(
        input: &popup.input, surface: popup.surface,
        fallback: fallback(popup.scale, otherwise: input.bufferScale), objects: objects)
    {
      requestPopupRedraw()
    }
  }

  private func scheduleKeyRepeat() {
    let deadline =
      running && (!keyboardInPopup || popup?.dismissed == false)
      ? typing.repeatDeadline : nil
    guard deadline != repeatDeadline else { return }
    repeatTask?.cancel()
    repeatTask = nil
    repeatDeadline = deadline
    guard let deadline else { return }
    repeatTask = Task { @MainActor [weak self] in
      do { try await ContinuousClock().sleep(until: deadline) } catch { return }
      guard let self, self.running, self.repeatDeadline == deadline else { return }
      self.repeatTask = nil
      // Leave the deadline armed until a frame consumes the bounded repeat batch.
      // A delayed frame callback or buffer release must not cause a timer spin.
      if self.keyboardInPopup { self.requestPopupRedraw() } else { self.requestRedraw() }
    }
  }

  public func beginFrame() -> WaylandInput {
    frame.redrawRequested = false
    if running && !keyboardInPopup {
      typing.repeatKeys(input: &input)
      scheduleKeyRepeat()
    }
    let snapshot = input
    input.resetEdges()
    return snapshot
  }
  public func endFrame(continuously: Bool = false) throws {
    guard lifecycle == .connected else { throw WaylandError.connection }
    guard running else { return }
    scale.prepare(width: input.width, height: input.height, objects: objects)
    try frame.endFrame(
      on: surface, objects: objects,
      continuously: continuously)
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
      objects: objects, fractionalManager: fractionalManager, viewporter: viewporter,
      onDismiss: onDismiss)
    if let popup { dmabuf.watch(surface: popup.surface) }
    pointerSerial = nil
    signal()
  }
  public func requestPopupDismissal() {
    popup?.dismissed = true
    scheduleKeyRepeat()
    signal()
  }
  public func dismissPopup() {
    guard let child = popup else { return }
    popup = nil
    pointerInPopup = false
    if keyboardInPopup { typing.leave(input: &child.input) }
    keyboardInPopup = false
    scheduleKeyRepeat()
    dmabuf.unwatch(surface: child.surface)
    child.close()
    signal()
  }
  public var popupInput: WaylandInput? { popup?.input }
  public var popupConfigured: Bool { popup?.frame.configured ?? false }
  public var popupDismissed: Bool { popup?.dismissed ?? false }
  public func takePopupInput() -> WaylandInput? {
    guard let popup, popup.frame.configured, !popup.dismissed else { return nil }
    popup.frame.redrawRequested = false
    if running && keyboardInPopup {
      typing.repeatKeys(input: &popup.input)
      scheduleKeyRepeat()
    }
    let snapshot = popup.input
    popup.input.resetEdges()
    return snapshot
  }
  public func endPopupFrame(continuously: Bool = false) throws {
    guard lifecycle == .connected else { throw WaylandError.connection }
    guard running, let popup, !popup.dismissed else { return }
    popup.scale.prepare(width: popup.input.width, height: popup.input.height, objects: objects)
    try popup.frame.endFrame(
      on: popup.surface, objects: objects,
      continuously: continuously)
  }
  public var dmabufPreferences: WaylandDMABufFeedback? { dmabuf.preferences(surface: surface) }
  public var popupDMABufPreferences: WaylandDMABufFeedback? {
    popup.flatMap { dmabuf.preferences(surface: $0.surface) }
  }
  public func importDMABuf(
    width: Int32, height: Int32, format: UInt32, modifier: UInt64,
    planes: borrowing Span<WaylandDMABufPlane>, popup: Bool = false
  ) throws -> WaylandDMABufBuffer {
    guard lifecycle == .connected, running else { throw WaylandError.connection }
    guard let frame = popup ? self.popup?.frame : frame else { throw WaylandError.connection }
    return try dmabuf.importBuffer(
      width: width, height: height, format: format, modifier: modifier, planes: planes,
      surface: popup ? self.popup?.surface ?? 0 : surface,
      changed: { [weak self, weak frame] in
        guard let frame, frame.waitingForBuffer else { return }
        frame.waitingForBuffer = false
        frame.redrawRequested = true
        self?.signal()
      })
  }
  public func waitForDMABufBuffer(popup: Bool = false) {
    let frame = popup ? self.popup?.frame : frame
    frame?.waitingForBuffer = true
  }
  public func presentDMABuf(_ buffer: WaylandDMABufBuffer, popup: Bool = false) throws {
    guard lifecycle == .connected, dmabuf.owns(buffer) else { throw WaylandError.connection }
    let target = popup ? self.popup?.surface ?? 0 : surface
    guard target != 0 else { throw WaylandError.connection }
    try buffer.present(on: target)
  }
  public func readClipboard() async -> String? {
    guard running, let fd = clipboard.beginRead() else { return nil }
    guard let bytes = try? await clipboard.io.read(from: fd) else { return nil }
    return String(bytes: bytes, encoding: .utf8)
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

  public func close() async {
    cleanup()
    await io?.value
    await clipboardShutdown?.value
  }

  public func cleanup() {
    guard lifecycle != .closed else { return }
    lifecycle = .closed
    running = false
    scheduleKeyRepeat()
    frame.close(objects: objects)
    io?.cancel()
    writes?.finish()
    writes = nil
    decoder = WireDecoder()
    dismissPopup()
    dmabuf.close()
    scale.close(objects: objects)
    objects.request(fractionalManager, 0)
    objects.request(viewporter, 0)
    clipboard.close()
    let io = clipboard.io
    clipboardShutdown = Task { await io.shutdown() }
    typing.leave(input: &input)
    input.leavePointer()
    idleInhibitor = 0
    idleManager = 0
    idleManagerName = nil
    objects.discard()
    signal()
  }
}
