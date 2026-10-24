/// Shares a selection across descendant text that has opted in with `.selectable()`.
public struct TextSelectionGroup<Content: Block>: Block {
  public typealias Body = Never
  let key: UInt64
  let content: Content

  public init(key: UInt64, @BlockBuilder content: () -> Content) {
    self.key = key
    self.content = content()
  }

  init(key: UInt64, content: Content) {
    self.key = key
    self.content = content
  }

  public borrowing func _build(into frame: inout UIFrame) {
    let content = content
    frame.withSelectionGroup(key) { frame in
      content._build(into: &frame)
    }
  }
}

extension Block {
  public func textSelectionGroup(key: UInt64) -> TextSelectionGroup<Self> {
    TextSelectionGroup(key: key, content: self)
  }
}
