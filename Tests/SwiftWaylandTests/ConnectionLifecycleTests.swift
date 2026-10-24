import CWaylandTestSupport
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

private struct ConnectionPeer: Sendable {
  let socket: WireDescriptor
  var bytes = ByteBufferAllocator().buffer(capacity: 4096)
  var registry: UInt32 = 0
  var shell: UInt32 = 0
  var surface: UInt32 = 0
  var xdgSurface: UInt32 = 0
  var toplevel: UInt32 = 0
  var dmabuf: UInt32 = 0
  var seat: UInt32 = 0
  var pointer: UInt32 = 0
  var idleManager: UInt32 = 0

  static func pair() throws -> (Int32, ConnectionPeer) {
    var fds: [Int32] = [-1, -1]
    try #require(
      unsafe socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_CLOEXEC.rawValue), 0, &fds) == 0)
    let client = WireDescriptor(taking: fds[0])
    let server = WireDescriptor(taking: fds[1])
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    try #require(
      unsafe setsockopt(
        fds[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
    return (client.take(), ConnectionPeer(socket: server))
  }

  func send(_ object: UInt32, _ opcode: UInt16, _ arguments: [WireValue] = []) throws {
    let packet = try WirePacket(object: object, opcode: opcode, arguments: arguments)
    let fds = packet.descriptors.map { $0.borrow { $0 } }
    let count = socket.borrow { fd in
      unsafe packet.bytes.withUnsafeReadableBytes { bytes in
        fds.withUnsafeBufferPointer {
          unsafe cwl_send(fd, bytes.baseAddress, bytes.count, $0.baseAddress, $0.count)
        }
      }
    }
    try #require(count == packet.bytes.readableBytes)
  }

  mutating func next() throws -> (id: UInt32, opcode: UInt16, body: ByteBuffer) {
    while true {
      let start = bytes.readerIndex
      if let header: UInt32 = bytes.getInteger(at: start + 4, endianness: .host) {
        let size = Int(header >> 16)
        try #require(size >= 8)
        if bytes.readableBytes >= size {
          let id: UInt32 = bytes.readInteger(endianness: .host)!
          bytes.moveReaderIndex(forwardBy: 4)
          return (id, UInt16(truncatingIfNeeded: header), bytes.readSlice(length: size - 8)!)
        }
      }
      var scratch = [UInt8](repeating: 0, count: 4096)
      let count = socket.borrow { unsafe recv($0, &scratch, scratch.count, 0) }
      try #require(count > 0)
      bytes.writeBytes(scratch.prefix(count))
    }
  }

  mutating func configure(dmabufVersion: UInt32 = 3) throws {
    var compositor: UInt32 = 0
    while true {
      var request = try next()
      let first: UInt32? = request.body.readInteger(endianness: .host)
      switch (request.id, request.opcode) {
      case (1, 1):
        registry = try #require(first)
        for (name, interface): (UInt32, String) in [
          (1, "wl_compositor"), (2, "xdg_wm_base"), (3, "zwp_linux_dmabuf_v1"), (4, "wl_seat"),
          (5, "zwp_idle_inhibit_manager_v1"),
        ] {
          try send(
            registry, 0, [.uint(name), .string(interface), .uint(name == 3 ? dmabufVersion : 6)])
        }
      case (1, 0):
        let callback = try #require(first)
        try send(callback, 0, [.uint(1)])
        try send(1, 1, [.uint(callback)])
      case (registry, 0):
        let id: UInt32 = try #require(
          request.body.getInteger(at: request.body.writerIndex - 4, endianness: .host))
        switch first {
        case 1: compositor = id
        case 2: shell = id
        case 5: idleManager = id
        case 4:
          seat = id
          try send(seat, 0, [.uint(1)])
        case 3:
          dmabuf = id
          if dmabufVersion == 3 {
            try send(dmabuf, 1, [.uint(0x3432_5241), .uint(0), .uint(0)])
          }
        default: break
        }
      case (dmabuf, 2), (dmabuf, 3):
        try sendFeedback(try #require(first), device: 123)
      case (seat, 0): pointer = try #require(first)
      case (compositor, 0): surface = try #require(first)
      case (shell, 2): xdgSurface = try #require(first)
      case (xdgSurface, 1): toplevel = try #require(first)
      case (surface, 6):
        try send(toplevel, 0, [.int(100), .int(80), .array(ByteBuffer())])
        try send(xdgSurface, 0, [.uint(1)])
        return
      default: break
      }
    }
  }

  func sendFeedback(_ id: UInt32, device: UInt64) throws {
    let (table, _) = try tableEvent([.init(format: 0x3432_5241, modifier: 0)], id: id)
    try send(id, table.opcode, table.arguments)
    try send(id, 2, [deviceBytes(device)])
    for event in trancheEvents(device: device, indices: [0], id: id) {
      try send(id, event.opcode, event.arguments)
    }
    try send(id, 0)
  }

  mutating func throughSync() throws -> (
    callback: UInt32, requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)]
  ) {
    var requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)] = []
    while true {
      let request = try next()
      if request.id == 1, request.opcode == 0 {
        let callback: UInt32 = try #require(
          request.body.getInteger(at: request.body.readerIndex, endianness: .host))
        return (callback, requests)
      }
      requests.append(request)
    }
  }

  mutating func throughPong() throws -> [(id: UInt32, opcode: UInt16, body: ByteBuffer)] {
    var requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)] = []
    while true {
      let request = try next()
      if request.id == shell, request.opcode == 3 { return requests }
      requests.append(request)
    }
  }
}

