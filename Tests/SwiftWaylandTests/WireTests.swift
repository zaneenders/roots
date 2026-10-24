import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

private func event(_ object: UInt32, _ opcode: UInt16, _ arguments: [WireValue]) throws
  -> WirePacket
{
  try WirePacket(object: object, opcode: opcode, arguments: arguments)
}

@Test func wireRoundTripsNativeEndianStringsArraysAndSignedFixed() throws {
  var interfaces: [UInt32: String] = [1: "wl_display"]
  var decoder = WireDecoder()
  interfaces[2] = "wl_registry"
  var packet = try event(2, 0, [.uint(42), .string("wl_compositor"), .uint(6)])
  try decoder.append(&packet.bytes, descriptors: [])
  let result = try #require(try decoder.next(interfaces: interfaces))
  #expect(result.object == 2 && result.opcode == 0)
  #expect(
    result.arguments[0].word == 42 && result.arguments[1].text == "wl_compositor"
      && result.arguments[2].word == 6)
  interfaces[3] = "wl_pointer"
  var motion = try event(3, 2, [.uint(10), .int(-512), .int(768)])
  try decoder.append(&motion.bytes, descriptors: [])
  let pointer = try #require(try decoder.next(interfaces: interfaces))
  #expect(pointer.arguments[1].signed == -512 && pointer.arguments[2].signed == 768)
  interfaces[4] = "wl_keyboard"
  var array = ByteBufferAllocator().buffer(capacity: 8)
  array.writeInteger(UInt32(30), endianness: .host)
  var enter = try event(4, 1, [.uint(7), .uint(8), .array(array)])
  try decoder.append(&enter.bytes, descriptors: [])
  let key = try #require(try decoder.next(interfaces: interfaces))
  guard case .array(let keys) = key.arguments[2] else {
    Issue.record("Missing array")
    return
  }
  #expect(keys == array)
}

