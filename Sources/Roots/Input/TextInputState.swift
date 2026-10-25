/// Text-input context in logical surface coordinates. All text offsets are UTF-8 bytes.
/// Backends may impose additional limits on surrounding text.
public struct TextInputState: Equatable, Sendable {
  public enum Purpose: Sendable {
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
  public var isValid: Bool {
    let bytes = Array(surroundingText.utf8)
    func boundary(_ index: Int32) -> Bool {
      index >= 0 && Int(index) <= bytes.count
        && (Int(index) == bytes.count || bytes[Int(index)] & 0xc0 != 0x80)
    }
    return hints.rawValue & ~UInt32(1023) == 0
      && boundary(cursor) && boundary(anchor)
      && cursorRectangle.z >= 0 && cursorRectangle.w >= 0
  }
}