@MainActor private func connectedPeer(dmabufVersion: UInt32 = 3) async throws -> (
  WaylandConnection, ConnectionPeer, Int32
) {
  let (fd, peer) = try ConnectionPeer.pair()
  let server = blockingTestTask {
    var peer = peer
    do {
      try peer.configure(dmabufVersion: dmabufVersion)
      return peer
    } catch {
      peer.socket.close()
      throw error
    }
  }
  let connection = WaylandConnection(configuration: .init(width: 100, height: 80))
  do {
    try await connection.connect(path: nil, environment: ["WAYLAND_SOCKET": String(fd)])
    return (connection, try await server.value, fd)
  } catch {
    connection.cleanup()
    throw error
  }
}

@MainActor private func drain(_ connection: WaylandConnection, _ peer: inout ConnectionPeer)
  async throws
  -> [(id: UInt32, opcode: UInt16, body: ByteBuffer)]
{
  try connection.receive(.init(object: peer.shell, opcode: 0, arguments: [.uint(99)]))
  let snapshot = peer
  let (updated, requests) = try await blockingTestTask {
    var peer = snapshot
    let requests = try peer.throughPong()
    return (peer, requests)
  }.value
  peer = updated
  return requests
}

@Test @MainActor func inheritedSocketConnectsWithoutDisplayPathAndClosesOnCleanup() async throws {
  let (connection, peer, fd) = try await connectedPeer()
  #expect(connection.configured && connection.running)
  #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0)
  connection.cleanup()
  let reachedEOF = await blockingTestTask {
    var scratch = [UInt8](repeating: 0, count: 4096)
    var count = 1
    while count > 0 { count = peer.socket.borrow { unsafe recv($0, &scratch, scratch.count, 0) } }
    return count == 0
  }.value
  #expect(reachedEOF)
}

@Test(arguments: ["", "-1", "invalid", "2147483648", "1x"])
@MainActor func invalidInheritedSocketDoesNotFallBackToDisplay(value: String) async {
  let connection = WaylandConnection(configuration: .init())
  await #expect(throws: WaylandError.connection) {
    try await connection.connect(
      path: nil, environment: ["WAYLAND_SOCKET": value, "WAYLAND_DISPLAY": "/nonexistent"])
  }
  #expect(!connection.running)
}

