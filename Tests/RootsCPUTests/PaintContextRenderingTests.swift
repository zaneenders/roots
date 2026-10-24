@_spi(Hosting) import Roots
import RootsCPU
import Testing

@Test @MainActor func insideStrokesPreserveTheUnderlyingSurfaceAndWideStrokesFill() {
  let renderer = CPURenderer(width: 32, height: 24)
  var ui = UIHost()
  ui.frame(
    build: {
      Row(in: Region(0, 0, 32, 24)) {
        Canvas(key: 1, extent: 32, color: Color(0, 0, 1)) { context in
          context.fillRect(context.region, color: Color(0, 0, 1))
          context.strokeRect(Region(4, 4, 16, 16), color: Color(1, 0, 0, 0.5), radius: 4, width: 2)
          context.strokeRect(Region(24, 8, 4, 8), color: Color(0, 1, 0), radius: 2, width: 10)
        }
      }
    }, present: { renderer.render($0) })
  func pixel(_ x: Int, _ y: Int) -> [UInt8] {
    Array(renderer.pixels[(y * 32 + x) * 3..<(y * 32 + x) * 3 + 3])
  }
  #expect(pixel(12, 12) == [0, 0, 255])
  #expect(pixel(12, 4)[0] > 0 && pixel(12, 4)[2] > 0)
  #expect(pixel(12, 2) == [0, 0, 255])
  #expect(pixel(26, 12) == [0, 255, 0])
}

@Test @MainActor func linesAreAntialiasedAndRoundCapsExtendBeyondTheSegment() {
  let renderer = CPURenderer(width: 40, height: 32)
  var ui = UIHost()
  ui.frame(
    build: {
      Row(in: Region(0, 0, 40, 32)) {
        Canvas(key: 1, extent: 40) { context in
          context.fillRect(context.region, color: Color(0, 0, 0))
          context.strokeLine(from: .init(x: 8, y: 8), to: .init(x: 24, y: 8), color: Color(1, 1, 1), width: 4)
          context.strokeLine(
            from: .init(x: 8, y: 20), to: .init(x: 24, y: 20), color: Color(1, 1, 1), width: 4, cap: .butt)
          context.strokeLine(
            from: .init(x: 30, y: 4), to: .init(x: 35, y: 28), color: Color(1, 1, 1), width: 1)
        }
      }
    }, present: { renderer.render($0) })
  func red(_ x: Int, _ y: Int) -> UInt8 { renderer.pixels[(y * 40 + x) * 3] }
  #expect(red(6, 8) > 127)
  #expect(red(6, 20) == 0)
  #expect(red(16, 8) == 255 && red(16, 20) == 255)
  #expect((4..<28).contains { y in (29..<37).contains { x in red(x, y) > 0 && red(x, y) < 255 } })
}
