import NIOCore
import Testing

@testable import SwiftWayland

private let fractionalScaleGlobals = ["wp_fractional_scale_manager_v1", "wp_viewporter"]

@Test(
  arguments: [fractionalScaleGlobals, fractionalScaleGlobals.reversed().map { $0 }],
  [UInt32(120), 150, 180, 210, 240])
@MainActor func fractionalScaleNegotiatesInEitherGlobalOrder(
  globals: [String], preferredScale: UInt32
)
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer(
    scaleGlobals: globals, preferredScale: preferredScale)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(peer.fractional != 0 && peer.viewport != 0)
  #expect(connection.input.bufferScale == 1)
  #expect(connection.input.fractionalScale120 == preferredScale)
  #expect(connection.input.renderScale == Double(preferredScale) / 120)
  #expect(connection.input.width == 100 && connection.input.height == 80)
  _ = connection.beginFrame()
  try connection.endFrame()
  let requests = try await drain(connection, &peer)
  let destination = try #require(requests.first { $0.id == peer.viewport && $0.opcode == 2 })
  #expect(destination.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 100)
  #expect(destination.body.getInteger(at: 4, endianness: .host, as: Int32.self) == 80)
  #expect(
    requests.contains {
      $0.id == peer.surface && $0.opcode == 8
        && $0.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 1
    })
  #expect(!requests.contains { $0.id == peer.viewport && $0.opcode == 1 })

  try connection.receive(
    .init(
      object: peer.toplevel, opcode: 0,
      arguments: [.int(101), .int(77), .array(ByteBuffer())]))
  try connection.receive(.init(object: peer.xdgSurface, opcode: 0, arguments: [.uint(2)]))
  try connection.receive(.init(object: peer.fractional, opcode: 0, arguments: [.uint(180)]))
  let callback = try frameCallback(in: requests, on: peer.surface)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(3)]))
  #expect(connection.canRender && connection.input.renderScale == 1.5)
  _ = connection.beginFrame()
  try connection.endFrame()
  let resized = try await drain(connection, &peer)
  let size = try #require(resized.first { $0.id == peer.viewport && $0.opcode == 2 })
  #expect(size.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 101)
  #expect(size.body.getInteger(at: 4, endianness: .host, as: Int32.self) == 77)
}

@Test(arguments: [[], ["wp_viewporter"], ["wp_fractional_scale_manager_v1"]])
@MainActor func missingFractionalProtocolPreservesIntegerScaling(globals: [String]) async throws {
  let (connection, initialPeer, _) = try await connectedPeer(scaleGlobals: globals)
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(peer.fractional == 0 && peer.viewport == 0)
  try connection.receive(.init(object: peer.surface, opcode: 2, arguments: [.int(2)]))
  #expect(connection.input.fractionalScale120 == nil && connection.input.renderScale == 2)
  _ = connection.beginFrame()
  try connection.endFrame()
  let requests = try await drain(connection, &peer)
  #expect(
    requests.contains {
      $0.id == peer.surface && $0.opcode == 8
        && $0.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 2
    })
}

@Test @MainActor func fractionalScaleIsIndependentForEachSurfaceAndIgnoresIntegerPreferences()
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer(
    scaleGlobals: fractionalScaleGlobals)
  defer { connection.cleanup() }
  var peer = initialPeer
  _ = connection.beginFrame()
  try connection.presentPopup(
    configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 41, height: 31),
    grab: false)
  let requests = try await drain(connection, &peer)
  let fractionalRequest = try #require(
    requests.first { $0.id == peer.fractionalManager && $0.opcode == 1 })
  let fractional: UInt32 = try #require(fractionalRequest.body.getInteger(at: 0, endianness: .host))
  let viewportRequest = try #require(requests.first { $0.id == peer.viewporter && $0.opcode == 1 })
  let viewport: UInt32 = try #require(viewportRequest.body.getInteger(at: 0, endianness: .host))
  let surface: UInt32 = try #require(viewportRequest.body.getInteger(at: 4, endianness: .host))
  let xdgRequest = try #require(requests.first { $0.id == peer.shell && $0.opcode == 2 })
  let xdg: UInt32 = try #require(xdgRequest.body.getInteger(at: 0, endianness: .host))
  try connection.receive(.init(object: xdg, opcode: 0, arguments: [.uint(4)]))
  _ = connection.takePopupInput()
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(210)]))
  #expect(connection.canRenderPopup && !connection.redrawRequested)
  #expect(connection.popupInput?.renderScale == 1.75 && connection.input.renderScale == 1.25)
  #expect(connection.popupInput?.bufferScale == 1)
  _ = connection.takePopupInput()
  for (id, value): (UInt32, Int32) in [(surface, 3), (peer.surface, 2)] {
    try connection.receive(.init(object: id, opcode: 2, arguments: [.int(value)]))
  }
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(0)]))
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(210)]))
  #expect(!connection.canRenderPopup && !connection.redrawRequested)
  #expect(connection.popupInput?.renderScale == 1.75 && connection.input.renderScale == 1.25)
  try connection.endPopupFrame()
  let committed = try await drain(connection, &peer)
  #expect(
    committed.contains {
      $0.id == viewport && $0.opcode == 2
        && $0.body.getInteger(at: 0, endianness: .host, as: Int32.self) == 41
        && $0.body.getInteger(at: 4, endianness: .host, as: Int32.self) == 31
    })
  #expect(!committed.contains { $0.id == peer.viewport })
  connection.dismissPopup()
  let destroyed = try await drain(connection, &peer)
  let viewportDestroy = try #require(destroyed.firstIndex { $0.id == viewport && $0.opcode == 0 })
  let scaleDestroy = try #require(destroyed.firstIndex { $0.id == fractional && $0.opcode == 0 })
  let surfaceDestroy = try #require(destroyed.firstIndex { $0.id == surface && $0.opcode == 0 })
  #expect(viewportDestroy < surfaceDestroy && scaleDestroy < surfaceDestroy)
  _ = try await configurePopup(connection, &peer)
  _ = connection.takePopupInput()
  try connection.receive(.init(object: fractional, opcode: 0, arguments: [.uint(240)]))
  #expect(!connection.canRenderPopup && connection.popupInput?.fractionalScale120 == nil)
  #expect(connection.input.renderScale == 1.25)
}