@Test @MainActor func toplevelConfigurationIsLatchedUntilAcknowledgement() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = try await drain(connection, &peer)
  _ = connection.beginFrame()
  for size: SIMD2<Int32> in [SIMD2(200, 150), SIMD2(240, 0)] {
    try connection.receive(
      .init(
        object: peer.toplevel, opcode: 0,
        arguments: [.int(size.x), .int(size.y), .array(ByteBuffer())]))
    #expect(connection.input.width == 100 && connection.input.height == 80)
    #expect(!connection.redrawRequested)
  }
  connection.requestRedraw()
  #expect(connection.beginFrame().width == 100)
  try connection.receive(.init(object: peer.xdgSurface, opcode: 0, arguments: [.uint(2)]))
  #expect(connection.canRender)
  let input = connection.beginFrame()
  #expect(input.width == 240 && input.height == 80)
  try connection.endFrame(continuously: true)
  let requests = try await drain(connection, &peer)
  let ack = try #require(requests.firstIndex { $0.id == peer.xdgSurface && $0.opcode == 4 })
  let frame = try #require(requests.firstIndex { $0.id == peer.surface && $0.opcode == 3 })
  #expect(ack < frame)
}

@Test @MainActor func retiredPopupEventsCannotAcknowledgeOrDismissItsReplacement() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = try await drain(connection, &peer)
  let configuration = WaylandPopupConfiguration(
    x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 40, height: 30)
  try connection.presentPopup(configuration: configuration, grab: false)
  let created = try await drain(connection, &peer)
  let xdgRequest = try #require(created.first { $0.id == peer.shell && $0.opcode == 2 })
  let xdg: UInt32 = try #require(
    xdgRequest.body.getInteger(at: xdgRequest.body.readerIndex, endianness: .host))
  let popupRequest = try #require(created.first { $0.id == xdg && $0.opcode == 2 })
  let popup: UInt32 = try #require(
    popupRequest.body.getInteger(at: popupRequest.body.readerIndex, endianness: .host))
  try connection.receive(
    .init(object: popup, opcode: 0, arguments: [.int(0), .int(0), .int(60), .int(50)]))
  #expect(connection.popupInput?.width == 40 && !connection.popupConfigured)
  try connection.receive(.init(object: xdg, opcode: 0, arguments: [.uint(2)]))
  #expect(connection.popupInput?.width == 60 && connection.popupConfigured)
  _ = try await drain(connection, &peer)
  connection.dismissPopup()
  try connection.presentPopup(configuration: configuration, grab: false)
  try connection.receive(
    .init(object: popup, opcode: 0, arguments: [.int(0), .int(0), .int(90), .int(90)]))
  try connection.receive(.init(object: xdg, opcode: 0, arguments: [.uint(3)]))
  try connection.receive(.init(object: popup, opcode: 1, arguments: []))
  #expect(
    connection.popupInput?.width == 40 && !connection.popupConfigured && !connection.popupDismissed)
  let requests = try await drain(connection, &peer)
  #expect(requests.filter { $0.id == xdg }.map(\.opcode) == [0])
  #expect(requests.filter { $0.id == popup }.map(\.opcode) == [0])
}

@Test @MainActor func inheritedSocketCancellationClosesTheTransferredDescriptor() async throws {
  let (fd, peer) = try ConnectionPeer.pair()
  let connection = WaylandConnection(configuration: .init())
  defer { connection.cleanup() }
  let session = Task {
    try await connection.connect(path: nil, environment: ["WAYLAND_SOCKET": String(fd)])
  }
  let received = try await blockingTestTask {
    var peer = peer
    let first = try peer.next()
    return first.id == 1 && first.opcode == 1
  }.value
  #expect(received)
  session.cancel()
  await #expect(throws: CancellationError.self) { try await session.value }
  let reachedEOF = await blockingTestTask {
    var scratch = [UInt8](repeating: 0, count: 4096)
    var count = 1
    while count > 0 { count = peer.socket.borrow { unsafe recv($0, &scratch, scratch.count, 0) } }
    return count == 0
  }.value
  #expect(reachedEOF && !connection.running)
}

