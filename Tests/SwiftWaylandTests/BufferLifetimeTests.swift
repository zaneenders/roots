import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

@Test @MainActor func closedSubmittedBuffersWaitForReleaseAndSurviveImportPruning() throws {
  let objects = WaylandObjects()
  let dmabuf = WaylandDMABuf(objects: objects)
  dmabuf.factory = objects.allocate("zwp_linux_dmabuf_v1", version: 3)
  dmabuf.modifier(format: 1, high: 0, low: 0)
  let surface = objects.allocate("wl_surface", version: 3)
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 16)]
  var changes = 0
  let buffer = try dmabuf.importBuffer(
    width: 4, height: 4, format: 1, modifier: 0, planes: planes.span, changed: { changes += 1 })
  let id: UInt32 = 0xff00_0000
  dmabuf.event(.init(object: buffer.params, opcode: 0, arguments: [.uint(id)]))
  try buffer.present(on: surface)
  _ = try objects.takeRequests()
  buffer.close()
  buffer.close()
  #expect(buffer.state == .closed && buffer.id == id && objects.isLive(id))
  #expect(try objects.takeRequests().isEmpty)
  let next = try dmabuf.importBuffer(
    width: 4, height: 4, format: 1, modifier: 0, planes: planes.span, changed: {})
  #expect(dmabuf.owns(buffer))
  _ = try objects.takeRequests()
  dmabuf.event(.init(object: id, opcode: 0, arguments: []))
  #expect(buffer.id == 0 && buffer.state == .closed && !objects.isLive(id))
  #expect(changes == 1)
  let requests = try objects.takeRequests()
  #expect(requests.count == 2)  // wl_buffer.destroy followed by the reclamation sync.
  #expect(requests.first?.bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == id)
  next.close()
  dmabuf.close()
}

@Test(arguments: [false, true]) @MainActor
func bufferCleanupKeepsSubmittedBuffersUntilRelease(alreadyClosed: Bool) throws {
  let objects = WaylandObjects()
  let dmabuf = WaylandDMABuf(objects: objects)
  dmabuf.factory = objects.allocate("zwp_linux_dmabuf_v1", version: 3)
  dmabuf.modifier(format: 1, high: 0, low: 0)
  let surface = objects.allocate("wl_surface", version: 3)
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 16)]
  var changes = 0
  let buffer = try dmabuf.importBuffer(
    width: 4, height: 4, format: 1, modifier: 0, planes: planes.span, changed: { changes += 1 })
  let id: UInt32 = 0xff00_0000
  dmabuf.event(.init(object: buffer.params, opcode: 0, arguments: [.uint(id)]))
  try buffer.present(on: surface)
  _ = try objects.takeRequests()

  if alreadyClosed { buffer.close() }
  dmabuf.close()
  dmabuf.close()
  #expect(dmabuf.factory == 0 && dmabuf.preferences() == nil)
  #expect(buffer.state == .closed && buffer.id == id && objects.isLive(id))
  #expect(dmabuf.owns(buffer))
  #expect(try objects.takeRequests().isEmpty)

  dmabuf.event(.init(object: id, opcode: 0, arguments: []))
  #expect(buffer.state == .closed && buffer.id == 0 && !objects.isLive(id))
  #expect(!dmabuf.owns(buffer))
  #expect(changes == 1)
  let requests = try objects.takeRequests()
  #expect(requests.count == 2)  // wl_buffer.destroy followed by the reclamation sync.
  #expect(requests.first?.bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == id)
  dmabuf.event(.init(object: id, opcode: 0, arguments: []))
  dmabuf.close()
  #expect(try objects.takeRequests().isEmpty)
}

@Test(arguments: [UInt32(3), 4]) @MainActor
func removedDMABufGlobalStillDestroysExplicitlyClosedBuffersOnRelease(version: UInt32)
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer(dmabufVersion: version)
  defer { connection.cleanup() }
  var peer = initialPeer
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 400)]
  let buffer = try connection.importDMABuf(
    width: 100, height: 80, format: 0x3432_5241, modifier: 0, planes: planes.span)
  let id: UInt32 = 0xff00_0000
  try connection.receive(.init(object: buffer.params, opcode: 0, arguments: [.uint(id)]))
  try connection.presentDMABuf(buffer)
  _ = try await drain(connection, &peer)
  buffer.close()
  let preferences = connection.dmabufPreferences

  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(3)]))
  let removed = try await drain(connection, &peer)
  #expect(removed.filter { $0.id == peer.dmabuf && $0.opcode == 0 }.count == 1)
  #expect(!removed.contains { $0.id == id })
  #expect(connection.running && connection.dmabufPreferences == preferences)
  #expect(buffer.state == .closed && buffer.id == id)

  try connection.receive(.init(object: id, opcode: 0, arguments: []))
  let released = try await drain(connection, &peer)
  #expect(buffer.state == .closed && buffer.id == 0)
  #expect(released.filter { $0.id == id && $0.opcode == 0 }.count == 1)
  #expect(connection.running && connection.protocolFailure == nil)
}

