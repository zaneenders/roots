#if os(Linux)
  import Roots
  import Testing
  import WaylandBridge

  @testable import RootsDesktop

  @MainActor
  struct WaylandPopupTests {
    @Test func failedPresentationDoesNotBuildContentOrCloseAnUnstartedSession() {
      var builds = 0
      var closes = 0
      let popup = WaylandPopup(
        configuration: .init(x: 0, y: 0, anchorWidth: 20, anchorHeight: 26, width: 320, height: 320)
      ) { _ in
        builds += 1
        return EmptyBlock()
      }.onClose { closes += 1 }
      #expect(!popup.present())
      #expect(builds == 0 && closes == 0)
    }

    @Test func popupSessionUsesSharedRuntimeForKeysFocusAndFeedback() {
      final class Delegate: DesktopFrameDelegate {
        var frames = 0
        func didFinishFrame(_ state: borrowing UIState) {
          frames += 1
          #expect(state.state(for: 1)?.focused == true)
        }
      }
      let delegate = Delegate()
      var keys = 0
      var session = DesktopSession(nodeCapacity: 16, scrollAcceleration: 0, scrollDeceleration: 8)
      session.delegate = delegate
      session.keyHandler = { _ in
        keys += 1
        return true
      }
      let runtime = session.makeRuntime(
        content: { viewport in
          ColumnBlock(in: viewport.bounds) {
            ButtonBlock(key: 1, "Action", onClick: {})
            FocusBlock(key: 1)
          }
        }, offscreen: true)
      defer { runtime.stop() }
      runtime.frame(
        input: Input(keyEvents: [KeyEvent(.enter)]), viewport: Viewport(size: .init(320, 320)),
        time: 0,
        present: { _ in })
      #expect(keys == 1 && delegate.frames == 1)
    }
  }
#endif