@Test(arguments: [false, true]) @MainActor func drainDeliversFinalBufferBeforeCleanup(
  closeRequested: Bool
) async throws {
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  let bufferID: UInt32 = 0xff00_0000
  let server = blockingTestTask {
    var peer = peer
    var params: UInt32 = 0
    while true {
      let request = try peer.next()
      if request.id == peer.dmabuf, request.opcode == 1 {
        params = try #require(
          request.body.getInteger(at: request.body.readerIndex, endianness: .host))
      } else if request.id == params, request.opcode == 2 {
        try peer.send(params, 0, [.uint(bufferID)])
        break
      }
    }
    let (callback, requests) = try peer.throughSync()
    let surfaceRequests = requests.filter { $0.id == peer.surface }
    #expect(surfaceRequests.map(\.opcode) == [7, 1, 2, 6])
    let attach = try #require(surfaceRequests.first { $0.opcode == 1 })
    #expect(
      attach.body.getInteger(at: attach.body.readerIndex, endianness: .host, as: UInt32.self)
        == bufferID)
    try peer.send(callback, 0, [.uint(1)])
  }
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 400)]
  let buffer = try connection.importDMABuf(
    width: 100, height: 80, format: 0x3432_5241, modifier: 0, planes: planes.span)
  connection.waitForDMABufBuffer()
  while buffer.state == .importing { try await connection.dispatchAsync() }
  _ = connection.beginFrame()
  try connection.presentDMABuf(buffer)
  if closeRequested { connection.requestClose() }
  try await connection.drain()
  connection.cleanup()
  try await server.value
}

@Test @MainActor func drainIsCancellableAndExcludesConcurrentDispatch() async throws {
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  let server = blockingTestTask {
    var peer = peer
    _ = try peer.throughSync()
  }
  let draining = Task { try await connection.drain() }
  defer { draining.cancel() }
  try await server.value
  await #expect(throws: WaylandError.busy) { try await connection.dispatchAsync() }
  await #expect(throws: WaylandError.busy) { try await connection.drain() }
  draining.cancel()
  await #expect(throws: CancellationError.self) { try await draining.value }
}

@Test @MainActor func protocolErrorFailsSuspendedDispatch() async throws {
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  _ = connection.beginFrame()
  try peer.send(1, 0, [.uint(peer.surface), .uint(0), .string("rejected commit")])
  await #expect(throws: WaylandError.dispatch) { try await connection.dispatchAsync() }
  #expect(!connection.running && connection.protocolError == "rejected commit")
}

@Test(arguments: [false, true]) @MainActor func protocolErrorSurvivesCoalescedEventsAndDisconnect(
  halfClose: Bool
)
  async throws
{
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var bytes = try WirePacket(object: peer.shell, opcode: 0, arguments: [.uint(99)]).bytes
  bytes.writeImmutableBuffer(
    try WirePacket(object: peer.xdgSurface, opcode: 0, arguments: [.uint(2)]).bytes)
  bytes.writeImmutableBuffer(
    try WirePacket(
      object: 1, opcode: 0,
      arguments: [.uint(peer.surface), .uint(0), .string("rejected final commit")]
    )
    .bytes)
  let sent = peer.socket.borrow { fd in
    unsafe bytes.withUnsafeReadableBytes { unsafe cwl_send(fd, $0.baseAddress, $0.count, nil, 0) }
  }
  #expect(sent == bytes.readableBytes)
  if halfClose {
    peer.socket.borrow { #expect(shutdown($0, Int32(SHUT_WR)) == 0) }
  } else {
    peer.socket.close()
  }
  await #expect(throws: WaylandError.dispatch) {
    while connection.running {
      _ = connection.beginFrame()
      try await connection.dispatchAsync()
    }
  }
  #expect(!connection.running && connection.protocolError == "rejected final commit")
}

@Test @MainActor func protocolErrorFailsDrain() async throws {
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  let server = blockingTestTask {
    var peer = peer
    _ = try peer.throughSync()
    try peer.send(1, 0, [.uint(peer.surface), .uint(0), .string("rejected final commit")])
  }
  await #expect(throws: WaylandError.dispatch) { try await connection.drain() }
  try await server.value
  #expect(!connection.running && connection.protocolError == "rejected final commit")
}

