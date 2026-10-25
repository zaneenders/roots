@MainActor
@_spi(Hosting) public struct UIHost: ~Copyable {
  private var store: UIStore

  @inline(never)
  deinit {}

  public init(
    nodeCapacity: Int = 128, drawCapacity: Int? = 32_768, scrollAcceleration: Float = 0,
    scrollDeceleration: Float = 8
  ) {
    store = UIStore(
      nodeCapacity: nodeCapacity, drawCapacity: drawCapacity,
      scrollAcceleration: scrollAcceleration, scrollDeceleration: scrollDeceleration)
  }

  public var liveCount: Int { store.liveCount }
  public var droppedDraws: Int { store.droppedDraws }
  public var needsAnimationFrame: Bool { store.needsAnimationFrame }
  public var cursorStyle: CursorStyle { store.cursorStyle }
  public var selectedText: String? { store.selectedText }
  public func state(for key: UInt64) -> NodeState? {
    guard let handle = store.handle(for: key) else { return nil }
    return store.state(for: handle)
  }

  @inlinable
  public mutating func frame<Content: Block>(
    input: Input = Input(), dt: Float = 1 / 60, primaryShortcut: KeyModifiers = .control,
    onKey: ((KeyEvent) -> Bool)? = nil, onCopy: ((String) -> Void)? = nil,
    @BlockBuilder build: @MainActor () -> Content,
    present: (borrowing UIDrawBatch) -> Void
  ) {
    lowerFrame(
      input: input, dt: dt, primaryShortcut: primaryShortcut, onKey: onKey, onCopy: onCopy,
      build: { frame in
        let content = build()
        content._build(into: &frame)
      }, present: present)
  }

  package mutating func trackedFrame<Content: Block>(
    input: Input, dt: Float, inputElapsed: Float?, primaryShortcut: KeyModifiers,
    onKey: ((KeyEvent) -> Bool)?, onCopy: ((String) -> Void)?,
    @BlockBuilder build: @MainActor () -> Content,
    present: (borrowing UIDrawBatch) -> Void, track: ((() -> Void) -> Void)?
  ) {
    lowerFrame(
      input: input, dt: dt, primaryShortcut: primaryShortcut, onKey: onKey, onCopy: onCopy,
      build: { frame in
        let content = build()
        content._build(into: &frame)
      }, present: present, inputElapsed: inputElapsed, track: track)
  }

  package func present(_ body: (borrowing UIDrawBatch) -> Void) {
    store.present(body)
  }

  public func withState(_ body: (borrowing UIState) -> Void) {
    body(UIState(host: self))
  }

  package mutating func rebuild<Content: Block>(
    mousePosition: Coordinate?, @BlockBuilder build: @MainActor () -> Content,
    present: (borrowing UIDrawBatch) -> Void, track: ((() -> Void) -> Void)? = nil
  ) {
    lowerFrame(
      input: Input(mousePosition: mousePosition), dt: 0, primaryShortcut: .control,
      onKey: nil, onCopy: nil, dispatchInput: false,
      build: { frame in
        let content = build()
        content._build(into: &frame)
      }, present: present, track: track)
  }

  @usableFromInline
  mutating func lowerFrame(
    input: Input, dt: Float, primaryShortcut: KeyModifiers,
    onKey: ((KeyEvent) -> Bool)?, onCopy: ((String) -> Void)?, dispatchInput: Bool = true,
    build: (inout UIFrame) -> Void, present: (borrowing UIDrawBatch) -> Void,
    inputElapsed: Float? = nil, track: ((() -> Void) -> Void)? = nil
  ) {
    store.frame(
      input: input, dt: dt, primaryShortcut: primaryShortcut, onKey: onKey, onCopy: onCopy,
      dispatchInput: dispatchInput, build: build, present: present, inputElapsed: inputElapsed,
      track: track)
  }
}
