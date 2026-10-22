struct Cursor: BitwiseCopyable {
  var rect: Rect
  var position: Float = 0
  var gap: Float
  var horizontal: Bool
  var scrollParent: Int?
}
