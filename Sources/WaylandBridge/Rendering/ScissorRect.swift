import Roots

struct ScissorRect: Equatable {
  var x: Int32 = 0
  var y: Int32 = 0
  var width: Int32 = 0
  var height: Int32 = 0

  init(_ region: Region, width: Int32, height: Int32, scale: Float = 1) {
    guard region.x.isFinite, region.y.isFinite, region.width.isFinite, region.height.isFinite,
      region.width > 0, region.height > 0, scale.isFinite, scale > 0
    else { return }
    let x0 = max(0, min(Double(width), (Double(region.x) * Double(scale) - 0.5).rounded(.up)))
    let y0 = max(0, min(Double(height), (Double(region.y) * Double(scale) - 0.5).rounded(.up)))
    let x1 = max(
      0, min(Double(width), (Double(region.x + region.width) * Double(scale) - 0.5).rounded(.up)))
    let y1 = max(
      0, min(Double(height), (Double(region.y + region.height) * Double(scale) - 0.5).rounded(.up)))
    x = Int32(x0)
    y = Int32(y0)
    self.width = Int32(x1 - x0)
    self.height = Int32(y1 - y0)
  }
}
