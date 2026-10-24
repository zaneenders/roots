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

private let fractionalScaleGlobals = ["wp_fractional_scale_manager_v1", "wp_viewporter"]

@Test(
  arguments: [fractionalScaleGlobals, fractionalScaleGlobals.reversed().map { $0 }],
  [UInt32(120), 150, 180, 210, 240])
@MainActor func fractionalScaleNegotiatesInEitherGlobalOrder(
  globals: [String], preferredScale: UInt32
)
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer(
    scaleGlobals: globals, preferredScale: preferredScale)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(peer.fractional != 0 && peer.viewport != 0)
  #expect(connection.input.bufferScale == 1)
  #expect(connection.input.fractionalScale120 == preferredScale)
  #expect(connection.input.renderScale == Double(preferredScale) / 120)
  #expect(connection.input.width == 100 && connection.input.height == 80)
  _ = connection.beginFrame()
  try connection.endFrame()
  let requests = try await drain(connection, &peer)
  let destination = try #require(requests.first { $0.id == peer.viewport && $0.opcode == 2 })
  #expect(destination.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 100)
  #expect(destination.body.getInteger(at: 4, endianness: .host, as: Int32.self) == 80)
  #expect(
    requests.contains {
      $0.id == peer.surface && $0.opcode == 8
        && $0.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 1
    })
  #expect(!requests.contains { $0.id == peer.viewport && $0.opcode == 1 })

  try connection.receive(
    .init(
      object: peer.toplevel, opcode: 0,
      arguments: [.int(101), .int(77), .array(ByteBuffer())]))
  try connection.receive(.init(object: peer.xdgSurface, opcode: 0, arguments: [.uint(2)]))
  try connection.receive(.init(object: peer.fractional, opcode: 0, arguments: [.uint(180)]))
  let callback = try frameCallback(in: requests, on: peer.surface)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(3)]))
  #expect(connection.canRender && connection.input.renderScale == 1.5)
  _ = connection.beginFrame()
  try connection.endFrame()
  let resized = try await drain(connection, &peer)
  let size = try #require(resized.first { $0.id == peer.viewport && $0.opcode == 2 })
  #expect(size.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 101)
  #expect(size.body.getInteger(at: 4, endianness: .host, as: Int32.self) == 77)
}

@Test(arguments: [[], ["wp_viewporter"], ["wp_fractional_scale_manager_v1"]])
@MainActor func missingFractionalProtocolPreservesIntegerScaling(globals: [String]) async throws {
  let (connection, initialPeer, _) = try await connectedPeer(scaleGlobals: globals)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(peer.fractional == 0 && peer.viewport == 0)
  try connection.receive(.init(object: peer.surface, opcode: 2, arguments: [.int(2)]))
  #expect(connection.input.fractionalScale120 == nil && connection.input.renderScale == 2)
  _ = connection.beginFrame()
  try connection.endFrame()
  let requests = try await drain(connection, &peer)
  #expect(
    requests.contains {
      $0.id == peer.surface && $0.opcode == 8
        && $0.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 2
    })
}

