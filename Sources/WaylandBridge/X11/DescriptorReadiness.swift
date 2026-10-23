import Dispatch
import Glibc

enum DescriptorReadinessError: Error, Equatable {
  case duplicateFailed(Int32)
  case alreadyWaiting
}

/// Suspends the main actor without allowing a dispatch handler to access native host or GPU handles.
@MainActor final class DescriptorReadiness {
  private let descriptor: Int32
  private let writable: Bool
  private var source: (any DispatchSourceProtocol)?
  private var continuation: CheckedContinuation<Void, any Error>?
  private var timer: Task<Void, Never>?
  private var cancelled = false
  private var woken = false

  init(_ descriptor: Int32, writable: Bool = false) {
    self.descriptor = descriptor
    self.writable = writable
  }

  func wait(until deadline: ContinuousClock.Instant? = nil) async throws {
    guard continuation == nil else { throw DescriptorReadinessError.alreadyWaiting }
    guard !cancelled else { throw CancellationError() }
    try Task.checkCancellation()
    if woken { return }
    if let deadline, deadline <= .now { return }
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        // Own a duplicate: the source's cancellation handler may run after the host closes its FD.
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else {
          continuation.resume(throwing: DescriptorReadinessError.duplicateFailed(errno))
          return
        }
        self.continuation = continuation
        let source: any DispatchSourceProtocol =
          writable
          ? DispatchSource.makeWriteSource(fileDescriptor: duplicate, queue: .main)
          : DispatchSource.makeReadSource(fileDescriptor: duplicate, queue: .main)
        self.source = source
        source.setCancelHandler { _ = close(duplicate) }
        source.setEventHandler { [weak self] in
          MainActor.assumeIsolated { self?.finish(.success(())) }
        }
        source.resume()
        if let deadline {
          timer = Task { @MainActor [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            self?.finish(.success(()))
          }
        }
      }
    } onCancel: {
      Task { @MainActor in self.cancel() }
    }
  }

  /// An application redraw/close is a successful wake, not task cancellation.
  /// Remember an early wake so installation of the continuation cannot lose it.
  func wake() {
    woken = true
    finish(.success(()))
  }

  func cancel() {
    cancelled = true
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<Void, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    timer?.cancel()
    timer = nil
    source?.cancel()
    source = nil
    continuation.resume(with: result)
  }
}
