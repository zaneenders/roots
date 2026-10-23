public struct Rectangle: Block {
  public typealias Body = Never
  private var style: RectangleStyle

  public init(cornerRadius: Float = 0) {
    precondition(cornerRadius.isFinite && cornerRadius >= 0)
    style = RectangleStyle(cornerRadius: cornerRadius)
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

public typealias Rect = Rectangle

struct RectangleStyle {
  var cornerRadius: Float = 0
  var strokeWidth: Float?
}
