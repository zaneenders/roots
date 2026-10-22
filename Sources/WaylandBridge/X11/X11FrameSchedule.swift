/// Coalesced on-demand invalidation with a bounded presentation rate. An idle
/// window has no frame deadline and therefore no unconditional animation timer.
struct X11FrameSchedule {
  private(set) var redrawRequested = true
  private var nextFrame: ContinuousClock.Instant
  static let interval: Duration = .nanoseconds(16_666_667)

  init(now: ContinuousClock.Instant = .now) { nextFrame = now }

  var deadline: ContinuousClock.Instant? { redrawRequested ? nextFrame : nil }

  /// Clipboard work must retain a deadline even when the window is idle or
  /// unmapped; only render deadlines are gated on whether it is drawable.
  func waitDeadline(drawable: Bool, clipboardDeadline: ContinuousClock.Instant?) -> ContinuousClock
    .Instant?
  {
    let renderDeadline = drawable ? deadline : nil
    if let clipboardDeadline { return min(renderDeadline ?? clipboardDeadline, clipboardDeadline) }
    return renderDeadline
  }

  func isReady(now: ContinuousClock.Instant = .now) -> Bool {
    redrawRequested && now >= nextFrame
  }

  mutating func requestRedraw() { redrawRequested = true }

  mutating func mapped(now: ContinuousClock.Instant = .now) {
    nextFrame = now
    redrawRequested = true
  }

  mutating func beginFrame() { redrawRequested = false }

  mutating func endFrame(continuously: Bool, now: ContinuousClock.Instant = .now) {
    // No catch-up burst after a slow callback. Crucially, do not clear requests
    // made during that callback; continuous mode is only for finite frame runs.
    nextFrame = now.advanced(by: Self.interval)
    if continuously { redrawRequested = true }
  }
}
