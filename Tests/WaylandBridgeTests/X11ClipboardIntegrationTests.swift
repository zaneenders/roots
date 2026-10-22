import CX11
import Foundation
import Glibc
import Testing

@testable import WaylandBridge

/// Uses only the inherited, authenticated DISPLAY. Never starts a server or
/// changes access controls. Run separately on Xorg and XWayland:
/// ROOTS_X11_CLIPBOARD_TESTS=1 swift test --filter X11ClipboardIntegrationTests
@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["ROOTS_X11_CLIPBOARD_TESTS"] == "1")
)
@MainActor struct X11ClipboardIntegrationTests {
  @Test func clipboardRoundTripsBothDirectionsIncludingINCR() async throws {
    let first = try X11ClipboardPeer()
    let second = try X11ClipboardPeer()
    defer {
      first.close()
      second.close()
    }
    let large = String(repeating: "café 🙂\n第二行\n", count: 30_000)
    for (source, destination) in [(first, second), (second, first)] {
      for text in ["", "short", "café 🙂\n第二行\n", large] {
        #expect(source.clipboard.write(text, timestamp: 0))
        try await settle([first, second])
        let received = try await read(destination, pumping: [first, second])
        let matches = received == text
        #expect(
          matches, "Received \(received?.utf8.count ?? -1) UTF-8 bytes; expected \(text.utf8.count)"
        )
        try await settle([first, second])
      }
    }
  }

  @Test func ownershipLossKeepsAnAlreadyAcceptedINCRSnapshotAlive() async throws {
    let source = try X11ClipboardPeer()
    let destination = try X11ClipboardPeer()
    let replacement = try X11ClipboardPeer()
    defer {
      source.close()
      destination.close()
      replacement.close()
    }
    let original = String(repeating: "original 🙂\n", count: 50_000)
    #expect(source.clipboard.write(original, timestamp: 0))
    try await settle([source, destination])
    // A clipboard manager may request TARGETS as soon as ownership changes.
    // Reproduce that unrelated request explicitly: a source request counter is
    // not evidence that the destination's subsequent read was accepted.
    try replacement.requestTargets()
    let metadataDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while replacement.selectionNotifications == 0, .now < metadataDeadline {
      for peer in [source, destination, replacement] { try peer.pump() }
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(replacement.selectionNotifications > 0)
    try #require(source.selectionRequests > 0)
    #expect(destination.acceptedIncrementalReads == 0)
    var completed = false
    var result: String?
    let pending = Task { @MainActor in
      result = await destination.clipboard.read()
      completed = true
    }
    defer { pending.cancel() }
    let acceptedDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while destination.acceptedIncrementalReads == 0, .now < acceptedDeadline {
      try source.pump()
      try destination.pump()
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(destination.acceptedIncrementalReads == 1)
    try #require(
      !completed, "Ownership must change while the accepted INCR transfer is still active")
    #expect(replacement.clipboard.write("replacement", timestamp: 0))
    try await settle([replacement])
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !completed, .now < deadline {
      for peer in [source, destination, replacement] { try peer.pump() }
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(completed)
    await pending.value
    let retainedOriginal = result == original
    #expect(
      retainedOriginal,
      "Accepted INCR snapshot: received \(result?.utf8.count ?? -1) UTF-8 bytes; expected \(original.utf8.count)"
    )
    let newest = try await read(destination, pumping: [source, destination, replacement])
    let matchesReplacement = newest == "replacement"
    #expect(
      matchesReplacement,
      "The next read should return the replacement; received \(newest?.utf8.count ?? -1) bytes")
  }

  @Test func cancelledReadDoesNotPoisonTheNextRead() async throws {
    let source = try X11ClipboardPeer()
    let destination = try X11ClipboardPeer()
    defer {
      source.close()
      destination.close()
    }
    #expect(source.clipboard.write(String(repeating: "🙂", count: 100_000), timestamp: 0))
    try await settle([source, destination])
    let pending = Task { await destination.clipboard.read() }
    await Task.yield()
    pending.cancel()
    #expect(await pending.value == nil)
    let recovered = try await read(destination, pumping: [source, destination])
    let matches = recovered == String(repeating: "🙂", count: 100_000)
    #expect(
      matches,
      "The next read should recover after cancellation; received \(recovered?.utf8.count ?? -1) bytes"
    )
  }

  @Test func malformedAndOversizedPeerRepliesAreRejected() async throws {
    let source = try X11ClipboardPeer()
    let destination = try X11ClipboardPeer()
    defer {
      source.close()
      destination.close()
    }
    #expect(source.clipboard.write("placeholder", timestamp: 0))
    try await settle([source, destination])
    source.selectionOverride = { request in
      source.reply(request, type: request.target, format: 8, bytes: [0xff])
    }
    #expect(try await read(destination, pumping: [source, destination]) == nil)
    let incr = try source.atom("INCR")
    source.selectionOverride = { request in
      source.reply(request, type: incr, format: 32, bytes: [0xff, 0xff, 0xff, 0xff])
    }
    #expect(try await read(destination, pumping: [source, destination]) == nil)
    source.selectionOverride = { request in
      source.reply(request, type: request.target, format: 16, bytes: [65, 0])
    }
    #expect(try await read(destination, pumping: [source, destination]) == nil)
    source.selectionOverride = nil
  }

  @Test func stalledOwnerTimesOutAndCloseResumesAPendingReadOnce() async throws {
    let source = try X11ClipboardPeer()
    let destination = try X11ClipboardPeer()
    defer {
      source.close()
      destination.close()
    }
    #expect(source.clipboard.write("unresponsive", timestamp: 0))
    try await settle([source, destination])
    source.selectionOverride = { _ in }
    let start = ContinuousClock.now
    #expect(try await read(destination, pumping: [source, destination]) == nil)
    #expect(start.duration(to: .now) >= .seconds(5))
    let pending = Task { await destination.clipboard.read() }
    await Task.yield()
    destination.close()
    destination.close()
    #expect(await pending.value == nil)
    #expect(await destination.clipboard.read() == nil)
    #expect(!destination.clipboard.write("closed", timestamp: 0))
  }

  @Test func destroyedRequestorReleasesTheOutgoingTransfer() async throws {
    let source = try X11ClipboardPeer()
    let destination = try X11ClipboardPeer()
    defer {
      source.close()
      destination.close()
    }
    #expect(source.clipboard.write(String(repeating: "large", count: 100_000), timestamp: 0))
    try await settle([source, destination])
    let pending = Task { await destination.clipboard.read() }
    // Wait for this destination's accepted INCR announcement, not unrelated
    // SelectionRequest traffic from desktop clipboard managers.
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while destination.acceptedIncrementalReads == 0, .now < deadline {
      try source.pump()
      try destination.pump()
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(destination.acceptedIncrementalReads == 1)
    destination.close()
    #expect(await pending.value == nil)
    try await settle([source])
    #expect(source.clipboard.nextDeadline == nil)
  }

  private func settle(_ peers: [X11ClipboardPeer]) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    repeat {
      for peer in peers { try peer.pump() }
      if peers.allSatisfy({ $0.clipboard.nextDeadline == nil }) { return }
      try await Task.sleep(for: .milliseconds(2))
    } while .now < deadline
    Issue.record("Clipboard did not become idle within its bounded deadline")
  }

  private func read(_ peer: X11ClipboardPeer, pumping peers: [X11ClipboardPeer]) async throws
    -> String?
  {
    var completed = false
    var result: String?
    let task = Task { @MainActor in
      result = await peer.clipboard.read()
      completed = true
    }
    defer { task.cancel() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !completed, .now < deadline {
      for peer in peers { try peer.pump() }
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(completed, "Read did not complete within its bounded deadline")
    await task.value
    return result
  }
}

@safe @MainActor private final class X11ClipboardPeer {
  private var connection: OpaquePointer?
  private var window: UInt32 = 0
  let clipboard: X11Clipboard
  var selectionOverride: ((xcb_selection_request_event_t) -> Void)?
  var selectionRequests = 0
  var selectionNotifications = 0
  var acceptedIncrementalReads = 0

  init() throws {
    var screen: Int32 = 0
    guard let connection = unsafe xcb_connect(nil, &screen) else { throw PeerError.connection }
    guard unsafe xcb_connection_has_error(connection) == 0 else {
      unsafe xcb_disconnect(connection)
      throw PeerError.connection
    }
    var initialized = false
    defer { if !initialized { unsafe xcb_disconnect(connection) } }
    guard let setup = unsafe xcb_get_setup(connection) else { throw PeerError.connection }
    var screens = unsafe xcb_setup_roots_iterator(setup)
    for _ in 0..<screen { unsafe xcb_screen_next(&screens) }
    guard let root = unsafe screens.data else { throw PeerError.connection }
    let window = unsafe xcb_generate_id(connection)
    var mask = UInt32(
      XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue | XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue)
    let cookie = unsafe xcb_create_window_checked(
      connection, 0, window, root.pointee.root, 0, 0, 1, 1, 0,
      UInt16(XCB_WINDOW_CLASS_INPUT_ONLY.rawValue),
      0, UInt32(XCB_CW_EVENT_MASK.rawValue), &mask)
    if let error = unsafe xcb_request_check(connection, cookie) {
      unsafe free(error)
      throw PeerError.connection
    }
    clipboard = try unsafe X11Clipboard(connection: connection, window: window)
    unsafe self.connection = connection
    self.window = window
    initialized = true
  }

  isolated deinit { close() }

  func pump() throws {
    guard let connection = unsafe connection else { return }
    clipboard.poll()
    for _ in 0..<256 {
      guard let event = unsafe xcb_poll_for_event(connection) else { break }
      defer { unsafe free(event) }
      let type = unsafe event.pointee.response_type & 0x7f
      if type == XCB_SELECTION_REQUEST {
        selectionRequests += 1
        if let selectionOverride {
          selectionOverride(
            unsafe UnsafeRawPointer(event).load(as: xcb_selection_request_event_t.self))
          continue
        }
      }
      if type == XCB_SELECTION_NOTIFY {
        let notification = unsafe UnsafeRawPointer(event).load(
          as: xcb_selection_notify_event_t.self)
        if notification.property != 0 {
          selectionNotifications += 1
          if try isIncrementalAnnouncement(notification) { acceptedIncrementalReads += 1 }
        }
      }
      if type == 0 { throw PeerError.protocolError }
      unsafe clipboard.handle(event)
    }
    _ = unsafe xcb_flush(connection)
  }

  func requestTargets() throws {
    guard let connection = unsafe connection else { throw PeerError.connection }
    let clipboard = try atom("CLIPBOARD")
    let targets = try atom("TARGETS")
    let property = try atom("_ROOTS_CLIPBOARD_TEST_METADATA")
    _ = unsafe xcb_convert_selection(connection, window, clipboard, targets, property, 0)
    _ = unsafe xcb_flush(connection)
  }

  private func isIncrementalAnnouncement(_ notification: xcb_selection_notify_event_t) throws
    -> Bool
  {
    guard let connection = unsafe connection else { throw PeerError.connection }
    guard notification.selection == (try atom("CLIPBOARD")),
      notification.target == (try atom("UTF8_STRING")),
      notification.property == (try atom("_ROOTS_CLIPBOARD")),
      notification.requestor != window
    else { return false }
    let incr = try atom("INCR")
    let cookie = unsafe xcb_get_property(
      connection, 0, notification.requestor, notification.property,
      UInt32(XCB_GET_PROPERTY_TYPE_ANY.rawValue), 0, 1)
    // This test-only server round trip inspects an already published property.
    // It never waits for the selection owner or acknowledges/deletes the data.
    guard let reply = unsafe xcb_get_property_reply(connection, cookie, nil) else {
      throw PeerError.protocolError
    }
    defer { unsafe free(reply) }
    let header = unsafe reply.pointee
    return header.type == incr && header.format == 32 && header.value_len == 1
      && header.bytes_after == 0
  }

  func atom(_ name: String) throws -> UInt32 {
    guard let connection = unsafe connection else { throw PeerError.connection }
    let cookie = unsafe xcb_intern_atom(connection, 0, UInt16(name.utf8.count), name)
    guard let reply = unsafe xcb_intern_atom_reply(connection, cookie, nil) else {
      throw PeerError.connection
    }
    defer { unsafe free(reply) }
    return unsafe reply.pointee.atom
  }

  func reply(_ request: xcb_selection_request_event_t, type: UInt32, format: UInt8, bytes: [UInt8])
  {
    guard let connection = unsafe connection else { return }
    bytes.withUnsafeBytes { buffer in
      _ = unsafe xcb_change_property(
        connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), request.requestor, request.property,
        type, format,
        UInt32(bytes.count / Int(format / 8)), buffer.baseAddress)
    }
    var event = xcb_selection_notify_event_t()
    event.response_type = UInt8(XCB_SELECTION_NOTIFY)
    event.time = request.time
    event.requestor = request.requestor
    event.selection = request.selection
    event.target = request.target
    event.property = request.property
    var wire = [UInt8](repeating: 0, count: 32)
    withUnsafeBytes(of: &event) { source in
      for index in source.indices { wire[index] = unsafe source[index] }
    }
    wire.withUnsafeBytes { buffer in
      _ = unsafe xcb_send_event(
        connection, 0, request.requestor, 0, buffer.baseAddress!.assumingMemoryBound(to: CChar.self)
      )
    }
    _ = unsafe xcb_flush(connection)
  }

  func close() {
    clipboard.close()
    selectionOverride = nil
    if let connection = unsafe connection {
      if window != 0 { _ = unsafe xcb_destroy_window(connection, window) }
      _ = unsafe xcb_flush(connection)
      unsafe xcb_disconnect(connection)
    }
    unsafe connection = nil
    window = 0
  }

  private enum PeerError: Error { case connection, protocolError }
}
