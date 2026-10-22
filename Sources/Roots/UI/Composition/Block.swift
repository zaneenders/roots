@MainActor
public protocol Block {
  associatedtype Body: Block
  @BlockBuilder var body: Body { get }
  borrowing func _build(into frame: inout UIFrame)
}

extension Block {
  public borrowing func _build(into frame: inout UIFrame) {
    let content = body
    content._build(into: &frame)
  }
}

extension Block where Body == Never {
  public var body: Never { fatalError("Primitive blocks lower directly; they have no body") }
}

extension Never: Block {
  public typealias Body = Never
  public borrowing func _build(into frame: inout UIFrame) {}
}

@MainActor
@resultBuilder
public enum BlockBuilder {
  public static func buildBlock() -> EmptyBlock { EmptyBlock() }
  public static func buildExpression<Content: Block>(_ content: Content) -> Content { content }
  public static func buildPartialBlock<Content: Block>(first: Content) -> Content { first }
  public static func buildPartialBlock<First: Block, Next: Block>(
    accumulated: First, next: Next
  ) -> PairBlock<First, Next> { PairBlock(first: accumulated, next: next) }
  public static func buildEither<First: Block, Second: Block>(first: First) -> ConditionalBlock<
    First, Second
  > {
    .first(first)
  }
  public static func buildEither<First: Block, Second: Block>(second: Second) -> ConditionalBlock<
    First, Second
  > {
    .second(second)
  }
  public static func buildOptional<Content: Block>(_ content: Content?) -> OptionalBlock<Content> {
    OptionalBlock(content: content)
  }
}

public struct EmptyBlock: Block {
  public typealias Body = Never
  public init() {}
  public borrowing func _build(into frame: inout UIFrame) {}
}

public struct PairBlock<First: Block, Next: Block>: Block {
  public typealias Body = Never
  let first: First
  let next: Next
  public borrowing func _build(into frame: inout UIFrame) {
    first._build(into: &frame)
    next._build(into: &frame)
  }
}

public enum ConditionalBlock<First: Block, Second: Block>: Block {
  public typealias Body = Never
  case first(First)
  case second(Second)
  public borrowing func _build(into frame: inout UIFrame) {
    switch copy self {
    case .first(let content): content._build(into: &frame)
    case .second(let content): content._build(into: &frame)
    }
  }
}

public struct OptionalBlock<Content: Block>: Block {
  public typealias Body = Never
  let content: Content?
  public borrowing func _build(into frame: inout UIFrame) { content?._build(into: &frame) }
}

public struct ForEachBlock<Data: RandomAccessCollection, Content: Block>: Block {
  public typealias Body = Never
  @usableFromInline
  let data: Data
  @usableFromInline
  let content: @MainActor (Data.Element) -> Content
  @inlinable
  public init(_ data: Data, @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content) {
    self.data = data
    self.content = content
  }
  @inlinable
  public borrowing func _build(into frame: inout UIFrame) {
    for element in data {
      let row = content(element)
      row._build(into: &frame)
    }
  }
}
