import Roots

struct ScissorRect: Equatable {
  var x: Int32 = 0
  var y: Int32 = 0
  var width: Int32 = 0
  var height: Int32 = 0

  init(_ rect: Rect, width: Int32, height: Int32, scale: Float = 1) {
    guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
      rect.width > 0, rect.height > 0, scale.isFinite, scale > 0
    else { return }
    let x0 = max(0, min(Double(width), (Double(rect.x) * Double(scale) - 0.5).rounded(.up)))
    let y0 = max(0, min(Double(height), (Double(rect.y) * Double(scale) - 0.5).rounded(.up)))
    let x1 = max(
      0, min(Double(width), (Double(rect.x + rect.width) * Double(scale) - 0.5).rounded(.up)))
    let y1 = max(
      0, min(Double(height), (Double(rect.y + rect.height) * Double(scale) - 0.5).rounded(.up)))
    x = Int32(x0)
    y = Int32(y0)
    self.width = Int32(x1 - x0)
    self.height = Int32(y1 - y0)
  }
}
