@_spi(Hosting) import Roots
import RootsCPU
import Testing

@Test @MainActor func rectangleRendersSquareCornersPaddingAndBackground() {
  let renderer = CPURenderer(width: 20, height: 20)
  var host = UIHost()
  host.frame(
    build: {
      ZStack(in: Region(0, 0, 20, 20)) {
        Rect()
          .color(Color(1, 0, 0))
          .frame(width: .fixed(8), height: .fixed(8))
          .padding(4)
          .background(Color(0, 0, 1))
      }
    }, present: { renderer.render($0) })

  func pixel(_ x: Int, _ y: Int) -> [UInt8] {
    Array(renderer.pixels[(y * 20 + x) * 3..<(y * 20 + x) * 3 + 3])
  }
  #expect(pixel(10, 10) == [255, 0, 0])
  #expect(pixel(6, 6) == [255, 0, 0])
  #expect(pixel(13, 13) == [255, 0, 0])
  #expect(pixel(10, 3) == [0, 0, 255])
  #expect(pixel(10, 19) == [10, 13, 18])
}

@Test(arguments: [
  (Float(0), Optional<Float>.none), (3, nil), (3, 0.5), (100, 2), (3, 0), (3, 20)
])
@MainActor func rectangleMatchesCanvasFillAndInsideStroke(radius: Float, width: Float?) {
  let actual = CPURenderer(width: 40, height: 40)
  let expected = CPURenderer(width: 40, height: 40)
  let color = Color(0.8, 0.2, 0.4, 0.6)
  var host = UIHost()
  var reference = UIHost()
  host.frame(
    build: {
      ScrollColumn(key: 1, in: Region(5, 5, 30, 20), gap: 0) {
        if let width {
          Rect(cornerRadius: radius).stroke(width: width).color(color)
            .frame(width: .fixed(30), height: .fixed(30))
        } else {
          Rect(cornerRadius: radius).color(color)
            .frame(width: .fixed(30), height: .fixed(30))
        }
      }
      ScrollToBlock(5, in: 1)
    }, present: { actual.render($0) })
  reference.frame(
    build: {
      ScrollColumn(key: 1, in: Region(5, 5, 30, 20), gap: 0) {
        Canvas(key: 2, extent: 30, color: Color(0, 0, 0, 0)) { context in
          if let width {
            context.strokeRect(context.region, color: color, radius: radius, width: width)
          } else {
            context.fillRect(context.region, color: color, radius: radius)
          }
        }
      }
      ScrollToBlock(5, in: 1)
    }, present: { expected.render($0) })
  #expect(actual.pixels == expected.pixels)
}