@Test @MainActor func fractionalScaleIsIndependentForEachSurfaceAndIgnoresIntegerPreferences()
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer(
    scaleGlobals: fractionalScaleGlobals)
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = connection.beginFrame()
  try connection.presentPopup(
    configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 41, height: 31),
    grab: false)
  let requests = try await drain(connection, &peer)
  let fractionalRequest = try #require(
    requests.first { $0.id == peer.fractionalManager && $0.opcode == 1 })
  let fractional: UInt32 = try #require(fractionalRequest.body.getInteger(at: 0, endianness: .host))
  let viewportRequest = try #require(requests.first { $0.id == peer.viewporter && $0.opcode == 1 })
  let viewport: UInt32 = try #require(viewportRequest.body.getInteger(at: 0, endianness: .host))
  let surface: UInt32 = try #require(viewportRequest.body.getInteger(at: 4, endianness: .host))
  let xdgRequest = try #require(requests.first { $0.id == peer.shell && $0.opcode == 2 })
  let xdg: UInt32 = try #require(xdgRequest.body.getInteger(at: 0, endianness: .host))
  try connection.receive(.init(object: xdg, opcode: 0, arguments: [.uint(4)]))
  _ = connection.takePopupInput()
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(210)]))
  #expect(connection.canRenderPopup && !connection.redrawRequested)
  #expect(connection.popupInput?.renderScale == 1.75 && connection.input.renderScale == 1.25)
  #expect(connection.popupInput?.bufferScale == 1)
  _ = connection.takePopupInput()
  for (id, value): (UInt32, Int32) in [(surface, 3), (peer.surface, 2)] {
    try connection.receive(.init(object: id, opcode: 2, arguments: [.int(value)]))
  }
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(0)]))
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(210)]))
  #expect(!connection.canRenderPopup && !connection.redrawRequested)
  #expect(connection.popupInput?.renderScale == 1.75 && connection.input.renderScale == 1.25)
  try connection.endPopupFrame()
  let committed = try await drain(connection, &peer)
  #expect(
    committed.contains {
      $0.id == viewport && $0.opcode == 2
        && $0.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 41
        && $0.body.getInteger(at: 4, endianness: .host, as: Int32.self) == 31
    })
  #expect(!committed.contains { $0.id == peer.viewport })
  connection.dismissPopup()
  let destroyed = try await drain(connection, &peer)
  let viewportDestroy = try #require(destroyed.firstIndex { $0.id == viewport && $0.opcode == 0 })
  let scaleDestroy = try #require(destroyed.firstIndex { $0.id == fractional && $0.opcode == 0 })
  let surfaceDestroy = try #require(destroyed.firstIndex { $0.id == surface && $0.opcode == 0 })
  #expect(viewportDestroy < surfaceDestroy && scaleDestroy < surfaceDestroy)
  _ = try await configurePopup(connection, &peer)
  _ = connection.takePopupInput()
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(240)]))
  #expect(!connection.canRenderPopup && connection.popupInput?.fractionalScale120 == nil)
  #expect(connection.input.renderScale == 1.25)
}

@Test @MainActor func fractionalScaleObjectsSurviveManagerRemoval() async throws {
  let (connection, initialPeer, _) = try await connectedPeer(
    scaleGlobals: fractionalScaleGlobals)
  defer { connection.cleanup() }
  var peer = initialPeer
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(6)]))
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(7)]))
  try connection.receive(.init(object: peer.fractional, opcode: 0, arguments: [.uint(180)]))
  #expect(connection.input.renderScale == 1.5)
  _ = connection.beginFrame()
  try connection.endFrame()
  let requests = try await drain(connection, &peer)
  #expect(requests.contains { $0.id == peer.viewport && $0.opcode == 2 })
  #expect(requests.contains { $0.id == peer.fractionalManager && $0.opcode == 0 })
  #expect(requests.contains { $0.id == peer.viewporter && $0.opcode == 0 })
  #expect(!requests.contains { $0.id == peer.fractional && $0.opcode == 0 })
  _ = try await configurePopup(connection, &peer)
  #expect(connection.popupInput?.fractionalScale120 == nil)
}

