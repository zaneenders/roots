import CX11
import Foundation
import Glibc

/// Bounds apply to the complete transfer, not to each chunk. A peer cannot extend
/// the lifetime indefinitely by dribbling bytes or property notifications.
enum X11ClipboardLimits {
  static let maximumBytes = 16 * 1024 * 1024
  static let chunkBytes = 64 * 1024
  static let maximumSends = 8
  static let maximumSendingBytes = 32 * 1024 * 1024
  static let timeout: Duration = .seconds(5)
}

/// Owned storage only; UTF-8 is decoded after the final chunk, so a code point may
/// straddle either a GetProperty reply or an INCR chunk.
struct X11ClipboardReadBuffer {
  enum Step: Equatable {
    case moreProperty(offset: UInt32)
    case nextChunk
    case complete(String)
    case invalid
  }

  private(set) var incremental = false
  private(set) var finished = false
  private var minimumBytes = 0
  private var bytes: [UInt8] = []
  private var propertyBytes = 0

  mutating func beginIncremental(
    advertisedBytes: UInt32, format: UInt8, valueCount: Int, bytesAfter: UInt32
  ) -> Bool {
    guard !finished, !incremental, bytes.isEmpty, propertyBytes == 0,
      format == 32, valueCount == 1, bytesAfter == 0,
      advertisedBytes <= X11ClipboardLimits.maximumBytes
    else {
      finished = true
      return false
    }
    minimumBytes = Int(advertisedBytes)
    incremental = true
    return true
  }

  mutating func receive(_ fragment: [UInt8], format: UInt8, bytesAfter: UInt32) -> Step {
    guard !finished, format == 8,
      fragment.count <= X11ClipboardLimits.maximumBytes - bytes.count,
      Int(bytesAfter) <= X11ClipboardLimits.maximumBytes - bytes.count - fragment.count,
      bytesAfter == 0 || (!fragment.isEmpty && fragment.count.isMultiple(of: 4))
    else {
      finished = true
      return .invalid
    }
    bytes.append(contentsOf: fragment)
    propertyBytes += fragment.count
    if bytesAfter != 0 { return .moreProperty(offset: UInt32(propertyBytes / 4)) }
    if incremental, propertyBytes != 0 {
      propertyBytes = 0
      return .nextChunk
    }
    finished = true
    guard bytes.count >= minimumBytes, let text = String(bytes: bytes, encoding: .utf8) else {
      return .invalid
    }
    return .complete(text)
  }
}

struct X11ClipboardSendBuffer {
  let bytes: [UInt8]
  private(set) var offset = 0
  private var sentTerminator = false

  /// The empty terminator is a real property write and must be acknowledged too.
  mutating func nextChunk(maximum: Int) -> [UInt8]? {
    guard maximum > 0, !sentTerminator else { return nil }
    if offset == bytes.count {
      sentTerminator = true
      return []
    }
    let end = min(bytes.count, offset + maximum)
    let result = Array(bytes[offset..<end])
    offset = end
    return result
  }
}

/// Actor-owned XCB state. The host must forward events, call poll before draining
/// XCB's event queue, include nextDeadline in its wait, and close before disconnect.
/// Only atom lookup at initialization waits for a server reply. Transfer replies
/// are polled; no native pointer, span, or reply allocation crosses an await.
@safe @MainActor final class X11Clipboard {
  private enum StartupError: Error { case unavailable }

  private struct Atoms {
    let clipboard: UInt32
    let utf8: UInt32
    let targets: UInt32
    let timestamp: UInt32
    let incr: UInt32
    let property: UInt32
    let clock: UInt32
  }

  private struct Read {
    let id: UUID
    let window: UInt32
    let continuation: CheckedContinuation<String?, Never>
    let deadline: ContinuousClock.Instant
    var timestamp: UInt32 = 0
    var awaitingNotify = false
    var reply: UInt32?
    var buffer = X11ClipboardReadBuffer()
  }

  private struct Key: Hashable {
    let window: UInt32
    let property: UInt32
  }

  private enum Value {
    case bytes([UInt8])
    case words([UInt32])

