import CWaylandTestSupport
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

@MainActor private func roundtrip(_ peer: inout ConnectionPeer) async throws {
  try peer.send(peer.shell, 0, [.uint(99)])
  let snapshot = peer
  peer = try await blockingTestTask {
    var peer = snapshot
    _ = try peer.throughPong()
    return peer
  }.value
}

@Test(arguments: [
  Set(["zwp_linux_dmabuf_v1"]), Set(["wl_seat"]),
  Set(["zwp_linux_dmabuf_v1", "wl_seat", "zwp_idle_inhibit_manager_v1"])
])
@MainActor func compositorWithoutOptionalGlobalsStillConfigures(omitted: Set<String>) async throws {
  let (connection, initialPeer, _) = try await connectedPeer(omittingGlobals: omitted)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(connection.running && connection.configured && connection.canRender)
  #expect(!connection.setCursor(.text))
  #expect(
    !connection.setTextInput(
      .init(surroundingText: "", cursor: 0, anchor: 0, cursorRectangle: .zero)))
  if omitted.contains("zwp_idle_inhibit_manager_v1") {
    #expect(!connection.setIdleInhibited(true))
  }
  if omitted.contains("zwp_linux_dmabuf_v1") { #expect(connection.dmabufPreferences == nil) }
  _ = connection.beginFrame()
  try connection.endFrame()
  let callback = try frameCallback(in: await drain(connection, &peer), on: peer.surface)
  connection.requestRedraw()
  #expect(!connection.canRender)
  try peer.send(callback, 0, [.uint(1)])
  try peer.send(1, 1, [.uint(callback)])
  try await roundtrip(&peer)
  #expect(connection.canRender && connection.protocolFailure == nil)
  await connection.close()
}

@Test(arguments: [false, true])
@MainActor func rejectedImportWakesOnlyItsSurfaceAndAllowsRetry(popup: Bool) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = try await configurePopup(connection, &peer)
  let rejected = try importTestBuffer(connection, width: 40, height: 30, popup: popup)
  let params = rejected.params
  connection.waitForDMABufBuffer()
  connection.waitForDMABufBuffer(popup: true)
  try peer.send(params, 1)
  try await roundtrip(&peer)
  #expect(rejected.state == .failed && rejected.params == 0)
  #expect(connection.canRender == !popup && connection.canRenderPopup == popup)
  #expect(throws: WaylandError.busy) { try connection.presentDMABuf(rejected, popup: popup) }
  rejected.close()
  rejected.close()

  let retry = try importTestBuffer(connection, width: 40, height: 30, popup: popup)
  connection.waitForDMABufBuffer(popup: popup)
  try peer.send(retry.params, 0, [.uint(0xff00_0000)])
  try await roundtrip(&peer)
  #expect(retry.state == .available && connection.running)
  #expect(connection.canRender == !popup && connection.canRenderPopup == popup)
  try connection.presentDMABuf(retry, popup: popup)
  connection.waitForDMABufBuffer(popup: popup)
  try peer.send(retry.id, 0)
  try await roundtrip(&peer)
  #expect(retry.state == .available && connection.protocolFailure == nil)
  retry.close()
  await connection.close()
}

@Test @MainActor func coalescedResizeAndDismissalCannotConfigureReplacementPopup() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let old = try await configurePopup(connection, &peer)
  connection.dismissPopup()
  let replacement = try await configurePopup(connection, &peer)
  _ = connection.takePopupInput()
  var burst = ByteBuffer()
  for (object, opcode, arguments): (UInt32, UInt16, [WireValue]) in [
    (old.popup, 0, [.int(0), .int(0), .int(250), .int(200)]),
    (old.xdg, 0, [.uint(90)]), (old.popup, 1, []),
    (peer.toplevel, 0, [.int(180), .int(120), .array(ByteBuffer())]),
    (peer.xdgSurface, 0, [.uint(91)])
  ] {
    burst.writeImmutableBuffer(
      try WirePacket(object: object, opcode: opcode, arguments: arguments).bytes)
  }
  let sent = peer.socket.borrow { fd in
    unsafe burst.withUnsafeReadableBytes { unsafe cwl_send(fd, $0.baseAddress, $0.count, nil, 0) }
  }
  try #require(sent == burst.readableBytes)
  try await roundtrip(&peer)
  #expect(connection.input.width == 180 && connection.input.height == 120)
  #expect(connection.popupInput?.width == 40 && connection.popupInput?.height == 30)
  #expect(!connection.popupDismissed && !connection.canRenderPopup)
  try peer.send(replacement.xdg, 0, [.uint(92)])
  try await roundtrip(&peer)
  #expect(connection.canRenderPopup && connection.protocolFailure == nil)
  await connection.close()
}
