import Roots

struct Invalid: Block {
  typealias Body = Never
  borrowing func _build(into frame: inout UIFrame) {
    Task { BlockBuilder.buildBlock()._build(into: &frame) }
  }
}
