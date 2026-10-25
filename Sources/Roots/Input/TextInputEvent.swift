/// All text offsets and deletion lengths are UTF-8 bytes, not Swift Character indices.
public struct TextPreedit: Equatable, Sendable {
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
/// `keyEvents` retains physical/logical keys for shortcuts; do not also insert their characters.
public struct TextInputEvent: Equatable, Sendable {
  public var committed: String?
  public var preedit: TextPreedit?
  public var deleteBefore: UInt32
  public var deleteAfter: UInt32
  public init(
    committed: String? = nil, preedit: TextPreedit? = nil,
    deleteBefore: UInt32 = 0, deleteAfter: UInt32 = 0
  ) {
    self.committed = committed
    self.preedit = preedit
    self.deleteBefore = deleteBefore
    self.deleteAfter = deleteAfter
  }
}