@Test(arguments: [UInt32(3), 4], [false, true]) @MainActor
func removedDMABufFactoryKeepsAvailableSubmittedAndImportingBuffersUsable(
  version: UInt32, popup: Bool
) async throws {
  let (connection, initialPeer, _) = try await connectedPeer(dmabufVersion: version)
  defer { connection.cleanup() }
  var peer = initialPeer
  let xdgSurface: UInt32
  if popup {
    xdgSurface = try await configurePopup(connection, &peer).xdg
  } else {
    xdgSurface = peer.xdgSurface
  }
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 160)]
  var buffers: [WaylandDMABufBuffer] = []
  for _ in 0..<3 {
    buffers.append(
      try connection.importDMABuf(
        width: 40, height: 30, format: 0x3432_5241, modifier: 0,
        planes: planes.span, popup: popup))
  }
  for index in 0..<2 {
    try connection.receive(
      .init(
        object: buffers[index].params, opcode: 0,
        arguments: [.uint(0xff00_0000 + UInt32(index))]))
  }
  try connection.presentDMABuf(buffers[1], popup: popup)
  _ = try await drain(connection, &peer)
  let preferences = try #require(
    popup ? connection.popupDMABufPreferences : connection.dmabufPreferences)

  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(3)]))
  let removed = try await drain(connection, &peer)
  #expect(buffers.map(\.state) == [.available, .submitted, .importing])
  #expect((popup ? connection.popupDMABufPreferences : connection.dmabufPreferences) == preferences)
  #expect(!connection.canImportDMABuf(popup: popup))
  #expect(
    !removed.contains { request in
      buffers.contains { $0.id == request.id || $0.params == request.id }
    })
  #expect(throws: WaylandError.missingGlobals) {
    try connection.importDMABuf(
      width: 40, height: 30, format: 0x3432_5241, modifier: 0,
      planes: planes.span, popup: popup)
  }

  // A new configure may fit an existing allocation even while imports are unavailable.
  connection.waitForDMABufBuffer(popup: popup)
  try connection.receive(.init(object: xdgSurface, opcode: 0, arguments: [.uint(10)]))
  #expect(popup ? connection.canRenderPopup : connection.canRender)

  // Existing allocations can still be presented, released, and reused.
  try connection.presentDMABuf(buffers[0], popup: popup)
  connection.waitForDMABufBuffer(popup: popup)
  try connection.receive(.init(object: buffers[1].id, opcode: 0, arguments: []))
  #expect(buffers[1].state == .available)
  #expect(popup ? connection.canRenderPopup : connection.canRender)
  try connection.presentDMABuf(buffers[1], popup: popup)

  // Removing the factory must also let already-issued imports finish.
  connection.waitForDMABufBuffer(popup: popup)
  try connection.receive(
    .init(object: buffers[2].params, opcode: 0, arguments: [.uint(0xff00_0002)]))
  #expect(buffers[2].state == .available)
  #expect(popup ? connection.canRenderPopup : connection.canRender)
  try connection.presentDMABuf(buffers[2], popup: popup)
  #expect(connection.running && connection.protocolFailure == nil)
  await connection.close()
  #expect(buffers.allSatisfy { $0.state == .closed })
  #expect(connection.dmabufPreferences == nil && !connection.canImportDMABuf())
}

@Test(arguments: [UInt32(3), 4], [UInt32(3), 4]) @MainActor
func replacementDMABufFactoryRequiresFreshFeedbackAndWakesBothSurfaces(
  version: UInt32, replacementVersion: UInt32
) async throws {
  let (connection, initialPeer, _) = try await connectedPeer(dmabufVersion: version)
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  let preferences = connection.dmabufPreferences
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(3)]))
  _ = try await drain(connection, &peer)
  connection.waitForDMABufBuffer()
  connection.waitForDMABufBuffer(popup: true)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [.uint(30), .string("zwp_linux_dmabuf_v1"), .uint(replacementVersion)]))
  let requests = try await drain(connection, &peer)
  let binding = try #require(requests.first { $0.id == peer.registry && $0.opcode == 0 })
  let factory: UInt32 = try #require(
    binding.body.getInteger(at: binding.body.writerIndex - 4, endianness: .host))
  #expect(connection.dmabufPreferences == preferences)
  #expect(!connection.canImportDMABuf() && !connection.canImportDMABuf(popup: true))
  #expect(!connection.canRender && !connection.canRenderPopup)

  if replacementVersion == 4 {
    let watches = requests.filter { $0.id == factory && ($0.opcode == 2 || $0.opcode == 3) }
    #expect(watches.count == 3)  // default, parent, and existing popup
    for watch in watches {
      let id: UInt32 = try #require(
        watch.body.getInteger(at: watch.body.readerIndex, endianness: .host))
      let surface: UInt32
      if watch.opcode == 2 {
        surface = 0
      } else {
        surface = try #require(
          watch.body.getInteger(at: watch.body.readerIndex + 4, endianness: .host))
      }
      let device: UInt64 = surface == popup.surface ? 888 : 777
      let (table, _) = try tableEvent([.init(format: 0x3432_5241, modifier: 1)], id: id)
      try connection.receive(table)
      try connection.receive(.init(object: id, opcode: 2, arguments: [deviceBytes(device)]))
      for event in trancheEvents(device: device, indices: [0], id: id) {
        try connection.receive(event)
      }
      try connection.receive(.init(object: id, opcode: 0, arguments: []))
    }
    #expect(connection.dmabufPreferences?.mainDevice == 777)
    #expect(connection.popupDMABufPreferences?.mainDevice == 888)
  } else {
    try connection.receive(
      .init(object: factory, opcode: 1, arguments: [.uint(0x3432_5241), .uint(0), .uint(1)]))
  }
  #expect(connection.canImportDMABuf() && connection.canImportDMABuf(popup: true))
  #expect(connection.canRender && connection.canRenderPopup)
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 160)]
  for popup in [false, true] {
    #expect(throws: WaylandError.missingGlobals) {
      try connection.importDMABuf(
        width: 40, height: 30, format: 0x3432_5241, modifier: 0,
        planes: planes.span, popup: popup)
    }
    let buffer = try connection.importDMABuf(
      width: 40, height: 30, format: 0x3432_5241, modifier: 1,
      planes: planes.span, popup: popup)
    #expect(buffer.state == .importing)
    buffer.close()
  }
}
