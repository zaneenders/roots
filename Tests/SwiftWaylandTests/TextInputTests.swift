import NIOCore
import Testing

@testable import SwiftWayland

@MainActor private func textFixture() throws -> (WaylandObjects, WaylandTextInput) {
  let objects = WaylandObjects()
  let input = WaylandTextInput(objects: objects)
  input.manager = objects.allocate("zwp_text_input_manager_v3")
  input.attach(seat: objects.allocate("wl_seat"))
  _ = try objects.takeRequests()
  return (objects, input)
}

private func editState(_ text: String = "éa") -> WaylandTextInputState {
  .init(
    surroundingText: text, cursor: Int32(text.utf8.count), anchor: 0,
    cursorRectangle: SIMD4(10, 20, 1, 18))
}

@Test @MainActor func textInputEnablesOnlyEnteredEditorAndCommitsStateAtomically() throws {
  let (objects, input) = try textFixture()
  input.set(editState(), on: 20)
  #expect(try objects.takeRequests().isEmpty)
  #expect(input.event(.init(object: input.id, opcode: 0, arguments: [.uint(20)])) == nil)
  let requests = try objects.takeRequests()
  let opcodes = requests.map {
    $0.bytes.getInteger(at: 4, endianness: .host, as: UInt32.self)! & 0xffff
  }
  #expect(opcodes == [1, 3, 4, 5, 6, 7])
  input.set(editState(), on: 20)
  #expect(try objects.takeRequests().isEmpty)
  input.set(nil, on: 20)
  let disabled = try objects.takeRequests()
  #expect(
    disabled.map { $0.bytes.getInteger(at: 4, endianness: .host, as: UInt32.self)! & 0xffff } == [
      2, 7,
    ])
}

@Test @MainActor func textInputDoneBatchesUTF8PreeditCommitAndDeletion() throws {
  let (_, input) = try textFixture()
  input.set(editState(), on: 20)
  _ = input.event(.init(object: input.id, opcode: 0, arguments: [.uint(20)]))
  #expect(
    input.event(
      .init(
        object: input.id, opcode: 2,
        arguments: [.string("日本"), .int(3), .int(6)])) == nil)
  #expect(input.event(.init(object: input.id, opcode: 3, arguments: [.string("é")])) == nil)
  #expect(input.event(.init(object: input.id, opcode: 4, arguments: [.uint(2), .uint(1)])) == nil)
  let update = try #require(input.event(.init(object: input.id, opcode: 5, arguments: [.uint(1)])))
  #expect(update.surface == 20)
  #expect(
    update.edit
      == .init(
        committed: "é", preedit: .init(text: "日本", cursorBegin: 3, cursorEnd: 6),
        deleteBefore: 2, deleteAfter: 1))
  let next = try #require(input.event(.init(object: input.id, opcode: 5, arguments: [.uint(1)])))
  #expect(next.edit == .init())
  let leave = try #require(input.event(.init(object: input.id, opcode: 1, arguments: [.uint(20)])))
  #expect(leave.surface == 20 && leave.edit.preedit == nil)
  #expect(input.event(.init(object: input.id, opcode: 5, arguments: [.uint(1)])) == nil)
}

@Test @MainActor func staleDoneStillDeliversEditsButDefersStateUntilMatchingSerial() throws {
  let (objects, input) = try textFixture()
  input.set(editState(), on: 20)
  _ = input.event(.init(object: input.id, opcode: 0, arguments: [.uint(20)]))
  _ = try objects.takeRequests()
  _ = input.event(.init(object: input.id, opcode: 3, arguments: [.string("x")]))
  let stale = try #require(input.event(.init(object: input.id, opcode: 5, arguments: [.uint(0)])))
  #expect(stale.edit.committed == "x")
  input.set(editState("éax"), on: 20)
  #expect(try objects.takeRequests().isEmpty)
  _ = input.event(.init(object: input.id, opcode: 5, arguments: [.uint(1)]))
  #expect(try objects.takeRequests().count == 5)
}

@Test @MainActor func textInputFocusSwitchClearsPendingCompositionAndReenablesPopup() throws {
  let (objects, input) = try textFixture()
  input.set(editState(), on: 20)
  input.set(editState("popup"), on: 21)
  _ = input.event(.init(object: input.id, opcode: 0, arguments: [.uint(20)]))
  _ = input.event(.init(object: input.id, opcode: 3, arguments: [.string("old")]))
  _ = input.event(.init(object: input.id, opcode: 1, arguments: [.uint(20)]))
  _ = input.event(.init(object: input.id, opcode: 0, arguments: [.uint(21)]))
  let done = try #require(input.event(.init(object: input.id, opcode: 5, arguments: [.uint(2)])))
  #expect(done.surface == 21 && done.edit.committed == nil)
  input.detach()
  _ = try objects.takeRequests()
  input.attach(seat: objects.allocate("wl_seat"))
  _ = input.event(.init(object: input.id, opcode: 0, arguments: [.uint(21)]))
  #expect(try objects.takeRequests().count == 7)
}

@Test func textInputStateValidatesUTF8ByteBoundariesAndMessageSize() {
  var state = editState()
  #expect(state.isValid)
  state.cursor = 1
  #expect(!state.isValid)
  state.cursor = -1
  #expect(!state.isValid)
  state = editState(String(repeating: "x", count: 4001))
  #expect(!state.isValid)
  state = editState("a\0b")
  #expect(!state.isValid)
  state = editState()
  state.cursorRectangle.z = -1
  #expect(!state.isValid)
}

@Test @MainActor func inputMethodReceivesPasswordPurposeAndSensitiveHints() throws {
  let (objects, input) = try textFixture()
  var state = editState()
  state.purpose = .password
  state.hints = [.hidden, .sensitiveData]
  input.set(state, on: 20)
  _ = input.event(.init(object: input.id, opcode: 0, arguments: [.uint(20)]))
  let requests = try objects.takeRequests()
  let content = try #require(
    requests.first {
      $0.bytes.getInteger(at: 4, endianness: .host, as: UInt32.self)! & 0xffff == 5
    })
  #expect(content.bytes.getInteger(at: 8, endianness: .host, as: UInt32.self) == 192)
  #expect(content.bytes.getInteger(at: 12, endianness: .host, as: UInt32.self) == 8)
}

@Test @MainActor func cursorManagerReplacementRetainsCurrentPointerFocus() throws {
  let objects = WaylandObjects()
  let cursor = WaylandCursor(objects: objects)
  let pointer = objects.allocate("wl_pointer")
  cursor.manager = objects.allocate("wp_cursor_shape_manager_v1")
  cursor.attach(pointer: pointer)
  cursor.set(.text, on: 20)
  cursor.enter(surface: 20, serial: 45)
  cursor.close()
  _ = try objects.takeRequests()
  cursor.manager = objects.allocate("wp_cursor_shape_manager_v1")
  cursor.attach(pointer: pointer)
  let requests = try objects.takeRequests()
  let shape = try #require(requests.last)
  #expect(shape.bytes.getInteger(at: 8, endianness: .host, as: UInt32.self) == 45)
  #expect(shape.bytes.getInteger(at: 12, endianness: .host, as: UInt32.self) == 9)
}