@Test @MainActor func integerFallbackTracksEachSurfaceOutputAndFallsBackAfterRemoval() async throws
{
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  for name: UInt32 in [20, 21] {
    try connection.receive(
      .init(
        object: peer.registry, opcode: 0,
        arguments: [.uint(name), .string("wl_output"), .uint(3)]))
  }
  let requests = try await drain(connection, &peer)
  let outputRequests = requests.filter { $0.id == peer.registry && $0.opcode == 0 }
  #expect(outputRequests.count == 2)
  let outputs: [UInt32] = try outputRequests.map {
    try #require($0.body.getInteger(at: $0.body.writerIndex - 4, endianness: .host))
  }
  for (index, output) in outputs.enumerated() {
    try connection.receive(.init(object: output, opcode: 3, arguments: [.int(Int32(index + 2))]))
    try connection.receive(.init(object: output, opcode: 2, arguments: []))
  }
  try connection.receive(.init(object: peer.surface, opcode: 0, arguments: [.uint(outputs[0])]))
  #expect(connection.input.renderScale == 2 && connection.popupInput?.renderScale == 2)
  try connection.receive(.init(object: popup.surface, opcode: 0, arguments: [.uint(outputs[1])]))
  #expect(connection.input.renderScale == 2 && connection.popupInput?.renderScale == 3)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(21)]))
  #expect(connection.popupInput?.renderScale == 2)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(20)]))
  #expect(connection.input.renderScale == 1 && connection.popupInput?.renderScale == 1)
}

@Test @MainActor func lateFractionalGlobalsExtendExistingSurfacesWithoutDuplicatingObjects()
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  try connection.receive(.init(object: peer.surface, opcode: 2, arguments: [.int(2)]))
  for (index, interface) in fractionalScaleGlobals.enumerated() {
    try connection.receive(
      .init(
        object: peer.registry, opcode: 0,
        arguments: [.uint(UInt32(index + 20)), .string(interface), .uint(1)]))
  }
  let requests = try await drain(connection, &peer)
  let bindings = requests.filter { $0.id == peer.registry && $0.opcode == 0 }
  let manager: UInt32 = try #require(
    bindings.first?.body.getInteger(
      at: bindings[0].body.writerIndex - 4, endianness: .host))
  let creations = requests.filter { $0.id == manager && $0.opcode == 1 }
  #expect(creations.count == 2)
  #expect(connection.input.renderScale == 2 && connection.popupInput?.renderScale == 2)
  for request in creations {
    let fractional: UInt32 = try #require(request.body.getInteger(at: 0, endianness: .host))
    let surface: UInt32 = try #require(request.body.getInteger(at: 4, endianness: .host))
    try connection.receive(
      .init(
        object: fractional, opcode: 0,
        arguments: [.uint(surface == popup.surface ? 210 : 150)]))
  }
  #expect(connection.input.bufferScale == 1 && connection.input.renderScale == 1.25)
  #expect(connection.popupInput?.bufferScale == 1 && connection.popupInput?.renderScale == 1.75)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [.uint(22), .string("wp_viewporter"), .uint(1)]))
  let duplicate = try await drain(connection, &peer)
  #expect(!duplicate.contains { $0.id == manager && $0.opcode == 1 })
}

@MainActor private func configureKeyboard(
  _ connection: WaylandConnection, _ peer: inout ConnectionPeer, surface: UInt32
) async throws -> UInt32 {
  try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(3)]))
  let requests = try await drain(connection, &peer)
  let request = try #require(requests.first { $0.id == peer.seat && $0.opcode == 1 })
  let keyboard: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex, endianness: .host))
  try loadTestKeymap(connection, keyboard: keyboard)
  try connection.receive(
    .init(object: keyboard, opcode: 1, arguments: [.uint(1), .uint(surface), .array(ByteBuffer())]))
  return keyboard
}

