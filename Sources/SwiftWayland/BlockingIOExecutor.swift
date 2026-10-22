import Foundation

final class BlockingIOExecutor: TaskExecutor {
  static let shared = BlockingIOExecutor()

  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    Thread.detachNewThread {
      unsafe job.runSynchronously(on: self.asUnownedTaskExecutor())
    }
  }
}
