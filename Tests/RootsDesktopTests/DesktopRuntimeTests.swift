import Observation
import Roots
import RootsCPU
import Testing

@testable import RootsDesktop

@MainActor @Observable
private final class Model {
  var title = "First"
  var red: Float = 0
  var clicks = 0
  var rows: [UInt64] = [2]
  var child: Model?
}

private struct ObservedContent: Block {
  let model: Model
  let bounds: Region

  var body: some Block {
    Column(in: bounds, gap: 0) {
      Text(model.title)
        .size(20)
        .selectable(key: 1)
        .alignment(.leading)
        .padding(horizontal: 12)
        .frame(width: .fill, height: .fixed(32))
        .background(.panel)
      ForEach(model.rows) { key in
        Canvas(key: key, extent: 20) { context in
          context.fillRect(context.region, color: Color(model.red, 0, 0))
        }
      }
    }
  }
}

@MainActor
struct DesktopRuntimeTests {
  let viewport = Viewport(size: .init(100, 100))

  @Test func contentIsLazyAndReevaluatesWithViewportWhileStatePersists() {
    let model = Model()
    var builds = 0
    let window = DesktopWindow("Test") { viewport in
      builds += 1
      return Column(in: viewport.bounds, gap: 0) {
        Button(key: 1, model.title) { model.clicks += 1 }
      }
    }
    #expect(builds == 0)
    var redraws = 0
    let runtime = DesktopRuntime(
      content: window.content, primaryShortcut: .control, onCopy: { _ in },
      requestRedraw: { redraws += 1 })
    defer { runtime.stop() }
    runtime.frame(input: Input(), viewport: viewport, time: 0, present: { _ in })
    runtime.frame(
      input: Input(x: 5, y: 5, pressed: true), viewport: viewport, time: 0.01, present: { _ in })
    runtime.frame(
      input: Input(x: 5, y: 5, released: true), viewport: viewport, time: 0.02, present: { _ in })
    #expect(model.clicks == 1)
    #expect(runtime.state(for: 1)?.clicks == 1)
    runtime.frame(
      input: Input(), viewport: Viewport(size: .init(200, 100), scale: 2), time: 0.03,
      present: { _ in })
    #expect(builds == 4)
    #expect(runtime.state(for: 1)?.region.width == 200)
    #expect(runtime.state(for: 1)?.clicks == 1)
    #expect(redraws > 0)
  }

  @Test func buttonInputRebuildsNonObservableModel() throws {
    @MainActor
    final class Counter {
      var count = 0
    }
    let model = Counter()
    var titles: [String] = []
    var requests = 0
    let runtime = DesktopRuntime(
      content: { viewport in
        let title = "Count: \(model.count)"
        titles.append(title)
        return Column(in: viewport.bounds) {
          Text(title)
            .size(20)
            .selectable(key: 1)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(32))
            .background(.panel)
          Button(key: 2, "Increment") { model.count += 1 }
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: { requests += 1 })
    defer { runtime.stop() }
    runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { _ in })
    let button = try #require(runtime.state(for: 2)?.region)
    let x = button.x + button.width / 2
    let y = button.y + button.height / 2
    runtime.frame(
      input: Input(x: x, y: y, pressed: true), viewport: viewport, dt: 0, present: { _ in })
    let beforeRelease = requests
    runtime.frame(
      input: Input(x: x, y: y, released: true), viewport: viewport, dt: 0, present: { _ in })
    #expect(model.count == 1)
    #expect(titles.last == "Count: 0")
    #expect(requests == beforeRelease + 1)
    runtime.frame(input: Input(x: x, y: y), viewport: viewport, dt: 0, present: { _ in })
    #expect(titles.last == "Count: 1")
    #expect(model.count == 1)
  }

  @Test func observationIncludesNestedBodiesRowsAndPainters() async throws {
    let model = Model()
    let (redraws, signal) = AsyncStream<Void>.makeStream()
    var iterator = redraws.makeAsyncIterator()
    var requests = 0
    let runtime = DesktopRuntime(
      content: { ObservedContent(model: model, bounds: $0.bounds) }, primaryShortcut: .control,
      onCopy: { _ in },
      requestRedraw: {
        requests += 1
        signal.yield()
      })
    defer {
      runtime.stop()
      signal.finish()
    }
    let renderer = CPURenderer(width: 100, height: 100)
    runtime.frame(input: Input(), viewport: viewport, time: 0, present: { renderer.render($0) })
    #expect(requests == 0)
    model.title = "Changed"
    #expect(await iterator.next() != nil)
    runtime.frame(input: Input(), viewport: viewport, time: 1, present: { renderer.render($0) })
    model.rows.append(3)
    #expect(await iterator.next() != nil)
    runtime.frame(input: Input(), viewport: viewport, time: 2, present: { renderer.render($0) })
    #expect(runtime.state(for: 3) != nil)
    model.red = 1
    #expect(await iterator.next() != nil)
    runtime.frame(input: Input(), viewport: viewport, time: 3, present: { renderer.render($0) })
    let pixel = (40 * 100 + 10) * 3
    #expect(Array(renderer.pixels[pixel..<pixel + 3]) == [255, 0, 0])
    #expect(requests == 3)
  }

