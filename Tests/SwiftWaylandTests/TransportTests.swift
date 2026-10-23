import CWaylandTestSupport
import Glibc
import NIOCore
import NIOPosix
import Testing

@testable import SwiftWayland

private func sockets() throws -> [Int32] {
  var fds: [Int32] = [-1, -1]
  try #require(
    unsafe socketpair(
      AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue | SOCK_CLOEXEC.rawValue), 0, &fds
    )
      == 0)
  return fds
}

@Test func nioTransportReceivesAncillaryKeymapAndClosesOnEOF() async throws {
  let pair = try sockets()
  let peer = WireDescriptor(taking: pair[1])
  defer { peer.close() }
  let (transport, stream) = try await WaylandTransport.takingSocket(pair[0])
  var iterator = stream.makeAsyncIterator()
  try await transport.register([2: "wl_keyboard"])
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  let owned = WireDescriptor(taking: fd)
  defer { owned.close() }
  let packet = try WirePacket(object: 2, opcode: 0, arguments: [.uint(1), .fd(owned), .uint(10)])
  let raw = [fd]
  let sent = unsafe packet.bytes.withUnsafeReadableBytes { bytes in
    unsafe cwl_send(pair[1], bytes.baseAddress, bytes.count, raw, 1)
  }
  #expect(sent == packet.bytes.readableBytes)
  let message = try #require(await iterator.next())
  guard case .fd(let received) = message.arguments[1] else {
    Issue.record("Missing FD")
    return
  }
  #expect(received.borrow { fcntl($0, F_GETFD) & FD_CLOEXEC != 0 })
  received.close()
  try await transport.acknowledged(objects: [:])
  peer.close()
  do {
    _ = try await iterator.next()
    Issue.record("Expected EOF failure")
  } catch { #expect(error as? WaylandError == .connection) }
  await transport.close()
}

@Test func nioTransportQueuesPartialWritesAndTransfersFDExactlyOnce() async throws {
  let pair = try sockets()
  let peer = WireDescriptor(taking: pair[1])
  defer { peer.close() }
  var size: Int32 = 4096
  try #require(
    unsafe setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
      == 0)
  let (transport, _) = try await WaylandTransport.takingSocket(pair[0])
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  let owned = WireDescriptor(taking: fd)
  defer { owned.close() }
  var packets: [WirePacket] = []
  for index in 0..<40 {
    packets.append(
      try WirePacket(
        object: 2, opcode: 0,
        arguments: [
          .uint(UInt32(index)), .string(String(repeating: "x", count: 30_000)),
          .fd(try WireDescriptor.duplicate(fd))
        ]))
  }
  let expected = packets.reduce(0) { $0 + $1.bytes.readableBytes }
  try await transport.send(packets, objects: [:])
  let reader = blockingTestTask { () throws -> (Int, Int) in
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    var total = 0
    var descriptorCount = 0
    var bytes = [UInt8](repeating: 0, count: 65_536)
    while total < expected && ContinuousClock.now < deadline {
      var fds = [Int32](repeating: -1, count: 256)
      var count = 256
      let n = peer.borrow { fd in unsafe cwl_receive(fd, &bytes, bytes.count, &fds, &count) }
      for fd in fds.prefix(count) {
        _ = close(fd)
        descriptorCount += 1
      }
      if n > 0 {
        total += n
      } else if errno == EAGAIN {
        usleep(1000)
      } else {
        throw WaylandError.dispatch
      }
    }
    return (total, descriptorCount)
  }
  let (total, count) = try await reader.value
  #expect(total == expected && count == packets.count)
  await transport.close()
}

@Test func nioTransportRegistersServerCreatedObjectsBeforeDecodingNextEvent() async throws {
  let pair = try sockets()
  defer { _ = close(pair[1]) }
  let (transport, stream) = try await WaylandTransport.takingSocket(pair[0])
  var iterator = stream.makeAsyncIterator()
  try await transport.register([2: "wl_data_device"])
  let offer: UInt32 = 0xff00_0000
  var bytes = try WirePacket(object: 2, opcode: 0, arguments: [.uint(offer)]).bytes
  bytes.writeImmutableBuffer(
    try WirePacket(object: offer, opcode: 0, arguments: [.string("text/plain")]).bytes)
  let n = unsafe bytes.withUnsafeReadableBytes {
    unsafe cwl_send(pair[1], $0.baseAddress, $0.count, nil, 0)
  }
  #expect(n == bytes.readableBytes)
  #expect(try await iterator.next()?.arguments[0].word == offer)
  try await transport.acknowledged(objects: [offer: "wl_data_offer"])
  #expect(try await iterator.next()?.arguments[0].text == "text/plain")
  await transport.close()
}

@Test func nioTransportDrainsEventsAndRegistersServerObjectsAfterEOF() async throws {
  let pair = try sockets()
  let peer = WireDescriptor(taking: pair[1])
  defer { peer.close() }
  let (transport, stream) = try await WaylandTransport.takingSocket(pair[0])
  try await transport.register([2: "wl_data_device"])
  let offer: UInt32 = 0xff00_0000
  var bytes = try WirePacket(object: 2, opcode: 0, arguments: [.uint(offer)]).bytes
  bytes.writeImmutableBuffer(
    try WirePacket(object: offer, opcode: 0, arguments: [.string("text/plain")]).bytes)
  bytes.writeImmutableBuffer(
    try WirePacket(
      object: 1, opcode: 0, arguments: [.uint(2), .uint(0), .string("rejected offer")]
    ).bytes)
  #expect(
    unsafe bytes.withUnsafeReadableBytes {
      unsafe cwl_send(pair[1], $0.baseAddress, $0.count, nil, 0)
    }
      == bytes.readableBytes)
  #expect(shutdown(pair[1], Int32(SHUT_WR)) == 0)
  #expect(fcntl(pair[1], F_SETFL, 0) == 0)
  var timeout = timeval(tv_sec: 3, tv_usec: 0)
  #expect(
    unsafe setsockopt(
      pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
  let eof = await blockingTestTask {
    var byte: UInt8 = 0
    return peer.borrow { unsafe recv($0, &byte, 1, 0) }
  }.value
  try #require(eof == 0)
  var iterator = stream.makeAsyncIterator()
  #expect(try await iterator.next()?.arguments[0].word == offer)
  try await transport.send(
    [try WirePacket(object: offer, opcode: 2, arguments: [])], objects: [offer: "wl_data_offer"])
  try await transport.acknowledged(objects: [:])
  #expect(try await iterator.next()?.arguments[0].text == "text/plain")
  try await transport.acknowledged(objects: [:])
  #expect(try await iterator.next()?.arguments[2].text == "rejected offer")
  try await transport.acknowledged(objects: [:])
  await #expect(throws: WaylandError.connection) { try await iterator.next() }
  await transport.close()
}

@Test func nioTransportEOFClosesDescriptorsWaitingForTheirMessage() async throws {
  let pair = try sockets()
  let (transport, stream) = try await WaylandTransport.takingSocket(pair[0])
  var iterator = stream.makeAsyncIterator()
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  let owned = WireDescriptor(taking: fd)
  defer { owned.close() }
  let bytes: [UInt8] = [1]
  let fds = [fd]
  #expect(unsafe cwl_send(pair[1], bytes, bytes.count, fds, 1) == 1)
  _ = close(pair[1])
  do {
    _ = try await iterator.next()
    Issue.record("Expected EOF")
  } catch { #expect(error as? WaylandError == .connection) }
  await transport.close()
}
