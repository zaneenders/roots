import Foundation
import Glibc
import NIOCore
import Synchronization

final class WireDescriptor: Sendable {
  private let value: Mutex<Int32>
  init(taking fd: Int32) { value = Mutex(fd) }
  deinit { close() }
  func close() {
    let fd = take()
    if fd >= 0 { _ = Glibc.close(fd) }
  }
  func take() -> Int32 {
    value.withLock {
      let fd = $0
      $0 = -1
      return fd
    }
  }
  func borrow<T>(_ body: (Int32) throws -> T) rethrows -> T { try value.withLock { try body($0) } }
  static func duplicate(_ fd: Int32) throws -> WireDescriptor {
    let copy = fcntl(fd, F_DUPFD_CLOEXEC, 0)
    guard copy >= 0 else { throw WaylandError.dispatch }
    return WireDescriptor(taking: copy)
  }
}

enum WireValue: Sendable {
  case uint(UInt32)
  case int(Int32)
  case string(String?)
  case array(ByteBuffer)
  case fd(WireDescriptor)
  var word: UInt32 {
    switch self {
    case .uint(let v): v
    case .int(let v): UInt32(bitPattern: v)
    default: 0
    }
  }
  var signed: Int32 { Int32(bitPattern: word) }
  var text: String? { if case .string(let s) = self { s } else { nil } }
}

struct WireMessage: Sendable {
  let object: UInt32
  let opcode: UInt16
  let arguments: [WireValue]
}

struct WirePacket: Sendable {
  var bytes: ByteBuffer
  var descriptors: [WireDescriptor]

  init(object: UInt32, opcode: UInt16, arguments: [WireValue]) throws {
    bytes = ByteBufferAllocator().buffer(capacity: 64)
    descriptors = []
    bytes.writeInteger(object, endianness: .host)
    bytes.writeInteger(UInt32(0), endianness: .host)
    for argument in arguments {
      switch argument {
      case .uint(let value): bytes.writeInteger(value, endianness: .host)
      case .int(let value): bytes.writeInteger(value, endianness: .host)
      case .string(let value):
        if let value {
          guard !value.utf8.contains(0), value.utf8.count < 65_000 else {
            throw WaylandError.invalidConfiguration
          }
          let count = value.utf8.count + 1
          bytes.writeInteger(UInt32(count), endianness: .host)
          bytes.writeString(value)
          bytes.writeInteger(UInt8(0))
          bytes.writeRepeatingByte(0, count: (4 - count % 4) % 4)
        } else {
          bytes.writeInteger(UInt32(0), endianness: .host)
        }
      case .array(var value):
        bytes.writeInteger(UInt32(value.readableBytes), endianness: .host)
        let count = value.readableBytes
        bytes.writeBuffer(&value)
        bytes.writeRepeatingByte(0, count: (4 - count % 4) % 4)
      case .fd(let fd): descriptors.append(fd)
      }
    }
    guard bytes.readableBytes <= 65_532 else { throw WaylandError.invalidConfiguration }
    bytes.setInteger(UInt32(bytes.readableBytes) << 16 | UInt32(opcode), at: 4, endianness: .host)
  }
}

struct WireDecoder {
  private var bytes = ByteBufferAllocator().buffer(capacity: 4096)
  private var descriptors: [WireDescriptor] = []
  private var descriptorIndex = 0

  mutating func append(_ incoming: inout ByteBuffer, descriptors: [WireDescriptor]) throws {
    guard bytes.readableBytes + incoming.readableBytes <= 1024 * 1024,
      self.descriptors.count - descriptorIndex + descriptors.count <= 256
    else { throw WaylandError.dispatch }
    bytes.writeBuffer(&incoming)
    self.descriptors.append(contentsOf: descriptors)
  }

  mutating func next(
    interfaces: [UInt32: String] = [1: "wl_display"], versions: [UInt32: UInt32] = [:]
  ) throws -> WireMessage? {
    let start = bytes.readerIndex
    guard let object: UInt32 = bytes.getInteger(at: start, endianness: .host),
      let header: UInt32 = bytes.getInteger(at: start + 4, endianness: .host)
    else { return nil }
    let length = Int(header >> 16)
    let opcode = UInt16(truncatingIfNeeded: header)
    guard length >= 8, length % 4 == 0, let interface = interfaces[object],
      let events = WireSchema.events[interface], Int(opcode) < events.count,
      events[Int(opcode)].since <= (versions[object] ?? 1)
    else { throw WaylandError.dispatch }
    guard bytes.readableBytes >= length else { return nil }
    let signature = events[Int(opcode)].signature
    let fdCount = signature.filter { $0 == "h" }.count
    guard descriptors.count - descriptorIndex >= fdCount else { return nil }
    var body = bytes.getSlice(at: start + 8, length: length - 8)!
    var arguments: [WireValue] = []
    for type in signature {
      switch type {
      case "h":
        arguments.append(.fd(descriptors[descriptorIndex]))
        descriptorIndex += 1
      case "u", "i":
        guard let word: UInt32 = body.readInteger(endianness: .host) else {
          throw WaylandError.dispatch
        }
        arguments.append(type == "u" ? .uint(word) : .int(Int32(bitPattern: word)))
      case "s", "a":
        guard let raw: UInt32 = body.readInteger(endianness: .host),
          raw <= UInt32(body.readableBytes)
        else {
          throw WaylandError.dispatch
        }
        let count = Int(raw)
        let padding = (4 - count % 4) % 4
        guard body.readableBytes >= count + padding, let value = body.readSlice(length: count)
        else {
          throw WaylandError.dispatch
        }
        body.moveReaderIndex(forwardBy: padding)
        if type == "a" {
          arguments.append(.array(value))
        } else if count == 0 {
          arguments.append(.string(nil))
        } else {
          guard value.getInteger(at: value.readerIndex + count - 1, as: UInt8.self) == 0,
            let utf8 = value.getBytes(at: value.readerIndex, length: count - 1),
            let string = String(bytes: utf8, encoding: .utf8), !string.utf8.contains(0)
          else { throw WaylandError.dispatch }
          arguments.append(.string(string))
        }
      default: throw WaylandError.dispatch
      }
    }
    guard body.readableBytes == 0 else { throw WaylandError.dispatch }
    bytes.moveReaderIndex(forwardBy: length)
    if descriptorIndex > 0 {
      descriptors.removeFirst(descriptorIndex)
      descriptorIndex = 0
    }
    if bytes.readerIndex > 65_536 { bytes.discardReadBytes() }
    return WireMessage(object: object, opcode: opcode, arguments: arguments)
  }
}
