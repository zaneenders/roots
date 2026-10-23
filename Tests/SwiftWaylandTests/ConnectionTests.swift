import CWaylandTestSupport
import Foundation
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

private final class StartupPeer: Sendable {
  let path: String
  let listener: WireDescriptor
  init() throws {
    path = "/tmp/shape-tree-wayland-\(UUID().uuidString)"
    let address = try SocketAddress(unixDomainSocketPath: path)
    let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_CLOEXEC.rawValue), 0)
    guard fd >= 0 else { throw WaylandError.connection }
    listener = WireDescriptor(taking: fd)
    let result = unsafe address.withSockAddr { unsafe Glibc.bind(fd, $0, socklen_t($1)) }
    guard result == 0, listen(fd, 1) == 0 else { throw WaylandError.connection }
  }
  deinit { _ = unsafe unlink(path) }
  func accept() throws -> WireDescriptor {
    let fd = listener.borrow { Glibc.accept($0, nil, nil) }
    guard fd >= 0 else { throw WaylandError.connection }
    return WireDescriptor(taking: fd)
  }
}

@Test(arguments: [false, true]) @MainActor func startupCancellationNeverBlocksMainActor(
  waitForConfigure: Bool
)
  async throws
{
  let peer = try StartupPeer()
  let (ready, signal) = AsyncStream<Void>.makeStream()
  let server = blockingTestTask { () throws -> Void in
    defer { signal.finish() }
    let client = try peer.accept()
    defer { client.close() }
    do {
      var pending = ByteBufferAllocator().buffer(capacity: 4096)
      var synchronized = 0
      var waiting = false
      while !waiting {
        var scratch = [UInt8](repeating: 0, count: 4096)
        let count = client.borrow { unsafe recv($0, &scratch, scratch.count, 0) }
        guard count > 0 else { throw WaylandError.connection }
        pending.writeBytes(scratch.prefix(count))
        while pending.readableBytes >= 8 {
          let start = pending.readerIndex
          let id: UInt32 = pending.getInteger(at: start, endianness: .host)!
          let header: UInt32 = pending.getInteger(at: start + 4, endianness: .host)!
          let size = Int(header >> 16)
          if pending.readableBytes < size { break }
          if id == 1, header & 0xffff == 1 {
            let registry: UInt32 = pending.getInteger(at: start + 8, endianness: .host)!
            for (name, interface): (UInt32, String) in [(1, "wl_compositor"), (2, "xdg_wm_base")] {
              let packet = try WirePacket(
                object: registry, opcode: 0, arguments: [.uint(name), .string(interface), .uint(6)])
              _ = client.borrow { fd in
                unsafe packet.bytes.withUnsafeReadableBytes {
                  unsafe cwl_send(fd, $0.baseAddress, $0.count, nil, 0)
                }
              }
            }
          } else if id == 1, header & 0xffff == 0 {
            if !waitForConfigure {
              waiting = true
              break
            }
            let callback: UInt32 = pending.getInteger(at: start + 8, endianness: .host)!
            let packet = try WirePacket(object: callback, opcode: 0, arguments: [.uint(1)])
            _ = client.borrow { fd in
              unsafe packet.bytes.withUnsafeReadableBytes {
                unsafe cwl_send(fd, $0.baseAddress, $0.count, nil, 0)
              }
            }
            synchronized += 1
          } else if synchronized == 2, header & 0xffff == 6 {
            waiting = true
          }
          pending.moveReaderIndex(forwardBy: size)
        }
      }
    }
    signal.yield(())
    var byte: UInt8 = 0
    while client.borrow({ unsafe recv($0, &byte, 1, 0) }) > 0 {}
  }
  let connection = WaylandConnection(configuration: .init())
  defer { connection.cleanup() }
  let session = Task { try await connection.connect(path: peer.path) }
  defer { session.cancel() }
  var phases = ready.makeAsyncIterator()
  try #require(await phases.next() != nil)
  #expect(connection.running && !connection.configured)
  session.cancel()
  do {
    try await session.value
    Issue.record("Expected startup cancellation")
  } catch { #expect(error is CancellationError) }
  #expect(!connection.running && !connection.configured)
  try await server.value
  connection.cleanup()
}

@Test @MainActor func connectionRejectsInvalidConfigurationsBeforeOpeningSocket() async {
  for configuration in [
    WaylandWindowConfiguration(width: 0), .init(height: -1), .init(minimumWidth: -1),
    .init(topBarOverlayHeight: .max)
  ] {
    let connection = WaylandConnection(configuration: configuration)
    await #expect(throws: WaylandError.invalidConfiguration) { try await connection.connect() }
    connection.cleanup()
    connection.cleanup()
  }
}

@Test @MainActor func closedConnectionRejectsDispatchAndKeepsInputInert() async {
  let connection = WaylandConnection(configuration: .init())
  connection.cleanup()
  connection.cleanup()
  await #expect(throws: WaylandError.connection) { try await connection.connect() }
  await #expect(throws: WaylandError.connection) { try await connection.dispatchAsync() }
  #expect(throws: WaylandError.connection) { try connection.endFrame() }
  connection.requestRedraw()
  _ = connection.beginFrame()
  #expect(!connection.canRender && !connection.running && !connection.frameReady)
}
