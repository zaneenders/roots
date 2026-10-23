#if os(Linux)
import Foundation
import Glibc
import NIOCore
import NIOPosix

@MainActor public enum WaylandAvailability {
  private static let globals = Task { try await detectGlobals() }
  private enum ProbeError: Error { case invalidReply, timeout }

  public static var compositor: Bool {
    get async throws {
      let globals = try await globals.value
      return globals["wl_compositor", default: 0] >= 3 && globals["xdg_wm_base", default: 0] >= 1
    }
  }

  public static var presentation: Bool {
    get async throws {
      guard try await compositor else { return false }
      let globals = try await globals.value
      return globals["zwp_linux_dmabuf_v1", default: 0] >= 3 && EGLAvailability.canExportDMABuf
    }
  }

  public static var layerPresentation: Bool {
    get async throws {
      guard try await presentation else { return false }
      return try await globals.value["zwlr_layer_shell_v1", default: 0] >= 1
    }
  }

  private static func detectGlobals() async throws -> [String: UInt32] {
    let environment = ProcessInfo.processInfo.environment
    let display = environment["WAYLAND_DISPLAY"] ?? "wayland-0"
    let path: String
    if display.hasPrefix("/") {
      path = display
    } else {
      guard let directory = environment["XDG_RUNTIME_DIR"] else { return [:] }
      path = directory + "/" + display
    }
    let channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    do {
      channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .connectTimeout(.seconds(5))
        .connect(unixDomainSocketPath: path) { channel in
          channel.eventLoop.makeCompletedFuture {
            try NIOAsyncChannel(wrappingChannelSynchronously: channel)
          }
        }
    } catch let error as IOError where [ENOENT, ECONNREFUSED, EACCES].contains(error.errnoCode) {
      return [:]
    }
    return try await channel.executeThenClose { inbound, outbound in
      var request = ByteBuffer()
      for word: UInt32 in [1, 12 << 16 | 1, 2, 1, 12 << 16, 3] {
        request.writeInteger(word, endianness: .host)
      }
      try await outbound.write(request)
      return try await withThrowingTaskGroup(of: [String: UInt32].self) { group in
        group.addTask {
          var globals: [String: UInt32] = [:]
          var pending = ByteBuffer()
          for try await var bytes in inbound {
            pending.writeBuffer(&bytes)
            guard pending.readableBytes <= 1024 * 1024 else { throw ProbeError.invalidReply }
            while pending.readableBytes >= 8 {
              let start = pending.readerIndex
              let object: UInt32 = pending.getInteger(at: start, endianness: .host)!
              let header: UInt32 = pending.getInteger(at: start + 4, endianness: .host)!
              let size = Int(header >> 16)
              guard size >= 8, size % 4 == 0 else { throw ProbeError.invalidReply }
              guard pending.readableBytes >= size else { break }
              if object == 3, header & 0xffff == 0 { return globals }
              guard object == 2, header & 0xffff == 0, size >= 20,
                let count: UInt32 = pending.getInteger(at: start + 12, endianness: .host),
                count > 0, Int(count) <= size - 20,
                let name = pending.getString(at: start + 16, length: Int(count) - 1),
                let version: UInt32 = pending.getInteger(at: start + size - 4, endianness: .host)
              else { throw ProbeError.invalidReply }
              globals[name] = max(globals[name, default: 0], version)
              pending.moveReaderIndex(forwardBy: size)
            }
            pending.discardReadBytes()
          }
          throw ProbeError.invalidReply
        }
        group.addTask {
          try await Task.sleep(for: .seconds(5))
          throw ProbeError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
      }
    }
  }
}
#endif
