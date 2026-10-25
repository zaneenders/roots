import Foundation
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

// These peers exercise wire messages, not GPU allocation. Imports duplicate the
// descriptor, so the test's placeholder can close as soon as the request is queued.
@MainActor func importTestBuffer(
  _ connection: WaylandConnection, width: Int32 = 100, height: Int32 = 80,
  modifier: UInt64 = 0, popup: Bool = false
) throws -> WaylandDMABufBuffer {
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: UInt32(width) * 4)]
  return try connection.importDMABuf(
    width: width, height: height, format: 0x3432_5241, modifier: modifier,
    planes: planes.span, popup: popup)
}

@MainActor func importTestBuffer(
  _ dmabuf: WaylandDMABuf, modifier: UInt64 = 0, surface: UInt32 = 0,
  changed: @escaping @MainActor () -> Void = {}
) throws -> WaylandDMABufBuffer {
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 16)]
  return try dmabuf.importBuffer(
    width: 4, height: 4, format: 1, modifier: modifier,
    planes: planes.span, surface: surface, changed: changed)
}

func deviceBytes(_ device: UInt64) -> WireValue {
  var bytes = ByteBuffer()
  bytes.writeInteger(dev_t(device), endianness: .host)
  return .array(bytes)
}

func tableEvent(
  _ pairs: [WaylandDMABufFormat], id: UInt32, size: UInt32? = nil
) throws -> WireMessage {
  var bytes = ByteBuffer()
  for pair in pairs {
    bytes.writeInteger(pair.format, endianness: .host)
    bytes.writeInteger(UInt32(0), endianness: .host)
    bytes.writeInteger(pair.modifier, endianness: .host)
  }
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try Data(bytes.readableBytesView).write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  let fd = unsafe open(path.path, O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  return .init(
    object: id, opcode: 1,
    arguments: [
      .fd(WireDescriptor(taking: fd)), .uint(size ?? UInt32(bytes.readableBytes))
    ]
  )
}

func trancheEvents(
  device: UInt64, indices: [UInt16], flags: UInt32 = 0, id: UInt32
) -> [WireMessage] {
  var bytes = ByteBuffer()
  for index in indices { bytes.writeInteger(index, endianness: .host) }
  return [
    .init(object: id, opcode: 4, arguments: [deviceBytes(device)]),
    .init(object: id, opcode: 6, arguments: [.uint(flags)]),
    .init(object: id, opcode: 5, arguments: [.array(bytes)]),
    .init(object: id, opcode: 3, arguments: [])
  ]
}
