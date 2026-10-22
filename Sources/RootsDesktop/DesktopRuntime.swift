import Observation
@_spi(Hosting) import Roots

@MainActor @Observable
private final class FrameInvalidation {
  var revision = 0
  @ObservationIgnored private var pending = false
  @ObservationIgnored private var active = true
  @ObservationIgnored private let requestRedraw: @MainActor () -> Void

  init(requestRedraw: @escaping @MainActor () -> Void) {
    self.requestRedraw = requestRedraw
  }

  func beginFrame() {
    revision += 1
    pending = false
  }

  func track(_ body: () -> Void) {
    let revision = revision
    withObservationTracking {
      _ = self.revision
      body()
    } onChange: { [weak self] in
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
  private let delegate: (any DesktopFrameDelegate)?
  private let content: @MainActor (Viewport) -> Content
  private let primaryShortcut: KeyModifiers
  private let onKey: ((KeyEvent) -> Bool)?
  private let onCopy: (String) -> Void
  private let invalidation: FrameInvalidation
  private var lastTime: Double?
  private var pointer = SIMD2<Float>(-1, -1)

  init(
    content: @escaping @MainActor (Viewport) -> Content, primaryShortcut: KeyModifiers,
    onKey: ((KeyEvent) -> Bool)? = nil, onCopy: @escaping (String) -> Void,
    requestRedraw: @escaping @MainActor () -> Void, delegate: (any DesktopFrameDelegate)? = nil,
    nodeCapacity: Int = 128, scrollAcceleration: Float = 0, scrollDeceleration: Float = 8
  ) {
    host = UIHost(
      nodeCapacity: nodeCapacity, drawCapacity: nil, scrollAcceleration: scrollAcceleration,
      scrollDeceleration: scrollDeceleration)
    self.delegate = delegate
    self.content = content
    self.primaryShortcut = primaryShortcut
    self.onKey = onKey
    self.onCopy = onCopy
    invalidation = FrameInvalidation(requestRedraw: requestRedraw)
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
    let invalidation = invalidation
    invalidation.beginFrame()
    invalidation.track {
      var frameInput = input
      invalidation.track { delegate?.prepareFrame(input: &frameInput, dt: dt) }
      var update = DesktopFrameUpdate.present
      invalidation.track {
        host.trackedFrame(
          input: frameInput, dt: dt, inputElapsed: inputElapsed, primaryShortcut: primaryShortcut,
          onKey: onKey, onCopy: onCopy,
          build: { content(viewport) },
          present: { draws in
            update = delegate?.frameUpdate(after: frameInput) ?? .present
            if case .present = update { present(draws) }
          }, track: invalidation.track)
        if case .rebuild(let pointer) = update {
          host.rebuild(
            pointer: pointer,
            build: { content(viewport) },
            present: present, track: invalidation.track)
        }
      }
      host.withState { delegate?.didFinishFrame($0) }
      if needsAnimationFrame { invalidation.request() }
    }
    let nextPointer = SIMD2<Float>(input.x, input.y)
    let pointerMoved = nextPointer != pointer
    pointer = nextPointer
    if pointerMoved || input.pressed || input.released || input.focusLost
      || !input.keyEvents.isEmpty
      || input.scrollX != 0 || input.scrollY != 0 || input.scrollVelocityY != nil
    {
      invalidation.request()
    }
  }

  var droppedDraws: Int { host.droppedDraws }
  var needsAnimationFrame: Bool {
    host.needsAnimationFrame || delegate?.needsAnimationFrame == true
  }

  func stop() { invalidation.stop() }
  func state(for key: UInt64) -> NodeState? { host.state(for: key) }
}
