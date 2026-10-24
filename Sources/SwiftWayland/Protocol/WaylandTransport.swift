import Dispatch
import Glibc
import NIOCore
import Synchronization
import SystemPackage

private final class SocketExecutor: SerialExecutor {
  let queue = DispatchQueue(label: "SwiftWayland.transport")

  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    let executor = unsafe asUnownedSerialExecutor()
    queue.async { unsafe job.runSynchronously(on: executor) }
  }

  func checkIsolated() { dispatchPrecondition(condition: .onQueue(queue)) }
}

actor WaylandTransport {
  private struct PendingWrite {
    var bytes: ByteBuffer
    var descriptors: [WireDescriptor]
  }

  private nonisolated let executor = SocketExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor {
    unsafe executor.asUnownedSerialExecutor()
  }

  private let socket: WireDescriptor
  private let continuation: AsyncThrowingStream<WireMessage, any Error>.Continuation
  private var readSource: (any DispatchSourceRead)?
  private var writeSource: (any DispatchSourceWrite)?
  private var readSuspended = true
  private var writeSuspended = true
  private var socketStopped = false
  private var connection: CheckedContinuation<Void, any Error>?
  private var decoder = WireDecoder()
  private var awaitingDelivery = false
  private var terminalError: (any Error)?
  private var writes = CircularBuffer<PendingWrite>()
  private var queuedBytes = 0

  private init(
    socket: WireDescriptor, continuation: AsyncThrowingStream<WireMessage, any Error>.Continuation
  ) {
    self.socket = socket
    self.continuation = continuation
  }

  isolated deinit { finish(WaylandError.connection) }

  static func connect(path: String) async throws -> (
    WaylandTransport, AsyncThrowingStream<WireMessage, any Error>
  ) {
    let address = try SocketAddress(unixDomainSocketPath: path)
    let fd = Glibc.socket(
      AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_NONBLOCK.rawValue | SOCK_CLOEXEC.rawValue), 0)
    guard fd >= 0 else { throw WaylandError.connection }
    return try await make(socket: WireDescriptor(taking: fd), address: address)
  }

  static func takingSocket(_ fd: Int32) async throws -> (
    WaylandTransport, AsyncThrowingStream<WireMessage, any Error>
  ) {
    try await make(socket: WireDescriptor(taking: fd), address: nil)
  }

  private static func make(socket: WireDescriptor, address: SocketAddress?) async throws -> (
    WaylandTransport, AsyncThrowingStream<WireMessage, any Error>
  ) {
    let (stream, continuation) = AsyncThrowingStream<WireMessage, any Error>.makeStream(
      bufferingPolicy: .bufferingOldest(1))
    let transport = WaylandTransport(socket: socket, continuation: continuation)
    do {
      try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try await transport.start(address: address)
        try Task.checkCancellation()
      } onCancel: {
        Task { await transport.close() }
      }
      return (transport, stream)
    } catch {
      await transport.close()
      try Task.checkCancellation()
      throw error
    }
  }

  private func start(address: SocketAddress?) async throws {
    guard !socketStopped else { throw CancellationError() }
    if address == nil { try socket.borrow { try UnixSocket.prepareConnected($0) } }
    installSources()
    if let address {
      let result = socket.borrow { fd in
        unsafe address.withSockAddr { unsafe Glibc.connect(fd, $0, socklen_t($1)) }
      }
      if result != 0 {
        guard errno == EINPROGRESS else { throw WaylandError.connection }
        try await withCheckedThrowingContinuation { continuation in
          connection = continuation
          setWriting(true)
          executor.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.assumeIsolated {
              if $0.connection != nil { $0.finish(WaylandError.connection) }
            }
          }
        }
      }
    }
    setReading(true)
  }

  private func installSources() {
    let fd = socket.borrow { $0 }
    let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: executor.queue)
    let write = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: executor.queue)
    // Both sources must relinquish the descriptor before it can be closed and reused.
    let cancellations = Mutex(2)
    let socket = self.socket
    let release: @Sendable () -> Void = {
      let last = cancellations.withLock { count in
        count -= 1
        return count == 0
      }
      if last { socket.close() }
    }
    read.setCancelHandler(handler: release)
    write.setCancelHandler(handler: release)
    read.setEventHandler { [weak self] in self?.assumeIsolated { $0.readReady() } }
    write.setEventHandler { [weak self] in self?.assumeIsolated { $0.writeReady() } }
    read.activate()
    read.suspend()
    write.activate()
    write.suspend()
    readSource = read
    writeSource = write
  }

  func register(_ objects: [UInt32: String]) {
    for (id, interface) in objects { decoder.interfaces[id] = interface }
  }

  func send(_ packets: [WirePacket], objects: [UInt32: String]) throws {
    register(objects)
    guard terminalError == nil else { return }
    guard !socketStopped else { throw WaylandError.connection }
    let total = packets.reduce(0) { $0 + $1.bytes.readableBytes }
    guard total <= 4 * 1024 * 1024 - queuedBytes else { throw WaylandError.dispatch }
    // Snapshot ownership before enqueueing: callers may explicitly close their originals.
    let pending = try packets.map { packet in
      PendingWrite(
        bytes: packet.bytes,
        descriptors: try packet.descriptors.map { descriptor in
          try descriptor.borrow { try WireDescriptor.duplicate($0) }
        })
    }
    queuedBytes += total
    for write in pending { writes.append(write) }
    flush()
  }

  func acknowledged(objects: [UInt32: String]) throws {
    register(objects)
    awaitingDelivery = false
    do {
      try deliverOne()
      updateReading()
    } catch {
      finish(error)
      throw error
    }
  }

  func close() { finish(WaylandError.connection) }

  private func readReady() {
    while !socketStopped, !readSuspended {
      if !readOnce() { return }
    }
  }

  private func readOnce() -> Bool {
    var bytes = [UInt8](repeating: 0, count: min(65_536, 1024 * 1024 - decoder.pendingBytes))
    let count: Int
    let descriptors: [WireDescriptor]
    do {
      (count, descriptors) = try socket.borrow { try UnixSocket.receive($0, into: &bytes) }
    } catch {
      if let error = error as? Errno {
        if error == .interrupted { return true }
        if error == .resourceTemporarilyUnavailable { return false }
        if error == .messageTooLong {
          finish(WaylandError.dispatch)
          return false
        }
      }
      endInput(WaylandError.connection)
      return false
    }
    if count == 0 {
      terminalError = WaylandError.connection
      stopSocket()
    }
    do {
      var buffer = ByteBuffer(bytes: bytes.prefix(count))
      try decoder.append(&buffer, descriptors: descriptors)
      try deliverOne()
      updateReading()
    } catch { finish(error) }
    return count > 0
  }

  private func endInput(_ error: any Error) {
    terminalError = error
    stopSocket()
    do { try deliverOne() } catch { finish(error) }
  }

  private func deliverOne() throws {
    guard !awaitingDelivery else { return }
    guard let message = try decoder.next() else {
      if let terminalError { finish(terminalError) }
      return
    }
    awaitingDelivery = true
    guard case .enqueued = continuation.yield(message) else { throw WaylandError.dispatch }
  }

  private func updateReading() {
    // Keep observing EOF while an event awaits acknowledgement, but bound read-ahead.
    setReading(!socketStopped && decoder.pendingBytes < 1024 * 1024)
  }

  private func writeReady() {
    guard !socketStopped else { return }
    do {
      if let connection {
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        let result = socket.borrow { unsafe getsockopt($0, SOL_SOCKET, SO_ERROR, &error, &size) }
        guard result == 0, error == 0 else { throw WaylandError.connection }
        self.connection = nil
        connection.resume()
      }
      flush()
    } catch { finish(error) }
  }

  private func flush() {
    while !writes.isEmpty {
      var write = writes.removeFirst()
      let descriptors = write.descriptors.map { $0.borrow { $0 } }
      let count: Int
      do {
        count = try socket.borrow { fd in
          try unsafe write.bytes.withUnsafeReadableBytes {
            try unsafe UnixSocket.send(fd, bytes: $0, descriptors: descriptors)
          }
        }
      } catch {
        if let error = error as? Errno,
          error == .interrupted || error == .resourceTemporarilyUnavailable
        {
          writes.prepend(write)
          if error == .interrupted { continue }
          setWriting(true)
          return
        }
        // A disconnected peer may have sent a final protocol error before rejecting our write.
        readReady()
        if !socketStopped { endInput(WaylandError.connection) }
        return
      }
      guard count > 0 else {
        // A disconnected peer may have sent a final protocol error before rejecting our write.
        readReady()
        if !socketStopped { endInput(WaylandError.connection) }
        return
      }
      // SCM_RIGHTS was delivered with the first successful byte, even on a partial write.
      write.descriptors.removeAll()
      write.bytes.moveReaderIndex(forwardBy: count)
      queuedBytes -= count
      if write.bytes.readableBytes > 0 { writes.prepend(write) }
    }
    setWriting(false)
  }

  private func setReading(_ enabled: Bool) {
    guard let readSource, enabled == readSuspended else { return }
    if enabled { readSource.resume() } else { readSource.suspend() }
    readSuspended = !enabled
  }

  private func setWriting(_ enabled: Bool) {
    guard let writeSource, enabled == writeSuspended else { return }
    if enabled { writeSource.resume() } else { writeSource.suspend() }
    writeSuspended = !enabled
  }

  private func stopSocket() {
    guard !socketStopped else { return }
    socketStopped = true
    if readSource == nil {
      socket.close()
    } else {
      setReading(true)
      setWriting(true)
      readSource?.cancel()
      writeSource?.cancel()
      readSource = nil
      writeSource = nil
    }
    writes.removeAll()
    queuedBytes = 0
  }

  private func finish(_ error: any Error) {
    terminalError = error
    stopSocket()
    let connection = self.connection
    self.connection = nil
    connection?.resume(throwing: error)
    decoder = WireDecoder()
    continuation.finish(throwing: error)
  }
}
