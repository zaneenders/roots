import BlockFixtureComponents
import Roots

@MainActor
func render(into frame: inout UIFrame) {
  let panel = PublicPanel { PublicLeaf() }
  let copy = panel
  copy._build(into: &frame)
  ColumnBlock(in: Rect(0, 0, 100, 100)) {
    if true { LabelBlock(key: 1, "") } else { ButtonBlock(key: 2, "") }
    if false { LabelBlock(key: 3, "") }
    ForEachBlock([UInt64(4), 5]) { LabelBlock(key: $0, "") }
  }._build(into: &frame)
}

@MainActor
func inspect(_ state: borrowing UIState) -> NodeState? { state.state(for: 1) }
