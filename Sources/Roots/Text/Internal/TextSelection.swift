extension UIStorage {
  var selectedText: String? {
    if let selection = activeGroupSelection, !selection.range.isEmpty {
      return String(selection.text.dropFirst(selection.range.lowerBound).prefix(selection.range.count))
    }
    guard let i = resolve(focused), let layout = nodes[i].textLayout, !nodes[i].selection.isEmpty
    else { return nil }
    return String(
      layout.text.dropFirst(nodes[i].selection.lowerBound).prefix(nodes[i].selection.count))
  }

  mutating func pointer(_ phase: PointerEvent.Phase, input: Input, to i: Int) {
    guard let position = input.mousePosition ?? lastMousePosition else { return }
    let region = nodes[i].region
    nodes[i].interaction.handlePointer(
      PointerEvent(
        phase: phase, position: Coordinate(x: position.x - region.x, y: position.y - region.y),
        region: region))
  }

  mutating func handleTextKey(
    _ event: KeyEvent, at i: Int, primaryShortcut: KeyModifiers, onCopy: ((String) -> Void)?
  ) {
    guard event.phase != .released, let layout = nodes[i].textLayout else { return }
    if handleGroupSelectionKey(event, at: i, primaryShortcut: primaryShortcut, onCopy: onCopy) { return }
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
    let clip = node.clip.map { $0.intersection(node.region) } ?? node.region
    if !layout.flowLines.isEmpty {
      for fragment in layout.fragments {
        if let background = fragment.background {
          emit(
            DrawRect(
              Region(
                node.region.x + fragment.region.x, node.region.y + fragment.region.y,
                fragment.advance, fragment.region.height), background, clip: clip))
        }
      }
      if selected {
        for line in layout.flowLines {
          let start = max(line.start, node.selection.lowerBound)
          let end = min(line.end, node.selection.upperBound)
          if end > start {
            let x = line.stops[start - line.start]
            let right = line.stops[end - line.start]
            emit(
              DrawRect(
                Region(node.region.x + x, node.region.y + line.region.y, right - x, line.region.height),
                Color(0.28, 0.24, 0.42), clip: clip))
          }
        }
      }
      for fragment in layout.fragments {
        drawText(
          fragment.text, x: node.region.x + fragment.region.x, y: node.region.y + fragment.region.y,
          font: fragment.font, color: fragment.color, clip: clip)
      }
      return
    }
    for (index, line) in layout.lines.enumerated() {
      let content = line.content
      let font = content.font
      let y = node.region.y + content.y
      guard y + font.lineHeight > clip.y, y < clip.y + clip.height else { continue }
      if let background = content.background {
        emit(
          DrawRect(Region(node.region.x, y, node.region.width, font.lineHeight), background, clip: clip))
      }
      var x = node.region.x + content.x
      for run in line.paintRuns where !run.text.isEmpty {
        if let background = run.background {
          emit(
            DrawRect(Region(x, y, font.width(of: run.text), font.lineHeight), background, clip: clip))
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
              Region(
                node.region.x + content.x + Float(line.column(at: start - line.start)) * font.advance,
                y,
                Float(line.column(at: end - line.start) - line.column(at: start - line.start))
                  * font.advance,
                font.lineHeight), Color(0.28, 0.24, 0.42), clip: clip))
        }
      }
      x = node.region.x + content.x
      for run in line.paintRuns where !run.text.isEmpty {
        x = drawText(run.text, x: x, y: y, font: font, color: run.color, clip: clip)
      }
    }
  }
}
