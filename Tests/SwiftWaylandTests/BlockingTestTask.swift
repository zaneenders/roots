@testable import SwiftWayland

func blockingTestTask<Result: Sendable>(
  _ operation: @escaping @Sendable () throws -> Result
) -> Task<Result, any Error> {
  Task(executorPreference: BlockingIOExecutor.shared) { try operation() }
}

func blockingTestTask<Result: Sendable>(
  _ operation: @escaping @Sendable () -> Result
) -> Task<Result, Never> {
  Task(executorPreference: BlockingIOExecutor.shared) { operation() }
}