@Test(arguments: [false, true]) @MainActor
func keyboardRepeatSleepsUntilDeadlineAndWakesOnlyFocusedSurface(popup: Bool) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let surface = popup ? try await configurePopup(connection, &peer).surface : peer.surface
  let keyboard = try await configureKeyboard(connection, &peer, surface: surface)
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(2), .int(200)]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(2), .uint(0), .uint(16), .uint(1)]))
  let first = popup ? connection.takePopupInput()! : connection.beginFrame()
  #expect(first.keyEvents.count == 1 && first.keyEvents[0].phase == .pressed)
  if popup { try connection.endPopupFrame() } else { try connection.endFrame() }
  let callback = try frameCallback(in: await drain(connection, &peer), on: surface)
  #expect(!connection.redrawRequested)
  #expect(!connection.canRender && !connection.canRenderPopup)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(1)]))
  #expect(!connection.canRender && !connection.canRenderPopup)

  // No socket input is needed to wake dispatch at the repeat deadline.
  let timeout = Task {
    try await Task.sleep(for: .seconds(3))
    connection.requestClose()
  }
  defer { timeout.cancel() }
  while connection.running && !(popup ? connection.canRenderPopup : connection.canRender) {
    try await connection.dispatchAsync()
  }
  try #require(connection.running)
  #expect(popup ? !connection.redrawRequested : !connection.canRenderPopup)
  let repeated = popup ? connection.takePopupInput()! : connection.beginFrame()
  #expect(!repeated.keyEvents.isEmpty)
  #expect(repeated.keyEvents.allSatisfy { $0.phase == .repeated })
  if popup { try connection.endPopupFrame() } else { try connection.endFrame() }
  #expect(!connection.redrawRequested)
  #expect(!connection.canRenderPopup)
}

@Test(arguments: [false, true]) @MainActor
func keyboardRepeatWaitsForDelayedSurfaceCallback(popup: Bool) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let surface = popup ? try await configurePopup(connection, &peer).surface : peer.surface
  let keyboard = try await configureKeyboard(connection, &peer, surface: surface)
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(100), .int(0)]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(2), .uint(0), .uint(16), .uint(1)]))
  if popup {
    _ = connection.takePopupInput()
    try connection.endPopupFrame()
  } else {
    _ = connection.beginFrame()
    try connection.endFrame()
  }
  let callback = try frameCallback(in: await drain(connection, &peer), on: surface)
  try await Task.sleep(for: .milliseconds(400))
  #expect(!connection.canRender && !connection.canRenderPopup)
  if popup { #expect(!connection.redrawRequested) } else { #expect(connection.redrawRequested) }
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(1)]))
  #expect(popup ? connection.canRenderPopup : connection.canRender)
  let repeated = popup ? connection.takePopupInput()! : connection.beginFrame()
  #expect(!repeated.keyEvents.isEmpty && repeated.keyEvents.count <= 32)
  #expect(repeated.keyEvents.allSatisfy { $0.phase == .repeated })
}

@Test(arguments: ["release", "focus", "keymap", "disabled", "seat", "close", "popup"])
@MainActor func keyboardRepeatDeadlineIsCancelled(reason: String) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let surface =
    reason == "popup" ? try await configurePopup(connection, &peer).surface : peer.surface
  let keyboard = try await configureKeyboard(connection, &peer, surface: surface)
  try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(20), .int(100)]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(2), .uint(0), .uint(16), .uint(1)]))
  switch reason {
  case "release":
    try connection.receive(
      .init(object: keyboard, opcode: 3, arguments: [.uint(3), .uint(0), .uint(16), .uint(0)]))
  case "focus":
    try connection.receive(
      .init(object: keyboard, opcode: 2, arguments: [.uint(3), .uint(surface)]))
  case "keymap": try loadTestKeymap(connection, keyboard: keyboard)
  case "disabled":
    try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(0), .int(100)]))
  case "seat":
    try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(1)]))
  case "close": connection.requestClose()
  default: connection.dismissPopup()
  }
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try await Task.sleep(for: .milliseconds(200))
  #expect(!connection.redrawRequested && !connection.canRenderPopup)
  #expect(connection.beginFrame().keyEvents.isEmpty)
}

