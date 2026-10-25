import CWaylandTestSupport
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

struct ConnectionPeer: Sendable {
  let socket: WireDescriptor
  var bytes = ByteBufferAllocator().buffer(capacity: 4096)
  var registry: UInt32 = 0
  var shell: UInt32 = 0
  var surface: UInt32 = 0
  var xdgSurface: UInt32 = 0
  var toplevel: UInt32 = 0
  var dmabuf: UInt32 = 0
  var seat: UInt32 = 0
  var pointer: UInt32 = 0
  var idleManager: UInt32 = 0
  var fractionalManager: UInt32 = 0
  var viewporter: UInt32 = 0
  var fractional: UInt32 = 0
  var viewport: UInt32 = 0

  static func pair() throws -> (Int32, ConnectionPeer) {
    var fds: [Int32] = [-1, -1]
    try #require(
      unsafe socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue | SOCK_CLOEXEC.rawValue), 0, &fds) == 0)
    let client = WireDescriptor(taking: fds[0])
    let server = WireDescriptor(taking: fds[1])
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    try #require(
      unsafe setsockopt(
        fds[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
    return (client.take(), ConnectionPeer(socket: server))
  }

  func send(_ object: UInt32, _ opcode: UInt16, _ arguments: [WireValue] = []) throws {
    let packet = try WirePacket(object: object, opcode: opcode, arguments: arguments)
    let fds = packet.descriptors.map { $0.borrow { $0 } }
    let count = socket.borrow { fd in
      unsafe packet.bytes.withUnsafeReadableBytes { bytes in
        fds.withUnsafeBufferPointer {
          unsafe cwl_send(fd, bytes.baseAddress, bytes.count, $0.baseAddress, $0.count)
        }
      }
    }
    try #require(count == packet.bytes.readableBytes)
  }

  mutating func next() throws -> (id: UInt32, opcode: UInt16, body: ByteBuffer) {
    while true {
      let start = bytes.readerIndex
      if let header: UInt32 = bytes.getInteger(at: start + 4, endianness: .host) {
        let size = Int(header >> 16)
        try #require(size >= 8)
        if bytes.readableBytes >= size {
          let id: UInt32 = bytes.readInteger(endianness: .host)!
          bytes.moveReaderIndex(forwardBy: 4)
          return (id, UInt16(truncatingIfNeeded: header), bytes.readSlice(length: size - 8)!)
        }
      }
      var scratch = [UInt8](repeating: 0, count: 4096)
      let count = socket.borrow { unsafe recv($0, &scratch, scratch.count, 0) }
      try #require(count > 0)
      bytes.writeBytes(scratch.prefix(count))
    }
  }

  mutating func configure(
    dmabufVersion: UInt32 = 3, scaleGlobals: [String] = [], preferredScale: UInt32 = 150,
    seatVersion: UInt32 = 6, omittingGlobals: Set<String> = []
  ) throws {
    var compositor: UInt32 = 0
    while true {
      var request = try next()
      let first: UInt32? = request.body.readInteger(endianness: .host)
      switch (request.id, request.opcode) {
      case (1, 1):
        registry = try #require(first)
        for (name, interface): (UInt32, String) in [
          (1, "wl_compositor"), (2, "xdg_wm_base"), (3, "zwp_linux_dmabuf_v1"), (4, "wl_seat"),
          (5, "zwp_idle_inhibit_manager_v1")
        ] where !omittingGlobals.contains(interface) {
          try send(
            registry, 0,
            [
              .uint(name), .string(interface),
              .uint(name == 3 ? dmabufVersion : (name == 4 ? seatVersion : 6))
            ])
        }
        for (index, interface) in scaleGlobals.enumerated() {
          try send(registry, 0, [.uint(UInt32(index + 6)), .string(interface), .uint(1)])
        }
      case (1, 0):
        let callback = try #require(first)
        try send(callback, 0, [.uint(1)])
        try send(1, 1, [.uint(callback)])
      case (registry, 0):
        let id: UInt32 = try #require(
          request.body.getInteger(at: request.body.writerIndex - 4, endianness: .host))
        switch first {
        case 1: compositor = id
        case 2: shell = id
        case 5: idleManager = id
        case 4:
          seat = id
          try send(seat, 0, [.uint(1)])
        case 3:
          dmabuf = id
          if dmabufVersion == 3 {
            try send(dmabuf, 1, [.uint(0x3432_5241), .uint(0), .uint(0)])
          }
        default:
          if let first, first >= 6, Int(first - 6) < scaleGlobals.count {
            if scaleGlobals[Int(first - 6)] == "wp_viewporter" { viewporter = id }
            if scaleGlobals[Int(first - 6)] == "wp_fractional_scale_manager_v1" {
              fractionalManager = id
            }
          }
        }
      case (fractionalManager, 1): fractional = try #require(first)
      case (viewporter, 1): viewport = try #require(first)
      case (dmabuf, 2), (dmabuf, 3):
        try sendFeedback(try #require(first), device: 123)
      case (seat, 0): pointer = try #require(first)
      case (compositor, 0): surface = try #require(first)
      case (shell, 2): xdgSurface = try #require(first)
      case (xdgSurface, 1): toplevel = try #require(first)
      case (surface, 6):
        if fractional != 0 { try send(fractional, 0, [.uint(preferredScale)]) }
        try send(toplevel, 0, [.int(100), .int(80), .array(ByteBuffer())])
        try send(xdgSurface, 0, [.uint(1)])
        return
      default: break
      }
    }
  }

  func sendFeedback(_ id: UInt32, device: UInt64) throws {
    let table = try tableEvent([.init(format: 0x3432_5241, modifier: 0)], id: id)
    try send(id, table.opcode, table.arguments)
    try send(id, 2, [deviceBytes(device)])
    for event in trancheEvents(device: device, indices: [0], id: id) {
      try send(id, event.opcode, event.arguments)
    }
    try send(id, 0)
  }

  mutating func throughSync() throws -> (
    callback: UInt32, requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)]
  ) {
    var requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)] = []
    while true {
      let request = try next()
      if request.id == 1, request.opcode == 0 {
        let callback: UInt32 = try #require(
          request.body.getInteger(at: request.body.readerIndex, endianness: .host))
        return (callback, requests)
      }
      requests.append(request)
    }
  }

  mutating func throughPong() throws -> [(id: UInt32, opcode: UInt16, body: ByteBuffer)] {
    var requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)] = []
    while true {
      let request = try next()
      if request.id == shell, request.opcode == 3 { return requests }
      requests.append(request)
    }
  }
}

