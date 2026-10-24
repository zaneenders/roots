public struct UIFrame: ~Copyable, ~Escapable {
  private var storage: MutableRef<UIStorage>
  // Traversal is frame-local; only implicit nodes retain a path snapshot.
  @usableFromInline
  var identityPath: [IdentityComponent] = []

  @_lifetime(&storage)
  init(storage: inout UIStorage) {
    self.storage = MutableRef(&storage)
  }

  @inlinable
  mutating func beginItem(_ id: AnyHashable, at location: IdentityLocation) {
    identityPath.append(.item(location, id))
  }

  @inlinable
  mutating func beginChild(_ index: Int) {
    identityPath.append(.child(index))
  }

  @inlinable
  mutating func endIdentity() {
    _ = identityPath.removeLast()
  }

  mutating func withSelectionGroup(_ key: UInt64, _ body: (inout UIFrame) -> Void) {
    precondition(
      storage.value.selectionGroupKeys.insert(key).inserted,
      "Selection group keys must be unique within a frame")
    let previous = storage.value.selectionGroup
    storage.value.selectionGroup = key
    defer { storage.value.selectionGroup = previous }
    body(&self)
  }

  mutating func withColor(_ color: Color, _ body: (inout UIFrame) -> Void) {
    let previous = storage.value.foregroundColor
    storage.value.foregroundColor = color
    defer { storage.value.foregroundColor = previous }
    body(&self)
  }

  mutating func withBackground(_ color: Color, _ body: (inout UIFrame) -> Void) {
    if !storage.value.cursors.isEmpty { storage.value.ensureLayout() }
    let depth = storage.value.cursors.count
    let layoutStart = storage.value.layouts.count
    let handle = storage.value.declare(
      key: nil, title: "", region: Region(0, 0, 0, 0), color: color,
      focusable: false, participatesInLayout: false)
    storage.value.nodes[handle.slot].isBackground = true
    let nodeStart = storage.value.order.count
    storage.value.activeBackgrounds += 1
    body(&self)
    storage.value.activeBackgrounds -= 1
    storage.value.backgrounds.append(
      BackgroundRegion(
        node: handle.slot, depth: depth,
        layouts: layoutStart..<storage.value.layouts.count,
        nodes: nodeStart..<storage.value.order.count))
  }

  mutating func beginLayout(_ style: LayoutStyle, in bounds: Region? = nil) {
    storage.value.beginLayout(style, in: bounds)
  }

  @usableFromInline
  mutating func beginColumn(in region: Region, gap: Float = 8) {
    if storage.value.activeBackgrounds > 0 {
      beginLayout(LayoutStyle(kind: .column, gap: gap), in: region)
      return
    }
    storage.value.cursors.append(
      Cursor(
        region: region, startOrder: storage.value.order.count, gap: gap, horizontal: false,
        scrollParent: storage.value.scrollParent))
  }
  mutating func beginRow(in region: Region, gap: Float = 8) {
    if storage.value.activeBackgrounds > 0 {
      beginLayout(LayoutStyle(kind: .row, gap: gap), in: region)
      return
    }
    storage.value.cursors.append(
      Cursor(
        region: region, startOrder: storage.value.order.count, gap: gap, horizontal: true,
        scrollParent: storage.value.scrollParent))
  }
  mutating func beginScroll(
    key: UInt64, in region: Region, showsScrollIndicator: Bool = false
  ) {
    precondition(region.x.isFinite && region.y.isFinite && region.width.isFinite && region.height.isFinite)
    precondition(region.width >= 0 && region.height >= 0)
    let handle = storage.value.declare(
      key: key, title: "", region: region, color: .panel, scrollable: true,
      showsScrollIndicator: showsScrollIndicator)
    storage.value.beginLayout(LayoutStyle(kind: .scroll), in: region)
    storage.value.cursors[storage.value.cursors.count - 1].scrollParent = handle.slot
    storage.value.layouts[storage.value.layouts.count - 1].scrollParent = handle.slot
  }

  @discardableResult
  mutating func beginScrollColumn(
    key: UInt64, in region: Region, gap: Float = 8, showsScrollIndicator: Bool = false
  ) -> NodeHandle {
    precondition(region.x.isFinite && region.y.isFinite && region.width.isFinite && region.height.isFinite)
    precondition(region.width >= 0 && region.height >= 0 && gap.isFinite && gap >= 0)
    let handle = storage.value.declare(
      key: key, title: "", region: region, color: .panel, scrollable: true,
      showsScrollIndicator: showsScrollIndicator)
    storage.value.cursors.append(
      Cursor(
        region: region, isScrollViewport: true, startOrder: storage.value.order.count, gap: gap, horizontal: false,
        scrollParent: handle.slot))
    return handle
  }

  mutating func focus(_ handle: NodeHandle, reveal: Bool = false) {
    if let i = storage.value.resolve(handle),
      storage.value.nodes[i].isFocusable || storage.value.nodes[i].selectableLabel
        || storage.value.nodes[i].plainText?.selectable == true
        || storage.value.nodes[i].paragraph?.selectable == true
    {
      storage.value.focusAfterLayout = handle
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
    let cursor = storage.value.cursors.removeLast()
    if let layout = cursor.layout { storage.value.endLayout(layout) }
  }
  @discardableResult
  mutating func label(
    key: UInt64, _ title: String, extent: Float = 32, color: Color = .panel,
    font: MonospaceFont = MonospaceFont(),
    textOverflow: TextOverflow = .clip, selectable: Bool = true
  ) -> NodeHandle {
    let region = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: title, region: region, color: color, font: font, textOverflow: textOverflow,
      selectable: selectable)
  }
  @discardableResult
  mutating func button(
    key: UInt64, _ title: String, extent: Float = 44, color: Color = .panel,
    font: MonospaceFont = MonospaceFont(),
    textOverflow: TextOverflow = .clip, onClick: (() -> Void)? = nil
  ) -> NodeHandle {
    let region = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: title, region: region, color: color, font: font,
      textOverflow: textOverflow, interaction: .button(onClick: onClick))
  }

  @discardableResult
  mutating func text(
    key: UInt64, lines: [TextLine], extent: Float, color: Color = .panel,
    paint: ((inout UIPaintContext) -> Void)? = nil
  ) -> NodeHandle {
    let region = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: "", region: region, color: color,
      interaction: paint.map { .canvas(paint: $0) } ?? .none, textLines: lines)
  }

  @discardableResult
  mutating func canvas(
    key: UInt64, extent: Float? = nil, color: Color = .panel, blocksPointer: Bool = false,
    paint: @escaping (inout UIPaintContext) -> Void
  ) -> NodeHandle {
    if extent == nil { storage.value.ensureLayout() }
    let region = storage.value.place(extent ?? 0)
    let handle = storage.value.declare(
      key: key, title: "", region: region, color: color,
      interaction: blocksPointer
        ? .element(onKey: nil, onPointer: nil, onScroll: nil, paint: paint)
        : .canvas(paint: paint), focusable: false)
    if extent == nil {
      let leaf = storage.value.layouts.count - 1
      storage.value.layouts[leaf].style = LayoutStyle(kind: .leaf, width: .fill, height: .fill)
    }
    return handle
  }

  mutating func rectangle(_ style: RectangleStyle) {
    storage.value.ensureLayout()
    let handle = storage.value.declare(
      key: nil, title: "", region: Region(0, 0, 0, 0),
      color: storage.value.foregroundColor ?? .text, focusable: false)
    storage.value.nodes[handle.slot].rectangleStyle = style
    let leaf = storage.value.layouts.count - 1
    storage.value.layouts[leaf].style = LayoutStyle(kind: .leaf, width: .fill, height: .fill)
  }

  mutating func paragraph(
    _ runs: [ParagraphRun], key: UInt64?, identity: IdentityLocation? = nil,
    font: MonospaceFont, alignment: Alignment
  ) {
    storage.value.ensureLayout()
    let content = ParagraphContent(
      runs: runs, font: font, alignment: alignment, selectable: key != nil || identity != nil)
    _ = storage.value.declare(
      key: key, title: "", region: Region(0, 0, 0, 0), color: Color(0, 0, 0, 0),
      paragraph: content, identity: identity.map { ImplicitNodeIdentity(path: identityPath, location: $0) })
    let leaf = storage.value.layouts.count - 1
    storage.value.layouts[leaf].style = LayoutStyle(kind: .leaf, width: .fill)
    storage.value.layouts[leaf].measured =
      content.layout(
        width: .greatestFiniteMagnitude,
        color: storage.value.foregroundColor ?? .text
      ).size
  }

  mutating func plainText(_ text: String, key: UInt64?, identity: IdentityLocation? = nil, style: PlainTextStyle) {
    storage.value.ensureLayout()
    _ = storage.value.declare(
      key: key, title: text, region: Region(0, 0, 0, 0), color: Color(0, 0, 0, 0), plainText: style,
      identity: identity.map { ImplicitNodeIdentity(path: identityPath, location: $0) })
    let leaf = storage.value.layouts.count - 1
    storage.value.layouts[leaf].style = LayoutStyle(kind: .leaf)
    storage.value.layouts[leaf].measured = style.size(of: text)
  }

  @discardableResult
  mutating func element(
    key: UInt64, extent: Float = 44, color: Color = .panel, onKey: ((KeyEvent) -> Void)? = nil,
    onPointer: ((PointerEvent) -> Void)? = nil, onScroll: ((ScrollEvent) -> Void)? = nil,
    focusable: Bool = true, paint: @escaping (inout UIPaintContext) -> Void
  ) -> NodeHandle {
    let region = storage.value.place(extent)
    return storage.value.declare(
      key: key, title: "", region: region, color: color,
      interaction: .element(onKey: onKey, onPointer: onPointer, onScroll: onScroll, paint: paint),
      focusable: focusable)
  }
}
