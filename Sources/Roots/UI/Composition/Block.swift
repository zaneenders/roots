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
  public static func buildBlock() -> _Empty { _Empty() }
  public static func buildExpression<Content: Block>(_ content: Content) -> Content { content }
  public static func buildPartialBlock<Content: Block>(first: Content) -> Content { first }
  public static func buildPartialBlock<First: Block, Next: Block>(
    accumulated: First, next: Next
  ) -> _Pair<First, Next> { _Pair(first: accumulated, next: next) }
  public static func buildEither<First: Block, Second: Block>(first: First) -> _Conditional<
    First, Second
  > {
    _Conditional(content: .first(first))
  }
  public static func buildEither<First: Block, Second: Block>(second: Second) -> _Conditional<
    First, Second
  > {
    _Conditional(content: .second(second))
  }
  public static func buildOptional<Content: Block>(_ content: Content?) -> _OptionalContent<Content> {
    _OptionalContent(content: content)
  }
}

public struct _Empty: Block {
  public typealias Body = Never
  init() {}
  public borrowing func _build(into frame: inout UIFrame) {}
}

public struct _Pair<First: Block, Next: Block>: Block {
  public typealias Body = Never
  let first: First
  let next: Next
  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginChild(0)
    first._build(into: &frame)
    frame.endIdentity()
    frame.beginChild(1)
    next._build(into: &frame)
    frame.endIdentity()
  }
}

public struct _Conditional<First: Block, Second: Block>: Block {
  public typealias Body = Never
  enum Content {
    case first(First)
    case second(Second)
  }
  let content: Content
  public borrowing func _build(into frame: inout UIFrame) {
    switch content {
    case .first(let content):
      frame.beginChild(0)
      content._build(into: &frame)
    case .second(let content):
      frame.beginChild(1)
      content._build(into: &frame)
    }
    frame.endIdentity()
  }
}

public struct _OptionalContent<Content: Block>: Block {
  public typealias Body = Never
  let content: Content?
  public borrowing func _build(into frame: inout UIFrame) { content?._build(into: &frame) }
}

public struct ForEach<Data: RandomAccessCollection, Content: Block>: Block {
  public typealias Body = Never
  @usableFromInline
  let data: Data
  @usableFromInline
  let content: @MainActor (Data.Element) -> Content
  @usableFromInline
  let identity: ((Data.Element) -> AnyHashable)?
  @usableFromInline
  let location: IdentityLocation

  @inlinable
  public init(_ data: Data, @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content) {
    self.data = data
    self.content = content
    self.identity = nil
    self.location = IdentityLocation(file: #fileID, line: #line, column: #column)
  }

  public init<ID: Hashable>(
    _ data: Data, id: KeyPath<Data.Element, ID>,
    file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.data = data
    self.content = content
    self.identity = { AnyHashable($0[keyPath: id]) }
    self.location = IdentityLocation(file: file, line: line, column: column)
  }

  @inlinable
  public borrowing func _build(into frame: inout UIFrame) {
    if let identity {
      var seen: Set<AnyHashable> = []
      for element in data {
        let id = identity(element)
        precondition(seen.insert(id).inserted, "ForEach item IDs must be unique")
        frame.beginItem(id, at: location)
        let row = content(element)
        row._build(into: &frame)
        frame.endIdentity()
      }
    } else {
      for element in data {
        let row = content(element)
        row._build(into: &frame)
      }
    }
  }
}
