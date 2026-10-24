import Glibc
import SystemPackage
import Testing

@testable import SwiftWayland

private func clipboardPipe() throws -> [Int32] {
  let pipe = try FileDescriptor.pipe(options: [.closeOnExec, .nonBlocking])
  return [pipe.readEnd.rawValue, pipe.writeEnd.rawValue]
}

// Exit tests can briefly inherit another test's pipe before exec closes CLOEXEC FDs.
private func peerClosed(_ descriptor: Int32, writing: Bool) async -> Bool {
  for _ in 0..<100 {
    var peer = pollfd(fd: descriptor, events: 0, revents: 0)
    if unsafe poll(&peer, 1, 0) == 1,
      peer.revents & Int16(writing ? POLLERR : POLLHUP) != 0
    {
      return true
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return false
}

@Test func clipboardTransfersLargeUTF8TextWithoutBlockingTheReaderOrWriter() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  let text = String(repeating: "hello café 🙂\n", count: 20_000)
  async let write: Void = io.write(
    Array(text.utf8), to: OwnedFD(taking: FileDescriptor(rawValue: fds[1])))
  let bytes = try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])))
  #expect(String(bytes: bytes, encoding: .utf8) == text)
  try await write
}

@Test func clipboardPreservesInvalidUTF8ForTheCallerToReject() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  async let write: Void = io.write([0xFF], to: OwnedFD(taking: FileDescriptor(rawValue: fds[1])))
  let bytes = try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])))
  #expect(bytes == [0xFF])
  #expect(String(bytes: bytes, encoding: .utf8) == nil)
  try await write
}

@Test func clipboardRejectsOversizedReadsAndWrites() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  let writer = Task {
    try await io.write([1, 2, 3], to: OwnedFD(taking: FileDescriptor(rawValue: fds[1])))
  }
  await #expect(throws: ClipboardIO.Failure.tooLarge) {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])), limit: 2)
  }
  _ = await writer.result
  let oversized = try clipboardPipe()
  defer { _ = close(oversized[0]) }
  await #expect(throws: ClipboardIO.Failure.tooLarge) {
    try await io.write(
      [UInt8](repeating: 65, count: ClipboardIO.maximumBytes + 1),
      to: OwnedFD(taking: FileDescriptor(rawValue: oversized[1])))
  }
  #expect(await peerClosed(oversized[0], writing: false))
}

@Test func clipboardReadCanBeCancelledWhileTheSourceStalls() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  defer { _ = close(fds[1]) }
  let reader = Task { try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0]))) }
  try await Task.sleep(for: .milliseconds(20))
  reader.cancel()
  await #expect(throws: CancellationError.self) { try await reader.value }
  #expect(await peerClosed(fds[1], writing: true))
}

@Test func clipboardCancellationBeforeRegistrationClosesTheDescriptor() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  defer { _ = close(fds[1]) }
  let reader = Task {
    unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
    return try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])))
  }
  await #expect(throws: CancellationError.self) { try await reader.value }
  #expect(await peerClosed(fds[1], writing: true))
}

@Test func clipboardWriteCanBeCancelledWhileTheRecipientStalls() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  defer { _ = close(fds[0]) }
  let writer = Task {
    try await io.write(
      [UInt8](repeating: 42, count: 1024 * 1024),
      to: OwnedFD(taking: FileDescriptor(rawValue: fds[1])))
  }
  try await Task.sleep(for: .milliseconds(20))
  writer.cancel()
  await #expect(throws: CancellationError.self) { try await writer.value }
  #expect(await peerClosed(fds[0], writing: false))
}

@Test(arguments: [false, true])
func clipboardTransfersHaveDeadlines(writing: Bool) async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  let active = fds[writing ? 1 : 0]
  defer { _ = close(fds[writing ? 0 : 1]) }
  await #expect(throws: ClipboardIO.Failure.timedOut) {
    if writing {
      try await io.write(
        [UInt8](repeating: 42, count: 1024 * 1024),
        to: OwnedFD(taking: FileDescriptor(rawValue: active)),
        timeout: .milliseconds(20))
    } else {
      _ = try await io.read(
        from: OwnedFD(taking: FileDescriptor(rawValue: active)), timeout: .milliseconds(20))
    }
  }
  #expect(await peerClosed(fds[writing ? 0 : 1], writing: !writing))
}

@Test func clipboardWriteSurvivesAClosedRecipientAndClosesItsDescriptor() async throws {
  let io = ClipboardIO()
  var fds: [Int32] = [-1, -1]
  try #require(
    unsafe socketpair(
      AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue | SOCK_CLOEXEC.rawValue),
      0, &fds) == 0)
  defer { _ = close(fds[0]) }
  try #require(shutdown(fds[0], Int32(SHUT_RD)) == 0)
  await #expect(throws: (any Error).self) {
    try await io.write(
      Array("no recipient".utf8), to: OwnedFD(taking: FileDescriptor(rawValue: fds[1])))
  }
  #expect(await peerClosed(fds[0], writing: false))
}

@Test func clipboardBrokenPipeDoesNotTerminateTheProcess() async {
  await #expect(processExitsWith: .success) {
    _ = signal(SIGPIPE, SIG_DFL)
    let pipe = try FileDescriptor.pipe(options: .closeOnExec)
    try pipe.readEnd.close()
    do {
      try await ClipboardIO().write([42], to: OwnedFD(taking: pipe.writeEnd))
      Issue.record("Writing to a closed pipe unexpectedly succeeded")
    } catch {}
  }
}

