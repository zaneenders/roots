import Testing

public struct GraphicsTest: SuiteTrait, TestScoping {
  public init() {}

  public func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    await GraphicsTestLock.shared.acquire()
    do {
      try await function()
      await GraphicsTestLock.shared.release()
    } catch {
      await GraphicsTestLock.shared.release()
      throw error
    }
  }
}

private actor GraphicsTestLock {
  static let shared = GraphicsTestLock()
  private var locked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    if !locked {
      locked = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
  }
}