    var byteCount: Int {
      switch self {
      case .bytes(let bytes): bytes.count
      case .words(let words): words.count * 4
      }
    }
  }

  private struct Send {
    let request: xcb_selection_request_event_t
    let deadline: ContinuousClock.Instant
    let value: Value
    let type: UInt32
    var buffer: X11ClipboardSendBuffer?
    var propertyCheck: UInt32?
    var barrier: UInt32?
    var notified = false
    var awaitingDelete = false
    var deletedEarly = false
  }

  /// Event selection is per connection. Preserve our pre-existing mask even on
  /// foreign windows, and restore it only after the last transfer using it ends.
  private struct Watch {
    var attributes: UInt32?
    var originalMask: UInt32?
    var maskCheck: UInt32?
    var barrier: UInt32?
    var ready = false
  }

  private var connection: OpaquePointer?
  private let window: UInt32
  private let atoms: Atoms
  private let chunkBytes: Int
  private var readState: Read?
  private var sends: [Key: Send] = [:]
  private var watches: [UInt32: Watch] = [:]
  private var bytes: [UInt8]?
  private var ownershipTime: UInt32 = 0
  private var ownershipReply: UInt32?
  private var publicationDeadline: ContinuousClock.Instant?
  private var timestampedBytes: [UInt8]?

  init(connection: OpaquePointer, window: UInt32) throws {
    unsafe self.connection = connection
    self.window = window
    func atom(_ name: String) throws -> UInt32 {
      let cookie = unsafe xcb_intern_atom(connection, 0, UInt16(name.utf8.count), name)
      guard let reply = unsafe xcb_intern_atom_reply(connection, cookie, nil) else {
        throw StartupError.unavailable
      }
      defer { unsafe free(reply) }
      let result = unsafe reply.pointee.atom
      guard result != 0 else { throw StartupError.unavailable }
      return result
    }
    atoms = try Atoms(
      clipboard: atom("CLIPBOARD"), utf8: atom("UTF8_STRING"), targets: atom("TARGETS"),
      timestamp: atom("TIMESTAMP"), incr: atom("INCR"), property: atom("_ROOTS_CLIPBOARD"),
      clock: atom("_ROOTS_CLIPBOARD_TIME"))
    guard let setup = unsafe xcb_get_setup(connection) else { throw StartupError.unavailable }
    // No BIG-REQUESTS round trip is needed; the setup's core limit is sufficient.
    chunkBytes = min(
      X11ClipboardLimits.chunkBytes, Int(unsafe setup.pointee.maximum_request_length) * 4 - 24)
    guard chunkBytes > 0 else { throw StartupError.unavailable }
  }

  isolated deinit { close() }

  // An active transfer may have replies already buffered by XCB rather than
  // readable on its FD. Bound reply polling only while work exists; an otherwise
  // idle connection has no timer, including while its window is unmapped.
  var nextDeadline: ContinuousClock.Instant? {
    guard readState != nil || !sends.isEmpty || publicationDeadline != nil else { return nil }
    return .now.advanced(by: .milliseconds(10))
  }

  func read() async -> String? {
    let id = UUID()
    return await withTaskCancellationHandler {
      guard !Task.isCancelled, readState == nil else { return nil }
      return await withCheckedContinuation { continuation in
        beginRead(id: id, continuation: continuation)
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard self?.readState?.id == id else { return }
        self?.finishRead(nil)
      }
    }
  }

  private func beginRead(id: UUID, continuation: CheckedContinuation<String?, Never>) {
    guard !Task.isCancelled, readState == nil, let connection = unsafe connection else {
      continuation.resume(returning: nil)
      return
    }
    let requestor = unsafe xcb_generate_id(connection)
    // A separate window gives each read an independent property namespace.
    // Destroying it on cancel makes late SelectionNotify/INCR traffic harmless.
    var mask = UInt32(
      XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue | XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue)
    let create = unsafe xcb_create_window_checked(
      connection, 0, requestor, window, 0, 0, 1, 1, 0, UInt16(XCB_WINDOW_CLASS_INPUT_ONLY.rawValue),
      0, UInt32(XCB_CW_EVENT_MASK.rawValue), &mask)
    unsafe xcb_discard_reply(connection, create.sequence)
    readState = Read(
      id: id, window: requestor, continuation: continuation,
      deadline: .now.advanced(by: X11ClipboardLimits.timeout))
    // PropertyNotify supplies a real server timestamp for ConvertSelection.
    changeClock(on: requestor)
    flush()
  }

