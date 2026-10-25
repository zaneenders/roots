import CWaylandTestSupport
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

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
  let buffer = try importTestBuffer(connection)
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
  await #expect(
    throws: WaylandError.protocolViolation(
      .init(
        objectID: peer.surface, interface: "wl_surface", code: 0, message: "rejected commit"
      ))
  ) { try await connection.dispatchAsync() }
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
  await #expect(
    throws: WaylandError.protocolViolation(
      .init(
        objectID: peer.surface, interface: "wl_surface", code: 0, message: "rejected final commit"
      ))
  ) {
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
  await #expect(
    throws: WaylandError.protocolViolation(
      .init(
        objectID: peer.surface, interface: "wl_surface", code: 0, message: "rejected final commit"
      ))
  ) { try await connection.drain() }
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

@Test @MainActor func inputBurstsWaitForFrameCallbackAndPreserveEdgesWithoutAnimating() async throws {
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
  let buffer = try importTestBuffer(connection)
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

@Test @MainActor func protocolErrorsIdentifyRetiredAndUnknownObjects() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  connection.dismissPopup()
  for (id, interface): (UInt32, String?) in [(popup.surface, "wl_surface"), (999_999, nil)] {
    let error = WaylandProtocolError(
      objectID: id, interface: interface, code: 3, message: "invalid object")
    #expect(throws: WaylandError.protocolViolation(error)) {
      try connection.receive(
        .init(object: 1, opcode: 0, arguments: [.uint(id), .uint(3), .string(error.message)]))
    }
    #expect(connection.protocolFailure == error)
    #expect(connection.protocolError == error.message)
  }
  await connection.close()
  #expect(connection.protocolFailure?.objectID == 999_999)
}
