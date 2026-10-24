public struct Rectangle: Block {
  public typealias Body = Never
  private var style = RectangleStyle()

  public init() {}

  public func radius(_ radius: Float) -> Self {
    precondition(radius.isFinite && radius >= 0)
    var copy = self
    copy.style.cornerRadius = radius
    return copy
  }

  public func stroke(width: Float = 1) -> Self {
    precondition(width.isFinite && width >= 0)
    var copy = self
    copy.style.strokeWidth = width
    return copy
  }

  public borrowing func _build(into frame: inout UIFrame) {
    frame.rectangle(style)
  }
}

struct RectangleStyle {
  var cornerRadius: Float = 0
  var strokeWidth: Float?
}