  /// True means a bounded publication was queued, not confirmed peer delivery.
  @discardableResult func write(_ text: String, timestamp: UInt32) -> Bool {
    guard unsafe connection != nil, text.utf8.count <= X11ClipboardLimits.maximumBytes else {
      return false
    }
    let newBytes = Array(text.utf8)
    publicationDeadline = .now.advanced(by: X11ClipboardLimits.timeout)
    if timestamp == 0 {
      timestampedBytes = newBytes
      changeClock(on: window)
    } else {
      timestampedBytes = nil
      claim(newBytes, timestamp: timestamp)
    }
    flush()
    return true
  }

  /// Polling may move socket events into XCB's internal queue. Drain that queue
  /// immediately afterwards, rather than relying only on descriptor readiness.
  func poll() {
    guard let connection = unsafe connection else { return }
    guard unsafe xcb_connection_has_error(connection) == 0 else {
      close()
      return
    }
    let now = ContinuousClock.now
    if let readState, now >= readState.deadline { finishRead(nil) }
    if let publicationDeadline, now >= publicationDeadline {
      if let ownershipReply { unsafe xcb_discard_reply(connection, ownershipReply) }
      ownershipReply = nil
      self.publicationDeadline = nil
      timestampedBytes = nil
      bytes = nil
    }
    for (key, send) in sends where now >= send.deadline { finishSend(key, failed: true) }

    if let sequence = ownershipReply {
      consumeReply(sequence, as: xcb_get_selection_owner_reply_t.self) { reply in
        ownershipReply = nil
        publicationDeadline = timestampedBytes == nil ? nil : publicationDeadline
        if reply?.owner != window { bytes = nil }
      }
    }
    for requestor in Array(watches.keys) { pollWatch(requestor) }
    for key in Array(sends.keys) { pollSend(key) }
    if let sequence = readState?.reply { pollProperty(sequence) }
    flush()
  }

  @discardableResult func handle(_ event: UnsafePointer<xcb_generic_event_t>) -> Bool {
    guard unsafe connection != nil else { return false }
    switch unsafe event.pointee.response_type & 0x7f {
    case UInt8(XCB_SELECTION_NOTIFY):
      let notify = unsafe UnsafeRawPointer(event).load(as: xcb_selection_notify_event_t.self)
      guard let read = readState, notify.requestor == read.window,
        notify.selection == atoms.clipboard, notify.target == atoms.utf8,
        notify.time == read.timestamp, read.awaitingNotify
      else { return false }
      readState?.awaitingNotify = false
      guard notify.property == atoms.property else {
        finishRead(nil)
        return true
      }
      requestProperty(offset: 0)
    case UInt8(XCB_SELECTION_REQUEST):
      let request = unsafe UnsafeRawPointer(event).load(as: xcb_selection_request_event_t.self)
      guard request.owner == window, request.selection == atoms.clipboard else { return false }
      serve(request)
    case UInt8(XCB_SELECTION_CLEAR):
      let clear = unsafe UnsafeRawPointer(event).load(as: xcb_selection_clear_event_t.self)
      guard clear.owner == window, clear.selection == atoms.clipboard else { return false }
      if Self.isAtOrAfter(clear.time, ownershipTime) { bytes = nil }
    // ICCCM requires already accepted INCR transfers to keep serving their
    // immutable snapshot after ownership changes.
    case UInt8(XCB_PROPERTY_NOTIFY):
      let property = unsafe UnsafeRawPointer(event).load(as: xcb_property_notify_event_t.self)
      return handleProperty(property)
    case UInt8(XCB_DESTROY_NOTIFY):
      let destroyed = unsafe UnsafeRawPointer(event).load(as: xcb_destroy_notify_event_t.self)
      let keys = sends.keys.filter { $0.window == destroyed.window }
      for key in keys { finishSend(key, failed: true, destroyed: true) }
      if destroyed.window == readState?.window { finishRead(nil, destroyed: true) }
      return destroyed.window != window && !keys.isEmpty
    default:
      return false
    }
    flush()
    return true
  }

