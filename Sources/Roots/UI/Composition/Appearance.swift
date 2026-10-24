public struct _Background<Content: Block>: Block {
  public typealias Body = Never
  let content: Content
  let color: Color

  public borrowing func _build(into frame: inout UIFrame) {
    let content = content
    frame.withBackground(color) { frame in
      content._build(into: &frame)
    }
  }
}

public struct _Foreground<Content: Block>: Block {
  public typealias Body = Never
  let content: Content
  let color: Color

  public borrowing func _build(into frame: inout UIFrame) {
    let content = content
    frame.withColor(color) { frame in
      content._build(into: &frame)
    }
  }
}

extension Block {
  public func background(_ color: Color) -> _Background<Self> {
    _Background(content: self, color: color)
  }

  public func color(_ color: Color) -> _Foreground<Self> {
    _Foreground(content: self, color: color)
  }
}
