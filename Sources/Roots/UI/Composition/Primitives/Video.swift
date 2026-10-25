/// Codec-independent video/image display. The producer publishes frames to the source.
public struct Video: Block {
  public typealias Body = Never
  private let source: ImageSource
  private let key: UInt64
  private let contentMode: ImageContentMode

  public init(_ source: ImageSource, key: UInt64, contentMode: ImageContentMode = .fit) {
    self.source = source
    self.key = key
    self.contentMode = contentMode
  }

  public borrowing func _build(into frame: inout UIFrame) {
    let source = source
    let contentMode = contentMode
    frame.canvas(key: key, color: Color(0, 0, 0)) { context in
      context.drawImage(source, in: context.region, contentMode: contentMode)
    }
  }
}
