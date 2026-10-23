public struct TextRun: Sendable {
  public var text: String
  public var color: Color
  public var background: Color?

  public init(_ text: String, color: Color = .text, background: Color? = nil) {
    self.text = text
    self.color = color
    self.background = background
  }
}
