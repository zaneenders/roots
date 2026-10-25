import Observation
import Synchronization
@_spi(Hosting) import Roots

@MainActor @Observable
private final class FrameInvalidation {
  var revision = 0
  @ObservationIgnored private var pending = false
  private nonisolated let observedChange = Atomic<Bool>(false)
  @ObservationIgnored private var active = true
  @ObservationIgnored private let requestRedraw: @MainActor () -> Void

  init(requestRedraw: @escaping @MainActor () -> Void) {
    self.requestRedraw = requestRedraw
  }

  var hasPending: Bool { pending || observedChange.load(ordering: .relaxed) }

  func beginFrame() {
    revision += 1
    pending = false
    observedChange.store(false, ordering: .relaxed)
  }

  func track(_ body: () -> Void) {
    let revision = revision
    withObservationTracking {
      _ = self.revision
      body()
    } onChange: { [weak self] in
      self?.observedChange.store(true, ordering: .relaxed)
      Task { @MainActor [weak self] in
        guard let self, self.revision == revision else { return }
        self.request()
      }
    }
  }

  func request() {
    guard active, !pending else { return }
    pending = true
    requestRedraw()
  }

  func stop() {
    active = false
    revision += 1
  }
}

@MainActor
final class DesktopRuntime<Content: Block> {
  private var host: UIHost
  private let frameCallbacks: DesktopFrameCallbacks
  private let content: @MainActor (Viewport) -> Content
  private let primaryShortcut: KeyModifiers
  private let onKey: ((KeyEvent) -> Bool)?
  private let onCopy: (String) -> Void
  private let invalidation: FrameInvalidation
  private var lastTime: Double?
  private var mousePosition: Coordinate?
  private var viewport: Viewport?
  private var mediaPending = false
  private var lastExplicitRedraw: UInt64 = DesktopSystem.redrawRevision
  private var imageObservers: [ObjectIdentifier: (ImageSource, UInt64)] = [:]
  private let requestMediaRedraw: @MainActor () -> Void

  init(
    content: @escaping @MainActor (Viewport) -> Content, primaryShortcut: KeyModifiers,
    onKey: ((KeyEvent) -> Bool)? = nil, onCopy: @escaping (String) -> Void,
    requestRedraw: @escaping @MainActor () -> Void,
    frameCallbacks: DesktopFrameCallbacks = .init(),
    nodeCapacity: Int = 128, scrollAcceleration: Float = 0, scrollDeceleration: Float = 8
  ) {
    host = UIHost(
      nodeCapacity: nodeCapacity, drawCapacity: nil, scrollAcceleration: scrollAcceleration,
      scrollDeceleration: scrollDeceleration)
    self.frameCallbacks = frameCallbacks
    self.content = content
    self.primaryShortcut = primaryShortcut
    self.onKey = onKey
    self.onCopy = onCopy
    invalidation = FrameInvalidation(requestRedraw: requestRedraw)
    requestMediaRedraw = requestRedraw
  }

  func frame(
    input: Input, viewport: Viewport, time: Double, present: (borrowing UIDrawBatch) -> Void
  ) {
    let elapsed = lastTime.map { max(0, time - $0) } ?? 1 / 60
    lastTime = time
    frame(
      input: input, viewport: viewport, dt: Float(min(0.1, elapsed)),
      inputElapsed: Float(min(1, elapsed)),
      present: present)
  }

  func frame(
    input: Input, viewport: Viewport, dt: Float, inputElapsed: Float? = nil,
    present: (borrowing UIDrawBatch) -> Void
  ) {
    let changedInput = input.mousePosition != mousePosition || input.pressed || input.released
      || input.focusLost || !input.keyEvents.isEmpty || !input.textEvents.isEmpty
      || input.secondaryDown || input.secondaryPressed || input.secondaryReleased
      || input.middleDown || input.middlePressed || input.middleReleased
      || input.scrollStepsX != 0 || input.scrollStepsY != 0
      || input.scrollX != 0 || input.scrollY != 0 || input.scrollVelocityY != nil
    let mediaOnly = mediaPending && !invalidation.hasPending && self.viewport == viewport
      && !changedInput && !needsAnimationFrame
      && lastExplicitRedraw == DesktopSystem.redrawRevision
    mediaPending = false
    lastExplicitRedraw = DesktopSystem.redrawRevision
    self.viewport = viewport
    if mediaOnly {
      host.present(present)
      return
    }
    let invalidation = invalidation
    invalidation.beginFrame()
    invalidation.track {
      var frameInput = input
      invalidation.track { frameCallbacks.prepare?(&frameInput, dt) }
      var update = DesktopFrameUpdate.present
      invalidation.track {
        host.trackedFrame(
          input: frameInput, dt: dt, inputElapsed: inputElapsed, primaryShortcut: primaryShortcut,
          onKey: onKey, onCopy: onCopy,
          build: { content(viewport) },
          present: { draws in
            update = frameCallbacks.update?(frameInput) ?? .present
            if case .present = update {
              observeImages(in: draws)
              present(draws)
            }
          }, track: invalidation.track)
        if case .rebuild(let mousePosition) = update {
          host.rebuild(
            mousePosition: mousePosition,
            build: { content(viewport) },
            present: { draws in observeImages(in: draws); present(draws) }, track: invalidation.track)
        }
      }
      host.withState { frameCallbacks.finish?($0) }
      if needsAnimationFrame { invalidation.request() }
    }
    let mouseMoved = input.mousePosition != mousePosition
    mousePosition = input.mousePosition
    if mouseMoved || input.pressed || input.released || input.focusLost
      || !input.keyEvents.isEmpty || !input.textEvents.isEmpty
      || input.secondaryPressed || input.secondaryReleased || input.middlePressed
      || input.middleReleased
      || input.scrollStepsX != 0 || input.scrollStepsY != 0
      || input.scrollX != 0 || input.scrollY != 0 || input.scrollVelocityY != nil
    {
      invalidation.request()
    }
  }

  var cursorStyle: CursorStyle { host.cursorStyle }
  var droppedDraws: Int { host.droppedDraws }
  var needsAnimationFrame: Bool {
    host.needsAnimationFrame || frameCallbacks.needsAnimationFrame?() == true
  }

  private func observeImages(in batch: borrowing UIDrawBatch) {
    var sources: [ObjectIdentifier: ImageSource] = [:]
    for command in batch {
      if case .image(let image) = command { sources[ObjectIdentifier(image.source)] = image.source }
    }
    for id in imageObservers.keys.filter({ sources[$0] == nil }) {
      if let (source, token) = imageObservers.removeValue(forKey: id) { source.removeObserver(token) }
    }
    for (id, source) in sources where imageObservers[id] == nil {
      let token = source.observe { [weak self] in
        guard let self, !self.mediaPending else { return }
        self.mediaPending = true
        self.requestMediaRedraw()
      }
      imageObservers[id] = (source, token)
    }
  }

  func stop() {
    invalidation.stop()
    for (source, token) in imageObservers.values { source.removeObserver(token) }
    imageObservers.removeAll()
  }
  func state(for key: UInt64) -> NodeState? { host.state(for: key) }
}
