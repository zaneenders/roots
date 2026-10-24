public struct Column<Content: Block>: Block {
  public typealias Body = Never
  let region: Region?
  let gap: Float
  let alignment: Alignment
  let content: Content

  public init(
    in region: Region? = nil, gap: Float = 8, alignment: Alignment = .topLeading,
    @BlockBuilder content: () -> Content
  ) {
    self.region = region
    self.gap = gap
    self.alignment = alignment
    self.content = content()
  }

  public borrowing func _build(into frame: inout UIFrame) {
    if let region, alignment == .topLeading {
      frame.beginColumn(in: region, gap: gap)
    } else {
      frame.beginLayout(LayoutStyle(kind: .column, alignment: alignment, gap: gap), in: region)
    }
    defer { frame.end() }
    content._build(into: &frame)
  }
}

public struct Row<Content: Block>: Block {
  public typealias Body = Never
  let region: Region?
  let gap: Float
  let alignment: Alignment
  let content: Content

  public init(
    in region: Region? = nil, gap: Float = 8, alignment: Alignment = .topLeading,
    @BlockBuilder content: () -> Content
  ) {
    self.region = region
    self.gap = gap
    self.alignment = alignment
    self.content = content()
  }

  public borrowing func _build(into frame: inout UIFrame) {
    if let region, alignment == .topLeading {
      frame.beginRow(in: region, gap: gap)
    } else {
      frame.beginLayout(LayoutStyle(kind: .row, alignment: alignment, gap: gap), in: region)
    }
    defer { frame.end() }
    content._build(into: &frame)
  }
}

public struct Stack<Content: Block>: Block {
  public typealias Body = Never
  let region: Region?
  let alignment: Alignment
  let content: Content

  public init(
    in region: Region? = nil, alignment: Alignment = .center, @BlockBuilder content: () -> Content
  ) {
    self.region = region
    self.alignment = alignment
    self.content = content()
  }

  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginLayout(LayoutStyle(alignment: alignment), in: region)
    defer { frame.end() }
    content._build(into: &frame)
  }
}

public struct Grid<Content: Block>: Block {
  public typealias Body = Never
  let region: Region?
  let columns: Int
  let gap: Float
  let alignment: Alignment
  let content: Content

  public init(
    in region: Region? = nil, columns: Int, gap: Float = 8, alignment: Alignment = .center,
    @BlockBuilder content: () -> Content
  ) {
    precondition(columns > 0)
    self.region = region
    self.columns = columns
    self.gap = gap
    self.alignment = alignment
    self.content = content()
  }

  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginLayout(LayoutStyle(kind: .grid(columns), alignment: alignment, gap: gap), in: region)
    defer { frame.end() }
    content._build(into: &frame)
  }
}

/// A vertical viewport; its content chooses the layout rather than implying a column.
public struct Scroll<Content: Block>: Block {
  public typealias Body = Never
  let key: UInt64
  let region: Region
  let showsScrollIndicator: Bool
  let content: Content
  public init(
    key: UInt64, in region: Region, showsScrollIndicator: Bool = false,
    @BlockBuilder content: () -> Content
  ) {
    self.key = key
    self.region = region
    self.showsScrollIndicator = showsScrollIndicator
    self.content = content()
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginScroll(
      key: key, in: region, showsScrollIndicator: showsScrollIndicator)
    defer { frame.end() }
    content._build(into: &frame)
  }
}
