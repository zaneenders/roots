import BlockFixtureComponents
import Roots

@MainActor
func render(into frame: inout UIFrame) {
  let panel = PublicPanel { PublicLeaf() }
  let copy = panel
  copy._build(into: &frame)
  let rectangle: Rectangle = Rectangle().radius(3).stroke(width: 1.5)
  Column(in: Region(0, 0, 100, 100)) {
    Canvas(key: 6) { context in
      let region: Region = context.region
      context.fillRect(region, color: .accent)
      context.strokeRect(region, color: .text)
      let draw = DrawRect(region, .accent)
      let pointer = PointerEvent(phase: .pressed, position: .init(x: 0, y: 0), region: draw.region)
      let scroll = ScrollEvent(deltaY: 1, position: .init(x: 0, y: 0), region: pointer.region)
      _ = scroll.region
    }
    rectangle.color(.accent).frame(width: .fixed(24), height: .fixed(24))
      .padding(2).background(.panel)
    if true { Text("").selectable(key: 1) } else { Button(key: 2, "") }
    if false { Text("") }
    ForEach([UInt64(4), 5]) { Text("").selectable(key: $0) }
  }._build(into: &frame)
}

@MainActor
func inspect(_ state: borrowing UIState) -> NodeState? { state.state(for: 1) }

func publicGeometry() {
  let position = Coordinate(x: 10, y: 20)
  let size = Size(width: 100, height: 80)
  let input = Input(mousePosition: position)
  let region = Region(0, 0, size.width, size.height)
  let draw = DrawRect(region, .accent)
  _ = region.center
  _ = input.mousePosition
  _ = draw.localPosition(at: draw.position(at: position))
  _ = PolylineStroke(points: [position, region.center], width: 2)
}