  func close() {
    guard let connection = unsafe connection else { return }
    finishRead(nil)
    for key in Array(sends.keys) { finishSend(key, failed: true) }
    if let ownershipReply { unsafe xcb_discard_reply(connection, ownershipReply) }
    ownershipReply = nil
    publicationDeadline = nil
    timestampedBytes = nil
    bytes = nil
    flush()
    // The host destroys its owner window next. Do not clear CLIPBOARD with
    // CurrentTime here: that could revoke a newer owner's selection.
    unsafe self.connection = nil
  }

  static func isAtOrAfter(_ time: UInt32, _ earlier: UInt32) -> Bool {
    Int32(bitPattern: time &- earlier) >= 0
  }

  private func claim(_ bytes: [UInt8], timestamp: UInt32) {
    guard let connection = unsafe connection else { return }
    if let ownershipReply { unsafe xcb_discard_reply(connection, ownershipReply) }
    self.bytes = bytes
    ownershipTime = timestamp
    let cookie = unsafe xcb_set_selection_owner_checked(
      connection, window, atoms.clipboard, timestamp)
    unsafe xcb_discard_reply(connection, cookie.sequence)
    ownershipReply = unsafe xcb_get_selection_owner(connection, atoms.clipboard).sequence
  }

  private func changeClock(on requestor: UInt32) {
    let sequence = changeProperty(
      on: requestor, property: atoms.clock, type: UInt32(XCB_ATOM_INTEGER.rawValue),
      value: .bytes([]))
    if let connection = unsafe connection { unsafe xcb_discard_reply(connection, sequence) }
  }

  private func handleProperty(_ event: xcb_property_notify_event_t) -> Bool {
    guard let connection = unsafe connection else { return false }
    if event.atom == atoms.clock, event.state == XCB_PROPERTY_NEW_VALUE.rawValue {
      if event.window == window, let timestampedBytes {
        self.timestampedBytes = nil
        claim(timestampedBytes, timestamp: event.time)
        flush()
        return true
      }
      if event.window == readState?.window, readState?.timestamp == 0 {
        readState?.timestamp = event.time
        readState?.awaitingNotify = true
        let cookie = unsafe xcb_convert_selection_checked(
          connection, event.window, atoms.clipboard, atoms.utf8, atoms.property, event.time)
        unsafe xcb_discard_reply(connection, cookie.sequence)
        flush()
        return true
      }
    }
    if event.window == readState?.window, event.atom == atoms.property,
      event.state == XCB_PROPERTY_NEW_VALUE.rawValue, readState?.buffer.incremental == true,
      readState?.reply == nil
    {
      requestProperty(offset: 0)
      flush()
      return true
    }
    let key = Key(window: event.window, property: event.atom)
    guard sends[key] != nil, event.state == XCB_PROPERTY_DELETE.rawValue else { return false }
    if sends[key]?.awaitingDelete == true {
      sendNextChunk(key)
    } else if sends[key]?.notified == true, sends[key]?.barrier != nil {
      sends[key]?.deletedEarly = true
    }
    flush()
    return true
  }

  private func requestProperty(offset: UInt32) {
    guard let connection = unsafe connection, let requestor = readState?.window else { return }
    readState?.reply = unsafe xcb_get_property(
      connection, 0, requestor, atoms.property, UInt32(XCB_GET_PROPERTY_TYPE_ANY.rawValue),
      offset, UInt32(X11ClipboardLimits.chunkBytes / 4)
    ).sequence
  }

