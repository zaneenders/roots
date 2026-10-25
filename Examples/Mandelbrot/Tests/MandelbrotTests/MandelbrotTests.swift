@_spi(Hosting) import Roots
import Testing

@testable import Mandelbrot

struct MandelbrotTests {
  @Test func pointsInsideAndOutsideTheSet() {
    #expect(MandelbrotImage.color(real: 0, imaginary: 0) == MandelbrotImage.interior)
    #expect(MandelbrotImage.color(real: -1, imaginary: 0) == MandelbrotImage.interior)
    #expect(MandelbrotImage.color(real: 1, imaginary: 1) != MandelbrotImage.interior)
    #expect(MandelbrotImage.color(real: -2.35, imaginary: -1.15) != MandelbrotImage.interior)
  }

  @Test func paletteIsOpaqueAndSymmetricAcrossTheRealAxis() {
    for real in [-2.35, -0.75, 0, 0.3, 1.05] {
      let color = MandelbrotImage.color(real: real, imaginary: 0.4)
      #expect(color == MandelbrotImage.color(real: real, imaginary: -0.4))
      #expect(color.a == 1)
      for channel in [color.r, color.g, color.b] {
        #expect(channel.isFinite && channel >= 0 && channel <= 1)
        #expect(abs(channel * 255 - (channel * 255).rounded()) < 0.001)
      }
    }
  }

  @Test func cachedRunsReproduceEverySample() {
    let width = MandelbrotImage.width
    let height = MandelbrotImage.height
    var pixels = [Color](repeating: MandelbrotImage.interior, count: width * height)
    var previousEnd = 0
    for run in MandelbrotImage.runs {
      let region = run.region
      #expect(run.isValid)
      #expect(region.height == 1)
      let x = Int(region.x)
      let y = Int(region.y)
      let length = Int(region.width)
      #expect(x >= 0 && x + length <= width && y >= 0 && y < height)
      let start = y * width + x
      #expect(start >= previousEnd)
      for index in start..<(start + length) { pixels[index] = run.color }
      previousEnd = start + length
    }
    #expect(!MandelbrotImage.runs.isEmpty)
    #expect(MandelbrotImage.runs.count < width * height)
    for y in 0..<height {
      let imaginary = -1.15 + 2.3 * Double(y) / Double(height - 1)
      for x in 0..<width {
        let real = -2.35 + 3.4 * Double(x) / Double(width - 1)
        #expect(pixels[y * width + x] == MandelbrotImage.color(real: real, imaginary: imaginary))
      }
    }
  }

  @Test func imageFitsAndCentersWithoutStretching() {
    #expect(MandelbrotImage.fitted(in: Region(10, 20, 1000, 400)) == Region(190, 20, 640, 400))
    #expect(MandelbrotImage.fitted(in: Region(10, 20, 320, 500)) == Region(10, 170, 320, 200))
    #expect(MandelbrotImage.fitted(in: Region(0, 0, 0, 400)).isEmpty)
    #expect(MandelbrotImage.fitted(in: Region(0, 0, 640, 0)).isEmpty)
  }

  @MainActor
  @Test func resizingPaintsTheCompleteImageWithinTheCanvas() throws {
    var host = UIHost(drawCapacity: nil)
    for bounds in [Region(0, 0, 1120, 840), Region(30, 40, 480, 360)] {
      var imageDraws: [DrawRect] = []
      host.frame(
        build: { MandelbrotPage(bounds: bounds) },
        present: { batch in
          for case .rectangle(let draw) in batch where draw.glyphUV == nil && draw.radius == 0 {
            imageDraws.append(draw)
          }
        })
      #expect(host.droppedDraws == 0)
      let canvas = try #require(host.state(for: 1)?.region)
      #expect(canvas.width > 0 && canvas.height > 0)
      let fitted = MandelbrotImage.fitted(in: canvas)
      #expect(imageDraws.count == MandelbrotImage.runs.count + 1)
      let background = try #require(imageDraws.first)
      #expect(background.region == fitted)
      #expect(background.color == MandelbrotImage.interior)
      let overlap = fitted.width / Float(MandelbrotImage.width) / 2 + 0.001
      for draw in imageDraws {
        #expect(draw.isValid)
        #expect(draw.clip == fitted)
        #expect(draw.region.x >= fitted.x - overlap && draw.region.y >= fitted.y - overlap)
        #expect(draw.region.x + draw.region.width <= fitted.x + fitted.width + overlap)
        #expect(draw.region.y + draw.region.height <= fitted.y + fitted.height + overlap)
      }
    }
  }
}