  @Test func oldSubscriptionsAndQueuedRedrawsCannotOutliveTheirFrameOrSession() async {
    let first = Model()
    let second = Model()
    let selection = Model()
    selection.child = first
    var requests = 0
    let runtime = DesktopRuntime(
      content: { ObservedContent(model: selection.child!, bounds: $0.bounds) },
      primaryShortcut: .control,
      onCopy: { _ in }, requestRedraw: { requests += 1 })
    runtime.frame(input: Input(), viewport: viewport, time: 0, present: { _ in })
    first.title = "Pending"
    selection.child = second
    runtime.frame(input: Input(), viewport: viewport, time: 1, present: { _ in })
    await Task { @MainActor in }.value
    #expect(requests == 0)
    first.red = 1
    await Task { @MainActor in }.value
    #expect(requests == 0)
    second.title = "Pending at shutdown"
    runtime.stop()
    await Task { @MainActor in }.value
    #expect(requests == 0)
  }

  @Test func inputAndObservationCoalesceAndKeyboardInterceptionPrecedesControls() async {
    let model = Model()
    var requests = 0
    var intercepted = 0
    let runtime = DesktopRuntime(
      content: { viewport in
        Column(in: viewport.bounds) {
          Button(key: 1, model.title) { model.clicks += 1 }
          FocusBlock(key: 1)
        }
      }, primaryShortcut: .control,
      onKey: { _ in
        intercepted += 1
        model.title = "Intercepted"
        return true
      },
      onCopy: { _ in }, requestRedraw: { requests += 1 })
    defer { runtime.stop() }
    runtime.frame(
      input: Input(keyEvents: [KeyEvent(.enter)]), viewport: viewport, time: 0, present: { _ in })
    await Task { @MainActor in }.value
    #expect(intercepted == 1)
    #expect(model.clicks == 0)
    #expect(requests == 1)
  }

  @Test func pointerMotionRequestsOneFollowupButIdleFramesDoNotPoll() {
    var requests = 0
    let runtime = DesktopRuntime(
      content: { _ in EmptyBlock() }, primaryShortcut: .control, onCopy: { _ in },
      requestRedraw: { requests += 1 })
    defer { runtime.stop() }
    runtime.frame(input: Input(x: 5, y: 5), viewport: viewport, time: 0, present: { _ in })
    #expect(requests == 1)
    runtime.frame(input: Input(x: 5, y: 5), viewport: viewport, time: 1, present: { _ in })
    #expect(requests == 1)
    runtime.frame(input: Input(x: 10, y: 5), viewport: viewport, time: 2, present: { _ in })
    #expect(requests == 2)
  }

  @Test func activeEngineAnimationsRequestAnotherFrame() {
    var requests = 0
    let runtime = DesktopRuntime(
      content: { viewport in
        Column(in: viewport.bounds) { Button(key: 1, "Hover") }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: { requests += 1 })
    defer { runtime.stop() }
    runtime.frame(input: Input(x: 5, y: 5), viewport: viewport, time: 0, present: { _ in })
    #expect(requests == 1)
  }

  @Test func stoppingReleasesRetainedCallbacksAndModels() {
    weak var releasedModel: Model?
    do {
      let model = Model()
      releasedModel = model
      let runtime = DesktopRuntime(
        content: { viewport in
          Column(in: viewport.bounds) { Button(key: 1, "Action") { model.clicks += 1 } }
        }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {})
      runtime.frame(input: Input(), viewport: viewport, time: 0, present: { _ in })
      runtime.stop()
    }
    #expect(releasedModel == nil)
  }
}

@MainActor
private final class FramePolicy {
  var prepares: [Float] = []
  var updates = 0
  var finishes = 0
  var suppressInput = false
  var rebuild = false
  var rebuildPointer: SIMD2<Float>?
  var needsAnimationFrame = false
  var buttonState: NodeState?
  var selectedText: String?
  var onUpdate: (() -> Void)?
  var onFinish: (() -> Void)?

  var callbacks: DesktopFrameCallbacks {
    .init(
      prepare: { self.prepareFrame(input: &$0, dt: $1) },
      update: { self.frameUpdate(after: $0) },
      finish: { self.didFinishFrame($0) },
      needsAnimationFrame: { self.needsAnimationFrame })
  }

