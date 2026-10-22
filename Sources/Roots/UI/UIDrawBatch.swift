public struct UIDrawBatch: ~Copyable, ~Escapable, Iterable {
  package let draws: Span<DrawRect>

  @_lifetime(copy draws)
  init(_ draws: Span<DrawRect>) {
    self.draws = draws
  }

  public var count: Int { draws.count }
  public var isEmpty: Bool { draws.isEmpty }
  public var underestimatedCount: Int { draws.count }

  public subscript(index: Int) -> DrawRect {
    _read { yield draws[index] }
  }

  @_lifetime(borrow self)
  public func makeBorrowingIterator() -> Span<DrawRect>.BorrowingIterator {
    draws.makeBorrowingIterator()
  }
}
