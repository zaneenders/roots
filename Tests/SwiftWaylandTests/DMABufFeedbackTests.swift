import Foundation
import Glibc
import NIOCore
import Testing

@testable import SwiftWayland

func deviceBytes(_ device: UInt64) -> WireValue {
  var bytes = ByteBuffer()
  bytes.writeInteger(dev_t(device), endianness: .host)
  return .array(bytes)
}

func tableEvent(
  _ pairs: [WaylandDMABufFormat], id: UInt32, size: UInt32? = nil
) throws -> (WireMessage, Int32) {
  var bytes = ByteBuffer()
  for pair in pairs {
    bytes.writeInteger(pair.format, endianness: .host)
    bytes.writeInteger(UInt32(0), endianness: .host)
    bytes.writeInteger(pair.modifier, endianness: .host)
  }
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try Data(bytes.readableBytesView).write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  let fd = unsafe open(path.path, O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  return (
    .init(
      object: id, opcode: 1,
      arguments: [
        .fd(WireDescriptor(taking: fd)), .uint(size ?? UInt32(bytes.readableBytes)),
      ]), fd
  )
}

func trancheEvents(
  device: UInt64, indices: [UInt16], flags: UInt32 = 0, id: UInt32
) -> [WireMessage] {
  var bytes = ByteBuffer()
  for index in indices { bytes.writeInteger(index, endianness: .host) }
  return [
    .init(object: id, opcode: 4, arguments: [deviceBytes(device)]),
    .init(object: id, opcode: 6, arguments: [.uint(flags)]),
    .init(object: id, opcode: 5, arguments: [.array(bytes)]),
    .init(object: id, opcode: 3, arguments: []),
  ]
}

@Test @MainActor func feedbackPublishesAtomicallyAndReusesTableAcrossUpdates() throws {
  let feedback = DMABufFeedback(id: 2)
  let pairs: [WaylandDMABufFormat] = [
    .init(format: 0x3432_5241, modifier: 9), .init(format: 0x3432_4241, modifier: 0),
  ]
  let (table, _) = try tableEvent(pairs, id: 2)
  #expect(try !feedback.event(table))
  guard case .fd(let owner) = table.arguments[0] else {
    Issue.record("Missing table FD")
    return
  }
  #expect(owner.borrow { $0 } == -1)
  #expect(try !feedback.event(.init(object: 2, opcode: 2, arguments: [deviceBytes(123)])))
  for message in trancheEvents(device: 456, indices: [1], flags: 1, id: 2)
    + trancheEvents(device: 123, indices: [0, 1], id: 2)
  { #expect(try !feedback.event(message)) }
  #expect(feedback.current == nil)
  #expect(try feedback.event(.init(object: 2, opcode: 0, arguments: [])))
  let first = try #require(feedback.current)
  #expect(first.mainDevice == 123)
  #expect(first.tranches.map(\.device) == [456, 123])
  #expect(first.tranches.map(\.flags) == [1, 0])
  #expect(first.tranches[0].formats == [pairs[1]])
  #expect(first.supports(format: pairs[0].format, modifier: 9))
  #expect(!first.supports(format: pairs[0].format, modifier: 0))

  _ = try feedback.event(.init(object: 2, opcode: 2, arguments: [deviceBytes(789)]))
  for message in trancheEvents(device: 789, indices: [1], id: 2) {
    _ = try feedback.event(message)
  }
  #expect(feedback.current == first)
  _ = try feedback.event(.init(object: 2, opcode: 0, arguments: []))
  #expect(feedback.current?.mainDevice == 789)
  #expect(feedback.current?.tranches.count == 1)
  #expect(feedback.current?.supports(format: pairs[0].format, modifier: 9) == false)
}

@Test(arguments: [UInt32(0), 15, 17, 32, 1_048_592])
@MainActor func feedbackRejectsInvalidTableSizesAndClosesFD(size: UInt32) throws {
  let feedback = DMABufFeedback(id: 2)
  let (table, _) = try tableEvent([.init(format: 1, modifier: 2)], id: 2, size: size)
  #expect(throws: WaylandError.dispatch) { try feedback.event(table) }
  guard case .fd(let owner) = table.arguments[0] else {
    Issue.record("Missing table FD")
    return
  }
  #expect(owner.borrow { $0 } == -1)
  #expect(feedback.current == nil)
}

@Test @MainActor func feedbackRejectsInvalidIndicesDevicesAndIncompleteTranches() throws {
  let feedback = DMABufFeedback(id: 2)
  let (table, _) = try tableEvent([.init(format: 1, modifier: 0)], id: 2)
  _ = try feedback.event(table)
  #expect(throws: WaylandError.dispatch) {
    try feedback.event(.init(object: 2, opcode: 2, arguments: [.array(ByteBuffer(bytes: [1]))]))
  }
  #expect(throws: WaylandError.dispatch) {
    try feedback.event(.init(object: 2, opcode: 5, arguments: [.array(ByteBuffer(bytes: [0]))]))
  }
  for event in trancheEvents(device: 123, indices: [1], id: 2).prefix(2) {
    _ = try feedback.event(event)
  }
  #expect(throws: WaylandError.dispatch) {
    try feedback.event(trancheEvents(device: 123, indices: [1], id: 2)[2])
  }
  #expect(throws: WaylandError.dispatch) {
    try feedback.event(.init(object: 2, opcode: 0, arguments: []))
  }
  #expect(throws: WaylandError.dispatch) {
    try feedback.event(.init(object: 2, opcode: 3, arguments: []))
  }
  #expect(feedback.current == nil)
}