@Test @MainActor func requestCloseFinishesWithAnUnresponsiveCompositorWithoutCancellation()
  async throws
{
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  _ = connection.beginFrame()
  var dispatchStarted = false
  let session = Task {
    defer { connection.cleanup() }
    while connection.running {
      dispatchStarted = true
      try await connection.dispatchAsync()
    }
    try await connection.drain()
  }
  while !dispatchStarted { await Task.yield() }
  let server = blockingTestTask {
    var peer = peer
    defer { peer.socket.borrow { _ = shutdown($0, Int32(SHUT_RDWR)) } }
    _ = try peer.throughSync()
    var byte: UInt8 = 0
    let count = peer.socket.borrow { unsafe recv($0, &byte, 1, 0) }
    #expect(count == 0)
  }
  let started = ContinuousClock.now
  connection.requestClose()
  try await session.value
  #expect(started.duration(to: .now) < .seconds(2))
  #expect(!connection.running && !connection.configured)
  try await server.value
}

@Test @MainActor func expiredDrainIgnoresLateCallbackAndAllowsAnotherDrain() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  let server = blockingTestTask {
    var peer = initialPeer
    let (callback, _) = try peer.throughSync()
    return (peer, callback)
  }
  try await connection.drain(timeout: .milliseconds(10))
  let (peer, callback) = try await server.value
  let reply = blockingTestTask {
    var peer = peer
    let (next, _) = try peer.throughSync()
    try peer.send(callback, 0, [.uint(1)])
    try peer.send(1, 1, [.uint(callback)])
    try peer.send(next, 0, [.uint(2)])
  }
  try await connection.drain()
  try await reply.value
  #expect(connection.running)
}

@Test @MainActor func inputBurstsWaitForFrameCallbackAndPreserveEdgesWithoutAnimating() async throws
{
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = connection.beginFrame()
  try connection.endFrame()
  #expect(!connection.frameReady && !connection.redrawRequested)
  let requests = try await drain(connection, &peer)
  let frame = try #require(requests.first { $0.id == peer.surface && $0.opcode == 3 })
  let callback: UInt32 = try #require(
    frame.body.getInteger(at: frame.body.readerIndex, endianness: .host))
  try peer.send(peer.pointer, 0, [.uint(1), .uint(peer.surface), .int(0), .int(0)])
  try peer.send(peer.pointer, 3, [.uint(2), .uint(0), .uint(0x110), .uint(1)])
  for x in 1...20 {
    try peer.send(peer.pointer, 2, [.uint(0), .int(Int32(x * 256)), .int(256)])
  }
  try peer.send(peer.pointer, 3, [.uint(3), .uint(0), .uint(0x110), .uint(0)])
  try peer.send(peer.shell, 0, [.uint(99)])
  let snapshot = peer
  peer = try await blockingTestTask {
    var peer = snapshot
    let requests = try peer.throughPong()
    #expect(!requests.contains { $0.id == peer.surface && $0.opcode == 3 })
    return peer
  }.value
  #expect(!connection.canRender && !connection.frameReady && connection.redrawRequested)
  #expect(
    connection.input.primaryPressed && connection.input.primaryReleased
      && !connection.input.primaryDown)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(1)]))
  #expect(connection.canRender)
  let input = connection.beginFrame()
  #expect(input.pointerX == 20 && input.pointerY == 1)
  #expect(input.primaryPressed && input.primaryReleased && !input.primaryDown)
  #expect(!connection.input.primaryPressed && !connection.input.primaryReleased)
  try connection.endFrame()
  let nextRequests = try await drain(connection, &peer)
  let nextFrame = try #require(nextRequests.first { $0.id == peer.surface && $0.opcode == 3 })
  let next: UInt32 = try #require(
    nextFrame.body.getInteger(at: nextFrame.body.readerIndex, endianness: .host))
  try connection.receive(.init(object: next, opcode: 0, arguments: [.uint(2)]))
  #expect(connection.frameReady && !connection.redrawRequested && !connection.canRender)
}

