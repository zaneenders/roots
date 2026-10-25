import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import MacOSBridge

extension MetalRenderingTests {
  @Test func imageTexturesMatchCPUAcrossReusedSlots() async throws {
    let renderer = try MetalRenderer(logicalSize: .init(20, 12), drawableSize: .init(20, 12))
    let cpu = CPURenderer(width: 20, height: 12)
    let source = ImageSource()
    for index in 0..<8 {
      let frame = try ImageFrame(
        width: 2, height: 2, format: .nv12,
        planes: [
          .init(bytes: [16, 235, UInt8(30 + index * 20), 145], bytesPerRow: 2),
          .init(bytes: [90, 200], bytesPerRow: 2),
        ])
      source.publish(frame)
      let commands: [DrawCommand] = [
        .rectangle(DrawRect(Region(0, 0, 20, 12), Color(0, 0, 0))),
        .image(ImageDraw(source, in: Region(2, 2, 16, 8), contentMode: .stretch)),
        .rectangle(DrawRect(Region(8, 4, 4, 4), .accent)),
      ]
      cpu.render(UIDrawBatch(commands.span))
      let image = try #require(
        await renderer.render(readback: true) {
          $0.render(UIDrawBatch(commands.span))
        })
      let pixels = Array(image.dropFirst(Data("P6\n20 12\n255\n".utf8).count))
      #expect(zip(pixels, cpu.pixels).allSatisfy { abs(Int($0) - Int($1)) <= 3 })
    }
  }
}
