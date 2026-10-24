import Roots
import Testing

struct SizeTests {
  @Test func dimensionsPreserveNamesAndValueSemantics() {
    let size = Size(width: 80, height: 40)
    #expect(size.width == 80)
    #expect(size.height == 40)
    var copy = size
    copy.width = 120
    copy.height = 60
    #expect(copy == Size(width: 120, height: 60))
    #expect(size == Size(width: 80, height: 40))
  }
}
