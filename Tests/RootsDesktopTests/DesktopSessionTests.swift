import Roots
import Testing

@testable import RootsDesktop

private enum SessionFailure: Error { case backend }

@MainActor
struct DesktopSessionTests {
  @Test(arguments: [false, true])
  func lifecycleClosesAfterPresentationOrBackendFailure(fails: Bool) async {
    var events: [String] = []
    var session = DesktopSession(nodeCapacity: 16, scrollAcceleration: 0, scrollDeceleration: 8)
    session.start = { events.append("start") }
    session.close = { events.append("close") }
    do {
      try await session.run(
        content: { _ in EmptyBlock() },
        present: { runtime in
          #expect(events == ["start"])
          events.append("present")
          runtime.frame(
            input: Input(), viewport: Viewport(size: .init(width: 100, height: 26)), time: 0,
            present: { _ in })
          await Task.yield()
          if fails { throw SessionFailure.backend }
        })
      #expect(!fails)
    } catch {
      #expect(fails && error is SessionFailure)
    }
    #expect(events == ["start", "present", "close"])
  }

  @Test func sharedSessionForwardsFrameCallbacksAndKeyboardInterception() async throws {
    var prepared = 0
    var updated = 0
    var finished = 0
    var intercepted = 0
    var session = DesktopSession(nodeCapacity: 16, scrollAcceleration: 0, scrollDeceleration: 8)
    session.frameCallbacks.prepare = { _, _ in prepared += 1 }
    session.frameCallbacks.update = { _ in
      updated += 1
      return .present
    }
    session.frameCallbacks.finish = { _ in finished += 1 }
    session.frameCallbacks.needsAnimationFrame = { true }
    session.keyHandler = { _ in
      intercepted += 1
      return true
    }
    try await session.run(
      content: { _ in EmptyBlock() }, offscreen: true,
      present: { runtime in
        runtime.frame(
          input: Input(keyEvents: [KeyEvent(.enter)]),
          viewport: Viewport(size: .init(width: 100, height: 26)),
          time: 0,
          present: { _ in })
        #expect(runtime.needsAnimationFrame)
      })
    #expect(prepared == 1 && updated == 1 && finished == 1 && intercepted == 1)
  }
}
