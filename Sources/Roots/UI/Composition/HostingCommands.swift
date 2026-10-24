@_spi(Hosting) public struct Focus: Block {
  public typealias Body = Never
  let key: UInt64
  let reveal: Bool
  public init(key: UInt64, reveal: Bool = false) {
    self.key = key
    self.reveal = reveal
  }
  public borrowing func _build(into frame: inout UIFrame) { frame.focus(key: key, reveal: reveal) }
}

@_spi(Hosting) public struct ScrollTo: Block {
  public typealias Body = Never
  let key: UInt64
  let offset: Float
  public init(_ offset: Float, in key: UInt64) {
    self.key = key
    self.offset = offset
  }
  public borrowing func _build(into frame: inout UIFrame) { frame.scrollTo(offset, in: key) }
}
