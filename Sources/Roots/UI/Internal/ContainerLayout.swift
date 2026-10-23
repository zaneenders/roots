struct LayoutElement {
  var style: LayoutStyle
  var depth: Int = 0
  var children: [Int] = []
  var node: Int?
  var bounds: Region?
  var scrollParent: Int?
  var measured = SIMD2<Float>.zero
  var region = Region(0, 0, 0, 0)
}

extension UIStorage {
  var currentCursor: Cursor? { cursors.isEmpty ? nil : cursors[cursors.count - 1] }

  mutating func ensureLayout() {
    guard let cursor = currentCursor else { preconditionFailure("Root containers require bounds") }
    guard cursor.layout == nil else { return }
    let index = layouts.count
    let style = LayoutStyle(
      kind: cursor.horizontal ? .row : .column, gap: cursor.gap,
      scrollsVertically: cursor.isScrollViewport)
    layouts.append(
      LayoutElement(style: style, depth: cursors.count - 1, bounds: cursor.region, scrollParent: scrollParent))
    cursors[cursors.count - 1].layout = index
    for position in cursor.startOrder..<order.count {
      let node = order[position]
      guard nodes[node].cursorDepth == cursors.count, !nodes[node].scrollable, !nodes[node].isBackground else {
        continue
      }
      let region = nodes[node].layoutRegion
      var leafStyle = LayoutStyle(kind: .leaf, width: .fill, height: .fill)
      if cursor.horizontal { leafStyle.width = .fixed(region.width) } else { leafStyle.height = .fixed(region.height) }
      attachLayoutLeaf(node, size: SIMD2(region.width, region.height), style: leafStyle)
    }
  }

  mutating func beginLayout(_ style: LayoutStyle, in bounds: Region?) {
    if bounds == nil { ensureLayout() }
    precondition(style.gap.isFinite && style.gap >= 0)
    precondition(bounds != nil || currentCursor != nil, "Root containers require bounds")
    if let bounds {
      precondition(bounds.x.isFinite && bounds.y.isFinite && bounds.width.isFinite && bounds.height.isFinite)
      precondition(bounds.width >= 0 && bounds.height >= 0)
    }
    let index = layouts.count
    layouts.append(LayoutElement(style: style, depth: cursors.count, bounds: bounds, scrollParent: scrollParent))
    if bounds == nil, let parent = currentCursor?.layout {
      layouts[parent].children.append(index)
    }
    cursors.append(
      Cursor(
        region: bounds ?? Region(0, 0, 0, 0), gap: 0, horizontal: false,
        layout: index, scrollParent: scrollParent))
  }

  mutating func endLayout(_ index: Int) {
    let element = layouts[index]
    let children = element.children
    var size = SIMD2<Float>.zero
    switch element.style.kind {
    case .leaf: return
    case .row, .column:
      let axis = element.style.kind.isRow ? 0 : 1
      for child in children {
        size[axis] += layouts[child].measured[axis]
        size[1 - axis] = max(size[1 - axis], layouts[child].measured[1 - axis])
      }
      size[axis] += Float(max(0, children.count - 1)) * element.style.gap
    case .stack, .frame:
      for child in children {
        size = SIMD2(max(size.x, layouts[child].measured.x), max(size.y, layouts[child].measured.y))
      }
    case .grid(let columns):
      precondition(columns > 0)
      for child in children {
        size = SIMD2(max(size.x, layouts[child].measured.x), max(size.y, layouts[child].measured.y))
      }
      let rows = (children.count + columns - 1) / columns
      let usedColumns = children.isEmpty ? 0 : columns
      size = SIMD2(
        size.x * Float(usedColumns) + Float(max(0, usedColumns - 1)) * element.style.gap,
        size.y * Float(rows) + Float(max(0, rows - 1)) * element.style.gap)
    }
    size += 2 * element.style.padding
    layouts[index].measured = SIMD2(
      element.style.width.measured(size.x), element.style.height.measured(size.y))
  }

  mutating func attachLayoutLeaf(_ node: Int, size: SIMD2<Float>, style: LayoutStyle) {
    guard let parent = currentCursor?.layout else { return }
    let index = layouts.count
    layouts.append(
      LayoutElement(
        style: style, depth: cursors.count, node: node,
        measured: SIMD2(
          style.width.measured(size.x), style.height.measured(size.y))))
    layouts[parent].children.append(index)
  }

  mutating func resolveLayouts() {
    if layouts.contains(where: { $0.node.map { nodes[$0].paragraph != nil } ?? false }) {
      // Widths are independent of wrapped heights. Place once to resolve widths,
      // then measure paragraphs and propagate their new heights bottom-up.
      placeLayouts(updateText: false)
      for index in layouts.indices.reversed() {
        if let node = layouts[index].node, let content = nodes[node].paragraph {
          layouts[index].measured.y =
            content.layout(
              width: layouts[index].region.width, color: nodes[node].foregroundColor
            ).size.y
        } else if layouts[index].node == nil {
          endLayout(index)
        }
      }
    }
    placeLayouts(updateText: true)
    finishLayouts()
  }