@Test(arguments: [false, true]) @MainActor func closeBoundsDrainWhenPeerStopsReplying(
  closeDuringDrain: Bool
)
  async throws
{
  let (connection, peer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  let syncReceived = blockingTestTask {
    var peer = peer
    return try peer.throughSync().callback
  }
  let started = ContinuousClock.now
  if !closeDuringDrain { connection.requestClose() }
  let draining = Task { try await connection.drain() }
  let callback = try await syncReceived.value
  if closeDuringDrain { connection.requestClose() }
  let disconnected = blockingTestTask {
    defer { peer.socket.close() }
    var scratch = [UInt8](repeating: 0, count: 4096)
    var count = 1
    while count > 0 { count = peer.socket.borrow { unsafe recv($0, &scratch, scratch.count, 0) } }
    return count == 0
  }
  try await draining.value
  #expect(started.duration(to: .now) < .seconds(2))
  #expect(!connection.running)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(1)]))
  connection.cleanup()
  #expect(await disconnected.value)
}

@Test @MainActor func idleInhibitionUsesOneParentScopedObjectAndReleasesOnDisable() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  var peer = initialPeer
  defer {
    connection.cleanup()
    peer.socket.close()
  }
  #expect(connection.setIdleInhibited(true))
  #expect(connection.setIdleInhibited(true))
  let created = try await drain(connection, &peer).filter {
    $0.id == peer.idleManager && $0.opcode == 1
  }
  let request = try #require(created.first)
  #expect(created.count == 1)
  let inhibitor: UInt32 = try #require(request.body.getInteger(at: 0, endianness: .host))
  #expect(request.body.getInteger(at: 4, endianness: .host, as: UInt32.self) == peer.surface)
  #expect(connection.setIdleInhibited(false))
  #expect(connection.setIdleInhibited(false))
  let destroyed = try await drain(connection, &peer).filter { $0.id == inhibitor && $0.opcode == 0 }
  #expect(destroyed.count == 1)
  #expect(connection.setIdleInhibited(true))
  _ = try await drain(connection, &peer)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(5)]))
  let removed = try await drain(connection, &peer)
  #expect(removed.filter { $0.id == peer.idleManager && $0.opcode == 0 }.count == 1)
  #expect(!connection.setIdleInhibited(true))
  connection.cleanup()
  #expect(!connection.setIdleInhibited(false))
}

@Test(.timeLimit(.minutes(1))) @MainActor func awaitableCloseClosesSocketBeforeReturning()
  async throws
{
  let (connection, peer, _) = try await connectedPeer()
  await connection.close()
  await connection.close()
  #expect(!connection.running && !connection.configured)
  try expectPeerEOF(peer)
  peer.socket.close()
}

@Test(.timeLimit(.minutes(1))) @MainActor
func connectionDecodesServerCreatedBufferAndReleaseInOneChunk() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 400)]
  let buffer = try connection.importDMABuf(
    width: 100, height: 80, format: 0x3432_5241, modifier: 0, planes: planes.span)
  var peer = initialPeer
  let requests = try await drain(connection, &peer)
  let create = try #require(requests.first { $0.id == peer.dmabuf && $0.opcode == 1 })
  let params: UInt32 = try #require(
    create.body.getInteger(at: create.body.readerIndex, endianness: .host))
  let id: UInt32 = 0xff00_0000
  var bytes = try WirePacket(object: params, opcode: 0, arguments: [.uint(id)]).bytes
  bytes.writeImmutableBuffer(try WirePacket(object: id, opcode: 0, arguments: []).bytes)
  var chunk = WireChunk(bytes: bytes, descriptors: [])
  try connection.receive(&chunk)
  #expect(buffer.state == .available)
  await connection.close()
  await connection.close()
}

@Test(.timeLimit(.minutes(1))) @MainActor func closeUnblocksBackpressuredConnectionWriter()
  async throws
{
  let (connection, peer, fd) = try await connectedPeer()
  defer { connection.cleanup() }
  var size: Int32 = 4096
  try #require(
    unsafe setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size)) == 0)
  for _ in 0..<10_000 {
    try connection.receive(.init(object: peer.xdgSurface, opcode: 0, arguments: [.uint(2)]))
  }
  var writable = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
  for _ in 0..<100 where unsafe poll(&writable, 1, 0) != 0 {
    try await Task.sleep(for: .milliseconds(1))
  }
  try #require(unsafe poll(&writable, 1, 0) == 0)
  // Queue another batch while the first remains blocked; drain gives the writer a turn.
  try await connection.drain(timeout: .milliseconds(10))
  await connection.close()
  #expect(!connection.running)
  try expectPeerEOF(peer)
  peer.socket.close()
}

