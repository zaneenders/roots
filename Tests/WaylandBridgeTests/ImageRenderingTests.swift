import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test func imageUploadsMatchCPUAndReplaceFramesWithoutReordering() throws {
    let renderer = NativeRenderer()
    try renderer.setup(input: .init(width: 24, height: 16))
    defer { renderer.cleanup() }
    let source = ImageSource()
    let cpu = CPURenderer(width: 24, height: 16, fragmentOrigin: .bottomLeft)
    var host = UIHost()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for format in [ImageFrame.Format.rgba8, .yuv420p, .nv12, .nv12, .rgba8] {
      let planes: [ImageFrame.Plane]
      switch format {
      case .rgba8:
        planes = [
          .init(
            bytes: [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 255, 255, 255, 255],
            bytesPerRow: 8)
        ]
      case .yuv420p:
        planes = [
          .init(bytes: [16, 235, 99, 99, 81, 145, 99, 99], bytesPerRow: 4),
          .init(bytes: [90], bytesPerRow: 1), .init(bytes: [200], bytesPerRow: 1),
        ]
      case .nv12:
        planes = [
          .init(bytes: [16, 235, 81, 145], bytesPerRow: 2),
          .init(bytes: [90, 200], bytesPerRow: 2),
        ]
      }
      source.publish(try ImageFrame(width: 2, height: 2, format: format, planes: planes))
      try renderer.beginFrame(width: 24, height: 16)
      host.frame(
        build: {
          Column(in: Region(0, 0, 24, 16)) {
            Canvas(key: 1, color: Color(0, 0, 0)) { paint in
              paint.drawImage(source, in: Region(2, 2, 20, 12), contentMode: .stretch, opacity: 0.8)
              paint.fillRect(Region(10, 6, 4, 4), color: Color(1, 0, 1))
            }
          }
        },
        present: { batch in
          renderer.withFrame { $0.render(batch) }
          cpu.render(batch)
        })
      try renderer.endFrame(surfaceless: true)
      let path = directory.appendingPathComponent("image.ppm")
      try renderer.screenshot(to: path.path)
      let pixels = Array(try Data(contentsOf: path).dropFirst(Data("P6\n24 16\n255\n".utf8).count))
      let error = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 255
      #expect(error <= 4, "format: \(format), error: \(error)")
    }
  }
}
