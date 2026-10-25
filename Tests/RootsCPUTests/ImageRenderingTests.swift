@_spi(Hosting) import Roots
import RootsCPU
import Testing

@Test @MainActor func cpuVideoRendersRGBAAndBothYUVLayouts() throws {
  let rgba = try ImageFrame(
    width: 2, height: 1, format: .rgba8,
    planes: [.init(bytes: [255, 0, 0, 255, 0, 255, 0, 255, 99, 99, 99, 99], bytesPerRow: 12)])
  let planar = try ImageFrame(
    width: 2, height: 1, format: .yuv420p,
    planes: [
      .init(bytes: [16, 235, 99, 99], bytesPerRow: 4),
      .init(bytes: [128], bytesPerRow: 1), .init(bytes: [128], bytesPerRow: 1),
    ])
  let nv12 = try ImageFrame(
    width: 2, height: 1, format: .nv12,
    planes: [.init(bytes: [16, 235], bytesPerRow: 2), .init(bytes: [128, 128], bytesPerRow: 2)])
  let source = ImageSource()
  let cpu = CPURenderer(width: 2, height: 1)
  var host = UIHost()
  for frame in [rgba, planar, nv12] {
    source.publish(frame)
    host.frame(
      build: {
        Column(in: Region(0, 0, 2, 1)) { Video(source, key: 1) }
      }, present: { cpu.render($0) })
    let expected: [UInt8] = frame === rgba ? [255, 0, 0, 0, 255, 0] : [0, 0, 0, 255, 255, 255]
    #expect(zip(cpu.pixels, expected).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
  }
}

@Test @MainActor func planarChromaSitingHandlesOddDimensions() throws {
  for location in [ImageFrame.ChromaLocation.center, .left, .topLeft] {
    let frame = try ImageFrame(
      width: 3, height: 3, format: .nv12,
      planes: [
        .init(bytes: [UInt8](repeating: 128, count: 9), bytesPerRow: 3),
        .init(bytes: [16, 128, 240, 128, 240, 128, 16, 128], bytesPerRow: 4),
      ],
      chromaLocation: location)
    let t = frame.chromaTransform
    #expect(t.x == 0.75 && t.y == 0.75)
    #expect(t.z == (location == .center ? 0 : 0.125))
    #expect(t.w == (location == .topLeft ? 0.125 : 0))
    let source = ImageSource(frame)
    let cpu = CPURenderer(width: 3, height: 3)
    cpu.render(UIDrawBatch([DrawCommand.image(ImageDraw(source, in: Region(0, 0, 3, 3)))].span))
    #expect(cpu.pixels.count == 27)
  }
}
