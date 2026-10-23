struct Cursor: BitwiseCopyable {
  var region: Region
  var isScrollViewport = false
  var startOrder: Int = 0
  var position: Float = 0
  var gap: Float
  var horizontal: Bool
  var layout: Int?
  var scrollParent: Int?
}
