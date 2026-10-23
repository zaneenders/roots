struct Node {
  var generation: UInt64 = 1
  var key: UInt64 = 0
  var hasKey = true
  var implicitIdentity: ImplicitNodeIdentity?
  var cursorDepth = 0
  var selectionGroup: UInt64?
  var plainText: PlainTextStyle?
  var paragraph: ParagraphContent?
  var seen: UInt64 = 0
  var live = false
  var region = Region(0, 0, 0, 0)
  var layoutRegion = Region(0, 0, 0, 0)
  var clip: Region?
  var scrollParent: Int?
  var scrollable = false
  var showsScrollIndicator = false
  var scrollOffset: Float = 0
  var contentHeight: Float = 0
  var scrollTranslation: Float = 0
  var isBackground = false
  var rectangleStyle: RectangleStyle?
  var foregroundColor = Color.text
  var color = Color.panel
  var title = ""
  var interaction = NodeInteraction.none
  var clicks = 0
  var hovered = false
  var hover: Float = 0
  var flash: Float = 0
  var font = MonospaceFont()
  var selectableLabel = false
  var textLayout: TextLayout?
  var selectionAnchor = 0
  var selectionCursor = 0
  var selection: Range<Int> {
    min(selectionAnchor, selectionCursor)..<max(selectionAnchor, selectionCursor)
  }
  var acceptsFocus = true
  var isFocusable: Bool { acceptsFocus && isInteractive }
  var isInteractive: Bool {
    interaction.isInteractive
      || (paragraph.map { $0.selectable && !(textLayout?.text.isEmpty ?? true) }
        ?? (textLayout != nil))
  }
  var textOverflow: TextOverflow = .clip
}
