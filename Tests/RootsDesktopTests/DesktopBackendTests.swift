import DesktopTestSupport
import Observation
import Roots
import Testing

@testable import RootsDesktop

@MainActor
private final class RecordingBackend: DesktopBackend, DesktopCursorSurface {
  enum Failure: Error, Equatable { case presentation }
  let primaryShortcut: KeyModifiers = .alt
  var configuration: BackendWindowConfiguration?
  var snapshots: [BackendFrame] = [
    .init(input: Input(), logicalSize: .init(width: 100, height: 80), scale: 1.25, timeSeconds: 0)
  ]
  var redraws = 0
  var closes = 0
  var clipboard: String?
  var cursors: [CursorShape] = []
  var drawCounts: [Int] = []
  var fails = false
  var afterFrame: (() async throws -> Void)?

  func run(configuration: BackendWindowConfiguration, frame: @escaping BackendFrameHandler) async throws {
    self.configuration = configuration
    for snapshot in snapshots {
      try Task.checkCancellation()
      frame(snapshot, { drawCounts.append($0.count) })
      try await afterFrame?()
    }
    if fails { throw Failure.presentation }
  }
  func requestRedraw() { redraws += 1 }
  func requestClose() { closes += 1 }
  func readClipboard() async -> String? { clipboard }
  func writeClipboard(_ text: String) -> Bool {
    clipboard = text
    return true
  }
  func setCursor(_ shape: CursorShape) -> Bool {
    cursors.append(shape)
    return true
  }
}

@MainActor @Observable
private final class BackendModel { var label = "First" }

@Suite(GraphicsTest(), .serialized)
@MainActor
struct DesktopBackendTests {
  @Test func injectedBackendReceivesConfigurationFramesAndSessionServices() async throws {
    let backend = RecordingBackend()
    let input = Input(
      secondaryDown: true, secondaryPressed: true, scrollStepsY: 0.25,
      textEvents: [.init(committed: "é")])
    backend.snapshots[0] = .init(
      input: input, logicalSize: .init(width: 100, height: 80), scale: 1.25, timeSeconds: 0)
    backend.snapshots.append(
      .init(
        input: Input(), logicalSize: .init(width: 120, height: 90), scale: 2, timeSeconds: 0.02))
    var viewports: [Viewport] = []
    var inputs: [Input] = []
    var events: [String] = []
    backend.afterFrame = {
      #expect(await DesktopSystem.readClipboard() == "copy")
      #expect(!DesktopSystem.setTextInput(nil))
    }
    try await DesktopWindow(
      "Injected", width: 100, height: 80, minimumSize: .init(width: 40, height: 30), backend: backend
    ) { viewport in
      viewports.append(viewport)
      return Column(in: viewport.bounds) { Text("Hello") }
    }
    .onStart {
      events.append("start")
      #expect(DesktopSystem.backend === backend)
      #expect(DesktopSystem.primaryShortcut == .alt)
      #expect(DesktopSystem.writeClipboard("copy"))
      #expect(DesktopSystem.setCursor(.crosshair))
    }
    .onPrepareFrame { input, _ in inputs.append(input) }
    .animationFrames { true }
    .onClose {
      events.append("close")
      #expect(DesktopSystem.backend === backend)
      DesktopSystem.requestClose()
    }
    .run()
    #expect(events == ["start", "close"])
    #expect(backend.configuration?.title == "Injected")
    #expect(backend.configuration?.minimumSize == Size(width: 40, height: 30))
    #expect(viewports.map(\.scale) == [1.25, 2])
    #expect(viewports.last?.bounds == Region(0, 0, 120, 90))
    #expect(inputs.first?.secondaryPressed == true && inputs.first?.scrollStepsY == 0.25)
    #expect(inputs.first?.textEvents == input.textEvents)
    #expect(backend.drawCounts.count == 2 && backend.drawCounts.allSatisfy { $0 > 0 })
    #expect(backend.redraws == 2 && backend.closes == 1)
    #expect(backend.cursors.allSatisfy { $0 == .crosshair })
    #expect(DesktopSystem.backend !== backend)
  }

  @Test func selectionCopiesThroughTheInjectedShortcutAndClipboard() async throws {
    let backend = RecordingBackend()
    backend.snapshots = [
      .init(
        input: Input(mousePosition: .init(x: 10, y: 10), pressed: true, released: true),
        logicalSize: .init(width: 200, height: 40), scale: 1, timeSeconds: 0),
      .init(
        input: Input(keyEvents: [
          KeyEvent(.character("a"), modifiers: .alt), KeyEvent(.character("c"), modifiers: .alt)
        ]), logicalSize: .init(width: 200, height: 40), scale: 1, timeSeconds: 1 / 60)
    ]
    try await DesktopWindow("Copy", backend: backend) { viewport in
      Column(in: viewport.bounds) { Text("Selectable text").selectable(key: 1) }
    }.run()
    #expect(backend.clipboard == "Selectable text")
  }

  @Test func failureRestoresRoutingClearsCursorOverridesAndClosesLifecycle() async throws {
    let backend = RecordingBackend()
    backend.fails = true
    var closes = 0
    let window = DesktopWindow("Failure", backend: backend) { _ in BlockBuilder.buildBlock() }
      .onClose { closes += 1 }
    await #expect(throws: RecordingBackend.Failure.presentation) {
      try await window.onStart { _ = DesktopSystem.setCursor(.grabbing) }.run()
    }
    #expect(DesktopSystem.backend !== backend && closes == 1)
    backend.fails = false
    backend.cursors.removeAll()
    try await window.run()
    #expect(backend.cursors == [.default] && closes == 2)
  }

  @Test func observationUsesInjectedBackendAndStopsAfterSession() async throws {
    let backend = RecordingBackend()
    let model = BackendModel()
    backend.afterFrame = {
      model.label = "Second"
      for _ in 0..<5 { await Task.yield() }
      #expect(backend.redraws == 1)
    }
    try await DesktopWindow("Observed", backend: backend) { viewport in
      Column(in: viewport.bounds) { Text(model.label) }
    }.run()
    let redraws = backend.redraws
    model.label = "After close"
    for _ in 0..<5 { await Task.yield() }
    #expect(backend.redraws == redraws)
  }

  @Test func nestedSessionCannotReplaceActiveBackend() async throws {
    let backend = RecordingBackend()
    let other = RecordingBackend()
    backend.afterFrame = {
      await #expect(throws: DesktopBackendError.alreadyRunning) {
        try await DesktopWindow("Nested", backend: other) { _ in BlockBuilder.buildBlock() }.run()
      }
      #expect(DesktopSystem.backend === backend)
    }
    try await DesktopWindow("Outer", backend: backend) { _ in BlockBuilder.buildBlock() }.run()
    #expect(other.configuration == nil)
  }

  @Test func cancellationClosesLifecycleAndRestoresRouting() async throws {
    let backend = RecordingBackend()
    var closes = 0
    var task: Task<Void, any Error>?
    backend.afterFrame = {
      task?.cancel()
      try Task.checkCancellation()
    }
    task = Task { @MainActor in
      try await DesktopWindow("Cancelled", backend: backend) { _ in BlockBuilder.buildBlock() }
        .onClose { closes += 1 }.run()
    }
    let running = try #require(task)
    await #expect(throws: CancellationError.self) { try await running.value }
    task = nil
    #expect(closes == 1 && DesktopSystem.backend !== backend)
  }
}
