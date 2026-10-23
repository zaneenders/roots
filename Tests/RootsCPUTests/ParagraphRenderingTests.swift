@_spi(Hosting) import Roots
import RootsCPU
import Testing

@Test @MainActor func paragraphInlineBackgroundsWrapAndStayInsideTheViewport() {
  let renderer = CPURenderer(width: 40, height: 48)
  var host = UIHost()
  host.frame(
    build: {
      Column(in: Region(0, 0, 22, 48), gap: 0) {
        Paragraph {
          Text("hello world")
            .color(Color(1, 1, 1))
            .background(Color(1, 0, 0))
        }
        .size(10)
        .background(Color(0, 0, 1))
      }
    }, present: { renderer.render($0) })

  func pixel(_ x: Int, _ y: Int) -> [UInt8] {
    Array(renderer.pixels[(y * 40 + x) * 3..<(y * 40 + x) * 3 + 3])
  }
  #expect(pixel(3, 11) == [255, 0, 0])
  let secondLine = pixel(3, 27)
  #expect(secondLine[0] == 255 && secondLine[1] <= 1 && secondLine[2] <= 1)
  #expect(pixel(20, 12) == [0, 0, 255])
  #expect(pixel(23, 13) != [255, 0, 0])
}