@Test @MainActor func desktopInputGlobalsAreOptionalAndCursorUsesEnterSerial() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(!connection.setCursor(.text))
  #expect(
    !connection.setTextInput(
      .init(
        surroundingText: "", cursor: 0, anchor: 0, cursorRectangle: .zero)))
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [
        .uint(40), .string("wp_cursor_shape_manager_v1"), .uint(2),
      ]))
  let requests = try await drain(connection, &peer)
  let bind = try #require(requests.first { $0.id == peer.registry })
  let manager: UInt32 = try #require(
    bind.body.getInteger(at: bind.body.writerIndex - 4, endianness: .host))
  let create = try #require(requests.first { $0.id == manager && $0.opcode == 1 })
  let device: UInt32 = try #require(create.body.getInteger(at: 0, endianness: .host))
  #expect(connection.setCursor(.text))
  #expect(try await drain(connection, &peer).isEmpty)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [
        .uint(17), .uint(peer.surface), .int(0), .int(0),
      ]))
  let shapes = try await drain(connection, &peer)
  let shape = try #require(shapes.first { $0.id == device && $0.opcode == 1 })
  #expect(shape.body.getInteger(at: 0, endianness: .host, as: UInt32.self) == 17)
  #expect(shape.body.getInteger(at: 4, endianness: .host, as: UInt32.self) == 9)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 1,
      arguments: [
        .uint(18), .uint(peer.surface),
      ]))
  #expect(connection.setCursor(.pointer))
  #expect(try await drain(connection, &peer).isEmpty)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [
        .uint(19), .uint(peer.surface), .int(0), .int(0),
      ]))
  let entered = try await drain(connection, &peer)
  #expect(
    entered.contains {
      $0.id == device && $0.opcode == 1
        && $0.body.getInteger(at: 0, endianness: .host, as: UInt32.self) == 19
    })
  try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(0)]))
  let removed = try await drain(connection, &peer)
  #expect(removed.first?.id == device && removed.first?.opcode == 0)
}

@Test @MainActor func modernPointerEventsReachOnlyTheFocusedSurface() async throws {
  let (connection, initialPeer, _) = try await connectedPeer(seatVersion: 9)
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [
        .uint(1), .uint(popup.surface), .int(0), .int(0),
      ]))
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 3,
      arguments: [
        .uint(2), .uint(0), .uint(0x111), .uint(1),
      ]))
  try connection.receive(.init(object: peer.pointer, opcode: 9, arguments: [.uint(0), .int(30)]))
  try connection.receive(.init(object: peer.pointer, opcode: 10, arguments: [.uint(0), .uint(1)]))
  try connection.receive(.init(object: peer.pointer, opcode: 5, arguments: []))
  let input = try #require(connection.takePopupInput())
  #expect(input.secondaryPressed && input.secondaryDown && !input.primaryDown)
  #expect(input.scrollStepsY == 0.25 && input.scrollInvertedY == true)
  #expect(connection.input.scrollStepsY == 0 && !connection.input.secondaryPressed)
}

@Test @MainActor func inputMethodTransactionsReachPopupOnlyAtDoneAndClearOnRemoval() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [
        .uint(41), .string("zwp_text_input_manager_v3"), .uint(2),
      ]))
  let requests = try await drain(connection, &peer)
  let bind = try #require(requests.first { $0.id == peer.registry })
  let manager: UInt32 = try #require(
    bind.body.getInteger(at: bind.body.writerIndex - 4, endianness: .host))
  let create = try #require(requests.first { $0.id == manager && $0.opcode == 1 })
  let text: UInt32 = try #require(create.body.getInteger(at: 0, endianness: .host))
  #expect(
    connection.setTextInput(
      .init(
        surroundingText: "", cursor: 0, anchor: 0,
        cursorRectangle: SIMD4(0, 0, 1, 20)), popup: true))
  try connection.receive(.init(object: text, opcode: 0, arguments: [.uint(popup.surface)]))
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(
    .init(object: text, opcode: 2, arguments: [.string("日"), .int(3), .int(3)]))
  try connection.receive(.init(object: text, opcode: 3, arguments: [.string("語")]))
  #expect(connection.popupInput?.textEvents.isEmpty == true)
  try connection.receive(.init(object: text, opcode: 5, arguments: [.uint(1)]))
  let input = try #require(connection.takePopupInput())
  #expect(
    input.textEvents == [
      .init(committed: "語", preedit: .init(text: "日", cursorBegin: 3, cursorEnd: 3))
    ])
  #expect(connection.input.textEvents.isEmpty && !connection.redrawRequested)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(41)]))
  #expect(connection.takePopupInput()?.textEvents == [.init()])
  #expect(
    !connection.setTextInput(
      .init(
        surroundingText: "", cursor: 0, anchor: 0,
        cursorRectangle: .zero), popup: true))
  try connection.receive(.init(object: text, opcode: 3, arguments: [.string("late")]))
  try connection.receive(.init(object: text, opcode: 5, arguments: [.uint(1)]))
  #expect(connection.popupInput?.textEvents.isEmpty == true)
}