  private func pollProperty(_ sequence: UInt32) {
    guard let connection = unsafe connection else { return }
    var pointer: UnsafeMutableRawPointer?
    var error: UnsafeMutablePointer<xcb_generic_error_t>?
    guard unsafe xcb_poll_for_reply(connection, sequence, &pointer, &error) != 0 else { return }
    defer {
      unsafe free(pointer)
      unsafe free(error)
    }
    readState?.reply = nil
    guard unsafe error == nil, let pointer = unsafe pointer else {
      finishRead(nil)
      return
    }
    unsafe consumeProperty(pointer.assumingMemoryBound(to: xcb_get_property_reply_t.self))
  }

  private func consumeProperty(_ reply: UnsafePointer<xcb_get_property_reply_t>) {
    guard readState != nil else { return }
    let header = unsafe reply.pointee
    let byteCount = Int(unsafe xcb_get_property_value_length(reply))
    guard byteCount >= 0, byteCount <= X11ClipboardLimits.chunkBytes else {
      finishRead(nil)
      return
    }
    let address = unsafe xcb_get_property_value(reply)
    if header.type == atoms.incr, readState?.buffer.incremental == false,
      header.format == 32, byteCount == 4, let address = unsafe address
    {
      let minimum = unsafe address.loadUnaligned(as: UInt32.self)
      guard
        readState?.buffer.beginIncremental(
          advertisedBytes: minimum, format: header.format, valueCount: Int(header.value_len),
          bytesAfter: header.bytes_after) == true
      else {
        finishRead(nil)
        return
      }
      deleteReadProperty()
      return
    }
    guard header.type == atoms.utf8, unsafe byteCount == 0 || address != nil else {
      finishRead(nil)
      return
    }
    let fragment: [UInt8]
    if let address = unsafe address, byteCount > 0 {
      fragment = unsafe Array(
        UnsafeBufferPointer(start: address.assumingMemoryBound(to: UInt8.self), count: byteCount))
    } else {
      fragment = []
    }
    guard
      let step = readState?.buffer.receive(
        fragment, format: header.format, bytesAfter: header.bytes_after)
    else {
      return
    }
    switch step {
    case .moreProperty(let offset): requestProperty(offset: offset)
    case .nextChunk: deleteReadProperty()
    case .complete(let text): finishRead(text)
    case .invalid: finishRead(nil)
    }
  }

  private func deleteReadProperty() {
    guard let connection = unsafe connection, let requestor = readState?.window else { return }
    let cookie = unsafe xcb_delete_property_checked(connection, requestor, atoms.property)
    unsafe xcb_discard_reply(connection, cookie.sequence)
  }

  private func finishRead(_ result: String?, destroyed: Bool = false) {
    guard let read = readState else { return }
    readState = nil
    if let connection = unsafe connection {
      if let reply = read.reply { unsafe xcb_discard_reply(connection, reply) }
      if !destroyed {
        let deleted = unsafe xcb_delete_property_checked(connection, read.window, atoms.property)
        unsafe xcb_discard_reply(connection, deleted.sequence)
        let cookie = unsafe xcb_destroy_window_checked(connection, read.window)
        unsafe xcb_discard_reply(connection, cookie.sequence)
      }
      flush()
    }
    read.continuation.resume(returning: result)
  }

  private func serve(_ request: xcb_selection_request_event_t) {
    let property = request.property == 0 ? request.target : request.property
    let key = Key(window: request.requestor, property: property)
    guard let bytes, request.requestor != 0, property != 0,
      request.time == 0 || Self.isAtOrAfter(request.time, ownershipTime),
      sends[key] == nil, sends.count < X11ClipboardLimits.maximumSends
    else {
      notify(request, property: 0)
      return
    }
    let value: Value
    let type: UInt32
    if request.target == atoms.targets {
      value = .words([atoms.targets, atoms.timestamp, atoms.utf8])
      type = UInt32(XCB_ATOM_ATOM.rawValue)
    } else if request.target == atoms.timestamp {
      value = .words([ownershipTime])
      type = UInt32(XCB_ATOM_INTEGER.rawValue)
    } else if request.target == atoms.utf8 {
      value = .bytes(bytes)
      type = atoms.utf8
    } else {
      notify(request, property: 0)
      return
    }
    let retained = sends.values.reduce(0) { $0 + $1.value.byteCount }
    guard value.byteCount <= X11ClipboardLimits.maximumSendingBytes - retained else {
      notify(request, property: 0)
      return
    }
    let incremental = value.byteCount > chunkBytes
    sends[key] = Send(
      request: request, deadline: .now.advanced(by: X11ClipboardLimits.timeout), value: value,
      type: type,
      buffer: incremental ? X11ClipboardSendBuffer(bytes: bytes) : nil)
    if incremental {
      if watches[key.window]?.ready == true {
        publishInitial(key)
      } else if watches[key.window] == nil, let connection = unsafe connection {
        watches[key.window] = Watch(
          attributes: unsafe xcb_get_window_attributes(connection, key.window).sequence)
      }
    } else {
      publishInitial(key)
    }
  }

