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

public struct RowBlock<Content: Block>: Block {
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

public struct ZStack<Content: Block>: Block {
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

public struct ScrollColumn<Content: Block>: Block {
  public typealias Body = Never
  let key: UInt64
  let region: Region
  let gap: Float
  let showsScrollIndicator: Bool
  let content: Content
  public init(
    key: UInt64, in region: Region, gap: Float = 8, showsScrollIndicator: Bool = false,
    @BlockBuilder content: () -> Content
  ) {
    self.key = key
    self.region = region
    self.gap = gap
    self.showsScrollIndicator = showsScrollIndicator
    self.content = content()
  }
  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginScrollColumn(
      key: key, in: region, gap: gap, showsScrollIndicator: showsScrollIndicator)
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
