import Roots
// expected-error: escaping closure captures 'inout' parameter 'frame'

struct Invalid: Block {
  typealias Body = Never
  borrowing func _build(into frame: inout UIFrame) {
    Task { BlockBuilder.buildBlock()._build(into: &frame) }
  }
}