@Test @MainActor func cursorShapesArePerSurfaceAndIgnoreDuplicateRequests() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [
        .uint(40), .string("wp_cursor_shape_manager_v1"), .uint(1),
      ]))
  _ = try await drain(connection, &peer)
  #expect(connection.setCursor(.text))
  #expect(connection.setCursor(.grabbing, popup: true))
  _ = try await drain(connection, &peer)
  for (surface, serial, shape): (UInt32, UInt32, UInt32) in [
    (peer.surface, 31, 9), (popup.surface, 32, 17), (peer.surface, 33, 9),
  ] {
    try connection.receive(
      .init(
        object: peer.pointer, opcode: 0,
        arguments: [
          .uint(serial), .uint(surface), .int(0), .int(0),
        ]))
    let requests = try await drain(connection, &peer)
    let request = try #require(requests.first { $0.opcode == 1 })
    #expect(request.body.getInteger(at: 0, endianness: .host, as: UInt32.self) == serial)
    #expect(request.body.getInteger(at: 4, endianness: .host, as: UInt32.self) == shape)
  }
  #expect(connection.setCursor(.text))
  #expect(try await drain(connection, &peer).isEmpty)
}

@Test @MainActor func reclamationBarrierDrainsLateBufferEventsBeforeForgettingTheID() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 400)]
  let buffer = try connection.importDMABuf(
    width: 100, height: 80, format: 0x3432_5241, modifier: 0, planes: planes.span)
  let requests = try await drain(connection, &peer)
  let create = try #require(requests.first { $0.id == peer.dmabuf && $0.opcode == 1 })
  let params: UInt32 = try #require(
    create.body.getInteger(at: create.body.readerIndex, endianness: .host))
  let id: UInt32 = 0xff00_0000
  try connection.receive(.init(object: params, opcode: 0, arguments: [.uint(id)]))
  buffer.close()
  try connection.receive(.init(object: peer.shell, opcode: 0, arguments: [.uint(99)]))
  let snapshot = peer
  let sync = try await blockingTestTask {
    var peer = snapshot
    return try peer.throughSync()
  }.value
  let callback = sync.callback
  let destroyed = sync.requests
  #expect(destroyed.contains { $0.id == id && $0.opcode == 0 })

  var bytes = try WirePacket(object: id, opcode: 0, arguments: []).bytes
  bytes.writeImmutableBuffer(
    try WirePacket(object: callback, opcode: 0, arguments: [.uint(0)]).bytes)
  bytes.writeImmutableBuffer(
    try WirePacket(object: 1, opcode: 1, arguments: [.uint(callback)]).bytes)
  var chunk = WireChunk(bytes: bytes, descriptors: [])
  try connection.receive(&chunk)
  #expect(buffer.state == .closed && connection.running)
  // No metadata remains once the barrier has completed.
  var late = WireChunk(
    bytes: try WirePacket(object: id, opcode: 0, arguments: []).bytes, descriptors: [])
  #expect(throws: WaylandError.dispatch) { try connection.receive(&late) }
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
