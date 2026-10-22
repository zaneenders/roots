import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test(arguments: [Int32(1), 2, 3])
  func analyticStrokesAndLinesMatchCPUWithScalingClippingAndOpacity(scale: Int32) throws {
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: 64, height: 48)
    input.bufferScale = scale
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    try renderer.beginFrame(width: 64, height: 48, bufferScale: scale)
    var ui = UIHost()
    var physicalDraws: [DrawRect] = []
    ui.frame(
      build: {
        RowBlock(in: Rect(0, 0, 64, 48)) {
          CanvasBlock(key: 1, extent: 64) { context in
            context.fillRect(context.rect, color: Color(0, 0, 0))
            context.strokeRect(Rect(4, 4, 24, 24), color: Color(0, 1, 0, 0.7), radius: 6, width: 2)
            context.strokeRect(Rect(4, 32, 8, 8), color: Color(1, 0, 1), radius: 2, width: 10)
            context.strokeLine(
              from: .init(32, 6), to: .init(56, 24), color: Color(1, 1, 1, 0.6), width: 3)
            context.strokeLine(
              from: .init(56, 30), to: .init(32, 42), color: Color(1, 0, 0), width: 2, cap: .butt)
            context.strokeLine(
              from: .init(20, 36), to: .init(20, 36), color: Color(0, 0, 1), width: 4)
            context.withOrigin(x: 60, y: 36) { local in
              local.strokeLine(
                from: .init(-4, -3), to: .init(8, 5), color: Color(1, 1, 0), width: 2)
            }
          }
        }
      },
      present: { draws in
        renderer.withFrame { $0.render(draws) }
        for draw in draws {
          var physical = draw
          let s = Float(scale)
          physical.rect = Rect(
            draw.rect.x * s, draw.rect.y * s, draw.rect.width * s, draw.rect.height * s)
          physical.radius *= s
          physical.strokeWidth *= s
          physical.clip = draw.clip.map { Rect($0.x * s, $0.y * s, $0.width * s, $0.height * s) }
          physicalDraws.append(physical)
        }
      })
    try renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let bytes = try Data(contentsOf: path)
    let width = 64 * Int(scale)
    let height = 48 * Int(scale)
    let pixels = Array(bytes.dropFirst(Data("P6\n\(width) \(height)\n255\n".utf8).count))
    let cpu = CPURenderer(width: width, height: height)
    cpu.render(physicalDraws.span)
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(pixels.count == cpu.pixels.count)
    #expect(maximumError <= 4)
    #expect(pixels[(16 * Int(scale) * width + 16 * Int(scale)) * 3 + 1] == 0)
  }
}
