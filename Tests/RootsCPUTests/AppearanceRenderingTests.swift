@_spi(Hosting) import Roots
import RootsCPU
import Testing

@Test @MainActor func nestedBackgroundsBlendOnceAndClipWithTheirScrollViewport() {
  let renderer = CPURenderer(width: 40, height: 32)
  var host = UIHost()
  host.frame(
    build: {
      ZStack(in: Region(0, 0, 40, 32)) {
        ScrollColumn(key: 1, in: Region(4, 4, 32, 24), gap: 0) {
          Column {
            Column {}.frame(width: .fixed(32), height: .fixed(40))
              .background(Color(1, 0, 0, 0.5))
          }.background(Color(0, 1, 0))
        }
        ScrollToBlock(8, in: 1)
      }.background(Color(0, 0, 1))
    }, present: { renderer.render($0) })

  func pixel(_ x: Int, _ y: Int) -> [UInt8] {
    Array(renderer.pixels[(y * 40 + x) * 3..<(y * 40 + x) * 3 + 3])
  }
  #expect(pixel(20, 16) == [127, 127, 0])
  #expect(pixel(20, 2) == [0, 0, 255])
  #expect(pixel(20, 29) == [0, 0, 255])
}
