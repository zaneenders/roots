import Testing

@testable import Roots

@Test func imageFrameValidatesEveryPlaneAndOverflow() throws {
  #expect(throws: ImageFrame.Error.self) {
    try ImageFrame(width: 0, height: 1, format: .rgba8, planes: [])
  }
  #expect(throws: ImageFrame.Error.self) {
    try ImageFrame(
      width: 2, height: 2, format: .rgba8,
      planes: [.init(bytes: [0], bytesPerRow: Int.max)])
  }
  #expect(throws: ImageFrame.Error.self) {
    try ImageFrame(
      width: 3, height: 3, format: .nv12,
      planes: [
        .init(bytes: [UInt8](repeating: 0, count: 9), bytesPerRow: 3),
        .init(bytes: [UInt8](repeating: 0, count: 6), bytesPerRow: 3),
      ])
  }
  let frame = try ImageFrame(
    width: 3, height: 3, format: .yuv420p,
    planes: [
      .init(bytes: [UInt8](repeating: 16, count: 12), bytesPerRow: 4),
      .init(bytes: [128, 128, 128, 128], bytesPerRow: 2),
      .init(bytes: [128, 128, 128, 128], bytesPerRow: 2),
    ])
  #expect(frame.planeWidth(1) == 2)
  #expect(frame.planeHeight(2) == 2)
}

@Test @MainActor func imageFitFillAndOwnedResolution() throws {
  let frame = try ImageFrame(
    width: 2, height: 1, format: .rgba8,
    planes: [.init(bytes: [255, 0, 0, 255, 0, 255, 0, 255], bytesPerRow: 8)])
  let source = ImageSource(frame)
  let bounds = Region(10, 20, 100, 100)
  let fit = try #require(ImageDraw(source, in: bounds).resolve())
  #expect(fit.region == Region(10, 45, 100, 50))
  let fill = try #require(ImageDraw(source, in: bounds, contentMode: .fill).resolve())
  #expect(fill.uv == Region(0.25, 0, 0.5, 1))
  source.publish(nil)
  #expect(fit.frame === frame)
  #expect(ImageDraw(source, in: bounds).resolve() == nil)
  source.publish(frame)
  #expect(ImageDraw(source, in: Region(.nan, 0, 1, 1)).resolve() == nil)
  #expect(ImageDraw(source, in: bounds, opacity: .nan).resolve() == nil)
}

@Test @MainActor func imageCommandsPreserveOrderTransformsAndClip() throws {
  var store = UIStore()
  let source = ImageSource()
  store.frame(
    build: { frame in
      frame.beginColumn(in: Region(0, 0, 80, 80))
      frame.canvas(key: 1) { paint in
        paint.withOrigin(x: 10, y: 20, scale: 2) { paint in
          paint.withClip(Region(0, 0, 10, 10)) { paint in
            paint.drawImage(source, in: Region(1, 2, 8, 6))
            paint.fillRect(Region(0, 0, 1, 1), color: .accent)
          }
        }
      }
      frame.end()
    },
    present: { batch in
      #expect(batch.count == 3)
      guard case .image(let draw) = batch[1] else {
        Issue.record("Missing image")
        return
      }
      #expect(draw.region == Region(12, 24, 16, 12))
      #expect(draw.clip == Region(10, 20, 20, 20))
      guard case .rectangle = batch[2] else {
        Issue.record("Painter order changed")
        return
      }
    })
}
