import Roots

@MainActor func externalImageClient(_ pixels: [UInt8]) throws {
  let frame = try ImageFrame(
    width: 1, height: 1, format: .rgba8,
    planes: [.init(bytes: pixels, bytesPerRow: 4)])
  let source = ImageSource(frame)
  let commands: [DrawCommand] = [.image(ImageDraw(source, in: Region(0, 0, 20, 20)))]
  let batch = UIDrawBatch(commands.span)
  for command in batch {
    if case .image(let image) = command, let resolved = image.resolve() {
      _ = resolved.frame.planes[0].bytes
      _ = resolved.frame.chromaTransform
    }
  }
  _ = Video(source, key: 1)
}
