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
