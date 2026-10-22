import Roots

struct MetalScissorRect: Equatable, Sendable {
  var x = 0
  var y = 0
  var width = 0
  var height = 0
  var isEmpty: Bool { width == 0 || height == 0 }

  init(_ rect: Rect, logicalSize: SIMD2<Float>, drawableSize: SIMD2<Int32>) {
    guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
      rect.width > 0, rect.height > 0,
      logicalSize.x.isFinite, logicalSize.y.isFinite, logicalSize.x > 0, logicalSize.y > 0,
      drawableSize.x > 0, drawableSize.y > 0
    else { return }
    let scaleX = Double(drawableSize.x) / Double(logicalSize.x)
    let scaleY = Double(drawableSize.y) / Double(logicalSize.y)
    let x0 = max(0, min(Double(drawableSize.x), (Double(rect.x) * scaleX - 0.5).rounded(.up)))
    let y0 = max(0, min(Double(drawableSize.y), (Double(rect.y) * scaleY - 0.5).rounded(.up)))
    let x1 = max(
      0, min(Double(drawableSize.x), (Double(rect.x + rect.width) * scaleX - 0.5).rounded(.up)))
    let y1 = max(
      0, min(Double(drawableSize.y), (Double(rect.y + rect.height) * scaleY - 0.5).rounded(.up)))
    x = Int(x0)
    y = Int(y0)
    width = max(0, Int(x1 - x0))
    height = max(0, Int(y1 - y0))
  }
}