  func prepareFrame(input: inout Input, dt: Float) {
    prepares.append(dt)
    if suppressInput { input = Input() }
  }

  func frameUpdate(after input: Input) -> DesktopFrameUpdate {
    updates += 1
    onUpdate?()
    return rebuild ? .rebuild(pointer: rebuildPointer) : .present
  }

  func didFinishFrame(_ state: borrowing UIState) {
    finishes += 1
    buttonState = state.state(for: 1)
    selectedText = state.selectedText
    onFinish?()
  }
}

extension DesktopRuntimeTests {
  @Test(arguments: [false, true], [false, true])
  func frameCallbacksInvalidateContentAndPaintReads(afterPresentation: Bool, paintOnly: Bool) async {
    let model = Model()
    let policy = FramePolicy()
    let change = {
      if paintOnly { model.red = 1 } else { model.title = "Changed" }
    }
    if afterPresentation { policy.onFinish = change } else { policy.onUpdate = change }
    var requests = 0
    var titles: [String] = []
    let runtime = DesktopRuntime(
      content: { viewport in
        if !paintOnly { titles.append(model.title) }
        return Column(in: viewport.bounds) {
          Canvas(key: 1, extent: 100) { painter in
            painter.fillRect(painter.region, color: Color(model.red, 0, 0))
          }
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: { requests += 1 },
      frameCallbacks: policy.callbacks)
    defer { runtime.stop() }
    let renderer = CPURenderer(width: 100, height: 100)
    runtime.frame(input: Input(), viewport: viewport, time: 0, present: { renderer.render($0) })
    await Task { @MainActor in }.value
    #expect(titles == (paintOnly ? [] : ["First"]))
    #expect(requests == 1)
    policy.onUpdate = nil
    policy.onFinish = nil
    runtime.frame(input: Input(), viewport: viewport, time: 1, present: { renderer.render($0) })
    let pixel = (40 * 100 + 10) * 3
    #expect(titles == (paintOnly ? [] : ["First", "Changed"]))
    #expect(Array(renderer.pixels[pixel..<pixel + 3]) == (paintOnly ? [255, 0, 0] : [0, 0, 0]))
    await Task { @MainActor in }.value
    #expect(requests == 1)
  }

  @Test func idleTimeExpiresScrollAccelerationWithoutUncappingAnimationDelta() {
    let policy = FramePolicy()
    let runtime = DesktopRuntime(
      content: { viewport in
        ScrollColumn(key: 1, in: viewport.bounds) {
          Text("")
            .size(20)
            .selectable(key: 2)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(2000))
            .background(.panel)
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {}, frameCallbacks: policy.callbacks,
      scrollAcceleration: 1)
    defer { runtime.stop() }
    func scroll(at time: Double) {
      runtime.frame(
        input: Input(x: 20, y: 20, scrollY: 60), viewport: viewport, time: time, present: { _ in })
    }
    scroll(at: 0)
    scroll(at: 0.05)
    #expect((runtime.state(for: 1)?.scrollOffset ?? 0) > 120)
    runtime.frame(input: Input(x: 20, y: 20), viewport: viewport, time: 0.066, present: { _ in })
    let before = runtime.state(for: 1)?.scrollOffset ?? 0
    scroll(at: 10)
    #expect(runtime.state(for: 1)?.scrollOffset == before + 60)
    #expect(policy.prepares.last == 0.1)
  }

  @Test func rebuildPresentsUpdatedContentWithoutReplayingInputOrLifecycle() {
    let policy = FramePolicy()
    var builds = 0
    var clicks = 0
    var presentations = 0
    let runtime = DesktopRuntime(
      content: { viewport in
        builds += 1
        return Column(in: viewport.bounds) {
          Button(key: 1, "Change") {
            clicks += 1
            policy.rebuild = true
          }
          if policy.rebuild {
            Text("Updated").size(20).selectable(key: 2).alignment(.leading).padding(horizontal: 12).frame(
              width: .fill, height: .fixed(32)
            ).background(.panel)
          }
          FocusBlock(key: 1)
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {}, frameCallbacks: policy.callbacks)
    defer { runtime.stop() }
    runtime.frame(input: Input(keyEvents: [KeyEvent(.enter)]), viewport: viewport, dt: 0.05) { _ in
      presentations += 1
      #expect(builds == 2)
    }
    #expect(clicks == 1)
    #expect(presentations == 1)
    #expect(policy.prepares == [0.05])
    #expect(policy.updates == 1)
    #expect(policy.finishes == 1)
    #expect(policy.buttonState?.clicks == 1)
    #expect(runtime.state(for: 2) != nil)
  }

  @Test func animationConditionObservationsWakeAnIdleRuntime() async {
    let model = Model()
    var redraws = 0
    let runtime = DesktopRuntime(
      content: { _ in EmptyBlock() }, primaryShortcut: .control, onCopy: { _ in },
      requestRedraw: { redraws += 1 },
      frameCallbacks: .init(needsAnimationFrame: { model.clicks > 0 }))
    defer { runtime.stop() }
    runtime.frame(input: Input(), viewport: viewport, time: 0, present: { _ in })
    #expect(redraws == 0)
    #expect(!runtime.needsAnimationFrame)

    model.clicks = 1
    await Task { @MainActor in }.value
    #expect(redraws == 1)
    #expect(runtime.needsAnimationFrame)
    runtime.frame(input: Input(), viewport: viewport, time: 1, present: { _ in })
    #expect(redraws == 2)

    model.clicks = 0
    runtime.frame(input: Input(), viewport: viewport, time: 2, present: { _ in })
    await Task { @MainActor in }.value
    #expect(redraws == 2)
    #expect(!runtime.needsAnimationFrame)
  }

  @Test func callbacksCanFilterInputAndRequestSimulationFrames() {
    let policy = FramePolicy()
    policy.suppressInput = true
    policy.needsAnimationFrame = true
    var keys = 0
    var redraws = 0
    let runtime = DesktopRuntime(
      content: { _ in EmptyBlock() }, primaryShortcut: .control,
      onKey: { _ in
        keys += 1
        return true
      },
      onCopy: { _ in }, requestRedraw: { redraws += 1 }, frameCallbacks: policy.callbacks)
    defer { runtime.stop() }
    runtime.frame(
      input: Input(keyEvents: [KeyEvent(.enter)]), viewport: viewport, time: 0, present: { _ in })
    #expect(keys == 0)
    #expect(redraws == 1)
    #expect(runtime.needsAnimationFrame)
    policy.needsAnimationFrame = false
    runtime.frame(input: Input(), viewport: viewport, time: 10, present: { _ in })
    runtime.frame(input: Input(), viewport: viewport, time: 9, present: { _ in })
    #expect(policy.prepares == [1 / 60, 0.1, 0])
    #expect(redraws == 1)
    #expect(!runtime.needsAnimationFrame)
  }
}

extension DesktopRuntimeTests {
  @Test(arguments: [false, true])
  func rebuildDoesNotDispatchCapturedPointerGestures(keepsPointer: Bool) {
    let policy = FramePolicy()
    policy.rebuild = true
    policy.rebuildPointer = keepsPointer ? .init(10, 10) : nil
    var events: [PointerEvent] = []
    let runtime = DesktopRuntime(
      content: { viewport in
        Column(in: viewport.bounds) {
          Element(key: 1, extent: 80, onPointer: { events.append($0) }) { _ in }
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {}, frameCallbacks: policy.callbacks)
    defer { runtime.stop() }
    runtime.frame(
      input: Input(x: 10, y: 10, pressed: true), viewport: viewport, dt: 0.01, present: { _ in })
    #expect(events.map(\.phase) == [.pressed])
    runtime.frame(input: Input(x: 20, y: 20), viewport: viewport, dt: 0.01, present: { _ in })
    #expect(events.map(\.phase) == [.pressed, .dragged])
    #expect(events.last?.x == 20)
    runtime.frame(
      input: Input(x: 20, y: 20, released: true), viewport: viewport, dt: 0.01, present: { _ in })
    #expect(events.map(\.phase) == [.pressed, .dragged, .released])
    runtime.frame(
      input: Input(x: 10, y: 10, pressed: true), viewport: viewport, dt: 0.01, present: { _ in })
    runtime.frame(input: Input(focusLost: true), viewport: viewport, dt: 0.01, present: { _ in })
    #expect(events.map(\.phase) == [.pressed, .dragged, .released, .pressed, .cancelled])
  }

  @Test func rebuildPreservesActiveTextSelection() {
    let policy = FramePolicy()
    policy.rebuild = true
    let runtime = DesktopRuntime(
      content: { viewport in
        Column(in: viewport.bounds) {
          RichText(key: 1, lines: [TextLine([TextRun("ABCD")], x: 0, y: 0)], extent: 80)
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {}, frameCallbacks: policy.callbacks)
    defer { runtime.stop() }
    runtime.frame(
      input: Input(x: 0, y: 10, pressed: true), viewport: viewport, dt: 0, present: { _ in })
    runtime.frame(input: Input(x: 24, y: 10), viewport: viewport, dt: 0, present: { _ in })
    #expect(policy.selectedText == "AB")
    runtime.frame(
      input: Input(x: 36, y: 10, released: true), viewport: viewport, dt: 0, present: { _ in })
    #expect(policy.selectedText == "ABC")
  }
}
