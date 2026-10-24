import NIOCore
import NIOPosix
import SystemPackage

struct OwnedFD: ~Copyable, Sendable {
  private(set) var descriptor: SystemPackage.FileDescriptor?

  init(taking descriptor: SystemPackage.FileDescriptor) { self.descriptor = descriptor }
  mutating func relinquish() { descriptor = nil }
  consuming func close() { try? descriptor.take()?.close() }
  deinit { try? descriptor?.close() }
}

actor ClipboardIO {
  static let maximumBytes = 16 * 1024 * 1024

  enum Failure: Error, Equatable {
    case busy, closed, invalidDescriptor, invalidLimit, tooLarge, timedOut
  }

  private struct Pending: ~Copyable {
    let id: UInt64
    var descriptor: OwnedFD?
    var channel: (any Channel)?
    let timeout: Scheduled<Void>
    let continuation: Continuation<[UInt8], any Error>
    let limit: Int
    let reading: Bool
    var buffer = ByteBuffer()
    var finishing = false

    init(
      id: UInt64, descriptor: consuming OwnedFD?,
      continuation: consuming Continuation<[UInt8], any Error>, limit: Int, reading: Bool,
      timeout: Scheduled<Void>
    ) {
      self.id = id
      self.descriptor = descriptor
      self.continuation = continuation
      self.limit = limit
      self.reading = reading
      self.timeout = timeout
    }
  }

  private nonisolated let loop: any EventLoop
  private nonisolated let executor: any SerialExecutor
  nonisolated var unownedExecutor: UnownedSerialExecutor {
    unsafe executor.asUnownedSerialExecutor()
  }

  private var pending: UniqueArray<Pending?>
  private let maximumBufferedBytes: Int
  private var reservedBytes = 0
  private var nextID: UInt64 = 0
  private var closed = false

  init(maximumTransfers: Int = 8, maximumBufferedBytes: Int = 32 * 1024 * 1024) {
    precondition(maximumTransfers > 0 && maximumBufferedBytes > 0)
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    self.loop = loop
    executor = loop.executor
    self.maximumBufferedBytes = maximumBufferedBytes
    pending = UniqueArray(capacity: maximumTransfers)
    for _ in 0..<maximumTransfers { pending.append(nil) }
  }

  func read(
    from descriptor: consuming OwnedFD, limit: Int = maximumBytes,
    timeout: Duration = .seconds(5)
  ) async throws -> [UInt8] {
    try await transfer(descriptor: descriptor, bytes: nil, limit: limit, timeout: timeout)
  }

  func write(
    _ bytes: [UInt8], to descriptor: consuming OwnedFD, timeout: Duration = .seconds(5)
  ) async throws {
    _ = try await transfer(
      descriptor: descriptor, bytes: bytes, limit: bytes.count, timeout: timeout)
  }

  private func transfer(
    descriptor: consuming OwnedFD, bytes: [UInt8]?, limit: Int, timeout: Duration
  ) async throws -> [UInt8] {
    var owned: OwnedFD? = consume descriptor
    defer { owned.take()?.close() }
    try Task.checkCancellation()
    guard !closed else { throw Failure.closed }
    if bytes != nil, limit > Self.maximumBytes { throw Failure.tooLarge }
    guard limit >= 0, limit <= Self.maximumBytes else { throw Failure.invalidLimit }
    guard let descriptor = owned?.descriptor, let info = try? descriptor.stat(),
      info.type == .fifo || info.type == .socket
    else { throw Failure.invalidDescriptor }
    guard limit <= maximumBufferedBytes - reservedBytes,
      let slot = pending.indices.first(where: { pending[$0] == nil })
    else { throw Failure.busy }
    nextID += 1
    let id = nextID
    return try await withTaskCancellationHandler {
      try await withContinuation(of: [UInt8].self, throwing: (any Error).self) { continuation in
        reservedBytes += limit
        let timeout = loop.scheduleTask(in: TimeAmount(max(.zero, timeout))) {
          self.assumeIsolated { $0.finish(slot, id: id, result: .failure(Failure.timedOut)) }
        }
        install(
          Pending(
            id: id, descriptor: owned.take(), continuation: continuation, limit: limit,
            reading: bytes == nil, timeout: timeout), at: slot)
        start(slot, id: id, bytes: bytes)
      }
    } onCancel: {
      self.loop.execute {
        self.assumeIsolated { $0.finish(slot, id: id, result: .failure(CancellationError())) }
      }
    }
  }

  private func install(_ operation: consuming Pending, at slot: Int) {
    var slots = pending.mutableSpan
    precondition(slots[slot] == nil)
    slots[slot] = consume operation
  }

  private func start(_ slot: Int, id: UInt64, bytes: [UInt8]?) {
    guard let descriptor = pending[slot]?.descriptor?.descriptor else {
      return
    }
    // No fallible channel options precede the initializer. Once called, NIO owns the FD,
    // including on subsequent registration failure; earlier failures leave it with us.
    let bootstrap = NIOPipeBootstrap(group: loop).channelInitializer { channel in
      self.assumeIsolated {
        var slots = $0.pending.mutableSpan
        slots[slot]?.descriptor?.relinquish()
        slots[slot]?.channel = channel
      }
      return channel.pipeline.addHandler(ClipboardHandler(owner: self, slot: slot, id: id))
    }
    let connected =
      bytes == nil
      ? bootstrap.takingOwnershipOfDescriptor(input: descriptor.rawValue)
      : bootstrap.takingOwnershipOfDescriptor(output: descriptor.rawValue)
    connected.whenComplete { result in
      self.assumeIsolated { owner in
        switch result {
        case .failure(let error): owner.finish(slot, id: id, result: .failure(error))
        case .success(let channel):
          guard owner.isActive(slot, id: id) else {
            channel.close(promise: nil)
            return
          }
          if let bytes {
            channel.writeAndFlush(ByteBuffer(bytes: bytes)).whenComplete { result in
              self.assumeIsolated {
                $0.finish(slot, id: id, result: result.map { [] })
              }
            }
          }
        }
      }
    }
  }

  private func isActive(_ slot: Int, id: UInt64) -> Bool {
    pending[slot]?.id == id && pending[slot]?.finishing == false
  }

  fileprivate func received(_ bytes: inout ByteBuffer, slot: Int, id: UInt64) {
    guard isActive(slot, id: id) else { return }
    guard let limit = pending[slot]?.limit, let count = pending[slot]?.buffer.readableBytes,
      bytes.readableBytes <= limit - count
    else {
      finish(slot, id: id, result: .failure(Failure.tooLarge))
      return
    }
    var slots = pending.mutableSpan
    slots[slot]?.buffer.writeBuffer(&bytes)
  }

  fileprivate func ended(_ slot: Int, id: UInt64, error: (any Error)? = nil) {
    guard isActive(slot, id: id) else { return }
    if let error {
      finish(slot, id: id, result: .failure(error))
    } else if pending[slot]?.reading == true {
      let bytes = Array(pending[slot]!.buffer.readableBytesView)
      finish(slot, id: id, result: .success(bytes))
    } else {
      finish(slot, id: id, result: .failure(Failure.closed))
    }
  }

  private func finish(_ slot: Int, id: UInt64, result: Result<[UInt8], any Error>) {
    guard isActive(slot, id: id) else { return }
    do {
      var slots = pending.mutableSpan
      slots[slot]?.finishing = true
    }
    pending[slot]?.timeout.cancel()
    if let channel = pending[slot]?.channel {
      channel.close(promise: nil)
      channel.closeFuture.whenComplete { _ in
        self.assumeIsolated { $0.retire(slot, id: id, result: result) }
      }
    } else {
      retire(slot, id: id, result: result)
    }
  }

  private func retire(_ slot: Int, id: UInt64, result: Result<[UInt8], any Error>) {
    guard pending[slot]?.id == id else { return }
    var slots = pending.mutableSpan
    guard var operation = slots[slot].take() else { return }
    reservedBytes -= operation.limit
    operation.descriptor.take()?.close()
    operation.continuation.resume(with: result)
  }

  func shutdown() async {
    closed = true
    var channels: [any Channel] = []
    for slot in pending.indices {
      if let channel = pending[slot]?.channel { channels.append(channel) }
      if let id = pending[slot]?.id { finish(slot, id: id, result: .failure(Failure.closed)) }
    }
    for channel in channels { try? await channel.closeFuture.get() }
  }
}

private final class ClipboardHandler: ChannelInboundHandler, Sendable {
  typealias InboundIn = ByteBuffer
  private let owner: ClipboardIO
  private let slot: Int
  private let id: UInt64

  init(owner: ClipboardIO, slot: Int, id: UInt64) {
    self.owner = owner
    self.slot = slot
    self.id = id
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var bytes = unwrapInboundIn(data)
    owner.assumeIsolated { $0.received(&bytes, slot: slot, id: id) }
  }

  func channelInactive(context: ChannelHandlerContext) {
    owner.assumeIsolated { $0.ended(slot, id: id) }
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    owner.assumeIsolated { $0.ended(slot, id: id, error: error) }
  }
}
