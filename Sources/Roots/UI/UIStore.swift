struct UIStore: ~Copyable {
  private var storage: UIStorage

  @inline(never)
  deinit {}

  init(
    nodeCapacity: Int = 128, drawCapacity: Int? = 32_768, scrollAcceleration: Float = 0,
    scrollDeceleration: Float = 8
  ) {
    precondition(nodeCapacity >= 0 && (drawCapacity.map { $0 >= 0 } ?? true))
    precondition(scrollAcceleration.isFinite && scrollAcceleration >= 0)
    precondition(scrollDeceleration.isFinite && scrollDeceleration > 0)
    storage = UIStorage(
      nodeCapacity: nodeCapacity, drawCapacity: drawCapacity,
      scrollAcceleration: scrollAcceleration, scrollDeceleration: scrollDeceleration)
  }

  var liveCount: Int { storage.order.count }
  var slotCount: Int { storage.nodes.count }
  var droppedDraws: Int { storage.droppedDraws }

  var needsAnimationFrame: Bool { storage.needsAnimationFrame }

  var selectedText: String? { storage.selectedText }

  func state(for handle: NodeHandle) -> NodeState? {
    guard let i = storage.resolve(handle) else { return nil }
    let node = storage.nodes[i]
    return NodeState(
      key: node.key, clicks: node.clicks, hovered: node.hovered, focused: storage.focused == handle,
      hoverAnimation: node.hover, region: node.region, scrollOffset: node.scrollOffset)
  }

  func handle(for key: UInt64) -> NodeHandle? { storage.keys[key].map { storage.handle($0) } }

  mutating func frame(
    input: Input = Input(), dt: Float = 1 / 60, primaryShortcut: KeyModifiers = .control,
    onKey: ((KeyEvent) -> Bool)? = nil, onCopy: ((String) -> Void)? = nil,
    dispatchInput: Bool = true,
    build: (inout UIFrame) -> Void,
    present: (borrowing UIDrawBatch) -> Void,
    inputElapsed: Float? = nil, track: ((() -> Void) -> Void)? = nil
  ) {
    precondition(storage.epoch != UInt64.max)
    storage.epoch += 1
    storage.order.removeAll()
    storage.cursors.removeAll()
    storage.layouts.removeAll(keepingCapacity: true)
    storage.backgrounds.removeAll(keepingCapacity: true)
    storage.focusAfterLayout = nil
    storage.selectionGroupKeys.removeAll(keepingCapacity: true)
    storage.draws.removeAll()
    storage.droppedDraws = 0
    let track = track ?? { $0() }
    track {
      var frame = UIFrame(storage: &storage)
      build(&frame)
    }
    storage.resolveLayouts()
    storage.finish(
      input: input, dt: dt, primaryShortcut: primaryShortcut, onKey: onKey, onCopy: onCopy,
      dispatchInput: dispatchInput, inputElapsed: inputElapsed)
    track { storage.paint() }
    present(UIDrawBatch(storage.draws.span))
    storage.draws.removeAll()
  }
}