@Test @MainActor func surfaceFeedbackOverridesDefaultAndRetirementIgnoresLateUpdates() throws {
  let objects = WaylandObjects()
  let dmabuf = WaylandDMABuf(objects: objects)
  dmabuf.factory = objects.allocate("zwp_linux_dmabuf_v1", version: 4)
  dmabuf.version = 4
  dmabuf.watch()
  dmabuf.watch(surface: 42)
  dmabuf.watch(surface: 42)
  let requests = try objects.takeRequests()
  #expect(requests.count == 2)
  let ids = requests.map { $0.bytes.getInteger(at: 8, endianness: .host, as: UInt32.self)! }
  for (index, id) in ids.enumerated() {
    let (table, _) = try tableEvent([.init(format: 1, modifier: UInt64(index))], id: id)
    _ = try dmabuf.feedbackEvent(table)
    _ = try dmabuf.feedbackEvent(.init(object: id, opcode: 2, arguments: [deviceBytes(123)]))
    for event in trancheEvents(device: 123, indices: [0], id: id) {
      _ = try dmabuf.feedbackEvent(event)
    }
    if index == 1 { #expect(dmabuf.preferences(surface: 42) == dmabuf.preferences()) }
    _ = try dmabuf.feedbackEvent(.init(object: id, opcode: 0, arguments: []))
  }
  #expect(dmabuf.preferences()?.supports(format: 1, modifier: 0) == true)
  #expect(dmabuf.preferences(surface: 42)?.supports(format: 1, modifier: 1) == true)
  let fd = unsafe open("/dev/null", O_RDONLY | O_CLOEXEC)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  let planes = [WaylandDMABufPlane(descriptor: fd, offset: 0, stride: 16)]
  #expect(throws: WaylandError.missingGlobals) {
    try dmabuf.importBuffer(
      width: 4, height: 4, format: 1, modifier: 0, planes: planes.span, surface: 42, changed: {})
  }
  #expect(try objects.takeRequests().isEmpty)
  let buffer = try dmabuf.importBuffer(
    width: 4, height: 4, format: 1, modifier: 1, planes: planes.span, surface: 42, changed: {})
  #expect(buffer.state == .importing)
  dmabuf.event(.init(object: buffer.params, opcode: 1, arguments: []))
  #expect(buffer.state == .failed)
  buffer.close()
  dmabuf.removeFactory()
  #expect(dmabuf.preferences()?.supports(format: 1, modifier: 0) == true)
  #expect(dmabuf.preferences(surface: 42)?.supports(format: 1, modifier: 1) == true)
  #expect(!dmabuf.canImport(surface: 42))
  dmabuf.unwatch(surface: 42)
  #expect(!objects.isLive(ids[1]))
  #expect(try !dmabuf.feedbackEvent(.init(object: ids[1], opcode: 0, arguments: [])))
  #expect(dmabuf.preferences(surface: 42) == dmabuf.preferences())
  dmabuf.close()
  #expect(dmabuf.preferences() == nil)
}

@Test @MainActor func versionThreeUsesOnlyAdvertisedFormatModifierPairs() throws {
  let objects = WaylandObjects()
  let dmabuf = WaylandDMABuf(objects: objects)
  dmabuf.factory = objects.allocate("zwp_linux_dmabuf_v1")
  dmabuf.modifier(format: 1, high: 2, low: 3)
  dmabuf.watch()
  #expect(try objects.takeRequests().isEmpty)
  let feedback = try #require(dmabuf.preferences())
  #expect(feedback.mainDevice == nil)
  #expect(feedback.supports(format: 1, modifier: UInt64(2) << 32 | 3))
  #expect(!feedback.supports(format: 1, modifier: 0))
}

@Test @MainActor func feedbackReplacesTablesWithoutPublishingPartialBatches() throws {
  let feedback = DMABufFeedback(id: 2)
  for modifier: UInt64 in [0, 42] {
    let before = feedback.current
    let (table, _) = try tableEvent([.init(format: 1, modifier: modifier)], id: 2)
    _ = try feedback.event(table)
    _ = try feedback.event(.init(object: 2, opcode: 2, arguments: [deviceBytes(123)]))
    for event in trancheEvents(device: 123, indices: [0], id: 2) {
      _ = try feedback.event(event)
    }
    #expect(feedback.current == before)
    _ = try feedback.event(.init(object: 2, opcode: 0, arguments: []))
    #expect(feedback.current?.tranches[0].formats == [.init(format: 1, modifier: modifier)])
  }
}
