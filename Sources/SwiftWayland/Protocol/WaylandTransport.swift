import NIOCore
import NIOPosix

struct WireChunk: Sendable {
  var bytes: ByteBuffer
  var descriptors: [WireDescriptor]
}

struct WireBatch: Sendable {
  static let maximumBytes = 4 * 1024 * 1024
  static let maximumDescriptors = 256
  let packets: [WirePacket]

  init(_ packets: [WirePacket]) throws {
    guard packets.reduce(0, { $0 + $1.bytes.readableBytes }) <= Self.maximumBytes,
      packets.reduce(0, { $0 + $1.descriptors.count }) <= Self.maximumDescriptors
    else { throw WaylandError.dispatch }
    // Own the descriptors before crossing the async writer. write() does not wait for sendmsg().
    self.packets = try packets.map { packet in
      guard packet.descriptors.count <= 1 else { throw WaylandError.invalidConfiguration }
      var packet = packet
      packet.descriptors = try packet.descriptors.map { try $0.borrow(WireDescriptor.duplicate) }
      return packet
    }
  }
}

typealias WaylandTransport = NIOAsyncChannel<WireChunk, WireBatch>

extension NIOAsyncChannel where Inbound == WireChunk, Outbound == WireBatch {
  static func connect(path: String) async throws -> Self {
    try await make { $0.connect(unixDomainSocketPath: path) }
  }

  static func takingSocket(_ fd: Int32) async throws -> Self {
    try await make { $0.withConnectedSocket(fd) }
  }

  private static func make(
    _ connect: (ClientBootstrap) -> EventLoopFuture<any Channel>
  ) async throws -> Self {
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    let installed = NIOLoopBoundBox<Self?>.makeEmptyBox(eventLoop: loop)
    let bootstrap = ClientBootstrap(group: loop)
      .channelOption(ChannelOptions.receiveFileDescriptors, value: true)
      .channelOption(
        ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: 65_536)
      )
      .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .connectTimeout(.seconds(5))
      .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHandler(WireChannelHandler())
          installed.value = try Self(
            wrappingChannelSynchronously: channel,
            configuration: .init(backPressureStrategy: .init(lowWatermark: 1, highWatermark: 2)))
        }
      }
    let future = connect(bootstrap).map { _ in installed.value! }
    // EventLoopFuture.get() is not cancellation-aware. Close even a late successful connection.
    let (connected, completion) = AsyncThrowingStream<Self, any Error>.makeStream(
      bufferingPolicy: .bufferingOldest(1))
    future.whenComplete { result in
      switch result {
      case .success(let channel):
        if case .terminated = completion.yield(channel) { channel.channel.close(promise: nil) }
        completion.finish()
      case .failure(let error): completion.finish(throwing: error)
      }
    }
    var iterator = connected.makeAsyncIterator()
    let channel = try await withTaskCancellationHandler {
      guard let channel = try await iterator.next() else { throw CancellationError() }
      return channel
    } onCancel: {
      completion.finish(throwing: CancellationError())
      future.whenSuccess { $0.channel.close(promise: nil) }
    }
    if Task.isCancelled {
      try? await channel.channel.close().get()
      throw CancellationError()
    }
    return channel
  }
}

private final class WireChannelHandler: ChannelDuplexHandler {
  typealias InboundIn = AddressedEnvelope<ByteBuffer>
  typealias InboundOut = WireChunk
  typealias OutboundIn = WireBatch
  typealias OutboundOut = AddressedEnvelope<ByteBuffer>
  private var queuedBytes = 0
  private var queuedDescriptors = 0

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let envelope = unwrapInboundIn(data)
    // NIO envelopes carry raw FDs, not ownership. Adopt before any async buffering or cancellation.
    let chunk = WireChunk(
      bytes: envelope.data,
      descriptors: (envelope.metadata?.receivedFileDescriptors ?? []).map(
        WireDescriptor.init(taking:)))
    context.fireChannelRead(wrapInboundOut(chunk))
  }

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let batch = unwrapOutboundIn(data)
    let bytes = batch.packets.reduce(0) { $0 + $1.bytes.readableBytes }
    let descriptors = batch.packets.reduce(0) { $0 + $1.descriptors.count }
    guard bytes <= WireBatch.maximumBytes - queuedBytes,
      descriptors <= WireBatch.maximumDescriptors - queuedDescriptors
    else {
      promise?.fail(WaylandError.dispatch)
      errorCaught(context: context, error: WaylandError.dispatch)
      return
    }
    guard let address = context.channel.remoteAddress, context.channel.isActive else {
      promise?.fail(WaylandError.connection)
      errorCaught(context: context, error: WaylandError.connection)
      return
    }
    queuedBytes += bytes
    queuedDescriptors += descriptors
    let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
    let completion = context.eventLoop.makePromise(of: Void.self)
    completion.futureResult.whenComplete { result in
      // Keep the batch's owned FDs alive until NIO finishes borrowing them. A batch can be reused.
      defer { withExtendedLifetime(batch) {} }
      bound.value.0.queuedBytes -= bytes
      bound.value.0.queuedDescriptors -= descriptors
      if case .failure(let error) = result, bound.value.1.channel.isActive {
        bound.value.0.errorCaught(context: bound.value.1, error: error)
      }
    }
    if let promise { completion.futureResult.cascade(to: promise) }
    guard !batch.packets.isEmpty else {
      completion.succeed(())
      return
    }
    for (index, packet) in batch.packets.enumerated() {
      let metadata = packet.descriptors.first.map {
        AddressedEnvelope<ByteBuffer>.Metadata(
          ecnState: .transportNotCapable, fd: $0.borrow { Int($0) })
      }
      context.write(
        wrapOutboundOut(
          AddressedEnvelope(remoteAddress: address, data: packet.bytes, metadata: metadata)),
        promise: index == batch.packets.count - 1 ? completion : nil)
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    context.fireErrorCaught(error)
    context.close(promise: nil)
  }

  func channelInactive(context: ChannelHandlerContext) {
    // The async stream drains buffered chunks before reporting EOF as a connection failure.
    context.fireErrorCaught(WaylandError.connection)
    context.fireChannelInactive()
  }
}