  private func pollWatch(_ requestor: UInt32) {
    guard let watch = watches[requestor] else { return }
    if let sequence = watch.attributes {
      consumeReply(sequence, as: xcb_get_window_attributes_reply_t.self) { reply in
        watches[requestor]?.attributes = nil
        guard let reply, let connection = unsafe connection else {
          failWatch(requestor)
          return
        }
        watches[requestor]?.originalMask = reply.your_event_mask
        var mask =
          reply.your_event_mask
          | UInt32(
            XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue | XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue)
        watches[requestor]?.maskCheck = unsafe xcb_change_window_attributes_checked(
          connection, requestor, UInt32(XCB_CW_EVENT_MASK.rawValue), &mask
        ).sequence
        watches[requestor]?.barrier = unsafe xcb_get_input_focus(connection).sequence
      }
    } else if let sequence = watch.barrier {
      consumeReply(sequence, as: xcb_get_input_focus_reply_t.self) { reply in
        watches[requestor]?.barrier = nil
        guard reply != nil, let check = watches[requestor]?.maskCheck, checkSucceeded(check) else {
          failWatch(requestor)
          return
        }
        watches[requestor]?.maskCheck = nil
        watches[requestor]?.ready = true
        for key in sends.keys.filter({ $0.window == requestor && sends[$0]?.buffer != nil }) {
          publishInitial(key)
        }
      }
    }
  }

  private func failWatch(_ requestor: UInt32) {
    for key in sends.keys.filter({ $0.window == requestor }) { finishSend(key, failed: true) }
  }

  private func publishInitial(_ key: Key) {
    guard let send = sends[key] else { return }
    if send.buffer != nil {
      publish(key, type: atoms.incr, value: .words([UInt32(send.value.byteCount)]))
    } else {
      publish(key, type: send.type, value: send.value)
    }
  }

  private func publish(_ key: Key, type: UInt32, value: Value) {
    guard let connection = unsafe connection else { return }
    sends[key]?.awaitingDelete = false
    sends[key]?.propertyCheck = changeProperty(
      on: key.window, property: key.property, type: type, value: value)
    sends[key]?.barrier = unsafe xcb_get_input_focus(connection).sequence
  }

  private func pollSend(_ key: Key) {
    guard let sequence = sends[key]?.barrier else { return }
    consumeReply(sequence, as: xcb_get_input_focus_reply_t.self) { reply in
      sends[key]?.barrier = nil
      guard reply != nil, let check = sends[key]?.propertyCheck, checkSucceeded(check),
        let send = sends[key]
      else {
        finishSend(key, failed: true)
        return
      }
      sends[key]?.propertyCheck = nil
      if !send.notified {
        notify(send.request, property: key.property)
        sends[key]?.notified = true
      }
      if send.buffer == nil {
        finishSend(key, failed: false)
      } else {
        sends[key]?.awaitingDelete = true
        if send.deletedEarly {
          sends[key]?.deletedEarly = false
          sendNextChunk(key)
        }
      }
    }
  }

  private func sendNextChunk(_ key: Key) {
    guard let next = sends[key]?.buffer?.nextChunk(maximum: chunkBytes) else {
      finishSend(key, failed: false)
      return
    }
    publish(key, type: atoms.utf8, value: .bytes(next))
  }

