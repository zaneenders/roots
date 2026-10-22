public struct ColumnBlock<Content: Block>: Block {
  public typealias Body = Never
  @usableFromInline
  let rect: Rect
  @usableFromInline
  let gap: Float
  @usableFromInline
  let content: Content
  @inlinable
  public init(in rect: Rect, gap: Float = 8, @BlockBuilder content: () -> Content) {
    self.rect = rect
    self.gap = gap
    self.content = content()
  }
  @inlinable
  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginColumn(in: rect, gap: gap)
    defer { frame.end() }
    content._build(into: &frame)
  }
}

public struct RowBlock<Content: Block>: Block {
  public typealias Body = Never
  let rect: Rect
  let gap: Float
  let content: Content
  public init(in rect: Rect, gap: Float = 8, @BlockBuilder content: () -> Content) {
    self.rect = rect
    self.gap = gap
    self.content = content()
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginRow(in: rect, gap: gap)
    defer { frame.end() }
    content._build(into: &frame)
  }
}

public struct ScrollColumnBlock<Content: Block>: Block {
  public typealias Body = Never
  let key: UInt64
  let rect: Rect
  let gap: Float
  let showsScrollIndicator: Bool
  let content: Content
  public init(
    key: UInt64, in rect: Rect, gap: Float = 8, showsScrollIndicator: Bool = false,
    @BlockBuilder content: () -> Content
  ) {
    self.key = key
    self.rect = rect
    self.gap = gap
    self.showsScrollIndicator = showsScrollIndicator
    self.content = content()
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginScrollColumn(
      key: key, in: rect, gap: gap, showsScrollIndicator: showsScrollIndicator)
    defer { frame.end() }
    content._build(into: &frame)
  }
}

public struct FocusBlock: Block {
  public typealias Body = Never
  let key: UInt64
  let reveal: Bool
  public init(key: UInt64, reveal: Bool = false) {
    self.key = key
    self.reveal = reveal
  }
  public borrowing func _build(into frame: inout UIFrame) { frame.focus(key: key, reveal: reveal) }
}

public struct ScrollToBlock: Block {
  public typealias Body = Never
  let key: UInt64
  let offset: Float
  public init(_ offset: Float, in key: UInt64) {
    self.key = key
    self.offset = offset
  }
  public borrowing func _build(into frame: inout UIFrame) { frame.scrollTo(offset, in: key) }
}
