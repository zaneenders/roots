extension UIStorage {
  var scrollParent: Int? { cursors.isEmpty ? nil : cursors[cursors.count - 1].scrollParent }

  mutating func place(_ extent: Float) -> Rect {
    precondition(!cursors.isEmpty, "Begin a row or column before adding a node")
    let i = cursors.count - 1
    let cursor = cursors[i]
    let result =
      cursor.horizontal
      ? Rect(cursor.rect.x + cursor.position, cursor.rect.y, extent, cursor.rect.height)
      : Rect(cursor.rect.x, cursor.rect.y + cursor.position, cursor.rect.width, extent)
    cursors[i].position += extent + cursor.gap
    return result
  }

  mutating func declare(
    key: UInt64, title: String, rect: Rect, color: Color, font: MonospaceFont = MonospaceFont(),
    scrollable: Bool = false, textOverflow: TextOverflow = .clip,
    interaction: NodeInteraction = .none,
    selectable: Bool = false, textLines: [TextLine]? = nil, focusable: Bool = true,
    showsScrollIndicator: Bool = false
  ) -> NodeHandle {
    let index: Int
    if let old = keys[key] {
      index = old
    } else {
      if !free.isEmpty {
        index = free.removeLast()
      } else {
        index = nodes.count
        nodes.append(Node())
      }
      nodes[index].key = key
      nodes[index].live = true
      keys[key] = index
    }
    precondition(nodes[index].seen != epoch, "Keys must be unique within a frame")
    nodes[index].seen = epoch
    nodes[index].rect = rect
    nodes[index].layoutRect = rect
    nodes[index].scrollParent = scrollParent
    if !scrollable { nodes[index].scrollOffset = 0 }
    nodes[index].scrollable = scrollable
    nodes[index].showsScrollIndicator = showsScrollIndicator
    nodes[index].contentHeight = 0
    nodes[index].title = title
    nodes[index].color = color
    nodes[index].interaction = interaction
    nodes[index].acceptsFocus = focusable
    nodes[index].font = font
    nodes[index].textOverflow = textOverflow
    var layout: TextLayout?
    swap(&layout, &nodes[index].textLayout)
    let hadLayout = layout != nil
    var content = textLines
    if selectable {
      let displayed =
        textOverflow == .truncateTail ? font.truncating(title, to: rect.width - 24) : title
      let y = (rect.height - font.height(of: title)) / 2
      content = displayed.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
        TextLine(
          [TextRun(String($0.element))], y: y + Float($0.offset) * font.lineHeight, font: font)
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
    if let parent = nodes[index].scrollParent {
      nodes[parent].contentHeight = max(
        nodes[parent].contentHeight, rect.y + rect.height - nodes[parent].layoutRect.y)
    }
    order.append(index)
    return handle(index)
  }

  func contains(_ i: Int, x: Float, y: Float) -> Bool {
    nodes[i].rect.contains(x: x, y: y) && (nodes[i].clip?.contains(x: x, y: y) ?? true)
  }

}