@Test func clipboardRejectsNonpollableDescriptorsWithoutUsingCapacity() async throws {
  let io = ClipboardIO(maximumTransfers: 1)
  // NIO only accepts pollable descriptors; reject files and devices before adoption.
  for path in ["/proc/self/status", "/dev/null"] {
    let fd = try FileDescriptor.open(FilePath(path), .readOnly, options: .closeOnExec)
    await #expect(throws: ClipboardIO.Failure.invalidDescriptor) {
      try await io.read(from: OwnedFD(taking: fd))
    }
  }
  let fds = try clipboardPipe()
  _ = close(fds[1])
  let bytes = try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])))
  #expect(bytes.isEmpty)
}

@Test func clipboardEmptyTransferReachesEOF() async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  async let write: Void = io.write([], to: OwnedFD(taking: FileDescriptor(rawValue: fds[1])))
  let bytes = try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])), limit: 0)
  #expect(bytes.isEmpty)
  try await write
}

@Test func clipboardAdmissionBoundsTransfersAndBytes() async throws {
  let io = ClipboardIO(maximumTransfers: 1, maximumBufferedBytes: 16)
  let first = try clipboardPipe()
  defer { _ = close(first[1]) }
  let reader = Task {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: first[0])), limit: 16)
  }
  try await Task.sleep(for: .milliseconds(20))
  let second = try clipboardPipe()
  defer { _ = close(second[1]) }
  await #expect(throws: ClipboardIO.Failure.busy) {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: second[0])), limit: 1)
  }
  #expect(await peerClosed(second[1], writing: true))
  reader.cancel()
  _ = await reader.result

  let third = try clipboardPipe()
  defer { _ = close(third[1]) }
  await #expect(throws: ClipboardIO.Failure.busy) {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: third[0])), limit: 17)
  }
  #expect(await peerClosed(third[1], writing: true))
}

@Test func clipboardReservationsBoundCombinedBufferUsage() async throws {
  let io = ClipboardIO(maximumTransfers: 2, maximumBufferedBytes: 16)
  let first = try clipboardPipe()
  defer { _ = close(first[1]) }
  let reader = Task {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: first[0])), limit: 16)
  }
  try await Task.sleep(for: .milliseconds(20))
  let second = try clipboardPipe()
  defer { _ = close(second[1]) }
  await #expect(throws: ClipboardIO.Failure.busy) {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: second[0])), limit: 1)
  }
  reader.cancel()
  _ = await reader.result
  let third = try clipboardPipe()
  _ = close(third[1])
  let bytes = try await io.read(
    from: OwnedFD(taking: FileDescriptor(rawValue: third[0])), limit: 16)
  #expect(bytes.isEmpty)
}

@Test(arguments: [false, true])
func clipboardShutdownCancelsTransfersAndRejectsNewOnes(writing: Bool) async throws {
  let io = ClipboardIO()
  let fds = try clipboardPipe()
  let active = fds[writing ? 1 : 0]
  let peer = fds[writing ? 0 : 1]
  defer { _ = close(peer) }
  let transfer = Task {
    if writing {
      try await io.write(
        [UInt8](repeating: 42, count: 1024 * 1024),
        to: OwnedFD(taking: FileDescriptor(rawValue: active)))
    } else {
      _ = try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: active)))
    }
  }
  try await Task.sleep(for: .milliseconds(20))
  await io.shutdown()
  await #expect(throws: ClipboardIO.Failure.closed) { try await transfer.value }
  #expect(await peerClosed(peer, writing: !writing))
  let next = try clipboardPipe()
  defer { _ = close(next[1]) }
  await #expect(throws: ClipboardIO.Failure.closed) {
    try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: next[0])))
  }
  #expect(await peerClosed(next[1], writing: true))
}

@Test func clipboardImmediateCompletionsMoveContinuationsThroughValueSlots() async throws {
  let io = ClipboardIO(maximumTransfers: 1)
  for _ in 0..<32 {
    let fds = try clipboardPipe()
    try FileDescriptor(rawValue: fds[1]).writeAll([UInt8(42)])
    _ = close(fds[1])
    let bytes = try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0])), limit: 1)
    #expect(bytes == [42])
  }
  await io.shutdown()
}

@Test func clipboardSlotsCanBeReusedAfterCancellationAndLateCallbacks() async throws {
  let io = ClipboardIO(maximumTransfers: 1)
  for _ in 0..<10 {
    let fds = try clipboardPipe()
    let reader = Task { try await io.read(from: OwnedFD(taking: FileDescriptor(rawValue: fds[0]))) }
    try await Task.sleep(for: .milliseconds(1))
    reader.cancel()
    _ = await reader.result
    _ = close(fds[1])

    let next = try clipboardPipe()
    let writer = Task {
      try await io.write([42], to: OwnedFD(taking: FileDescriptor(rawValue: next[1])))
    }
    try await writer.value
    let bytes = try await io.read(
      from: OwnedFD(taking: FileDescriptor(rawValue: next[0])), timeout: .seconds(1))
    #expect(bytes == [42])
  }
}

@Test @MainActor func clipboardIsUnavailableWithoutANativeSessionOrFocus() async {
  let connection = WaylandConnection(configuration: .init())
  #expect(!connection.writeClipboard("text"))
  #expect(await connection.readClipboard() == nil)
  let clipboard = WaylandClipboard(objects: WaylandObjects())
  #expect(!clipboard.write("text"))
  let unavailable = clipboard.beginRead() == nil
  #expect(unavailable)
  clipboard.close()
  clipboard.close()
}