@Test func wireHandlesEveryFragmentBoundaryAndCoalescedMessages() throws {
  let packet = try event(1, 1, [.uint(27)])
  for split in 0...packet.bytes.readableBytes {
    var decoder = WireDecoder()
    var first = packet.bytes.getSlice(at: 0, length: split)!
    var second = packet.bytes.getSlice(at: split, length: packet.bytes.readableBytes - split)!
    try decoder.append(&first, descriptors: [])
    if split < packet.bytes.readableBytes { #expect(try decoder.next() == nil) }
    try decoder.append(&second, descriptors: [])
    #expect(try decoder.next()?.arguments[0].word == 27)
    #expect(try decoder.next() == nil)
  }
  var decoder = WireDecoder()
  var joined = packet.bytes
  joined.writeImmutableBuffer(packet.bytes)
  try decoder.append(&joined, descriptors: [])
  #expect(try decoder.next()?.arguments[0].word == 27)
  #expect(try decoder.next()?.arguments[0].word == 27)
}

@Test func wireRejectsInvalidLengthOpcodeObjectAndMissingStringTerminator() throws {
  var interfaces: [UInt32: String] = [1: "wl_display"]
  for (object, header): (UInt32, UInt32) in [
    (1, 4 << 16), (1, 9 << 16), (999, 8 << 16), (1, 8 << 16 | 99)
  ] {
    var decoder = WireDecoder()
    var bytes = ByteBufferAllocator().buffer(capacity: 8)
    bytes.writeInteger(object, endianness: .host)
    bytes.writeInteger(header, endianness: .host)
    try decoder.append(&bytes, descriptors: [])
    #expect(throws: WaylandError.dispatch) { try decoder.next(interfaces: interfaces) }
  }
  var decoder = WireDecoder()
  interfaces[2] = "wl_data_offer"
  var packet = try event(2, 0, [.string("abc")])
  packet.bytes.setInteger(UInt8(1), at: packet.bytes.writerIndex - 1)
  try decoder.append(&packet.bytes, descriptors: [])
  #expect(throws: WaylandError.dispatch) { try decoder.next(interfaces: interfaces) }
}

@Test func wireFDQueueIsIndependentOfByteBoundariesAndClosesUnusedFDs() throws {
  var interfaces: [UInt32: String] = [1: "wl_display"]
  var fds: [Int32] = [-1, -1]
  try #require(unsafe pipe(&fds) == 0)
  defer { for fd in fds { _ = close(fd) } }
  let duplicate = try WireDescriptor.duplicate(fds[0])
  let raw = duplicate.borrow { $0 }
  #expect(fcntl(raw, F_GETFD) & FD_CLOEXEC != 0)
  var decoder = WireDecoder()
  interfaces[2] = "wl_keyboard"
  var keymap = try event(2, 0, [.uint(1), .fd(duplicate), .uint(8)])
  try decoder.append(&keymap.bytes, descriptors: [])
  #expect(try decoder.next(interfaces: interfaces) == nil)
  var empty = ByteBufferAllocator().buffer(capacity: 0)
  try decoder.append(&empty, descriptors: [duplicate])
  let message = try #require(try decoder.next(interfaces: interfaces))
  guard case .fd(let received) = message.arguments[1] else {
    Issue.record("Missing descriptor")
    return
  }
  #expect(received.borrow { $0 } == raw)
  received.close()
  received.close()
  #expect(received.borrow { $0 } == -1)
}

@Test @MainActor func wireObjectIDsOnlyRecycleAfterDeleteID() throws {
  let objects = WaylandObjects()
  let first = objects.allocate("wl_callback")
  let second = objects.allocate("wl_surface")
  #expect(first == 2 && second == 3)
  objects.deleted(first)
  #expect(objects.allocate("wl_callback") == first)
  objects.register(0xff00_0000, "wl_buffer")
  objects.deleted(0xff00_0000)
  #expect(objects.allocate("wl_surface") == 4)
}

@Test @MainActor func wireDMABufStateRequiresReleaseAndClosesTerminally() throws {
  let objects = WaylandObjects()
  let buffer = WaylandDMABufBuffer(params: 3, objects: objects, changed: {})
  #expect(throws: WaylandError.busy) { try buffer.present(on: 2) }
  buffer.created(0xff00_0000)
  try buffer.present(on: 2)
  #expect(buffer.state == .submitted)
  #expect(throws: WaylandError.busy) { try buffer.present(on: 2) }
  buffer.released()
  #expect(buffer.state == .available)
  buffer.close()
  buffer.close()
  buffer.released()
  #expect(buffer.state == .closed)
}

@Test @MainActor func destroyedObjectsKeepOnlyDecodingMetadataUntilIDReuse() throws {
  let objects = WaylandObjects()
  let surface = objects.allocate("xdg_surface")
  objects.request(surface, 0)
  #expect(!objects.isLive(surface) && objects.interfaces[surface] == "xdg_surface")
  objects.request(surface, 4, [.uint(1)])
  objects.request(surface, 0)
  #expect(try objects.takeRequests().count == 1)
  objects.deleted(surface)
  #expect(objects.allocate("wl_surface") == surface)
  #expect(objects.isLive(surface))
  objects.request(surface, 6)
  #expect(try objects.takeRequests().count == 1)
}

@Test @MainActor func retiredDMABufParamsStillDestroyLateServerBuffers() throws {
  let objects = WaylandObjects()
  let dmabuf = WaylandDMABuf(objects: objects)
  let params = objects.allocate("zwp_linux_buffer_params_v1")
  objects.request(params, 0)
  _ = try objects.takeRequests()
  let buffer: UInt32 = 0xff00_0000
  dmabuf.event(.init(object: params, opcode: 0, arguments: [.uint(buffer)]))
  #expect(objects.interfaces[buffer] == "wl_buffer" && !objects.isLive(buffer))
  let requests = try objects.takeRequests()
  #expect(requests.count == 1)
  #expect(requests.first?.bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == buffer)
}
