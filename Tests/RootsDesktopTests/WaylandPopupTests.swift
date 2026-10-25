#if os(Linux)
import DesktopTestSupport
@_spi(Hosting) import Roots
import Testing
import WaylandBridge

@testable import RootsDesktop

@Suite(GraphicsTest())
@MainActor
struct WaylandPopupTests {
  @Test func failedPresentationDoesNotBuildContentOrCloseAnUnstartedSession() {
    var builds = 0
    var closes = 0
    let popup = WaylandPopup(
      configuration: .init(x: 0, y: 0, anchorWidth: 20, anchorHeight: 26, width: 320, height: 320)
    ) { _ in
      builds += 1
      return BlockBuilder.buildBlock()
    }.onClose { closes += 1 }
    #expect(!popup.present())
    #expect(builds == 0 && closes == 0)
  }

  @Test func popupRuntimeInvalidationUsesItsOwnRedrawCallback() {
    var redraws = 0
    var session = DesktopSession(nodeCapacity: 16, scrollAcceleration: 0, scrollDeceleration: 8)
    session.frameCallbacks.needsAnimationFrame = { true }
    let runtime = session.makeRuntime(
      content: { _ in BlockBuilder.buildBlock() }, requestRedraw: { redraws += 1 })
    defer { runtime.stop() }
    for frame in 0..<2 {
      runtime.frame(
        input: Input(), viewport: Viewport(size: .init(width: 100, height: 26)),
        time: Double(frame) / 60, present: { _ in })
      #expect(redraws == frame + 1)
    }
  }

  @Test func popupSessionUsesSharedRuntimeForKeysFocusAndFeedback() {
    var frames = 0
    var keys = 0
    var session = DesktopSession(nodeCapacity: 16, scrollAcceleration: 0, scrollDeceleration: 8)
    session.frameCallbacks.finish = { state in
      frames += 1
      #expect(state.state(for: 1)?.focused == true)
    }
    session.keyHandler = { _ in
      keys += 1
      return true
    }
    let runtime = session.makeRuntime(
      content: { viewport in
        Column(in: viewport.bounds) {
          Button(key: 1, "Action", onClick: {})
          Focus(key: 1)
        }
      }, offscreen: true)
    defer { runtime.stop() }
    runtime.frame(
      input: Input(keyEvents: [KeyEvent(.enter)]), viewport: Viewport(size: .init(width: 320, height: 320)),
      time: 0,
      present: { _ in })
    #expect(keys == 1 && frames == 1)
  }
}
#endif
