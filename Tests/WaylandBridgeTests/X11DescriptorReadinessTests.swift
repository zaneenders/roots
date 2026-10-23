import Glibc
import Testing

@testable import WaylandBridge

@MainActor struct X11DescriptorReadinessTests {
  @Test func applicationWakeSucceedsWithoutDescriptorInput() async throws {
    // No FD duplication is needed for an early wake, even for an invalid FD.
    let early = DescriptorReadiness(-1)
    early.wake()
    try await early.wait()

    var descriptors: [Int32] = [-1, -1]
    try #require(unsafe pipe(&descriptors) == 0)
    defer {
      _ = close(descriptors[0])
      _ = close(descriptors[1])
    }
    let wait = DescriptorReadiness(descriptors[0])
    let wake = Task {
      try await Task.sleep(for: .milliseconds(5))
      wait.wake()
    }
    defer { wake.cancel() }
    let started = ContinuousClock.now
    try await wait.wait(until: started.advanced(by: .seconds(1)))
    #expect(started.duration(to: .now) < .milliseconds(500))
    try await wake.value
  }

  @Test func taskCancellationInterruptsAnInstalledDescriptorWait() async throws {
    var descriptors: [Int32] = [-1, -1]
    try #require(unsafe pipe(&descriptors) == 0)
    defer {
      _ = close(descriptors[0])
      _ = close(descriptors[1])
    }
    let wait = DescriptorReadiness(descriptors[0])
    let task = Task { try await wait.wait(until: .now.advanced(by: .seconds(1))) }
    try await Task.sleep(for: .milliseconds(5))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func cancellationRemainsDistinctFromApplicationWake() async {
    let wait = DescriptorReadiness(-1)
    wait.cancel()
    await #expect(throws: CancellationError.self) { try await wait.wait() }
  }
}
