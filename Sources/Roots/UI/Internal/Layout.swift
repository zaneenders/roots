extension UIStorage {
  var scrollParent: Int? { cursors.isEmpty ? nil : cursors[cursors.count - 1].scrollParent }

  mutating func place(_ extent: Float) -> Region {
    precondition(!cursors.isEmpty, "Begin a row or column before adding a node")
    let i = cursors.count - 1
    let cursor = cursors[i]
    if cursor.layout != nil { return Region(0, 0, extent, extent) }
    let result =
      cursor.horizontal
      ? Region(cursor.region.x + cursor.position, cursor.region.y, extent, cursor.region.height)
      : Region(cursor.region.x, cursor.region.y + cursor.position, cursor.region.width, extent)
    cursors[i].position += extent + cursor.gap
    return result
  }

  mutating func declare(
    key: UInt64?, title: String, region: Region, color: Color, font: MonospaceFont = MonospaceFont(),
    scrollable: Bool = false, textOverflow: TextOverflow = .clip,
    interaction: NodeInteraction = .none,
    selectable: Bool = false, textLines: [TextLine]? = nil, focusable: Bool = true,
    showsScrollIndicator: Bool = false, participatesInLayout: Bool = true,
    plainText: PlainTextStyle? = nil, paragraph: ParagraphContent? = nil, identity: IdentityLocation? = nil
  ) -> NodeHandle {
    let implicitIdentity = identity.map { ImplicitNodeIdentity(path: identityPath, location: $0) }
    let index: Int
    if let key, let old = keys[key] {
      index = old
    } else if let implicitIdentity, let old = implicitKeys[implicitIdentity] {
      index = old
    } else {
      if !free.isEmpty {
        index = free.removeLast()
      } else {
        index = nodes.count
        nodes.append(Node())
      }
      nodes[index].key = key ?? 0
      nodes[index].hasKey = key != nil
      nodes[index].implicitIdentity = implicitIdentity
      nodes[index].live = true
      if let key { keys[key] = index }
      if let implicitIdentity { implicitKeys[implicitIdentity] = index }
    }
    precondition(nodes[index].seen != epoch, "Keys must be unique within a frame")
    nodes[index].seen = epoch
    nodes[index].cursorDepth = cursors.count
    nodes[index].region = region
    nodes[index].layoutRegion = region
    nodes[index].scrollParent = scrollParent
    if !scrollable { nodes[index].scrollOffset = 0 }
    nodes[index].scrollable = scrollable
    nodes[index].showsScrollIndicator = showsScrollIndicator
    nodes[index].contentHeight = 0
    nodes[index].title = title
    if nodes[index].selectionGroup != selectionGroup {
      nodes[index].selectionAnchor = 0
      nodes[index].selectionCursor = 0
    }
    nodes[index].selectionGroup = selectionGroup
    nodes[index].plainText = plainText
    nodes[index].paragraph = paragraph
    nodes[index].isBackground = false
    nodes[index].rectangleStyle = nil
    nodes[index].foregroundColor = foregroundColor ?? .text
    nodes[index].color = color
    nodes[index].interaction = interaction
    nodes[index].acceptsFocus = focusable
    nodes[index].font = font
    nodes[index].textOverflow = textOverflow
    nodes[index].selectableLabel = selectable
    if paragraph == nil && plainText == nil && (!selectable || currentCursor?.layout == nil) {
      updateTextLayout(at: index, textLines: textLines)
    }
    if let parent = nodes[index].scrollParent {
      nodes[parent].contentHeight = max(
        nodes[parent].contentHeight, region.y + region.height - nodes[parent].layoutRegion.y)
    }
    if participatesInLayout, !scrollable, let layout = currentCursor?.layout {
      let axis = layouts[layout].style.kind.isRow ? 0 : 1
      var style = LayoutStyle(kind: .leaf, width: .fill, height: .fill)
      if axis == 0 { style.width = .fixed(region.width) } else { style.height = .fixed(region.height) }
      attachLayoutLeaf(index, size: SIMD2(region.width, region.height), style: style)
    }
    order.append(index)
    return handle(index)
  }

  mutating func updateTextLayout(at index: Int, textLines: [TextLine]? = nil) {
    let node = nodes[index]
    var layout: TextLayout?
    swap(&layout, &nodes[index].textLayout)
    let hadLayout = layout != nil
    var content = textLines
    if let style = node.plainText, style.selectable {
      content = style.lines(for: node.title, in: node.region, color: node.foregroundColor)
    } else if node.selectableLabel {
      let displayed =
        node.textOverflow == .truncateTail ? node.font.truncating(node.title, to: node.region.width - 24) : node.title
      let y = (node.region.height - node.font.height(of: node.title)) / 2
      content = displayed.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
        TextLine(
          [TextRun(String($0.element), color: node.foregroundColor)], y: y + Float($0.offset) * node.font.lineHeight,
          size: node.font.size)
      }
    }
    if let content {
      if layout != nil {
        if layout?.update(content, selectionEnd: nodes[index].selection.upperBound)
          .preservesSelection == false
        {
          nodes[index].selectionAnchor = 0
          nodes[index].selectionCursor = 0
        }
      } else {
        layout = TextLayout(content)
      }
    } else {
      layout = nil
    }
    if layout?.text.isEmpty == true { layout = nil }
    if layout == nil {
      nodes[index].selectionAnchor = 0
      nodes[index].selectionCursor = 0
    }
    if hadLayout != (layout != nil) {
      if focused == handle(index) { focused = nil }
      if pressed == handle(index) { pressed = nil }
    }
    nodes[index].textLayout = layout
  }

  func contains(_ i: Int, x: Float, y: Float) -> Bool {
    nodes[i].region.contains(x: x, y: y) && (nodes[i].clip?.contains(x: x, y: y) ?? true)
  }

}
