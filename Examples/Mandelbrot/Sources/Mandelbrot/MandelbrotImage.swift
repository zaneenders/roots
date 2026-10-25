import Foundation
import Roots

enum MandelbrotImage {
  static let width = 640
  static let height = 400
  static let maximumIterations = 160
  static let interior = Color(8 / 255, 10 / 255, 20 / 255)

  // Cache horizontal runs of equal RGBA8 colors, rather than creating a Block per pixel.
  static let runs: [DrawRect] = {
    var runs: [DrawRect] = []
    for y in 0..<height {
      let imaginary = -1.15 + 2.3 * Double(y) / Double(height - 1)
      var start = 0
      var previous = color(real: -2.35, imaginary: imaginary)
      for x in 1...width {
        let next =
          x < width
          ? color(real: -2.35 + 3.4 * Double(x) / Double(width - 1), imaginary: imaginary)
          : nil
        if next != previous {
          runs.append(DrawRect(Region(Float(start), Float(y), Float(x - start), 1), previous))
          start = x
          if let next { previous = next }
        }
      }
    }
    return runs
  }()

  static func color(real: Double, imaginary: Double) -> Color {
    var zx = 0.0
    var zy = 0.0
    var iteration = 0
    while zx * zx + zy * zy <= 4, iteration < maximumIterations {
      let nextX = zx * zx - zy * zy + real
      zy = 2 * zx * zy + imaginary
      zx = nextX
      iteration += 1
    }
    guard iteration < maximumIterations else { return interior }
    let magnitude = max(zx * zx + zy * zy, 4)
    let smooth = Double(iteration) + 1 - log2(log2(magnitude) / 2)
    let t = max(0, min(1, smooth / Double(maximumIterations)))
    let phase = 2 * Double.pi * (t * 8 + 0.62)
    func channel(_ offset: Double) -> Float {
      Float(UInt8(clamping: Int(127.5 + 127.5 * sin(phase + offset)))) / 255
    }
    return Color(channel(0), channel(2.094), channel(4.188))
  }

  static func fitted(in bounds: Region) -> Region {
    let scale = max(0, min(bounds.width / Float(width), bounds.height / Float(height)))
    let w = Float(width) * scale
    let h = Float(height) * scale
    return Region(bounds.x + (bounds.width - w) / 2, bounds.y + (bounds.height - h) / 2, w, h)
  }

  static func paint(in context: inout UIPaintContext) {
    let region = fitted(in: context.region)
    guard !region.isEmpty else { return }
    context.withOrigin(x: region.x, y: region.y, scale: region.width / Float(width)) { context in
      context.withClip(Region(0, 0, Float(width), Float(height))) { context in
        context.fillRect(Region(0, 0, Float(width), Float(height)), color: interior)
        // Overlap sample edges so rectangle antialiasing blends neighboring colors, not the background.
        for run in runs {
          context.fillRect(run.region.insetBy(dx: -0.5, dy: -0.5), color: run.color)
        }
      }
    }
  }
}
