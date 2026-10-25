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
func factoryClosureKeepsSubmittedBuffersUntilRelease(alreadyClosed: Bool) throws {
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
func removedDMABufGlobalStillDestroysSubmittedBuffersOnRelease(version: UInt32) async throws {
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

  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(3)]))
  let removed = try await drain(connection, &peer)
  #expect(removed.filter { $0.id == peer.dmabuf && $0.opcode == 0 }.count == 1)
  #expect(!removed.contains { $0.id == id })
  #expect(connection.running && connection.dmabufPreferences == nil)
  #expect(buffer.state == .closed && buffer.id == id)

  try connection.receive(.init(object: id, opcode: 0, arguments: []))
  let released = try await drain(connection, &peer)
  #expect(buffer.state == .closed && buffer.id == 0)
  #expect(released.filter { $0.id == id && $0.opcode == 0 }.count == 1)
  #expect(connection.running && connection.protocolFailure == nil)
}
