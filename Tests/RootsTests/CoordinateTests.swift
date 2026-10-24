import Roots
import Testing

struct CoordinateTests {
  @Test func coordinatesPreserveComponentsAndValueSemantics() {
    #expect(Coordinate.zero == Coordinate(x: 0, y: 0))
    let coordinate = Coordinate(x: 10, y: 20)
    #expect(coordinate.x == 10)
    #expect(coordinate.y == 20)
    #expect(coordinate == Coordinate(x: 10, y: 20))

    var copy = coordinate
    copy.x = -5
    copy.y = 30
    #expect(copy == Coordinate(x: -5, y: 30))
    #expect(coordinate == Coordinate(x: 10, y: 20))
    #expect(copy != coordinate)
  }

  @Test func rotatedDrawCoordinatesRoundTrip() {
    let draw = DrawRect(Region(10, 20, 40, 30), .accent, axis: SIMD2(0, 1))
    let local = Coordinate(x: 3, y: 4)
    let position = draw.position(at: local)
    #expect(position == Coordinate(x: 6, y: 23))
    #expect(draw.localPosition(at: position) == local)
  }
}
