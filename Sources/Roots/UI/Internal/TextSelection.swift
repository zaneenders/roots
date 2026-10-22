extension UIStorage {
  var selectedText: String? {
    guard let i = resolve(focused), let layout = nodes[i].textLayout, !nodes[i].selection.isEmpty
    else { return nil }
    return String(
      layout.text.dropFirst(nodes[i].selection.lowerBound).prefix(nodes[i].selection.count))
  }

  mutating func pointer(_ phase: PointerEvent.Phase, input: Input, to i: Int) {
    let rect = nodes[i].rect
    nodes[i].interaction.handlePointer(
      PointerEvent(phase: phase, x: input.x - rect.x, y: input.y - rect.y, rect: rect))
  }

  mutating func handleTextKey(
    _ event: KeyEvent, at i: Int, primaryShortcut: KeyModifiers, onCopy: ((String) -> Void)?
  ) {
    guard event.phase != .released, let layout = nodes[i].textLayout else { return }
    let modifiers = event.modifiers.intersection([.control, .alt, .super])
    if modifiers == primaryShortcut {
      switch event.key {
      case .character("a"), .character("A"):
        nodes[i].selectionAnchor = 0
        nodes[i].selectionCursor = layout.text.count
      case .character("c"), .character("C"):
        if event.phase == .pressed, let text = selectedText { onCopy?(text) }
      default: break
      }
    } else if modifiers.isEmpty {
      var cursor = nodes[i].selectionCursor
      switch event.key {
      case .left:
        cursor =
          !event.modifiers.contains(.shift) && !nodes[i].selection.isEmpty
          ? nodes[i].selection.lowerBound : max(0, cursor - 1)
      case .right:
        cursor =
          !event.modifiers.contains(.shift) && !nodes[i].selection.isEmpty
          ? nodes[i].selection.upperBound : min(layout.text.count, cursor + 1)
      case .home: cursor = 0
      case .end: cursor = layout.text.count
      case .escape: cursor = nodes[i].selectionAnchor
      default: return
      }
      nodes[i].selectionCursor = cursor
      if !event.modifiers.contains(.shift) { nodes[i].selectionAnchor = cursor }
    }
  }

  mutating func paintText(_ layout: TextLayout, node: Node, selected: Bool) {
    let clip = node.clip.map { $0.intersection(node.rect) } ?? node.rect
    for (index, line) in layout.lines.enumerated() {
      let content = line.content
      let font = content.font
      let y = node.rect.y + content.y
      guard y + font.lineHeight > clip.y, y < clip.y + clip.height else { continue }
      if let background = content.background {
        emit(
          DrawRect(Rect(node.rect.x, y, node.rect.width, font.lineHeight), background, clip: clip))
      }
      var x = node.rect.x + content.x
      for run in line.paintRuns where !run.text.isEmpty {
        if let background = run.background {
          emit(
            DrawRect(Rect(x, y, font.width(of: run.text), font.lineHeight), background, clip: clip))
        }
        x += font.width(of: run.text)
      }
      if selected {
        let start = max(line.start, node.selection.lowerBound)
        let lineEnd =
          index + 1 < layout.lines.count ? layout.lines[index + 1].start : line.start + line.count
        let end = min(lineEnd, node.selection.upperBound)
        if end > start {
          emit(
            DrawRect(
              Rect(
                node.rect.x + content.x + Float(line.column(at: start - line.start)) * font.advance,
                y,
                Float(line.column(at: end - line.start) - line.column(at: start - line.start))
                  * font.advance,
                font.lineHeight), Color(0.28, 0.24, 0.42), clip: clip))
        }
      }
      x = node.rect.x + content.x
      for run in line.paintRuns where !run.text.isEmpty {
        x = drawText(run.text, x: x, y: y, font: font, color: run.color, clip: clip)
      }
    }
  }
}
