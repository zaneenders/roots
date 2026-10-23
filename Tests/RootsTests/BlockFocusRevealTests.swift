@_spi(Hosting) import Roots
import Testing

@MainActor
struct BlockFocusRevealTests {
  @Test(arguments: [Float(0), 50, 100])
  func keysLeaveViewportSpanningElementsStationary(initialOffset: Float) {
    var host = UIHost()
    var received: [KeyEvent] = []
    let events = [
      KeyEvent(.right), KeyEvent(.right, phase: .repeated), KeyEvent(.right, phase: .repeated)
    ]
    for index in 0...events.count {
      host.frame(
        input: Input(keyEvents: index == 0 ? [] : [events[index - 1]]), dt: 0,
        build: {
          ScrollColumnBlock(key: 1, in: Rect(0, 0, 100, 100), gap: 0) {
            ElementBlock(key: 2, extent: 200, onKey: { received.append($0) }) { _ in }
          }
          if index == 0 { ScrollToBlock(initialOffset, in: 1) }
          FocusBlock(key: 2)
        }, present: { _ in })
      #expect(host.state(for: 1)?.scrollOffset == initialOffset)
      #expect(host.state(for: 2)?.focused == true)
    }
    #expect(received == events)
  }

  @Test(arguments: [
    (height: Float(200), initialOffset: Float(0), expectedOffset: Float(120)),
    (200, 80, 120), (200, 170, 170), (200, 240, 220), (200, 400, 220),
    (100, 0, 120), (100, 140, 120),
    (30, 0, 50), (30, 80, 80), (30, 140, 120), (30, 300, 120)
  ])
  func keysRevealTheNearestEdgeAndThenSettle(
    height: Float, initialOffset: Float, expectedOffset: Float
  ) {
    var host = UIHost()
    let events = [
      KeyEvent(.right), KeyEvent(.right, phase: .repeated), KeyEvent(.right, phase: .repeated)
    ]
    for index in 0...events.count {
      host.frame(
        input: Input(keyEvents: index == 0 ? [] : [events[index - 1]]), dt: 0,
        build: {
          ScrollColumnBlock(key: 1, in: Rect(10, 20, 100, 100), gap: 0) {
            CanvasBlock(key: 3, extent: 120) { _ in }
            ElementBlock(key: 2, extent: height, onKey: { _ in }) { _ in }
            CanvasBlock(key: 4, extent: 400) { _ in }
          }
          if index == 0 { ScrollToBlock(initialOffset, in: 1) }
          FocusBlock(key: 2)
        }, present: { _ in })
      #expect(host.state(for: 1)?.scrollOffset == (index == 0 ? initialOffset : expectedOffset))
    }
  }

  @Test(arguments: [
    (height: Float(200), initialOffset: Float(0), expectedOffset: Float(118)),
    (200, 400, 222), (98, 0, 118), (98, 300, 120),
    (96, 0, 118), (96, 300, 118), (30, 0, 52), (30, 300, 118)
  ])
  func requestedRevealAccountsForPaddingAndThenSettles(
    height: Float, initialOffset: Float, expectedOffset: Float
  ) {
    var host = UIHost()
    for index in 0..<4 {
      host.frame(
        dt: 0,
        build: {
          ScrollColumnBlock(key: 1, in: Rect(10, 20, 100, 100), gap: 0) {
            CanvasBlock(key: 3, extent: 120) { _ in }
            ElementBlock(key: 2, extent: height, onKey: { _ in }) { _ in }
            CanvasBlock(key: 4, extent: 400) { _ in }
          }
          if index == 0 { ScrollToBlock(initialOffset, in: 1) }
          FocusBlock(key: 2, reveal: true)
        }, present: { _ in })
      #expect(host.state(for: 1)?.scrollOffset == expectedOffset)
    }
  }

  @Test(arguments: [Float(30), 200], [false, true])
  func nestedViewportsSettleWithKeysAndRequestedReveal(height: Float, reveal: Bool) {
    var host = UIHost()
    for phase in [KeyPhase.pressed, .repeated, .repeated, .pressed] {
      host.frame(
        input: Input(keyEvents: [KeyEvent(.right, phase: phase)]), dt: 0,
        build: {
          ScrollColumnBlock(key: 10, in: Rect(10, 20, 100, 100), gap: 0) {
            ScrollColumnBlock(key: 1, in: Rect(10, 140, 100, 60), gap: 0) {
              CanvasBlock(key: 3, extent: 40) { _ in }
              ElementBlock(key: 2, extent: height, onKey: { _ in }) { _ in }
              CanvasBlock(key: 4, extent: 200) { _ in }
            }
            CanvasBlock(key: 11, extent: 400) { _ in }
          }
          FocusBlock(key: 2, reveal: reveal)
        }, present: { _ in })
      let innerOffset: Float = height == 200 ? 40 : (reveal ? 12 : 10)
      #expect(host.state(for: 1)?.scrollOffset == innerOffset)
      #expect(host.state(for: 10)?.scrollOffset == 80)
      #expect(host.state(for: 2)?.focused == true)
    }
  }

  @Test(arguments: [false, true])
  func nestedRevealUsesOnlyTheTargetsVisiblePortion(reveal: Bool) {
    var host = UIHost()
    for phase in [KeyPhase.pressed, .repeated, .repeated, .pressed] {
      host.frame(
        input: Input(keyEvents: [KeyEvent(.right, phase: phase)]), dt: 0,
        build: {
          ScrollColumnBlock(key: 10, in: Rect(10, 140, 100, 100), gap: 0) {
            ScrollColumnBlock(key: 1, in: Rect(10, 140, 100, 60), gap: 0) {
              ColumnBlock(in: Rect(10, 20, 100, 400), gap: 0) {
                ElementBlock(key: 2, extent: 400, onKey: { _ in }) { _ in }
              }
            }
            CanvasBlock(key: 11, extent: 400) { _ in }
          }
          if phase == .pressed { ScrollToBlock(100, in: 10) }
          FocusBlock(key: 2, reveal: reveal)
        }, present: { _ in })
      #expect(host.state(for: 1)?.scrollOffset == 0)
      #expect(host.state(for: 10)?.scrollOffset == 0)
      #expect(host.state(for: 1)?.rect == Rect(10, 140, 100, 60))
    }
  }
}
