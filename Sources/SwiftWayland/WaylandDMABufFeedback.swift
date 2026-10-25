import Glibc
import NIOCore

public struct WaylandDMABufFormat: Sendable, Hashable {
  public let format: UInt32
  public let modifier: UInt64

  public init(format: UInt32, modifier: UInt64) {
    self.format = format
    self.modifier = modifier
  }
}

public struct WaylandDMABufFeedback: Sendable, Equatable {
  public struct Tranche: Sendable, Equatable {
    public let device: UInt64?
    public let flags: UInt32
    public let formats: [WaylandDMABufFormat]
  }

  // nil identifies v3 announcements, which do not specify a device.
  public let mainDevice: UInt64?
  public let tranches: [Tranche]

  public func supports(format: UInt32, modifier: UInt64) -> Bool {
    let pair = WaylandDMABufFormat(format: format, modifier: modifier)
    return tranches.contains { $0.formats.contains(pair) }
  }
}

@MainActor final class DMABufFeedback {
  let id: UInt32
  private(set) var current: WaylandDMABufFeedback?
  private var table: [WaylandDMABufFormat] = []
  private var mainDevice: UInt64?
  private var tranches: [WaylandDMABufFeedback.Tranche] = []
  private var device: UInt64?
  private var flags: UInt32?
  private var formats: [WaylandDMABufFormat] = []
  private var formatCount = 0

  init(id: UInt32) { self.id = id }

  // Publish only at done. The format table survives subsequent feedback batches.
  func event(_ message: WireMessage) throws -> Bool {
    let a = message.arguments
    switch message.opcode {
    case 0:
      guard let mainDevice, !tranches.isEmpty, device == nil, flags == nil, formats.isEmpty else {
        throw WaylandError.dispatch
      }
      current = WaylandDMABufFeedback(mainDevice: mainDevice, tranches: tranches)
      self.mainDevice = nil
      tranches.removeAll(keepingCapacity: true)
      formatCount = 0
      return true
    case 1:
      guard case .fd(let fd) = a[0] else { throw WaylandError.dispatch }
      defer { fd.close() }
      table = try fd.borrow { try Self.readTable(fd: $0, size: a[1].word) }
    case 2:
      guard mainDevice == nil else { throw WaylandError.dispatch }
      mainDevice = try Self.device(a[0])
    case 3:
      guard let device, let flags, !formats.isEmpty, tranches.count < 256 else {
        throw WaylandError.dispatch
      }
      tranches.append(.init(device: device, flags: flags, formats: formats))
      self.device = nil
      self.flags = nil
      formats = []
    case 4:
      guard device == nil else { throw WaylandError.dispatch }
      device = try Self.device(a[0])
    case 5:
      guard case .array(var indices) = a[0], indices.readableBytes % 2 == 0,
        indices.readableBytes / 2 <= 65_536 - formatCount
      else { throw WaylandError.dispatch }
      while let index: UInt16 = indices.readInteger(endianness: .host) {
        guard Int(index) < table.count else { throw WaylandError.dispatch }
        formats.append(table[Int(index)])
        formatCount += 1
      }
    case 6:
      guard flags == nil else { throw WaylandError.dispatch }
      flags = a[0].word
    default: throw WaylandError.dispatch
    }
    return false
  }

  private static func device(_ value: WireValue) throws -> UInt64 {
    guard case .array(let bytes) = value, bytes.readableBytes == MemoryLayout<dev_t>.size,
      let device: dev_t = bytes.getInteger(at: bytes.readerIndex, endianness: .host)
    else { throw WaylandError.dispatch }
    return UInt64(device)
  }

  private static func readTable(fd: Int32, size: UInt32) throws -> [WaylandDMABufFormat] {
    guard size > 0, size % 16 == 0, size <= 65_536 * 16 else { throw WaylandError.dispatch }
    var info = stat()
    guard unsafe fstat(fd, &info) == 0, info.st_size >= Int64(size),
      let mapping = unsafe mmap(nil, Int(size), PROT_READ, MAP_PRIVATE, fd, 0),
      unsafe mapping != MAP_FAILED
    else { throw WaylandError.dispatch }
    defer { _ = unsafe munmap(mapping, Int(size)) }
    var result: [WaylandDMABufFormat] = []
    result.reserveCapacity(Int(size) / 16)
    for offset in stride(from: 0, to: Int(size), by: 16) {
      result.append(
        .init(
          format: unsafe mapping.loadUnaligned(fromByteOffset: offset, as: UInt32.self),
          modifier: unsafe mapping.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self)))
    }
    return result
  }
}
