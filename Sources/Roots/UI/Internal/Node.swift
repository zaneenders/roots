struct Node {
  var generation: UInt64 = 1
  var key: UInt64 = 0
  var seen: UInt64 = 0
  var live = false
  var rect = Rect(0, 0, 0, 0)
  var layoutRect = Rect(0, 0, 0, 0)
  var clip: Rect?
  var scrollParent: Int?
  var scrollable = false
  var showsScrollIndicator = false
  var scrollOffset: Float = 0
  var contentHeight: Float = 0
  var scrollTranslation: Float = 0
  var color = Color.panel
  var title = ""
  var interaction = NodeInteraction.none
  var clicks = 0
  var hovered = false
  var hover: Float = 0
  var flash: Float = 0
  var font = MonospaceFont()
  var textLayout: TextLayout?
  var selectionAnchor = 0
  var selectionCursor = 0
  var selection: Range<Int> {
    min(selectionAnchor, selectionCursor)..<max(selectionAnchor, selectionCursor)
  }
  var acceptsFocus = true
  var isFocusable: Bool { acceptsFocus && isInteractive }
  var isInteractive: Bool { interaction.isInteractive || textLayout != nil }
  var textOverflow: TextOverflow = .clip
}
