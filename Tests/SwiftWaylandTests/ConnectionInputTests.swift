import NIOCore
import Testing

@testable import SwiftWayland

@MainActor private func configureKeyboard(
  _ connection: WaylandConnection, _ peer: inout ConnectionPeer, surface: UInt32
) async throws -> UInt32 {
  try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(3)]))
  let requests = try await drain(connection, &peer)
  let request = try #require(requests.first { $0.id == peer.seat && $0.opcode == 1 })
  let keyboard: UInt32 = try #require(
    request.body.getInteger(at: request.body.readerIndex, endianness: .host))
  try loadTestKeymap(connection, keyboard: keyboard)
  try connection.receive(
    .init(object: keyboard, opcode: 1, arguments: [.uint(1), .uint(surface), .array(ByteBuffer())]))
  return keyboard
}

@Test(arguments: [false, true]) @MainActor
func keyboardRepeatSleepsUntilDeadlineAndWakesOnlyFocusedSurface(popup: Bool) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let surface = popup ? try await configurePopup(connection, &peer).surface : peer.surface
  let keyboard = try await configureKeyboard(connection, &peer, surface: surface)
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(2), .int(200)]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(2), .uint(0), .uint(16), .uint(1)]))
  let first = popup ? connection.takePopupInput()! : connection.beginFrame()
  #expect(first.keyEvents.count == 1 && first.keyEvents[0].phase == .pressed)
  if popup { try connection.endPopupFrame() } else { try connection.endFrame() }
  let callback = try frameCallback(in: await drain(connection, &peer), on: surface)
  #expect(!connection.redrawRequested)
  #expect(!connection.canRender && !connection.canRenderPopup)
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(1)]))
  #expect(!connection.canRender && !connection.canRenderPopup)

  // No socket input is needed to wake dispatch at the repeat deadline.
  let timeout = Task {
    try await Task.sleep(for: .seconds(3))
    connection.requestClose()
  }
  defer { timeout.cancel() }
  while connection.running && !(popup ? connection.canRenderPopup : connection.canRender) {
    try await connection.dispatchAsync()
  }
  try #require(connection.running)
  #expect(popup ? !connection.redrawRequested : !connection.canRenderPopup)
  let repeated = popup ? connection.takePopupInput()! : connection.beginFrame()
  #expect(!repeated.keyEvents.isEmpty)
  #expect(repeated.keyEvents.allSatisfy { $0.phase == .repeated })
  if popup { try connection.endPopupFrame() } else { try connection.endFrame() }
  #expect(!connection.redrawRequested)
  #expect(!connection.canRenderPopup)
}

@Test(arguments: [false, true]) @MainActor
func keyboardRepeatWaitsForDelayedSurfaceCallback(popup: Bool) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let surface = popup ? try await configurePopup(connection, &peer).surface : peer.surface
  let keyboard = try await configureKeyboard(connection, &peer, surface: surface)
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(100), .int(0)]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(2), .uint(0), .uint(16), .uint(1)]))
  if popup {
    _ = connection.takePopupInput()
    try connection.endPopupFrame()
  } else {
    _ = connection.beginFrame()
    try connection.endFrame()
  }
  let callback = try frameCallback(in: await drain(connection, &peer), on: surface)
  try await Task.sleep(for: .milliseconds(400))
  #expect(!connection.canRender && !connection.canRenderPopup)
  if popup { #expect(!connection.redrawRequested) } else { #expect(connection.redrawRequested) }
  try connection.receive(.init(object: callback, opcode: 0, arguments: [.uint(1)]))
  #expect(popup ? connection.canRenderPopup : connection.canRender)
  let repeated = popup ? connection.takePopupInput()! : connection.beginFrame()
  #expect(!repeated.keyEvents.isEmpty && repeated.keyEvents.count <= 32)
  #expect(repeated.keyEvents.allSatisfy { $0.phase == .repeated })
}

