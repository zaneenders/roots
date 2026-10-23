public struct TextLine: Sendable {
  public var runs: [TextRun]
  public var x: Float
  public var y: Float
  var font: MonospaceFont
  public var size: Float {
    get { font.size }
    set { font = MonospaceFont(size: newValue) }
  }
  public var background: Color?

  public init(
    _ runs: [TextRun], x: Float = 12, y: Float, size: Float = 20,
    background: Color? = nil
  ) {
    self.runs = runs
    self.x = x
    self.y = y
    self.font = MonospaceFont(size: size)
    self.background = background
  }
}
