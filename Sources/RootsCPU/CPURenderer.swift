import Foundation
import Roots

public final class CPURenderer {
  public enum FragmentOrigin: Sendable { case topLeft, bottomLeft }
  private let fragmentOrigin: FragmentOrigin
  public let width: Int, height: Int
  public private(set) var pixels: [UInt8]
  public init(width: Int, height: Int, fragmentOrigin: FragmentOrigin = .topLeft) {
    precondition(width > 0 && height > 0 && width <= 8192 && height <= 8192)
    self.width = width
    self.height = height
    self.fragmentOrigin = fragmentOrigin
    pixels = [UInt8](repeating: 0, count: width * height * 3)
  }

  @MainActor public func render(_ batch: borrowing UIDrawBatch) {
    clear()
    for command in batch {
      switch command {
      case .rectangle(let draw): renderRectangle(draw)
      case .image(let image):
        if let draw = image.resolve() { renderImage(draw) }
      }
    }
  }

  package func render(_ draws: borrowing Span<DrawRect>) {
    clear()
    for draw in draws { renderRectangle(draw) }
  }

  private func clear() {

    for i in stride(from: 0, to: pixels.count, by: 3) {
      pixels[i] = 10
      pixels[i + 1] = 13
      pixels[i + 2] = 18
    }

  }

