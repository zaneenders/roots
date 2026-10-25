import NIOCore
import Testing

@testable import SwiftWayland

@Test @MainActor func feedbackPublishesAtomicallyAndReusesTableAcrossUpdates() throws {
  let feedback = DMABufFeedback(id: 2)
  let pairs: [WaylandDMABufFormat] = [
    .init(format: 0x3432_5241, modifier: 9), .init(format: 0x3432_4241, modifier: 0)
  ]
  let table = try tableEvent(pairs, id: 2)
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
  let table = try tableEvent([.init(format: 1, modifier: 2)], id: 2, size: size)
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
  let table = try tableEvent([.init(format: 1, modifier: 0)], id: 2)
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
    let table = try tableEvent([.init(format: 1, modifier: UInt64(index))], id: id)
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
  #expect(throws: WaylandError.missingGlobals) {
    try importTestBuffer(dmabuf, surface: 42)
  }
  #expect(try objects.takeRequests().isEmpty)
  let buffer = try importTestBuffer(dmabuf, modifier: 1, surface: 42)
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
    let table = try tableEvent([.init(format: 1, modifier: modifier)], id: 2)
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

@Test @MainActor func connectionNegotiatesV4FeedbackBeforeReturningAndWatchesPopup() async throws {
  let (connection, initialPeer, _) = try await connectedPeer(dmabufVersion: 4)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(connection.dmabufPreferences?.mainDevice == 123)
  #expect(connection.dmabufPreferences?.supports(format: 0x3432_5241, modifier: 0) == true)
  try connection.presentPopup(
    configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 40, height: 30),
    grab: false)
  let requests = try await drain(connection, &peer)
  let watch = try #require(requests.first { $0.id == peer.dmabuf && $0.opcode == 3 })
  let feedback: UInt32 = try #require(
    watch.body.getInteger(at: watch.body.readerIndex, endianness: .host))
  try peer.sendFeedback(feedback, device: 456)
  for _ in 0..<100 where connection.popupDMABufPreferences?.mainDevice != 456 {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(connection.popupDMABufPreferences?.mainDevice == 456)
  #expect(connection.dmabufPreferences?.mainDevice == 123)
  connection.dismissPopup()
  let destroyed = try await drain(connection, &peer)
  #expect(destroyed.contains { $0.id == feedback && $0.opcode == 0 })
}