@Test(arguments: ["release", "focus", "keymap", "disabled", "seat", "close", "popup"])
@MainActor func keyboardRepeatDeadlineIsCancelled(reason: String) async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let surface =
    reason == "popup" ? try await configurePopup(connection, &peer).surface : peer.surface
  let keyboard = try await configureKeyboard(connection, &peer, surface: surface)
  try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(20), .int(100)]))
  try connection.receive(
    .init(object: keyboard, opcode: 3, arguments: [.uint(2), .uint(0), .uint(16), .uint(1)]))
  switch reason {
  case "release":
    try connection.receive(
      .init(object: keyboard, opcode: 3, arguments: [.uint(3), .uint(0), .uint(16), .uint(0)]))
  case "focus":
    try connection.receive(
      .init(object: keyboard, opcode: 2, arguments: [.uint(3), .uint(surface)]))
  case "keymap": try loadTestKeymap(connection, keyboard: keyboard)
  case "disabled":
    try connection.receive(.init(object: keyboard, opcode: 5, arguments: [.int(0), .int(100)]))
  case "seat":
    try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(1)]))
  case "close": connection.requestClose()
  default: connection.dismissPopup()
  }
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try await Task.sleep(for: .milliseconds(200))
  #expect(!connection.redrawRequested && !connection.canRenderPopup)
  #expect(connection.beginFrame().keyEvents.isEmpty)
}

@Test @MainActor func desktopInputGlobalsAreOptionalAndCursorUsesEnterSerial() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  #expect(!connection.setCursor(.text))
  #expect(
    !connection.setTextInput(
      .init(
        surroundingText: "", cursor: 0, anchor: 0, cursorRectangle: .zero)))
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [
        .uint(40), .string("wp_cursor_shape_manager_v1"), .uint(2)
      ]))
  let requests = try await drain(connection, &peer)
  let bind = try #require(requests.first { $0.id == peer.registry })
  let manager: UInt32 = try #require(
    bind.body.getInteger(at: bind.body.writerIndex - 4, endianness: .host))
  let create = try #require(requests.first { $0.id == manager && $0.opcode == 1 })
  let device: UInt32 = try #require(create.body.getInteger(at: 0, endianness: .host))
  #expect(connection.setCursor(.text))
  #expect(try await drain(connection, &peer).isEmpty)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [
        .uint(17), .uint(peer.surface), .int(0), .int(0)
      ]))
  let shapes = try await drain(connection, &peer)
  let shape = try #require(shapes.first { $0.id == device && $0.opcode == 1 })
  #expect(shape.body.getInteger(at: 0, endianness: .host, as: UInt32.self) == 17)
  #expect(shape.body.getInteger(at: 4, endianness: .host, as: UInt32.self) == 9)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 1,
      arguments: [
        .uint(18), .uint(peer.surface)
      ]))
  #expect(connection.setCursor(.pointer))
  #expect(try await drain(connection, &peer).isEmpty)
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [
        .uint(19), .uint(peer.surface), .int(0), .int(0)
      ]))
  let entered = try await drain(connection, &peer)
  #expect(
    entered.contains {
      $0.id == device && $0.opcode == 1
        && $0.body.getInteger(at: 0, endianness: .host, as: UInt32.self) == 19
    })
  try connection.receive(.init(object: peer.seat, opcode: 0, arguments: [.uint(0)]))
  let removed = try await drain(connection, &peer)
  #expect(removed.first?.id == device && removed.first?.opcode == 0)
}

@Test @MainActor func modernPointerEventsReachOnlyTheFocusedSurface() async throws {
  let (connection, initialPeer, _) = try await connectedPeer(seatVersion: 9)
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 0,
      arguments: [
        .uint(1), .uint(popup.surface), .int(0), .int(0)
      ]))
  try connection.receive(
    .init(
      object: peer.pointer, opcode: 3,
      arguments: [
        .uint(2), .uint(0), .uint(0x111), .uint(1)
      ]))
  try connection.receive(.init(object: peer.pointer, opcode: 9, arguments: [.uint(0), .int(30)]))
  try connection.receive(.init(object: peer.pointer, opcode: 10, arguments: [.uint(0), .uint(1)]))
  try connection.receive(.init(object: peer.pointer, opcode: 5, arguments: []))
  let input = try #require(connection.takePopupInput())
  #expect(input.secondaryPressed && input.secondaryDown && !input.primaryDown)
  #expect(input.scrollStepsY == 0.25 && input.scrollInvertedY == true)
  #expect(connection.input.scrollStepsY == 0 && !connection.input.secondaryPressed)
}

