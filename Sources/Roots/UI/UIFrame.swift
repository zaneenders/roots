public struct UIFrame: ~Copyable, ~Escapable {
  private var storage: MutableRef<UIStorage>

  @_lifetime(&storage)
  init(storage: inout UIStorage) {
    self.storage = MutableRef(&storage)
  }

  @usableFromInline
  mutating func beginColumn(in rect: Rect, gap: Float = 8) {
    storage.value.cursors.append(
      Cursor(rect: rect, gap: gap, horizontal: false, scrollParent: storage.value.scrollParent))
  }
  mutating func beginRow(in rect: Rect, gap: Float = 8) {
    storage.value.cursors.append(
      Cursor(rect: rect, gap: gap, horizontal: true, scrollParent: storage.value.scrollParent))
  }
  @discardableResult
  mutating func beginScrollColumn(
    key: UInt64, in rect: Rect, gap: Float = 8, showsScrollIndicator: Bool = false
  ) -> NodeHandle {
    precondition(rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite)
    precondition(rect.width >= 0 && rect.height >= 0 && gap.isFinite && gap >= 0)
    let handle = storage.value.declare(
      key: key, title: "", rect: rect, color: .panel, scrollable: true,
      showsScrollIndicator: showsScrollIndicator)
    storage.value.cursors.append(
      Cursor(rect: rect, gap: gap, horizontal: false, scrollParent: handle.slot))
    return handle
  }

  mutating func focus(_ handle: NodeHandle, reveal: Bool = false) {
    if let i = storage.value.resolve(handle), storage.value.nodes[i].isFocusable {
      storage.value.focused = handle
      storage.value.focusToReveal = reveal ? handle : nil
    }
  }

  mutating func scrollTo(_ offset: Float, in handle: NodeHandle) {
    if let i = storage.value.resolve(handle), storage.value.nodes[i].scrollable {
      storage.value.nodes[i].scrollOffset = offset
      storage.value.scrollTarget = nil
      storage.value.scrollVelocity = 0
    }
  }

  mutating func focus(key: UInt64, reveal: Bool = false) {
    if let slot = storage.value.keys[key], storage.value.nodes[slot].seen == storage.value.epoch {
      focus(storage.value.handle(slot), reveal: reveal)
    }
  }

  mutating func scrollTo(_ offset: Float, in key: UInt64) {
    if let slot = storage.value.keys[key], storage.value.nodes[slot].seen == storage.value.epoch {
      scrollTo(offset, in: storage.value.handle(slot))
    }
  }

  @usableFromInline
  mutating func end() {
    precondition(!storage.value.cursors.isEmpty)
    _ = storage.value.cursors.removeLast()
  }
  @discardableResult
  mutating func label(
    key: UInt64, _ title: String, extent: Float = 32, color: Color = .panel,
    font: MonospaceFont = MonospaceFont(),
    textOverflow: TextOverflow = .clip, selectable: Bool = true
  ) -> NodeHandle {
    let rect = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: title, rect: rect, color: color, font: font, textOverflow: textOverflow,
      selectable: selectable)
  }
  @discardableResult
  mutating func button(
    key: UInt64, _ title: String, extent: Float = 44, color: Color = .panel,
    font: MonospaceFont = MonospaceFont(),
    textOverflow: TextOverflow = .clip, onClick: (() -> Void)? = nil
  ) -> NodeHandle {
    let rect = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: title, rect: rect, color: color, font: font,
      textOverflow: textOverflow, interaction: .button(onClick: onClick))
  }

  @discardableResult
  mutating func text(
    key: UInt64, lines: [TextLine], extent: Float, color: Color = .panel,
    paint: ((inout UIPaintContext) -> Void)? = nil
  ) -> NodeHandle {
    let rect = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: "", rect: rect, color: color,
      interaction: paint.map { .canvas(paint: $0) } ?? .none, textLines: lines)
  }

  @discardableResult
  mutating func canvas(
    key: UInt64, extent: Float, color: Color = .panel,
    paint: @escaping (inout UIPaintContext) -> Void
  ) -> NodeHandle {
    let rect = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: "", rect: rect, color: color,
      interaction: .canvas(paint: paint))
  }

  @discardableResult
  mutating func element(
    key: UInt64, extent: Float = 44, color: Color = .panel, onKey: ((KeyEvent) -> Void)? = nil,
    onPointer: ((PointerEvent) -> Void)? = nil, onScroll: ((ScrollEvent) -> Void)? = nil,
    focusable: Bool = true, paint: @escaping (inout UIPaintContext) -> Void
  ) -> NodeHandle {
    let rect = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: "", rect: rect, color: color,
      interaction: .element(onKey: onKey, onPointer: onPointer, onScroll: onScroll, paint: paint),
      focusable: focusable)
  }
}