  private func renderRectangle(_ draw: DrawRect) {
    let r = draw.region
    guard draw.isValid else { return }
    var bounds = draw.bounds
    if let clip = draw.clip {
      guard clip.x.isFinite && clip.y.isFinite && clip.width.isFinite && clip.height.isFinite
      else { return }
      bounds = bounds.intersection(clip)
    }
    guard !bounds.isEmpty else { return }
    let x0 = Int(max(0, min(Float(width), bounds.x.rounded(.down))))
    let y0 = Int(max(0, min(Float(height), bounds.y.rounded(.down))))
    let x1 = Int(max(0, min(Float(width), (bounds.x + bounds.width).rounded(.up))))
    let y1 = Int(max(0, min(Float(height), (bounds.y + bounds.height).rounded(.up))))
    guard x1 > x0 && y1 > y0 else { return }
    let radius = max(0, min(draw.radius, min(r.width, r.height) / 2))
    let alpha = max(0, min(1, draw.color.a))
    let red = max(0, min(1, draw.color.r)) * 255
    let green = max(0, min(1, draw.color.g)) * 255
    let blue = max(0, min(1, draw.color.b)) * 255
    let lod: Float
    if let uv = draw.glyphUV {
      let atlasMipCount =
        draw.colorGlyph ? EmojiAtlas.shared.mipLevels.count : FontAtlas.shared.mipLevels.count
      let atlasDimension =
        draw.colorGlyph ? Float(EmojiAtlas.shared.height) : Float(FontAtlas.shared.height)
      let atlasWidth =
        draw.colorGlyph ? Float(EmojiAtlas.shared.width) : Float(FontAtlas.shared.width)
      let footprint = max(atlasWidth * uv.width / r.width, atlasDimension * uv.height / r.height)
      lod = min(Float(atlasMipCount - 1), max(0, log2(footprint)))
    } else {
      lod = 0
    }
    func distance(_ x: Float, _ y: Float) -> Float {
      if let stroke = draw.polyline { return stroke.distance(to: .init(x: x, y: y)) }
      let local = draw.localPosition(at: .init(x: x, y: y))
      let qx = abs(local.x - r.width / 2) - r.width / 2 + radius
      let qy = abs(local.y - r.height / 2) - r.height / 2 + radius
      let dx = max(qx, 0)
      let dy = max(qy, 0)
      return (dx * dx + dy * dy).squareRoot() + min(max(qx, qy), 0) - radius
    }
    func coverage(_ distance: Float, edge: Float) -> Float {
      let t = max(0, min(1, (distance + edge) / (2 * edge)))
      return 1 - t * t * (3 - 2 * t)
    }
    for y in y0..<y1 {
      for x in x0..<x1 {
        let px = Float(x) + 0.5
        let py = Float(y) + 0.5
        guard px >= bounds.x, px < bounds.x + bounds.width,
          py >= bounds.y, py < bounds.y + bounds.height
        else { continue }
        let local = draw.localPosition(at: .init(x: px, y: py))
        var alpha = alpha
        if draw.glyphUV == nil {
          let d = distance(px, py)
          let dx = distance(Float(x ^ 1) + 0.5, py) - d
          let pairedY =
            fragmentOrigin == .bottomLeft ? height - 1 - ((height - 1 - y) ^ 1) : y ^ 1
          let dy = distance(px, Float(pairedY) + 0.5) - d
          let edge = max((abs(dx) + abs(dy)) * 0.75, 0.0001)
          var shapeCoverage = coverage(d, edge: edge)
          if draw.strokeWidth > 0 && draw.strokeWidth < min(r.width, r.height) / 2 {
            shapeCoverage = max(0, shapeCoverage - coverage(d + draw.strokeWidth, edge: edge))
          }
          alpha *= shapeCoverage
        }
        var texRed = red
        var texGreen = green
        var texBlue = blue
        if let uv = draw.glyphUV {
          guard local.x >= 0, local.x < r.width, local.y >= 0, local.y < r.height
          else { continue }
          let u = uv.x + local.x / r.width * uv.width
          let v = uv.y + local.y / r.height * uv.height
          let lower = Int(lod)
          let fraction = lod - Float(lower)
          if draw.colorGlyph {
            let levels = EmojiAtlas.shared.mipLevels.count
            let upper = min(lower + 1, levels - 1)
            let low = sampleEmoji(u: u, v: v, level: lower)
            let high = sampleEmoji(u: u, v: v, level: upper)
            let texel = (
              low.0 * (1 - fraction) + high.0 * fraction,
              low.1 * (1 - fraction) + high.1 * fraction,
              low.2 * (1 - fraction) + high.2 * fraction,
              low.3 * (1 - fraction) + high.3 * fraction
            )
            let unpremultiply: Float = texel.3 > 0 ? 255 / texel.3 : 0
            texRed = texel.0 * unpremultiply
            texGreen = texel.1 * unpremultiply
            texBlue = texel.2 * unpremultiply
            alpha *= texel.3
          } else {
            let upper = min(lower + 1, FontAtlas.shared.mipLevels.count - 1)
            alpha *=
              sample(u: u, v: v, level: lower) * (1 - fraction)
              + sample(u: u, v: v, level: upper) * fraction
          }
        }
        let i = (y * width + x) * 3
        pixels[i] = UInt8(texRed * alpha + Float(pixels[i]) * (1 - alpha))
        pixels[i + 1] = UInt8(texGreen * alpha + Float(pixels[i + 1]) * (1 - alpha))
        pixels[i + 2] = UInt8(texBlue * alpha + Float(pixels[i + 2]) * (1 - alpha))
      }
    }
  }

