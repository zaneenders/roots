import Observation
import Synchronization
import Testing

@_spi(Hosting) @testable import Roots

@MainActor @Observable
private final class BlockModel {
  var title = "Initial"
  var alternate = false
  var unrelated = 0
  @ObservationIgnored var ignored = 0
}

private struct ModelLabel: Block {
  let model: BlockModel
  var body: some Block {
    LabelBlock(key: 1, model.title, selectable: false)
  }
}

private struct StoredContent<Content: Block>: Block {
  let content: Content
  init(@BlockBuilder content: () -> Content) { self.content = content() }
  var body: some Block { content }
}

@MainActor
struct BlockTests {
  @Test func composedAndImperativeGeometryDrawsAndInputAgree() {
    var legacy = UIStore()
    var host = UIHost()
    var legacyClicks = 0
    var clicks = 0
    for input in [Input(), Input(x: 5, y: 40, pressed: true), Input(x: 5, y: 40, released: true)] {
      var expected: [DrawRect] = []
      legacy.frame(
        input: input, dt: 0,
        build: { frame in
          frame.beginColumn(in: Rect(0, 0, 120, 100), gap: 4)
          frame.label(key: 1, "Title", extent: 32, selectable: false)
          frame.button(key: 2, "Action", extent: 40) { legacyClicks += 1 }
          frame.beginRow(in: Rect(200, 0, 100, 20), gap: 3)
          frame.label(key: 3, "", extent: 20)
          frame.label(key: 4, "", extent: 30)
          frame.end()
          frame.label(key: 5, "", extent: 10)
          frame.end()
        }, present: { for draw in $0 { expected.append(draw) } })
      host.frame(
        input: input, dt: 0,
        build: {
          ColumnBlock(in: Rect(0, 0, 120, 100), gap: 4) {
            StoredContent {
              LabelBlock(key: 1, "Title", extent: 32, selectable: false)
              ButtonBlock(key: 2, "Action", extent: 40) { clicks += 1 }
            }
            RowBlock(in: Rect(200, 0, 100, 20), gap: 3) {
              LabelBlock(key: 3, "", extent: 20)
              LabelBlock(key: 4, "", extent: 30)
            }
            LabelBlock(key: 5, "", extent: 10)
          }
        },
        present: { actual in
          #expect(actual.count == expected.count)
          for index in 0..<min(actual.count, expected.count) {
            #expect(actual[index].rect == expected[index].rect)
            #expect(actual[index].color == expected[index].color)
            #expect(actual[index].clip == expected[index].clip)
            #expect(actual[index].glyphUV == expected[index].glyphUV)
          }
        })
      #expect(host.state(for: 4)?.rect == Rect(223, 0, 30, 20))
      #expect(host.state(for: 5)?.rect == Rect(0, 80, 120, 10))
    }
    #expect(clicks == 1 && legacyClicks == 1)
  }

  @Test func branchesOptionalRowsAndEmptyContentPreserveOnlyLiveKeys() {
    var host = UIHost()
    for alternate in [false, true, false] {
      host.frame(
        build: {
          EmptyBlock()
          ColumnBlock(in: Rect(0, 0, 100, 100), gap: 0) {
            if alternate {
              ButtonBlock(key: 1, "Button")
            } else {
              LabelBlock(key: 2, "Label")
            }
            if alternate { LabelBlock(key: 3, "Optional") }
            ForEachBlock(alternate ? [UInt64(5), 4] : [4, 5]) { key in
              LabelBlock(key: key, "", extent: 10)
            }
          }
        }, present: { _ in })
      #expect((host.state(for: 1) != nil) == alternate)
      #expect((host.state(for: 2) == nil) == alternate)
      #expect((host.state(for: 3) != nil) == alternate)
      #expect(host.liveCount == (alternate ? 4 : 3))
    }
    host.frame(
      build: {},
      present: {
        let empty = $0.isEmpty
        #expect(empty)
      })
    #expect(host.liveCount == 0)
  }

  @Test func focusScrollAndCurrentFramePaintingUseTheSameEngine() {
    var host = UIHost()
    var activated = false
    var painted = false
    host.frame(
      input: Input(keyEvents: [KeyEvent(.enter)]), dt: 0,
      build: {
        ScrollColumnBlock(key: 10, in: Rect(0, 0, 100, 50), gap: 0) {
          LabelBlock(key: 1, "", extent: 100)
          ElementBlock(key: 2, extent: 30, onKey: { _ in activated = true }) { _ in
            painted = activated
          }
        }
        ScrollToBlock(10, in: 10)
        FocusBlock(key: 2, reveal: true)
      }, present: { _ in })
    #expect(host.state(for: 2)?.focused == true)
    #expect(host.state(for: 10)?.scrollOffset == 80)
    #expect(activated && painted)
  }

  @Test func nestedBodiesRowsAndPaintReadsStayInsideObservationTracking() {
    let model = BlockModel()
    var host = UIHost()
    let notifications = Synchronization.Mutex(0)
    func trackedFrame() {
      withObservationTracking {
        host.frame(
          build: {
            ColumnBlock(in: Rect(0, 0, 100, 100)) {
              StoredContent { ModelLabel(model: model) }
              ForEachBlock([UInt64(2)]) { key in
                LabelBlock(key: key, model.alternate ? "Alternate" : "Default")
              }
              CanvasBlock(key: 3, extent: 10) { _ in _ = model.title }
            }
          }, present: { _ in })
      } onChange: {
        notifications.withLock { $0 += 1 }
      }
    }
    trackedFrame()
    model.unrelated += 1
    model.ignored += 1
    #expect(notifications.withLock { $0 } == 0)
    model.title = "Changed"
    model.alternate = true
    #expect(notifications.withLock { $0 } == 1)
    trackedFrame()
    model.alternate = false
    #expect(notifications.withLock { $0 } == 2)
  }

  @Test func duplicateKeysStillTrap() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        var host = UIHost()
        host.frame(
          build: {
            ColumnBlock(in: Rect(0, 0, 100, 100)) {
              LabelBlock(key: 1, "First")
              LabelBlock(key: 1, "Duplicate")
            }
          }, present: { _ in })
      }
    }
  }

  @Test func requestsBeforeDeclarationDoNotUsePreviousFrameTargets() {
    var host = UIHost()
    host.frame(
      build: {
        ScrollColumnBlock(key: 10, in: Rect(0, 0, 100, 50), gap: 0) {
          ButtonBlock(key: 1, "", extent: 200)
        }
      }, present: { _ in })
    host.frame(
      build: {
        FocusBlock(key: 1)
        ScrollToBlock(100, in: 10)
        ScrollColumnBlock(key: 10, in: Rect(0, 0, 100, 50), gap: 0) {
          ButtonBlock(key: 1, "", extent: 200)
        }
      }, present: { _ in })
    #expect(host.state(for: 1)?.focused == false)
    #expect(host.state(for: 10)?.scrollOffset == 0)
  }

  @Test func descriptionsAndCallbacksReleaseWithoutRetainingTheHost() {
    final class Token {}
    weak var retained: Token?
    var host = UIHost()
    do {
      let token = Token()
      retained = token
      host.frame(
        build: {
          ColumnBlock(in: Rect(0, 0, 100, 40)) {
            ButtonBlock(key: 1, "") { _ = token }
          }
        }, present: { _ in })
    }
    #expect(retained != nil)
    host.frame(build: {}, present: { _ in })
    #expect(retained == nil)
  }
}
