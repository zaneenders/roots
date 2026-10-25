public struct UIDrawBatch: ~Copyable, ~Escapable, Iterable {
  public let commands: Span<DrawCommand>

  @_lifetime(copy draws)
  public init(_ draws: Span<DrawCommand>) {
    self.commands = draws
  }

  public var count: Int { commands.count }
  public var isEmpty: Bool { commands.isEmpty }
  public var underestimatedCount: Int { commands.count }

  public subscript(index: Int) -> DrawCommand {
    _read { yield commands[index] }
  }

  @_lifetime(borrow self)
  public func makeBorrowingIterator() -> Span<DrawCommand>.BorrowingIterator {
    commands.makeBorrowingIterator()
  }
}
