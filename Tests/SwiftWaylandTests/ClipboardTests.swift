import Glibc
import SystemPackage
import Testing

@testable import SwiftWayland

private func clipboardPipe() throws -> [Int32] {
  let pipe = try FileDescriptor.pipe(options: [.closeOnExec, .nonBlocking])
  return [pipe.readEnd.rawValue, pipe.writeEnd.rawValue]
}

@Test func clipboardTransfersLargeUTF8TextWithoutBlockingTheReaderOrWriter() async throws {
  let fds = try clipboardPipe()
  let text = String(repeating: "hello café 🙂\n", count: 20_000)
  let writer = blockingTestTask { ClipboardTransfer.write(Array(text.utf8), to: fds[1]) }
  let reader = blockingTestTask { ClipboardTransfer.read(from: fds[0]) }
  #expect(await reader.value == text)
  await writer.value
}

@Test func clipboardRejectsInvalidUTF8AndOversizedTransfers() async throws {
  for bytes in [[UInt8(0xFF)], [UInt8](repeating: 65, count: ClipboardTransfer.maximumBytes + 1)] {
    let fds = try clipboardPipe()
    let writer = blockingTestTask { ClipboardTransfer.write(bytes, to: fds[1]) }
    let reader = blockingTestTask { ClipboardTransfer.read(from: fds[0]) }
    #expect(await reader.value == nil)
    await writer.value
  }
}

@Test func clipboardReadCanBeCancelledWhileTheSourceStalls() async throws {
  let fds = try clipboardPipe()
  defer { _ = close(fds[1]) }
  let reader = blockingTestTask { ClipboardTransfer.read(from: fds[0]) }
  try await Task.sleep(for: .milliseconds(20))
  reader.cancel()
  #expect(await reader.value == nil)
  await blockingTestTask {
    var writer = pollfd(fd: fds[1], events: 0, revents: 0)
    #expect(unsafe poll(&writer, 1, 1000) == 1)
    #expect(writer.revents & Int16(POLLERR) != 0)
  }.value
}

@Test func clipboardWriteSurvivesAClosedRecipientAndClosesItsDescriptor() async throws {
  var fds: [Int32] = [-1, -1]
  try #require(
    unsafe socketpair(
      AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue | SOCK_CLOEXEC.rawValue), 0, &fds
    )
      == 0)
  defer { _ = close(fds[0]) }
  try #require(shutdown(fds[0], Int32(SHUT_RD)) == 0)
  ClipboardTransfer.write(Array("no recipient".utf8), to: fds[1])
  let recipient = fds[0]
  await blockingTestTask {
    var peer = pollfd(fd: recipient, events: 0, revents: 0)
    #expect(unsafe poll(&peer, 1, 1000) == 1)
    #expect(peer.revents & Int16(POLLHUP) != 0)
  }.value
}

@Test(arguments: [false, true])
func clipboardWriteRestoresUnblockedSIGPIPE(recipientOpen: Bool) async {
  await #expect(processExitsWith: .success) { [recipientOpen] in
    try checkUnblockedSIGPIPE(recipientOpen: recipientOpen)
  }
}

private func checkUnblockedSIGPIPE(recipientOpen: Bool) throws {
  _ = signal(SIGPIPE, SIG_DFL)
  let pipe = try FileDescriptor.pipe(options: .closeOnExec)
  defer { try? pipe.writeEnd.close() }
  if !recipientOpen { try pipe.readEnd.close() }
  defer { if recipientOpen { try? pipe.readEnd.close() } }

  var previous = sigset_t()
  try #require(unsafe pthread_sigmask(SIG_BLOCK, nil, &previous) == 0)
  var unblocked = previous
  _ = unsafe sigdelset(&unblocked, SIGPIPE)
  try #require(unsafe pthread_sigmask(SIG_SETMASK, &unblocked, nil) == 0)
  defer { _ = unsafe pthread_sigmask(SIG_SETMASK, &previous, nil) }

  try [UInt8(42)].withUnsafeBytes { buffer -> Void in
    if recipientOpen {
      let count = try unsafe ClipboardTransfer.writeWithoutSIGPIPE(buffer, to: pipe.writeEnd)
      #expect(count == 1)
    } else {
      #expect(throws: Errno.brokenPipe) {
        try unsafe ClipboardTransfer.writeWithoutSIGPIPE(buffer, to: pipe.writeEnd)
      }
    }
  }
  var current = sigset_t()
  try #require(unsafe pthread_sigmask(SIG_BLOCK, nil, &current) == 0)
  #expect(unsafe sigismember(&current, SIGPIPE) == 0)
}

@Test(arguments: [false, true])
func clipboardWritePreservesBlockedAndPendingSIGPIPE(pendingBefore: Bool) async {
  await #expect(processExitsWith: .success) { [pendingBefore] in
    try checkPendingSIGPIPE(pendingBefore: pendingBefore)
  }
}

private func checkPendingSIGPIPE(pendingBefore: Bool) throws {
  _ = signal(SIGPIPE, SIG_DFL)
  let pipe = try FileDescriptor.pipe(options: .closeOnExec)
  try pipe.readEnd.close()
  defer { try? pipe.writeEnd.close() }
  var blocked = sigset_t()
  var previous = sigset_t()
  _ = unsafe sigemptyset(&blocked)
  _ = unsafe sigaddset(&blocked, SIGPIPE)
  try #require(unsafe pthread_sigmask(SIG_BLOCK, &blocked, &previous) == 0)
  defer {
    if pendingBefore {
      var timeout = timespec(tv_sec: 0, tv_nsec: 0)
      _ = unsafe sigtimedwait(&blocked, nil, &timeout)
    }
    _ = unsafe pthread_sigmask(SIG_SETMASK, &previous, nil)
  }
  if pendingBefore { try #require(raise(SIGPIPE) == 0) }
  [UInt8(42)].withUnsafeBytes { buffer -> Void in
    #expect(throws: Errno.brokenPipe) {
      try unsafe ClipboardTransfer.writeWithoutSIGPIPE(buffer, to: pipe.writeEnd)
    }
  }
  var current = sigset_t()
  var pending = sigset_t()
  try #require(unsafe pthread_sigmask(SIG_BLOCK, nil, &current) == 0)
  try #require(unsafe sigpending(&pending) == 0)
  #expect(unsafe sigismember(&current, SIGPIPE) == 1)
  #expect(unsafe sigismember(&pending, SIGPIPE) == (pendingBefore ? 1 : 0))
}

@Test @MainActor func clipboardIsUnavailableWithoutANativeSessionOrFocus() async {
  let connection = WaylandConnection(configuration: .init())
  #expect(!connection.writeClipboard("text"))
  #expect(await connection.readClipboard() == nil)
  let clipboard = WaylandClipboard(objects: WaylandObjects())
  #expect(!clipboard.write("text"))
  #expect(clipboard.beginRead() == nil)
  clipboard.close()
  clipboard.close()
}
