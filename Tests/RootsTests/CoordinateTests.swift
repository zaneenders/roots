import Roots
import Testing

struct CoordinateTests {
  @Test func coordinatesPreserveComponentsAndValueSemantics() {
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
}
