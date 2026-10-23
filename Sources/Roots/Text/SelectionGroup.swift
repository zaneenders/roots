public struct SelectionGroup<Content: Block>: Block {
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
  public func selectionGroup(key: UInt64) -> SelectionGroup<Self> {
    SelectionGroup(key: key, content: self)
  }
}