@Test @MainActor func fractionalScaleObjectsSurviveManagerRemoval() async throws {
  let (connection, initialPeer, _) = try await connectedPeer(
    scaleGlobals: fractionalScaleGlobals)
  defer { connection.cleanup() }
  var peer = initialPeer
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(6)]))
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(7)]))
  try connection.receive(.init(object: peer.fractional, opcode: 0, arguments: [.uint(180)]))
  #expect(connection.input.renderScale == 1.5)
  _ = connection.beginFrame()
  try connection.endFrame()
  let requests = try await drain(connection, &peer)
  #expect(requests.contains { $0.id == peer.viewport && $0.opcode == 2 })
  #expect(requests.contains { $0.id == peer.fractionalManager && $0.opcode == 0 })
  #expect(requests.contains { $0.id == peer.viewporter && $0.opcode == 0 })
  #expect(!requests.contains { $0.id == peer.fractional && $0.opcode == 0 })
  _ = try await configurePopup(connection, &peer)
  #expect(connection.popupInput?.fractionalScale120 == nil)
}

@Test @MainActor func integerFallbackTracksEachSurfaceOutputAndFallsBackAfterRemoval() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  for name: UInt32 in [20, 21] {
    try connection.receive(
      .init(
        object: peer.registry, opcode: 0,
        arguments: [.uint(name), .string("wl_output"), .uint(3)]))
  }
  let requests = try await drain(connection, &peer)
  let outputRequests = requests.filter { $0.id == peer.registry && $0.opcode == 0 }
  #expect(outputRequests.count == 2)
  let outputs: [UInt32] = try outputRequests.map {
    try #require($0.body.getInteger(at: $0.body.writerIndex - 4, endianness: .host))
  }
  for (index, output) in outputs.enumerated() {
    try connection.receive(.init(object: output, opcode: 3, arguments: [.int(Int32(index + 2))]))
    try connection.receive(.init(object: output, opcode: 2, arguments: []))
  }
  try connection.receive(.init(object: peer.surface, opcode: 0, arguments: [.uint(outputs[0])]))
  #expect(connection.input.renderScale == 2 && connection.popupInput?.renderScale == 2)
  try connection.receive(.init(object: popup.surface, opcode: 0, arguments: [.uint(outputs[1])]))
  #expect(connection.input.renderScale == 2 && connection.popupInput?.renderScale == 3)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(21)]))
  #expect(connection.popupInput?.renderScale == 2)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(20)]))
  #expect(connection.input.renderScale == 1 && connection.popupInput?.renderScale == 1)
}

@Test @MainActor func lateFractionalGlobalsExtendExistingSurfacesWithoutDuplicatingObjects()
  async throws
{
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  try connection.receive(.init(object: peer.surface, opcode: 2, arguments: [.int(2)]))
  for (index, interface) in fractionalScaleGlobals.enumerated() {
    try connection.receive(
      .init(
        object: peer.registry, opcode: 0,
        arguments: [.uint(UInt32(index + 20)), .string(interface), .uint(1)]))
  }
  let requests = try await drain(connection, &peer)
  let bindings = requests.filter { $0.id == peer.registry && $0.opcode == 0 }
  let manager: UInt32 = try #require(
    bindings.first?.body.getInteger(
      at: bindings[0].body.writerIndex - 4, endianness: .host))
  let creations = requests.filter { $0.id == manager && $0.opcode == 1 }
  #expect(creations.count == 2)
  #expect(connection.input.renderScale == 2 && connection.popupInput?.renderScale == 2)
  for request in creations {
    let fractional: UInt32 = try #require(request.body.getInteger(at: 0, endianness: .host))
    let surface: UInt32 = try #require(request.body.getInteger(at: 4, endianness: .host))
    try connection.receive(
      .init(
        object: fractional, opcode: 0,
        arguments: [.uint(surface == popup.surface ? 210 : 150)]))
  }
  #expect(connection.input.bufferScale == 1 && connection.input.renderScale == 1.25)
  #expect(connection.popupInput?.bufferScale == 1 && connection.popupInput?.renderScale == 1.75)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [.uint(22), .string("wp_viewporter"), .uint(1)]))
  let duplicate = try await drain(connection, &peer)
  #expect(!duplicate.contains { $0.id == manager && $0.opcode == 1 })
}