@MainActor func connectedPeer(
  dmabufVersion: UInt32 = 3, scaleGlobals: [String] = [], preferredScale: UInt32 = 150,
  seatVersion: UInt32 = 6, omittingGlobals: Set<String> = []
) async throws -> (
  WaylandConnection, ConnectionPeer, Int32
) {
  let (fd, peer) = try ConnectionPeer.pair()
  let server = blockingTestTask {
    var peer = peer
    do {
      try peer.configure(
        dmabufVersion: dmabufVersion, scaleGlobals: scaleGlobals, preferredScale: preferredScale,
        seatVersion: seatVersion, omittingGlobals: omittingGlobals)
      return peer
    } catch {
      peer.socket.close()
      throw error
    }
  }
  let connection = WaylandConnection(configuration: .init(width: 100, height: 80))
  do {
    try await connection.connect(path: nil, environment: ["WAYLAND_SOCKET": String(fd)])
    return (connection, try await server.value, fd)
  } catch {
    connection.cleanup()
    throw error
  }
}

@MainActor func drain(_ connection: WaylandConnection, _ peer: inout ConnectionPeer)
  async throws
  -> [(id: UInt32, opcode: UInt16, body: ByteBuffer)]
{
  try connection.receive(.init(object: peer.shell, opcode: 0, arguments: [.uint(99)]))
  let snapshot = peer
  let (updated, requests) = try await blockingTestTask {
    var peer = snapshot
    let requests = try peer.throughPong()
    return (peer, requests)
  }.value
  peer = updated
  return requests
}

@MainActor func configurePopup(
  _ connection: WaylandConnection, _ peer: inout ConnectionPeer
) async throws -> (surface: UInt32, xdg: UInt32, popup: UInt32) {
  try connection.presentPopup(
    configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 40, height: 30),
    grab: false)
  let requests = try await drain(connection, &peer)
  let request = try #require(requests.first { $0.id == peer.shell && $0.opcode == 2 })
  let xdg: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex, endianness: .host))
  let surface: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex + 4, endianness: .host))
  let role = try #require(requests.first { $0.id == xdg && $0.opcode == 2 })
  let popup: UInt32 = try #require(
    role.body.getInteger(at: role.body.readerIndex, endianness: .host))
  try connection.receive(.init(object: xdg, opcode: 0, arguments: [.uint(2)]))
  return (surface, xdg, popup)
}

func frameCallback(
  in requests: [(id: UInt32, opcode: UInt16, body: ByteBuffer)], on surface: UInt32
) throws -> UInt32 {
  let request = try #require(requests.first { $0.id == surface && $0.opcode == 3 })
  return try #require(request.body.getInteger(at: request.body.readerIndex, endianness: .host))
}
