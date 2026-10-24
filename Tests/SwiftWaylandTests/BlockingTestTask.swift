import Foundation

func blockingTestTask<Result: Sendable>(
  _ operation: @escaping @Sendable () throws -> Result
) -> Task<Result, any Error> {
  Task {
    try await withCheckedThrowingContinuation { continuation in
      Thread.detachNewThread {
        continuation.resume(with: Swift.Result(catching: operation))
      }
    }
  }
}

func blockingTestTask<Result: Sendable>(
  _ operation: @escaping @Sendable () -> Result
) -> Task<Result, Never> {
  Task {
    await withCheckedContinuation { continuation in
      Thread.detachNewThread { continuation.resume(returning: operation()) }
    }
  }
}