  private func renderImage(_ draw: ResolvedImageDraw) {
    let bounds = draw.region.intersection(draw.clip ?? draw.region)
      .intersection(Region(0, 0, Float(width), Float(height)))
    guard !bounds.isEmpty else { return }
    let frame = draw.frame
    func sample(_ plane: Int, _ channel: Int, _ u: Float, _ v: Float) -> Float {
      let w = frame.planeWidth(plane), h = frame.planeHeight(plane)
      let x = u * Float(w) - 0.5, y = v * Float(h) - 0.5
      let ix = Int(floor(x)), iy = Int(floor(y))
      let dx = x - Float(ix), dy = y - Float(iy)
      func pixel(_ x: Int, _ y: Int) -> Float {
        Float(frame.planes[plane].bytes[
          max(0, min(h - 1, y)) * frame.planes[plane].bytesPerRow
            + max(0, min(w - 1, x)) * frame.planeChannels(plane) + channel]) / 255
      }
      return (pixel(ix, iy) * (1 - dx) + pixel(ix + 1, iy) * dx) * (1 - dy)
        + (pixel(ix, iy + 1) * (1 - dx) + pixel(ix + 1, iy + 1) * dx) * dy
    }
    for y in Int(bounds.y.rounded(.down))..<Int((bounds.y + bounds.height).rounded(.up)) {
      for x in Int(bounds.x.rounded(.down))..<Int((bounds.x + bounds.width).rounded(.up)) {
        guard bounds.contains(x: Float(x) + 0.5, y: Float(y) + 0.5) else { continue }
        let u = draw.uv.x + (Float(x) + 0.5 - draw.region.x) / draw.region.width * draw.uv.width
        let v = draw.uv.y + (Float(y) + 0.5 - draw.region.y) / draw.region.height * draw.uv.height
        let rgb: SIMD3<Float>
        var alpha = draw.opacity
        if frame.format == .rgba8 {
          rgb = SIMD3(sample(0, 0, u, v), sample(0, 1, u, v), sample(0, 2, u, v))
          alpha *= sample(0, 3, u, v)
        } else {
          let t = frame.chromaTransform
          let cu = u * t.x + t.z, cv = v * t.y + t.w
          let value = SIMD4(sample(0, 0, u, v), sample(1, 0, cu, cv),
            sample(frame.format == .nv12 ? 1 : 2, frame.format == .nv12 ? 1 : 0, cu, cv), 1)
          rgb = SIMD3((frame.red * value).sum(), (frame.green * value).sum(), (frame.blue * value).sum())
        }
        for c in 0..<3 {
          let i = (y * width + x) * 3 + c
          pixels[i] = UInt8(max(0, min(1, rgb[c])) * 255 * alpha + Float(pixels[i]) * (1 - alpha))
        }
      }
    }
  }

  private func sample(u: Float, v: Float, level: Int) -> Float {
    let mip = FontAtlas.shared.mipLevels[level]
    let x = u * Float(mip.width) - 0.5
    let y = v * Float(mip.height) - 0.5
    let x0 = Int(floor(x))
    let y0 = Int(floor(y))
    let dx = x - Float(x0)
    let dy = y - Float(y0)
    func pixel(_ x: Int, _ y: Int) -> Float {
      Float(mip.pixels[max(0, min(mip.height - 1, y)) * mip.width + max(0, min(mip.width - 1, x))])
        / 255
    }
    return (pixel(x0, y0) * (1 - dx) + pixel(x0 + 1, y0) * dx) * (1 - dy)
      + (pixel(x0, y0 + 1) * (1 - dx) + pixel(x0 + 1, y0 + 1) * dx) * dy
  }

  private func sampleEmoji(u: Float, v: Float, level: Int) -> (Float, Float, Float, Float) {
    let mip = EmojiAtlas.shared.mipLevels[level]
    let x = u * Float(mip.width) - 0.5
    let y = v * Float(mip.height) - 0.5
    let x0 = Int(floor(x))
    let y0 = Int(floor(y))
    let dx = x - Float(x0)
    let dy = y - Float(y0)
    func pixel(_ x: Int, _ y: Int, _ channel: Int) -> Float {
      let base = (max(0, min(mip.height - 1, y)) * mip.width + max(0, min(mip.width - 1, x))) * 4
      return Float(mip.pixels[base + channel]) / 255
    }
    func channel(_ c: Int) -> Float {
      (pixel(x0, y0, c) * (1 - dx) + pixel(x0 + 1, y0, c) * dx) * (1 - dy)
        + (pixel(x0, y0 + 1, c) * (1 - dx) + pixel(x0 + 1, y0 + 1, c) * dx) * dy
    }
    return (channel(2), channel(1), channel(0), channel(3))
  }

  public func writePPM(to path: String) throws {
    var bytes = Data("P6\n\(width) \(height)\n255\n".utf8)
    bytes.append(contentsOf: pixels)
    try bytes.write(to: URL(fileURLWithPath: path))
  }
}
