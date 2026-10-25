import Foundation
import Observation
import Roots

/// A timestamp clock, independent of decoder speed and display refresh rate.
struct PlaybackClock {
  private var origin = ContinuousClock.now
  private var pausedAt: ContinuousClock.Instant?

  mutating func reset(at now: ContinuousClock.Instant = .now) {
    origin = now
    pausedAt = nil
  }
  mutating func pause(at now: ContinuousClock.Instant = .now) {
    if pausedAt == nil { pausedAt = now }
  }
  mutating func resume(at now: ContinuousClock.Instant = .now) {
    if let pausedAt { origin += pausedAt.duration(to: now) }
    pausedAt = nil
  }
  func deadline(for seconds: Double) -> ContinuousClock.Instant { origin + .seconds(seconds) }
}

@MainActor @Observable
final class Player {
  let source = ImageSource()
  private(set) var status = "Opening…"
  private(set) var paused = false
  @ObservationIgnored private let path: String
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var stopping: Task<Void, Never>?
  @ObservationIgnored private var wake: CheckedContinuation<Void, Never>?
  @ObservationIgnored private var generation: UInt64 = 0
  @ObservationIgnored private var clock = PlaybackClock()

  init(path: String) { self.path = path }

  func start() {
    guard task == nil else { return }
    paused = false
    status = "Opening…"
    let generation = generation
    let previous = stopping
    task = Task { [weak self, path] in
      let decoder = Decoder()
      do {
        await previous?.value
        try Task.checkCancellation()
        try await decoder.open(path)
        try Task.checkCancellation()
        guard let self else {
          await decoder.close()
          return
        }
        var current = try await decoder.next()
        try Task.checkCancellation()
        self.clock.reset()
        if self.paused { self.clock.pause() }
        self.status = self.paused ? "Paused · Space to resume" : "Playing · muted"
        while let frame = current {
          try Task.checkCancellation()
          while self.paused {
            await withCheckedContinuation { self.wake = $0 }
            try Task.checkCancellation()
          }
          let deadline = self.clock.deadline(for: frame.seconds)
          if deadline > .now {
            // Short sleeps allow pause/restart without building an unbounded task queue.
            try await Task.sleep(until: min(deadline, .now + .milliseconds(50)), clock: .continuous)
            continue
          }
          // The source is a latest-frame mailbox. If decoding catches up faster
          // than presentation, intermediate frames are replaced, not queued.
          self.source.publish(frame.image)
          current = try await decoder.next()
        }
        try Task.checkCancellation()
        self.status = "Finished · R to restart"
      } catch is CancellationError {
        // Closing/restarting is not a playback error.
      } catch {
        if self?.generation == generation { self?.status = String(describing: error) }
      }
      await decoder.close()
      if self?.generation == generation { self?.task = nil }
    }
  }

  func togglePause() {
    guard task != nil else { return }
    paused.toggle()
    if paused {
      clock.pause()
      status = "Paused · Space to resume"
    } else {
      clock.resume()
      status = "Playing · muted"
      wake?.resume()
      wake = nil
    }
  }

  func stop() {
    generation += 1
    task?.cancel()
    stopping = task ?? stopping
    task = nil
    wake?.resume()
    wake = nil
  }

  func restart() {
    stop()
    paused = false
    source.publish(nil)
    start()
  }
}