private func expectPeerEOF(_ peer: ConnectionPeer) throws {
  // The numeric client FD may already have been reused by another concurrent test.
  var bytes = [UInt8](repeating: 0, count: 4096)
  var count = 1
  while count > 0 {
    count = peer.socket.borrow { unsafe recv($0, &bytes, bytes.count, Int32(MSG_DONTWAIT)) }
  }
  #expect(count == 0)
}

@MainActor private func configurePopup(
  _ connection: WaylandConnection, _ peer: inout ConnectionPeer
) async throws -> (surface: UInt32, xdg: UInt32) {
  try connection.presentPopup(
    configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 40, height: 30),
    grab: false)
  let requests = try await drain(connection, &peer)
  let request = try #require(requests.first { $0.id == peer.shell && $0.opcode == 2 })
  let xdg: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex, endianness: .host))
  let surface: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex + 4, endianness: .host))
  try connection.receive(.init(object: xdg, opcode: 0, arguments: [.uint(2)]))
  return (surface, xdg)
}

private func frameCallback(
  in requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)], on surface: UInt32
) throws -> UInt32 {
  let request = try #require(requests.first { $0.id == surface && $0.opcode == 3 })
  return try #require(request.body.getInteger(at: request.body.readerIndex, endianness: .host))
}

@Test @MainActor func popupFramesProgressWhileParentCallbackIsDelayed() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = connection.beginFrame()
  try connection.endFrame()
  let parentCallback = try frameCallback(in: await drain(connection, &peer), on: peer.surface)
  let popup = try await configurePopup(connection, &peer)
  #expect(!connection.canRender && !connection.redrawRequested && connection.canRenderPopup)

  for index in 0..<3 {
    _ = connection.takePopupInput()
    connection.requestPopupRedraw()
    try connection.endPopupFrame()
    #expect(!connection.canRenderPopup && !connection.frameReady)
    #expect(throws: WaylandError.connection) { try connection.endPopupFrame() }
    let requests = try await drain(connection, &peer)
    #expect(!requests.contains { $0.id == peer.surface && $0.opcode == 3 })
    let callback = try frameCallback(in: requests, on: popup.surface)
    try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(UInt32(index))]))
    #expect(connection.canRenderPopup && !connection.frameReady && !connection.redrawRequested)
  }

  _ = connection.takePopupInput()
  try connection.endPopupFrame(continuously: true)
  let popupCallback = try frameCallback(in: await drain(connection, &peer), on: popup.surface)
  connection.requestRedraw()
  try connection.receive(.init(object: parentCallback, opcode: 0, arguments: [.uint(4)]))
  #expect(connection.canRender && !connection.canRenderPopup)
  _ = connection.beginFrame()
  try connection.endFrame()
  try connection.receive(.init(object: popupCallback, opcode: 0, arguments: [.uint(5)]))
  #expect(!connection.canRender && connection.canRenderPopup)
}

@Test @MainActor func popupInputAndRedrawWakeOnlyThePopup() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = connection.beginFrame()
  let popup = try await configurePopup(connection, &peer)
  _ = connection.takePopupInput()
  #expect(!connection.redrawRequested && !connection.canRenderPopup)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [.uint(1), .uint(popup.surface), .int(256), .int(512)]))
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 3,
      arguments: [.uint(2), .uint(0), .uint(0x110), .uint(1)]))
  #expect(connection.canRenderPopup && !connection.redrawRequested)
  let input = try #require(connection.takePopupInput())
  #expect(input.pointerX == 1 && input.pointerY == 2 && input.primaryPressed)
  #expect(!connection.input.primaryPressed && !connection.input.pointerInside)
  try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(3)]))
  let requests = try await drain(connection, &peer)
  let request = try #require(requests.first { $0.id == peer.seat && $0.opcode == 1 })
  let keyboard: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex, endianness: .host))
  try connection.receive(
    .init(
      object: keyboard, opcode: 1,
      arguments: [.uint(3), .uint(popup.surface), .array(ByteBuffer())]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(4), .uint(0), .uint(16), .uint(1)]))
  #expect(connection.canRenderPopup && !connection.redrawRequested)
  #expect(connection.takePopupInput()?.keyEvents.map(\.physicalCode) == [16])
  #expect(connection.input.keyEvents.isEmpty)
  connection.waitForDMABufBuffer()
  let dispatch = Task { try await connection.dispatchAsync() }
  defer { dispatch.cancel() }
  await Task.yield()
  connection.requestPopupRedraw()
  try await dispatch.value
  #expect(connection.canRenderPopup && !connection.canRender)
}

