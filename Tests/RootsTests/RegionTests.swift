import Roots
import Testing

struct RegionTests {
  @Test func geometrySupportsOffsetsInsetsAndValueSemantics() {
    let region = Region(10, 20, 40, 30)
    var copy = region
    copy.width = 50
    #expect(region.width == 40)
    #expect(copy == Region(10, 20, 50, 30))
    #expect(region.center == SIMD2<Float>(30, 35))
    #expect(region.offsetBy(dx: 5, dy: -10) == Region(15, 10, 40, 30))
    #expect(region.insetBy(dx: 5, dy: 10) == Region(15, 30, 30, 10))
    #expect(region.insetBy(dx: 100, dy: 100) == Region(30, 35, 0, 0))
  }

  @Test func drawAndInputEventsExposeRegionGeometry() {
    let region = Region(10, 20, 40, 30)
    var draw = DrawRect(region, .accent)
    let pointer = PointerEvent(phase: .pressed, x: 12, y: 24, region: region)
    let scroll = ScrollEvent(deltaY: 5, x: 12, y: 24, region: region)
    #expect(draw.region == region)
    #expect(pointer.region == region)
    #expect(scroll.region == region)
    draw.region = region.offsetBy(dx: 5, dy: 10)
    #expect(draw.region == Region(15, 30, 40, 30))
  }

  @Test func containmentIncludesOnlyLeadingEdges() {
    let region = Region(10, 20, 40, 30)
    #expect(region.contains(x: 10, y: 20))
    #expect(region.contains(x: 49, y: 49))
    #expect(!region.contains(x: 50, y: 20))
    #expect(!region.contains(x: 10, y: 50))
    #expect(!Region(10, 20, 0, 30).contains(x: 10, y: 20))
  }

  @Test func intersectionPreservesEmptyAndOverlappingRegions() {
    let region = Region(10, 20, 40, 30)
    #expect(region.intersection(Region(30, 10, 40, 30)) == Region(30, 20, 20, 20))
    #expect(region.intersection(Region(60, 20, 10, 10)).isEmpty)
    #expect(region.intersection(Region(20, 30, 0, 10)).isEmpty)
  }
}
