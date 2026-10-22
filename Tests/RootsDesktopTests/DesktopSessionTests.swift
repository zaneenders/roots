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
            input: Input(), viewport: Viewport(size: .init(100, 26)), time: 0, present: { _ in })
          await Task.yield()
          if fails { throw SessionFailure.backend }
        })
      #expect(!fails)
    } catch {
      #expect(fails && error is SessionFailure)
    }
    #expect(events == ["start", "present", "close"])
  }

  @Test func sharedSessionForwardsFramePolicyAndKeyboardInterception() async throws {
    final class Delegate: DesktopFrameDelegate {
      var prepared = 0
      var finished = 0
      func prepareFrame(input: inout Input, dt: Float) { prepared += 1 }
      func didFinishFrame(_ state: borrowing UIState) { finished += 1 }
    }
    let delegate = Delegate()
    var intercepted = 0
    var session = DesktopSession(nodeCapacity: 16, scrollAcceleration: 0, scrollDeceleration: 8)
    session.delegate = delegate
    session.keyHandler = { _ in
      intercepted += 1
      return true
    }
    try await session.run(
      content: { _ in EmptyBlock() }, offscreen: true,
      present: { runtime in
        runtime.frame(
          input: Input(keyEvents: [KeyEvent(.enter)]), viewport: Viewport(size: .init(100, 26)),
          time: 0,
          present: { _ in })
      })
    #expect(delegate.prepared == 1 && delegate.finished == 1 && intercepted == 1)
  }
}