@Test(arguments: [false, true]) @MainActor func bufferAvailabilityIsScopedToItsSurface(
  popupFirst: Bool
) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = try await configurePopup(connection, &peer)
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 400)]
  let parent = try connection.importDMABuf(
    width: 100, height: 80, format: 0x3432_5241, modifier: 0, planes: planes.span)
  let popup = try connection.importDMABuf(
    width: 40, height: 30, format: 0x3432_5241, modifier: 0, planes: planes.span, popup: true)
  connection.waitForDMABufBuffer()
  connection.waitForDMABufBuffer(popup: true)
  #expect(!connection.canRender && !connection.canRenderPopup)
  let first = popupFirst ? popup : parent
  let second = popupFirst ? parent : popup
  try connection.receive(.init(object: first.params, opcode: 0, arguments: [.uint(0xff00_0000)]))
  #expect(connection.canRender == !popupFirst && connection.canRenderPopup == popupFirst)
  try connection.presentDMABuf(first, popup: popupFirst)
  connection.waitForDMABufBuffer(popup: popupFirst)
  try connection.receive(.init(object: second.params, opcode: 0, arguments: [.uint(0xff00_0001)]))
  #expect(connection.canRender == popupFirst && connection.canRenderPopup == !popupFirst)
  try connection.receive(.init(object: first.id, opcode: 0, arguments: []))
  #expect(connection.canRender && connection.canRenderPopup)
}

@Test @MainActor func dismissedPopupCallbacksAndBuffersCannotWakeItsReplacement() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  _ = connection.takePopupInput()
  try connection.endPopupFrame(continuously: true)
  let callback = try frameCallback(in: await drain(connection, &peer), on: popup.surface)
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 160)]
  let oldBuffer = try connection.importDMABuf(
    width: 40, height: 30, format: 0x3432_5241, modifier: 0, planes: planes.span, popup: true)
  try connection.receive(
    .init(object: oldBuffer.params, opcode: 0, arguments: [.uint(0xff00_0000)]))
  try connection.presentDMABuf(oldBuffer, popup: true)
  connection.waitForDMABufBuffer(popup: true)
  connection.waitForDMABufBuffer()
  connection.dismissPopup()
  #expect(!connection.canRender)
  _ = try await configurePopup(connection, &peer)
  connection.waitForDMABufBuffer(popup: true)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(3)]))
  try connection.receive(.init(object: oldBuffer.id, opcode: 0, arguments: []))
  #expect(!connection.canRender && !connection.canRenderPopup)
}

@Test @MainActor func connectionNegotiatesV4FeedbackBeforeReturningAndWatchesPopup() async throws {
  let (connection, initialPeer, _) = try await connectedPeer(dmabufVersion: 4)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(connection.dmabufPreferences?.mainDevice == 123)
  #expect(connection.dmabufPreferences?.supports(format: 0x3432_5241, modifier: 0) == true)
  try connection.presentPopup(
    configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 40, height: 30),
    grab: false)
  let requests = try await drain(connection, &peer)
  let watch = try #require(requests.first { $0.id == peer.dmabuf && $0.opcode == 3 })
  let feedback: UInt32 = try #require(
    watch.body.getInteger(at: watch.body.readerIndex, endianness: .host))
  try peer.sendFeedback(feedback, device: 456)
  for _ in 0..<100 where connection.popupDMABufPreferences?.mainDevice != 456 {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(connection.popupDMABufPreferences?.mainDevice == 456)
  #expect(connection.dmabufPreferences?.mainDevice == 123)
  connection.dismissPopup()
  let destroyed = try await drain(connection, &peer)
  #expect(destroyed.contains { $0.id == feedback && $0.opcode == 0 })
}
