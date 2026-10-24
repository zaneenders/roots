import NIOCore
import NIOPosix

actor WaylandTransport {
  private let channel: any Channel
  private let handler: NIOLoopBound<WireChannelHandler>

  private init(channel: any Channel, handler: NIOLoopBound<WireChannelHandler>) {
    self.channel = channel
    self.handler = handler
  }

  static func connect(path: String) async throws -> (
    WaylandTransport, AsyncThrowingStream<WireMessage, any Error>
  ) {
    try await make { bootstrap in bootstrap.connect(unixDomainSocketPath: path) }
  }

  static func takingSocket(_ fd: Int32) async throws -> (
    WaylandTransport, AsyncThrowingStream<WireMessage, any Error>
  ) {
    try await make { bootstrap in bootstrap.withConnectedSocket(fd) }
  }

  private static func make(
    _ connect: (ClientBootstrap) -> EventLoopFuture<any Channel>
  ) async throws -> (WaylandTransport, AsyncThrowingStream<WireMessage, any Error>) {
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    let (stream, continuation) = AsyncThrowingStream<WireMessage, any Error>.makeStream(
      bufferingPolicy: .bufferingOldest(1))
    let installed = loop.makePromise(of: NIOLoopBound<WireChannelHandler>.self)
    let bootstrap = ClientBootstrap(group: loop)
      .channelOption(ChannelOptions.receiveFileDescriptors, value: true)
      .channelOption(ChannelOptions.autoRead, value: false)
      .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .connectTimeout(.seconds(5))
      .channelInitializer { channel in
        let handler = WireChannelHandler(continuation: continuation)
        do {
          try channel.pipeline.syncOperations.addHandler(handler)
          installed.succeed(NIOLoopBound(handler, eventLoop: channel.eventLoop))
          return channel.eventLoop.makeSucceededVoidFuture()
        } catch {
          installed.fail(error)
          return channel.eventLoop.makeFailedFuture(error)
        }
      }
    let future = connect(bootstrap)
    let (connected, completion) = AsyncThrowingStream<any Channel, any Error>.makeStream(
      bufferingPolicy: .bufferingOldest(1))
    future.whenComplete { result in
      switch result {
      case .success(let channel):
        if case .terminated = completion.yield(channel) { channel.close(promise: nil) }
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
      future.whenSuccess { $0.close(promise: nil) }
    }
    let handler = try await installed.futureResult.get()
    if Task.isCancelled {
      try? await channel.close().get()
      throw CancellationError()
    }
    channel.read()
    return (WaylandTransport(channel: channel, handler: handler), stream)
  }

  func register(_ objects: [UInt32: String]) async throws {
    let handler = self.handler
    try await channel.eventLoop.submit { handler.value.register(objects) }.get()
  }

  func send(_ packets: [WirePacket], objects: [UInt32: String]) async throws {
    let handler = self.handler
    try await channel.eventLoop.submit { try handler.value.send(packets, objects: objects) }.get()
  }

  func acknowledged(objects: [UInt32: String]) async throws {
    let handler = self.handler
    try await channel.eventLoop.submit { try handler.value.acknowledged(objects: objects) }.get()
  }

  func close() async {
    let handler = self.handler
    try? await channel.eventLoop.submit { handler.value.finish(WaylandError.connection) }.get()
    try? await channel.close().get()
  }
}

private final class WireChannelHandler: ChannelInboundHandler {
  typealias InboundIn = AddressedEnvelope<ByteBuffer>
  private var decoder = WireDecoder()
  private var context: ChannelHandlerContext?
  private var awaitingDelivery = false
  private var terminalError: (any Error)?
  private var queuedBytes = 0
  private let continuation: AsyncThrowingStream<WireMessage, any Error>.Continuation

  init(continuation: AsyncThrowingStream<WireMessage, any Error>.Continuation) {
    self.continuation = continuation
  }
  func handlerAdded(context: ChannelHandlerContext) { self.context = context }
  func handlerRemoved(context: ChannelHandlerContext) { self.context = nil }
  func register(_ objects: [UInt32: String]) {
    for (id, interface) in objects { decoder.interfaces[id] = interface }
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var message = unwrapInboundIn(data)
    do {
      let fds = (message.metadata?.receivedFileDescriptors ?? []).map {
        WireDescriptor(taking: $0)
      }
      try decoder.append(&message.data, descriptors: fds)
      try deliverOne()
    } catch {
      finish(error)
      context.close(promise: nil)
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    if !awaitingDelivery, terminalError == nil { context.read() }
  }

  func acknowledged(objects: [UInt32: String]) throws {
    register(objects)
    awaitingDelivery = false
    do { try deliverOne() } catch {
      finish(error)
      throw error
    }
    if !awaitingDelivery, terminalError == nil { context?.read() }
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

  func send(_ packets: [WirePacket], objects: [UInt32: String]) throws {
    register(objects)
    guard terminalError == nil else { return }
    guard let context, context.channel.isActive, let address = context.channel.remoteAddress else {
      throw WaylandError.connection
    }
    let total = packets.reduce(0) { $0 + $1.bytes.readableBytes }
    guard total + queuedBytes <= 4 * 1024 * 1024 else { throw WaylandError.dispatch }
    let prepared = try packets.map { packet in
      guard packet.descriptors.count <= 1 else { throw WaylandError.invalidConfiguration }
      let descriptor = try packet.descriptors.first.map { fd in
        try fd.borrow { try WireDescriptor.duplicate($0) }
      }
      return (packet, descriptor)
    }
    queuedBytes += total
    for (packet, descriptor) in prepared {
      let promise = context.eventLoop.makePromise(of: Void.self)
      let bound = NIOLoopBound(self, eventLoop: context.eventLoop)
      let count = packet.bytes.readableBytes
      promise.futureResult.whenComplete { result in
        // NIO borrows metadata.fd until the write promise completes.
        descriptor?.close()
        bound.value.queuedBytes -= count
        if case .failure(let error) = result, let context = bound.value.context,
          context.channel.isActive
        {
          bound.value.errorCaught(context: context, error: error)
        }
      }
      if let descriptor {
        let metadata = AddressedEnvelope<ByteBuffer>.Metadata(
          ecnState: .transportNotCapable, fd: descriptor.borrow { Int($0) })
        context.write(
          NIOAny(AddressedEnvelope(remoteAddress: address, data: packet.bytes, metadata: metadata)),
          promise: promise)
      } else {
        context.write(NIOAny(packet.bytes), promise: promise)
      }
    }
    if awaitingDelivery, !packets.isEmpty { context.read() }
    context.flush()
  }

  func finish(_ error: any Error) {
    terminalError = error
    decoder = WireDecoder()
    continuation.finish(throwing: error)
  }

  func errorCaught(context: ChannelHandlerContext, error: any Error) {
    terminalError = error
    do { try deliverOne() } catch { finish(error) }
    context.close(promise: nil)
  }
  func channelInactive(context: ChannelHandlerContext) {
    if terminalError == nil { terminalError = WaylandError.connection }
    do { try deliverOne() } catch { finish(error) }
    context.fireChannelInactive()
  }
}
