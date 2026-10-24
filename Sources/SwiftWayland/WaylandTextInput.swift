/// All text offsets and deletion lengths are UTF-8 bytes, not Swift Character indices.
public struct WaylandPreedit: Equatable, Sendable {
  public var text: String
  public var cursorBegin: Int32
  public var cursorEnd: Int32
  public init(text: String, cursorBegin: Int32, cursorEnd: Int32) {
    self.text = text
    self.cursorBegin = cursorBegin
    self.cursorEnd = cursorEnd
  }
}

/// Apply atomically: remove old preedit, delete surrounding text, commit, then set new preedit.
public struct WaylandTextInputEvent: Equatable, Sendable {
  public var committed: String?
  public var preedit: WaylandPreedit?
  public var deleteBefore: UInt32
  public var deleteAfter: UInt32
  public init(
    committed: String? = nil, preedit: WaylandPreedit? = nil,
    deleteBefore: UInt32 = 0, deleteAfter: UInt32 = 0
  ) {
    self.committed = committed
    self.preedit = preedit
    self.deleteBefore = deleteBefore
    self.deleteAfter = deleteAfter
  }
}

public struct WaylandTextInputState: Equatable, Sendable {
  public enum Purpose: UInt32, Sendable {
    case normal, alpha, digits, number, phone, url, email, name, password, pin, date, time,
      dateTime, terminal
  }
  public struct Hints: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let completion = Hints(rawValue: 1)
    public static let spellcheck = Hints(rawValue: 2)
    public static let autoCapitalization = Hints(rawValue: 4)
    public static let lowercase = Hints(rawValue: 8)
    public static let uppercase = Hints(rawValue: 16)
    public static let titlecase = Hints(rawValue: 32)
    public static let hidden = Hints(rawValue: 64)
    public static let sensitiveData = Hints(rawValue: 128)
    public static let latin = Hints(rawValue: 256)
    public static let multiline = Hints(rawValue: 512)
  }
  public var purpose: Purpose
  public var hints: Hints
  public var surroundingText: String
  public var cursor: Int32
  public var anchor: Int32
  public var cursorRectangle: SIMD4<Int32>
  public var changeCausedByInputMethod: Bool
  public init(
    surroundingText: String, cursor: Int32, anchor: Int32,
    cursorRectangle: SIMD4<Int32>, changeCausedByInputMethod: Bool = false,
    purpose: Purpose = .normal, hints: Hints = []
  ) {
    self.purpose = purpose
    self.hints = hints
    self.surroundingText = surroundingText
    self.cursor = cursor
    self.anchor = anchor
    self.cursorRectangle = cursorRectangle
    self.changeCausedByInputMethod = changeCausedByInputMethod
  }
  var isValid: Bool {
    guard surroundingText.utf8.count <= 4000 else { return false }
    let bytes = Array(surroundingText.utf8)
    func boundary(_ index: Int32) -> Bool {
      index >= 0 && Int(index) <= bytes.count
        && (Int(index) == bytes.count || bytes[Int(index)] & 0xc0 != 0x80)
    }
    return hints.rawValue & ~UInt32(1023) == 0
      && !bytes.contains(0) && boundary(cursor) && boundary(anchor)
      && cursorRectangle.z >= 0 && cursorRectangle.w >= 0
  }
}

@MainActor final class WaylandTextInput {
  private let objects: WaylandObjects
  var manager: UInt32 = 0
  private(set) var id: UInt32 = 0
  private(set) var surface: UInt32 = 0
  private var states: [UInt32: WaylandTextInputState] = [:]
  private var enabled = false
  private var serial: UInt32 = 0
  private var pending = WaylandTextInputEvent()
  // A stale done still delivers edits, but state updates wait for a matching done.
  private var awaitingCurrent = false
  private var dirty = false

  init(objects: WaylandObjects) { self.objects = objects }

  func attach(seat: UInt32) {
    guard id == 0, manager != 0, seat != 0 else { return }
    id = objects.create(manager, 1, "zwp_text_input_v3", [.uint(seat)])
  }

  func set(_ state: WaylandTextInputState?, on surface: UInt32) {
    guard states[surface] != state else { return }
    states[surface] = state
    guard self.surface == surface else { return }
    dirty = true
    // Enable/disable transitions cannot wait for an old input-method transaction.
    if !awaitingCurrent || enabled != (state != nil) { apply() }
  }

  private func apply() {
    guard id != 0, surface != 0 else { return }
    let state = states[surface]
    guard dirty || enabled != (state != nil) else { return }
    dirty = false
    if let state {
      if !enabled { objects.request(id, 1) }
      objects.request(
        id, 3, [.string(state.surroundingText), .int(state.cursor), .int(state.anchor)])
      objects.request(id, 4, [.uint(state.changeCausedByInputMethod ? 0 : 1)])
      objects.request(id, 5, [.uint(state.hints.rawValue), .uint(state.purpose.rawValue)])
      let r = state.cursorRectangle
      objects.request(id, 6, [.int(r.x), .int(r.y), .int(r.z), .int(r.w)])
    } else {
      objects.request(id, 2)
      pending = .init()
    }
    enabled = state != nil
    objects.request(id, 7)
    serial &+= 1
  }

  func event(_ message: WireMessage) -> (surface: UInt32, edit: WaylandTextInputEvent)? {
    guard message.object == id else { return nil }
    let a = message.arguments
    switch message.opcode {
    case 0:
      surface = a[0].word
      enabled = false
      pending = .init()
      awaitingCurrent = false
      dirty = states[surface] != nil
      apply()
    case 1:
      let old = surface
      surface = 0
      enabled = false
      pending = .init()
      awaitingCurrent = false
      return (old, .init())
    case 2 where enabled:
      pending.preedit = a[0].text.map {
        WaylandPreedit(text: $0, cursorBegin: a[1].signed, cursorEnd: a[2].signed)
      }
    case 3 where enabled: pending.committed = a[0].text
    case 4 where enabled:
      pending.deleteBefore = a[0].word
      pending.deleteAfter = a[1].word
    case 5:
      let edit = pending
      pending = .init()
      awaitingCurrent = a[0].word != serial
      if !awaitingCurrent, dirty { apply() }
      if enabled { return (surface, edit) }
    default: break
    }
    return nil
  }

  func detach() {
    objects.request(id, 0)
    id = 0
    surface = 0
    enabled = false
    serial = 0
    pending = .init()
    awaitingCurrent = false
  }
  func close() {
    detach()
    objects.request(manager, 0)
    manager = 0
    states.removeAll()
  }
}