  private mutating func placeLayouts(updateText: Bool) {
    // Parents precede children in the frame-local array, so placement needs no recursion.
    for index in layouts.indices {
      if let bounds = layouts[index].bounds { layouts[index].region = bounds }
      let element = layouts[index]
      if let node = element.node {
        nodes[node].region = element.region
        nodes[node].layoutRegion = element.region
        if updateText {
          if nodes[node].paragraph != nil {
            updateParagraph(at: node)
          } else if nodes[node].selectableLabel || nodes[node].plainText != nil {
            updateTextLayout(at: node)
          }
        }
        continue
      }
      let inner = element.region.insetBy(dx: element.style.padding.x, dy: element.style.padding.y)
      let children = element.children
      switch element.style.kind {
      case .leaf: break
      case .row, .column:
        let axis = element.style.kind.isRow ? 0 : 1
        let available = axis == 0 ? inner.width : inner.height
        var sizes = children.map { layouts[$0].measured[axis] }
        let modes = children.map { axis == 0 ? layouts[$0].style.width : layouts[$0].style.height }
        let gap = Float(max(0, children.count - 1)) * element.style.gap
        if !element.style.scrollsVertically {
          distribute(&sizes, modes: modes, available: max(0, available - gap))
        }
        let used = sizes.reduce(0, +) + gap
        var position = max(0, available - used) * (axis == 0 ? element.style.alignment.x : element.style.alignment.y)
        for (offset, child) in children.enumerated() {
          let slot =
            axis == 0
            ? Region(inner.x + position, inner.y, sizes[offset], inner.height)
            : Region(inner.x, inner.y + position, inner.width, sizes[offset])
          placeLayout(child, in: slot, alignment: element.style.alignment, fixedAxis: axis)
          position += sizes[offset] + element.style.gap
        }
      case .stack, .frame:
        for child in children {
          placeLayout(child, in: inner, alignment: element.style.alignment)
          if case .frame = element.style.kind, !layouts[child].style.kind.isLeaf {
            if layouts[child].style.width == .fit {
              layouts[child].region.x = inner.x
              layouts[child].region.width = inner.width
            }
            if layouts[child].style.height == .fit {
              layouts[child].region.y = inner.y
              layouts[child].region.height = inner.height
            }
          }
        }
      case .grid(let columns):
        let rows = (children.count + columns - 1) / columns
        let width = max(0, inner.width - Float(columns - 1) * element.style.gap) / Float(columns)
        let height = rows == 0 ? 0 : max(0, inner.height - Float(rows - 1) * element.style.gap) / Float(rows)
        for (offset, child) in children.enumerated() {
          let slot = Region(
            inner.x + Float(offset % columns) * (width + element.style.gap),
            inner.y + Float(offset / columns) * (height + element.style.gap), width, height)
          placeLayout(child, in: slot, alignment: element.style.alignment)
        }
      }
    }
  }

  private mutating func finishLayouts() {
    resolveBackgrounds()
    if let index = resolve(focusAfterLayout), nodes[index].isFocusable {
      focused = focusAfterLayout
    }
    for node in order {
      if nodes[node].scrollable { nodes[node].contentHeight = 0 }
    }
    for element in layouts {
      if let parent = element.scrollParent {
        nodes[parent].contentHeight = max(
          nodes[parent].contentHeight,
          element.region.y + element.region.height - nodes[parent].layoutRegion.y)
      }
    }
    for node in order {
      if let parent = nodes[node].scrollParent {
        nodes[parent].contentHeight = max(
          nodes[parent].contentHeight,
          nodes[node].layoutRegion.y + nodes[node].layoutRegion.height - nodes[parent].layoutRegion.y)
      }
    }
  }

  private mutating func placeLayout(
    _ index: Int, in slot: Region, alignment: Alignment, fixedAxis: Int? = nil
  ) {
    let element = layouts[index]
    let width = fixedAxis == 0 ? slot.width : element.style.width.resolved(element.measured.x, available: slot.width)
    let height =
      fixedAxis == 1 ? slot.height : element.style.height.resolved(element.measured.y, available: slot.height)
    layouts[index].region = Region(
      slot.x + max(0, slot.width - width) * alignment.x,
      slot.y + max(0, slot.height - height) * alignment.y, width, height)
  }
}

extension LayoutStyle.Kind {
  var isLeaf: Bool { if case .leaf = self { true } else { false } }
  var isRow: Bool { if case .row = self { true } else { false } }
}

private func distribute(_ sizes: inout [Float], modes: [LayoutSize], available: Float) {
  var remaining = available - sizes.reduce(0, +)
  let growing = remaining > 0
  var candidates = sizes.indices.filter {
    if growing { return modes[$0] == .fill }
    if case .fixed = modes[$0] { return false }
    return sizes[$0] > 0
  }
  // Like Clay, level the smallest grow children (or largest shrink children) first.
  while !candidates.isEmpty && abs(remaining) > 0.001 {
    let extreme = candidates.map { sizes[$0] }.reduce(growing ? Float.infinity : 0, growing ? min : max)
    let active = candidates.filter { sizes[$0] == extreme }
    let next = candidates.map { sizes[$0] }.filter { growing ? $0 > extreme : $0 < extreme }
      .reduce(growing ? Float.infinity : 0, growing ? min : max)
    let amount =
      growing
      ? min(remaining / Float(active.count), next - extreme)
      : max(remaining / Float(active.count), next - extreme)
    for index in active { sizes[index] += amount }
    remaining -= amount * Float(active.count)
    if !growing { candidates.removeAll { sizes[$0] <= 0 } }
  }
}