@Test @MainActor func inputMethodTransactionsReachPopupOnlyAtDoneAndClearOnRemoval() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [
        .uint(41), .string("zwp_text_input_manager_v3"), .uint(2)
      ]))
  let requests = try await drain(connection, &peer)
  let bind = try #require(requests.first { $0.id == peer.registry })
  let manager: UInt32 = try #require(
    bind.body.getInteger(at: bind.body.writerIndex - 4, endianness: .host))
  let create = try #require(requests.first { $0.id == manager && $0.opcode == 1 })
  let text: UInt32 = try #require(create.body.getInteger(at: 0, endianness: .host))
  #expect(
    connection.setTextInput(
      .init(
        surroundingText: "", cursor: 0, anchor: 0,
        cursorRectangle: SIMD4(0, 0, 1, 20)), popup: true))
  try connection.receive(.init(object: text, opcode: 0, arguments: [.uint(popup.surface)]))
  _ = connection.beginFrame()
  _ = connection.takePopupInput()
  try connection.receive(
    .init(object: text, opcode: 2, arguments: [.string("日"), .int(3), .int(3)]))
  try connection.receive(.init(object: text, opcode: 3, arguments: [.string("語")]))
  #expect(connection.popupInput?.textEvents.isEmpty == true)
  try connection.receive(.init(object: text, opcode: 5, arguments: [.uint(1)]))
  let input = try #require(connection.takePopupInput())
  #expect(
    input.textEvents == [
      .init(committed: "語", preedit: .init(text: "日", cursorBegin: 3, cursorEnd: 3))
    ])
  #expect(connection.input.textEvents.isEmpty && !connection.redrawRequested)
  try connection.receive(.init(object: peer.registry, opcode: 1, arguments: [.uint(41)]))
  #expect(connection.takePopupInput()?.textEvents == [.init()])
  #expect(
    !connection.setTextInput(
      .init(
        surroundingText: "", cursor: 0, anchor: 0,
        cursorRectangle: .zero), popup: true))
  try connection.receive(.init(object: text, opcode: 3, arguments: [.string("late")]))
  try connection.receive(.init(object: text, opcode: 5, arguments: [.uint(1)]))
  #expect(connection.popupInput?.textEvents.isEmpty == true)
}

@Test @MainActor func cursorShapesArePerSurfaceAndIgnoreDuplicateRequests() async throws {
  let (connection, initialPeer, _) = try await connectedPeer()
  defer { connection.cleanup() }
  var peer = initialPeer
  let popup = try await configurePopup(connection, &peer)
  try connection.receive(
    .init(
      object: peer.registry, opcode: 0,
      arguments: [
        .uint(40), .string("wp_cursor_shape_manager_v1"), .uint(1)
      ]))
  _ = try await drain(connection, &peer)
  #expect(connection.setCursor(.text))
  #expect(connection.setCursor(.grabbing, popup: true))
  _ = try await drain(connection, &peer)
  for (surface, serial, shape): (UInt32, UInt32, UInt32) in [
    (peer.surface, 31, 9), (popup.surface, 32, 17), (peer.surface, 33, 9)
  ] {
    try connection.receive(
      .init(
        object: peer.pointer, opcode: 0,
        arguments: [
          .uint(serial), .uint(surface), .int(0), .int(0)
        ]))
    let requests = try await drain(connection, &peer)
    let request = try #require(requests.first { $0.opcode == 1 })
    #expect(request.body.getInteger(at: 0, endianness: .host, as: UInt32.self) == serial)
    #expect(request.body.getInteger(at: 4, endianness: .host, as: UInt32.self) == shape)
  }
  #expect(connection.setCursor(.text))
  #expect(try await drain(connection, &peer).isEmpty)
}
