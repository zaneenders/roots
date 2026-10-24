extension UIStorage {
  private func isDescendant(_ i: Int, of ancestor: Int) -> Bool {
    var parent = nodes[i].scrollParent
    while let p = parent {
      if p == ancestor { return true }
      parent = nodes[p].scrollParent
    }
    return false
  }

  mutating func finish(
    input: Input, dt: Float, primaryShortcut: KeyModifiers, onKey: ((KeyEvent) -> Bool)?,
    onCopy: ((String) -> Void)?,
    dispatchInput: Bool = true, inputElapsed: Float? = nil
  ) {
    var input = input
    input.mousePosition = input.mousePosition.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
    if dispatchInput, let position = input.mousePosition { lastMousePosition = position }
    mousePosition = input.focusLost ? nil : input.mousePosition
    precondition(cursors.isEmpty, "Every row/column must be ended")
    for i in 0..<nodes.count where nodes[i].live && nodes[i].seen != epoch {
      if nodes[i].hasKey { keys.removeValue(forKey: nodes[i].key) }
      if let identity = nodes[i].implicitIdentity { implicitKeys.removeValue(forKey: identity) }
      let next = nodes[i].generation.addingReportingOverflow(1)
      precondition(!next.overflow)
      nodes[i] = Node(generation: next.partialValue)
      free.append(i)
    }
    reconcileGroupSelection()
    if let i = resolve(focused), !nodes[i].isFocusable { focused = nil }
    if resolve(focused) == nil { focused = nil }
    if let i = resolve(pressed), !nodes[i].isInteractive { pressed = nil }
    if resolve(pressed) == nil { pressed = nil }
    if !dispatchInput {
      for position in 0..<order.count {
        let i = order[position]
        if nodes[i].scrollable { setScrollOffset(nodes[i].scrollOffset, for: i) }
      }
      layoutScrolls()
      if let i = resolve(focusToReveal), nodes[i].isFocusable { reveal(i, padding: 2) }
      focusToReveal = nil
      let hit = hitTest(at: input.mousePosition)
      updateHover(hit: hit.node, scrollbarHit: hit.scrollbar, dt: 0)
      return
    }
    if input.focusLost {
      if let i = resolve(pressed) { pointer(.cancelled, input: input, to: i) }
      pressed = nil
      scrollbarDrag = nil
      scrollTarget = nil
      scrollVelocity = 0
      scrollInputTarget = nil
      input.mousePosition = nil
      input.pressed = false
      input.released = false
      input.scrollX = 0
      input.scrollY = 0
      input.scrollVelocityY = nil
    }
    needsAnimationFrame = false
    let keyboardInput = input.keyEvents.contains { $0.phase != .released }
    updateScrolls(input: input, dt: dt, keyboardInput: keyboardInput, inputElapsed: inputElapsed)
    let hits = hitTest(at: input.mousePosition)
    var hit = hits.node
    let scrollbarHit = hits.scrollbar
    if input.pressed, let position = input.mousePosition, let i = scrollbarHit,
      let bar = scrollbar(at: i)
    {
      let onThumb = position.y >= bar.thumb.y && position.y < bar.thumb.y + bar.thumb.height
      scrollbarDrag = (handle(i), onThumb ? position.y - bar.thumb.y : bar.thumb.height / 2)
      pressed = nil
      scrollTarget = nil
      scrollVelocity = 0
      scrollInputTarget = nil
    }
    let draggingScrollbar = scrollbarDrag != nil
    if let drag = scrollbarDrag, let i = resolve(drag.handle), let bar = scrollbar(at: i) {
      if let position = input.mousePosition {
        setScrollOffset(bar.scrollOffset(at: position.y, grabOffset: drag.grabOffset), for: i)
        layoutScrolls()
      }
      if input.released { scrollbarDrag = nil }
    }
    if draggingScrollbar { hit = nil }
    if input.pressed, let position = input.mousePosition, !draggingScrollbar {
      clearGroupSelection()
      pressed = hit.map { handle($0) }
      focused = hit.flatMap { nodes[$0].isFocusable ? handle($0) : nil }
      if let hit {
        if let layout = nodes[hit].textLayout {
          let offset = layout.offset(x: position.x - nodes[hit].region.x, y: position.y - nodes[hit].region.y)
          nodes[hit].selectionAnchor = offset
          nodes[hit].selectionCursor = offset
          beginGroupSelection(at: hit, offset: offset)
        }
        pointer(.pressed, input: input, to: hit)
      }
    }
    if let i = resolve(pressed), !input.pressed || input.released {
      if let position = input.mousePosition {
        if let layout = nodes[i].textLayout {
          if !updateGroupSelection(x: position.x, y: position.y) {
            nodes[i].selectionCursor = layout.offset(
              x: position.x - nodes[i].region.x, y: position.y - nodes[i].region.y)
          }
        }
        pointer(input.released ? .released : .dragged, input: input, to: i)
      } else if input.released {
        pointer(.released, input: input, to: i)
      }
    }
    var activated: Int?
    if input.released {
      if let hit, handle(hit) == pressed, case .button = nodes[hit].interaction { activated = hit }
      pressed = nil
    }
    if let i = activated { activate(i) }
    for event in input.keyEvents {
      if event.key == .escape, event.phase == .pressed, selectedText != nil,
        let i = resolve(focused)
      {
        if !collapseGroupSelection() { nodes[i].selectionAnchor = nodes[i].selectionCursor }
        continue
      }
      if onKey?(event) == true { continue }
      if event.key == .tab, event.phase == .pressed, !event.modifiers.hasShortcutModifier {
        advanceFocus(backward: event.modifiers.contains(.shift))
        if !input.pressed, let i = resolve(focused) { reveal(i) }
        continue
      }
      guard let i = resolve(focused) else { continue }
      if nodes[i].textLayout != nil {
        handleTextKey(event, at: i, primaryShortcut: primaryShortcut, onCopy: onCopy)
        continue
      }
      if !input.pressed, event.phase != .released { reveal(i) }
      if case .button = nodes[i].interaction,
        event.phase == .pressed, !event.modifiers.hasShortcutModifier,
        event.key == .enter || event.key == .character(" ")
      {
        activate(i)
      } else {
        nodes[i].interaction.handleKey(event)
      }
    }
    updateHover(hit: hit, scrollbarHit: scrollbarHit, dt: dt)
  }

  private mutating func updateHover(hit: Int?, scrollbarHit: Int?, dt: Float) {
    if scrollVelocity != 0 { needsAnimationFrame = true }
    for i in order {
      nodes[i].hovered = hit == i || scrollbarHit == i
      let target: Float = hit == i && nodes[i].isFocusable && nodes[i].textLayout == nil ? 1 : 0
      nodes[i].hover += (target - nodes[i].hover) * min(1, max(0, dt) * 16)
      if abs(target - nodes[i].hover) < 0.001 { nodes[i].hover = target }
      nodes[i].flash = max(0, nodes[i].flash - max(0, dt) * 3)
      if nodes[i].flash < 0.001 { nodes[i].flash = 0 }
      if nodes[i].hover != target || nodes[i].flash > 0 { needsAnimationFrame = true }
    }
  }

  func hitTest(at position: Coordinate?, scrollable: Bool = false) -> (node: Int?, scrollbar: Int?) {
    guard let position else { return (nil, nil) }
    let x = position.x
    let y = position.y
    var hit: Int?
    var scrollbarHit: Int?
    for i in order where contains(i, x: x, y: y) {
      if let scrollbarHit, isDescendant(i, of: scrollbarHit) { continue }
      if let bar = scrollbar(at: i), bar.hitRegion.contains(x: x, y: y) {
        scrollbarHit = i
        hit = nil
      } else if nodes[i].isInteractive || (scrollable && nodes[i].scrollable) {
        hit = i
        scrollbarHit = nil
      }
    }
    return (hit, scrollbarHit)
  }

  private mutating func advanceFocus(backward: Bool) {
    var first: Int?
    var last: Int?
    var previous: Int?
    var next: Int?
    var foundCurrent = false
    for i in order where nodes[i].acceptsFocus && nodes[i].interaction.isInteractive {
      if first == nil { first = i }
      if handle(i) == focused {
        previous = last
        foundCurrent = true
      } else if foundCurrent && next == nil {
        next = i
      }
      last = i
    }
    if let i = backward ? (previous ?? last) : (next ?? first) { focused = handle(i) }
  }

  private mutating func activate(_ i: Int) {
    nodes[i].clicks += 1
    nodes[i].flash = 1
    nodes[i].interaction.activate()
  }

}