  private func finishSend(_ key: Key, failed: Bool, destroyed: Bool = false) {
    guard let send = sends.removeValue(forKey: key), let connection = unsafe connection else {
      return
    }
    if let check = send.propertyCheck { unsafe xcb_discard_reply(connection, check) }
    if let barrier = send.barrier { unsafe xcb_discard_reply(connection, barrier) }
    if failed, !send.notified, !destroyed { notify(send.request, property: 0) }
    guard !sends.contains(where: { $0.key.window == key.window && $0.value.buffer != nil }),
      let watch = watches.removeValue(forKey: key.window)
    else { return }
    if let sequence = watch.attributes { unsafe xcb_discard_reply(connection, sequence) }
    if let sequence = watch.maskCheck { unsafe xcb_discard_reply(connection, sequence) }
    if let sequence = watch.barrier { unsafe xcb_discard_reply(connection, sequence) }
    if !destroyed, var mask = watch.originalMask {
      let cookie = unsafe xcb_change_window_attributes_checked(
        connection, key.window, UInt32(XCB_CW_EVENT_MASK.rawValue), &mask)
      unsafe xcb_discard_reply(connection, cookie.sequence)
    }
  }

  private func changeProperty(on requestor: UInt32, property: UInt32, type: UInt32, value: Value)
    -> UInt32
  {
    guard let connection = unsafe connection else { return 0 }
    switch value {
    case .bytes(let bytes):
      return bytes.withUnsafeBytes { buffer in
        unsafe xcb_change_property_checked(
          connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), requestor, property, type, 8,
          UInt32(buffer.count),
          buffer.baseAddress
        ).sequence
      }
    case .words(let words):
      return words.withUnsafeBytes { buffer in
        unsafe xcb_change_property_checked(
          connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), requestor, property, type, 32,
          UInt32(words.count),
          buffer.baseAddress
        ).sequence
      }
    }
  }

  private func notify(_ request: xcb_selection_request_event_t, property: UInt32) {
    guard let connection = unsafe connection else { return }
    var event = xcb_selection_notify_event_t()
    event.response_type = UInt8(XCB_SELECTION_NOTIFY)
    event.time = request.time
    event.requestor = request.requestor
    event.selection = request.selection
    event.target = request.target
    event.property = property
    // XCB SendEvent always copies 32 bytes, even though the C event struct is smaller.
    var wire = [UInt8](repeating: 0, count: 32)
    withUnsafeBytes(of: &event) { source in
      for index in source.indices { wire[index] = unsafe source[index] }
    }
    let cookie = wire.withUnsafeBytes { buffer in
      unsafe xcb_send_event_checked(
        connection, 0, request.requestor, 0, buffer.baseAddress!.assumingMemoryBound(to: CChar.self)
      )
    }
    unsafe xcb_discard_reply(connection, cookie.sequence)
  }

  /// A later server reply proves the checked void request has been processed, so
  /// request_check here cannot wait for the peer or for an additional round trip.
  private func checkSucceeded(_ sequence: UInt32) -> Bool {
    guard let connection = unsafe connection else { return false }
    let error = unsafe xcb_request_check(connection, xcb_void_cookie_t(sequence: sequence))
    guard let error = unsafe error else { return true }
    unsafe free(error)
    return false
  }

  private func consumeReply<Reply: BitwiseCopyable>(
    _ sequence: UInt32, as: Reply.Type, _ body: (Reply?) -> Void
  ) {
    guard let connection = unsafe connection else { return }
    var pointer: UnsafeMutableRawPointer?
    var error: UnsafeMutablePointer<xcb_generic_error_t>?
    guard unsafe xcb_poll_for_reply(connection, sequence, &pointer, &error) != 0 else { return }
    defer {
      unsafe free(pointer)
      unsafe free(error)
    }
    guard unsafe error == nil, let pointer = unsafe pointer else {
      body(nil)
      return
    }
    body(unsafe pointer.load(as: Reply.self))
  }

  private func flush() {
    if let connection = unsafe connection { _ = unsafe xcb_flush(connection) }
  }
}
