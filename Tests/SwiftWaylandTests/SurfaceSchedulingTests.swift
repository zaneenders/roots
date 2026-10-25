import NIOCore
import Testing

@testable import SwiftWayland

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
  let parent = try importTestBuffer(connection)
  let popup = try importTestBuffer(connection, width: 40, height: 30, popup: true)
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
  let oldBuffer = try importTestBuffer(connection, width: 40, height: 30, popup: true)
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
