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

private struct ModelText: Block {
  let model: BlockModel
  var body: some Block {
    Text(model.title).selectable(key: 1).frame(width: .fill, height: .fixed(32))
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
    for input in [
      Input(), Input(mousePosition: .init(x: 5, y: 40), pressed: true),
      Input(mousePosition: .init(x: 5, y: 40), released: true)
    ] {
      var expected: [DrawRect] = []
      legacy.frame(
        input: input, dt: 0,
        build: { frame in
          frame.beginColumn(in: Region(0, 0, 120, 100), gap: 4)
          frame.canvas(key: 1, extent: 32) { _ in }
          frame.button(key: 2, "Action", extent: 40) { legacyClicks += 1 }
          frame.beginRow(in: Region(200, 0, 100, 20), gap: 3)
          frame.canvas(key: 3, extent: 20) { _ in }
          frame.canvas(key: 4, extent: 30) { _ in }
          frame.end()
          frame.canvas(key: 5, extent: 10) { _ in }
          frame.end()
        }, present: { for draw in $0.rectangles { expected.append(draw) } })
      host.frame(
        input: input, dt: 0,
        build: {
          Column(in: Region(0, 0, 120, 100), gap: 4) {
            StoredContent {
              Canvas(key: 1, extent: 32) { _ in }
              Button(key: 2, "Action", extent: 40) { clicks += 1 }
            }
            Row(in: Region(200, 0, 100, 20), gap: 3) {
              Canvas(key: 3, extent: 20) { _ in }
              Canvas(key: 4, extent: 30) { _ in }
            }
            Canvas(key: 5, extent: 10) { _ in }
          }
        },
        present: { actual in
          #expect(actual.count == expected.count)
          for index in 0..<min(actual.count, expected.count) {
            #expect(actual[index].rectangle.region == expected[index].region)
            #expect(actual[index].rectangle.color == expected[index].color)
            #expect(actual[index].rectangle.clip == expected[index].clip)
            #expect(actual[index].rectangle.glyphUV == expected[index].glyphUV)
          }
        })
      #expect(host.state(for: 4)?.region == Region(223, 0, 30, 20))
      #expect(host.state(for: 5)?.region == Region(0, 80, 120, 10))
    }
    #expect(clicks == 1 && legacyClicks == 1)
  }

  @Test func branchesOptionalRowsAndEmptyContentPreserveOnlyLiveKeys() {
    var host = UIHost()
    for alternate in [false, true, false] {
      host.frame(
        build: {
          BlockBuilder.buildBlock()
          Column(in: Region(0, 0, 100, 100), gap: 0) {
            if alternate {
              Button(key: 1, "Button")
            } else {
              Text("Label").selectable(key: 2).frame(width: .fill, height: .fixed(32))
            }
            if alternate { Text("Optional").selectable(key: 3).frame(width: .fill, height: .fixed(32)) }
            ForEach(alternate ? [UInt64(5), 4] : [4, 5]) { key in
              Text("").selectable(key: key).frame(width: .fill, height: .fixed(10))
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
        Scroll(key: 10, in: Region(0, 0, 100, 50)) {
          Column(gap: 0) {
            Text("").selectable(key: 1).frame(width: .fill, height: .fixed(100))
            Element(key: 2, extent: 30, onKey: { _ in activated = true }) { _ in
              painted = activated
            }
          }
        }
        ScrollTo(10, in: 10)
        Focus(key: 2, reveal: true)
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
            Column(in: Region(0, 0, 100, 100)) {
              StoredContent { ModelText(model: model) }
              ForEach([UInt64(2)]) { key in
                Text(model.alternate ? "Alternate" : "Default").selectable(key: key).frame(
                  width: .fill, height: .fixed(32))
              }
              Canvas(key: 3, extent: 10) { _ in _ = model.title }
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
            Column(in: Region(0, 0, 100, 100)) {
              Text("First").selectable(key: 1).frame(width: .fill, height: .fixed(32))
              Text("Duplicate").selectable(key: 1).frame(width: .fill, height: .fixed(32))
            }
          }, present: { _ in })
      }
    }
  }

  @Test func requestsBeforeDeclarationDoNotUsePreviousFrameTargets() {
    var host = UIHost()
    host.frame(
      build: {
        Scroll(key: 10, in: Region(0, 0, 100, 50)) {
          Column(gap: 0) {
            Button(key: 1, "", extent: 200)
          }
        }
      }, present: { _ in })
    host.frame(
      build: {
        Focus(key: 1)
        ScrollTo(100, in: 10)
        Scroll(key: 10, in: Region(0, 0, 100, 50)) {
          Column(gap: 0) {
            Button(key: 1, "", extent: 200)
          }
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
          Column(in: Region(0, 0, 100, 40)) {
            Button(key: 1, "") { _ = token }
          }
        }, present: { _ in })
    }
    #expect(retained != nil)
    host.frame(build: {}, present: { _ in })
    #expect(retained == nil)
  }
}
