import CWaylandTestSupport
import Glibc
import SystemPackage
import Testing

@testable import SwiftWayland

private func unixSocketPair(type: Int32 = Int32(SOCK_STREAM.rawValue)) throws -> [Int32] {
  var descriptors: [Int32] = [-1, -1]
  try #require(unsafe socketpair(AF_UNIX, type | Int32(SOCK_CLOEXEC.rawValue), 0, &descriptors) == 0)
  return descriptors
}

@Test func unixSocketPreparesConnectedStreamsWithoutClearingFlags() throws {
  let pair = try unixSocketPair()
  defer { for fd in pair { _ = close(fd) } }
  try #require(fcntl(pair[0], F_SETFD, 0) == 0)
  try #require(fcntl(pair[0], F_GETFL) & O_NONBLOCK == 0)
  try UnixSocket.prepareConnected(pair[0])
  #expect(fcntl(pair[0], F_GETFL) & O_NONBLOCK != 0)
  #expect(fcntl(pair[0], F_GETFL) & O_ACCMODE == O_RDWR)
  #expect(fcntl(pair[0], F_GETFD) & FD_CLOEXEC != 0)
  try UnixSocket.prepareConnected(pair[0])
}

@Test func unixSocketRejectsDatagramsAndUnconnectedStreams() throws {
  let pair = try unixSocketPair(type: Int32(SOCK_DGRAM.rawValue))
  defer { for fd in pair { _ = close(fd) } }
  #expect(throws: WaylandError.connection) { try UnixSocket.prepareConnected(pair[0]) }
  let unconnected = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_CLOEXEC.rawValue), 0)
  try #require(unconnected >= 0)
  defer { _ = close(unconnected) }
  #expect(throws: WaylandError.connection) { try UnixSocket.prepareConnected(unconnected) }
}

@Test(arguments: [0, 1, 3, 253])
func unixSocketReceivesDescriptorsFromCPeer(count: Int) throws {
  let pair = try unixSocketPair()
  defer { for fd in pair { _ = close(fd) } }
  let original = try FileDescriptor.open(FilePath("/dev/null"), .readOnly, options: .closeOnExec)
  defer { try? original.close() }
  let descriptors = Array(repeating: original.rawValue, count: count)
  let sent = unsafe cwl_send(pair[1], [UInt8(42)], 1, descriptors, descriptors.count)
  try #require(sent == 1)
  var bytes = [UInt8](repeating: 0, count: 16)
  let received = try UnixSocket.receive(pair[0], into: &bytes)
  defer { for descriptor in received.descriptors { descriptor.close() } }
  #expect(received.count == 1)
  #expect(bytes[0] == 42)
  #expect(received.descriptors.count == count)
  for descriptor in received.descriptors {
    #expect(descriptor.borrow { fcntl($0, F_GETFD) & FD_CLOEXEC != 0 })
  }
}

@Test(arguments: [0, 1])
func unixSocketClosesDescriptorsOnControlTruncation(limit: Int) throws {
  let pair = try unixSocketPair()
  defer { for fd in pair { _ = close(fd) } }
  let pipe = try FileDescriptor.pipe(options: .closeOnExec)
  defer { try? pipe.readEnd.close() }
  let descriptors = Array(repeating: pipe.writeEnd.rawValue, count: 3)
  let sent = unsafe cwl_send(pair[1], [UInt8(42)], 1, descriptors, descriptors.count)
  try pipe.writeEnd.close()
  try #require(sent == 1)
  var bytes = [UInt8](repeating: 0, count: 16)
  #expect(throws: Errno.messageTooLong) {
    try UnixSocket.receive(pair[0], into: &bytes, descriptorLimit: limit)
  }
  var status = pollfd(fd: pipe.readEnd.rawValue, events: Int16(POLLIN), revents: 0)
  #expect(unsafe poll(&status, 1, 1000) == 1 && status.revents & Int16(POLLHUP) != 0)
}

@Test(arguments: [0, 1, 3, 253])
func unixSocketSendsDescriptorsToCPeer(count: Int) throws {
  let pair = try unixSocketPair()
  defer { for fd in pair { _ = close(fd) } }
  let original = try FileDescriptor.open(FilePath("/dev/null"), .readOnly, options: .closeOnExec)
  defer { try? original.close() }
  let descriptors = Array(repeating: original.rawValue, count: count)
  let bytes: [UInt8] = [42]
  let sent = try bytes.withUnsafeBytes {
    try unsafe UnixSocket.send(pair[0], bytes: $0, descriptors: descriptors)
  }
  try #require(sent == 1)
  var buffer = [UInt8](repeating: 0, count: 16)
  var receivedDescriptors = [Int32](repeating: -1, count: count)
  var receivedCount = receivedDescriptors.count
  let received = unsafe cwl_receive(
    pair[1], &buffer, buffer.count, &receivedDescriptors, &receivedCount)
  defer { for fd in receivedDescriptors.prefix(receivedCount) { _ = close(fd) } }
  #expect(received == 1)
  #expect(buffer[0] == 42)
  #expect(receivedCount == count)
  for fd in receivedDescriptors.prefix(receivedCount) {
    #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0)
  }
}

@Test func unixSocketRejectsTooManyOutboundDescriptorsWithoutSendingBytes() throws {
  let pair = try unixSocketPair()
  defer { for fd in pair { _ = close(fd) } }
  let descriptors = [Int32](repeating: -1, count: 254)
  let bytes: [UInt8] = [42]
  #expect(throws: Errno.messageTooLong) {
    try bytes.withUnsafeBytes { try unsafe UnixSocket.send(pair[0], bytes: $0, descriptors: descriptors) }
  }
  var buffer = [UInt8](repeating: 0, count: 16)
  #expect(throws: Errno.resourceTemporarilyUnavailable) {
    try UnixSocket.receive(pair[1], into: &buffer)
  }
}

@Test func unixSocketSendSuppressesBrokenPipeSignal() throws {
  let pair = try unixSocketPair()
  defer { _ = close(pair[0]) }
  _ = close(pair[1])
  let bytes: [UInt8] = [42]
  #expect(throws: Errno.brokenPipe) {
    try bytes.withUnsafeBytes { try unsafe UnixSocket.send(pair[0], bytes: $0, descriptors: []) }
  }
}
