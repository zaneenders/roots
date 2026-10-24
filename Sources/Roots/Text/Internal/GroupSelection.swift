struct GroupSelection {
  let key: UInt64
  var text: String
  var anchor: Int
  var cursor: Int
  var range: Range<Int> { min(anchor, cursor)..<max(anchor, cursor) }
}

extension UIStorage {
  var activeGroupSelection: GroupSelection? {
    guard let selection = groupSelection, let focused = resolve(focused),
      nodes[focused].selectionGroup == selection.key, nodes[focused].textLayout != nil
    else { return nil }
    return selection
  }

  func selectionMembers(_ key: UInt64) -> [Int] {
    var members: [Int] = []
    for index in order where nodes[index].selectionGroup == key && nodes[index].isInteractive {
      if nodes[index].textLayout != nil { members.append(index) }
    }
    return members
  }

  func selectionText(_ members: [Int]) -> String {
    members.compactMap { nodes[$0].textLayout?.text }.joined(separator: "\n")
  }

  func isTextSelected(_ index: Int) -> Bool {
    if let selection = activeGroupSelection, nodes[index].selectionGroup == selection.key {
      return true
    }
    return focused == handle(index)
  }

  mutating func clearGroupSelection() {
    guard let selection = groupSelection else { return }
    for index in selectionMembers(selection.key) {
      nodes[index].selectionAnchor = 0
      nodes[index].selectionCursor = 0
    }
    groupSelection = nil
  }

  mutating func reconcileGroupSelection() {
    guard var selection = groupSelection else { return }
    let members = selectionMembers(selection.key)
    let text = selectionText(members)
    let end = selection.range.upperBound
    guard !members.isEmpty, text.count >= end,
      selection.text.prefix(end).unicodeScalars.elementsEqual(text.prefix(end).unicodeScalars)
    else {
      clearGroupSelection()
      return
    }
    selection.text = text
    groupSelection = selection
    applyGroupSelection()
  }

  mutating func beginGroupSelection(at index: Int, offset: Int) {
    guard let key = nodes[index].selectionGroup else { return }
    let members = selectionMembers(key)
    var start = 0
    for member in members {
      if member == index { break }
      start += (nodes[member].textLayout?.text.count ?? 0) + 1
    }
    groupSelection = GroupSelection(
      key: key, text: selectionText(members), anchor: start + offset, cursor: start + offset)
    applyGroupSelection()
  }

  mutating func applyGroupSelection() {
    guard let selection = groupSelection else { return }
    var start = 0
    for index in selectionMembers(selection.key) {
      let count = nodes[index].textLayout?.text.count ?? 0
      let lower = min(count, max(0, selection.range.lowerBound - start))
      let upper = min(count, max(0, selection.range.upperBound - start))
      nodes[index].selectionAnchor = lower
      nodes[index].selectionCursor = upper
      start += count + 1
    }
  }

  @discardableResult
  mutating func updateGroupSelection(x: Float, y: Float) -> Bool {
    guard x.isFinite, y.isFinite, var selection = activeGroupSelection else { return false }
    let members = selectionMembers(selection.key)
    guard
      let target = members.min(by: {
        let a = nodes[$0].region
        let b = nodes[$1].region
        let ay = max(a.y - y, y - a.y - a.height, 0)
        let by = max(b.y - y, y - b.y - b.height, 0)
        if ay != by { return ay < by }
        return max(a.x - x, x - a.x - a.width, 0) < max(b.x - x, x - b.x - b.width, 0)
      }), let layout = nodes[target].textLayout
    else { return false }
    var start = 0
    for member in members {
      if member == target { break }
      start += (nodes[member].textLayout?.text.count ?? 0) + 1
    }
    selection.cursor = start + layout.offset(x: x - nodes[target].region.x, y: y - nodes[target].region.y)
    groupSelection = selection
    applyGroupSelection()
    return true
  }

  @discardableResult
  mutating func collapseGroupSelection() -> Bool {
    guard var selection = activeGroupSelection else { return false }
    selection.anchor = selection.cursor
    groupSelection = selection
    applyGroupSelection()
    return true
  }

  mutating func handleGroupSelectionKey(
    _ event: KeyEvent, at index: Int, primaryShortcut: KeyModifiers, onCopy: ((String) -> Void)?
  ) -> Bool {
    guard let key = nodes[index].selectionGroup else { return false }
    let modifiers = event.modifiers.intersection([.control, .alt, .super])
    if modifiers == primaryShortcut {
      switch event.key {
      case .character("a"), .character("A"):
        let text = selectionText(selectionMembers(key))
        groupSelection = GroupSelection(key: key, text: text, anchor: 0, cursor: text.count)
        applyGroupSelection()
        return true
      case .character("c"), .character("C"):
        if event.phase == .pressed, let text = selectedText { onCopy?(text) }
        return true
      default: return false
      }
    }
    guard modifiers.isEmpty else { return false }
    if activeGroupSelection == nil {
      beginGroupSelection(at: index, offset: nodes[index].selectionCursor)
    }
    guard var selection = activeGroupSelection else { return false }
    switch event.key {
    case .left:
      selection.cursor =
        !event.modifiers.contains(.shift) && !selection.range.isEmpty
        ? selection.range.lowerBound : max(0, selection.cursor - 1)
    case .right:
      selection.cursor =
        !event.modifiers.contains(.shift) && !selection.range.isEmpty
        ? selection.range.upperBound : min(selection.text.count, selection.cursor + 1)
    case .home: selection.cursor = 0
    case .end: selection.cursor = selection.text.count
    case .escape: selection.cursor = selection.anchor
    default: return false
    }
    if !event.modifiers.contains(.shift) { selection.anchor = selection.cursor }
    groupSelection = selection
    applyGroupSelection()
    return true
  }
}
