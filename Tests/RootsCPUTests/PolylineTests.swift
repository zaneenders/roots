import Roots
import RootsCPU
import Testing

@Test func joinedAndSelfCrossingTranslucentStrokesBlendOnlyOnce() throws {
  for points: [Coordinate] in [
    [Coordinate(x: 8, y: 8), Coordinate(x: 24, y: 8), Coordinate(x: 24, y: 24)],
    [Coordinate(x: 8, y: 8), Coordinate(x: 24, y: 24), Coordinate(x: 8, y: 24), Coordinate(x: 24, y: 8)],
    [Coordinate(x: 8, y: 8), Coordinate(x: 8, y: 8), Coordinate(x: 24, y: 24)],
    [Coordinate(x: 8, y: 8)]
  ] {
    let stroke = try #require(PolylineStroke(points: points, width: 6))
    let cpu = CPURenderer(width: 32, height: 32)
    cpu.render(
      [
        DrawRect(Region(0, 0, 32, 32), Color(0, 0, 0)),
        DrawRect(polyline: stroke, color: Color(1, 1, 1, 0.5))
      ].span)
    #expect(cpu.pixels.max() == 127)
    #expect(cpu.pixels.contains { $0 > 0 && $0 < 127 })
    #expect(stroke.distance(to: points[0]) == -3)
  }
}

@Test func singlePointPolylineMatchesACircle() throws {
  let stroke = try #require(PolylineStroke(points: [Coordinate(x: 16, y: 16)], width: 8))
  let strokeCPU = CPURenderer(width: 32, height: 32)
  let circleCPU = CPURenderer(width: 32, height: 32)
  strokeCPU.render([DrawRect(polyline: stroke, color: .accent)].span)
  circleCPU.render([DrawRect(Region(12, 12, 8, 8), .accent, radius: 4)].span)
  #expect(strokeCPU.pixels == circleCPU.pixels)
}

@Test func longColoredSelfCrossingPathBlendsOnceAtChunkBoundaries() throws {
  let points = (0..<257).map { index in
    Coordinate(x: index % 2 == 0 ? 8 : 24, y: index % 2 == 0 ? 8 : 24)
  }
  let colors = points.map { _ in Color(1, 1, 1, 0.5) }
  let stroke = try #require(PolylineStroke(points: points, width: 6, colors: colors))
  let cpu = CPURenderer(width: 32, height: 32)
  cpu.render([DrawRect(Region(0, 0, 32, 32), Color(0, 0, 0)), DrawRect(polyline: stroke)].span)
  #expect(cpu.pixels.max() == 127)
}

@Test func translucentRibbonJoinsDoNotDoubleBlend() throws {
  let points: [Coordinate] = [.init(x: 5, y: 15), .init(x: 20, y: 15), .init(x: 35, y: 22)]
  let stroke = try #require(
    PolylineStroke(
      points: points, width: 6,
      colors: points.map { _ in Color(1, 1, 1, 0.5) }, rendering: .ribbon))
  #expect(stroke.ribbon != nil)
  let cpu = CPURenderer(width: 48, height: 40)
  cpu.render([DrawRect(Region(0, 0, 48, 40), Color(0, 0, 0)), DrawRect(polyline: stroke)].span)
  #expect(cpu.pixels.max() == 127)
  #expect(cpu.pixels[(15 * 48 + 20) * 3] == 127)
}

@Test(arguments: [false, true], [Float(-1), 1])
func largeOffscreenRibbonTrianglesStayWithinTheViewport(vertical: Bool, direction: Float) throws {
  let points: [Coordinate] = [
    .zero, .init(x: direction * 1e19, y: 0), .init(x: direction * 1e19, y: 1e15)
  ].map { vertical ? Coordinate(x: $0.y, y: $0.x) : $0 }
  let stroke = try #require(PolylineStroke(points: points, width: 1e13))
  #expect(stroke.usesRibbon(tint: .text))
  let draw = DrawRect(polyline: stroke, clip: Region(0, 0, 2, 2))
  #expect(draw.isValid)
  let marker = DrawRect(Region(4, 4, 2, 2), .accent)
  let cpu = CPURenderer(width: 10, height: 10)
  let reference = CPURenderer(width: 10, height: 10)
  cpu.render([draw, marker].span)
  reference.render([marker].span)
  for y in 0..<10 {
    for x in 0..<10 where x >= 2 || y >= 2 {
      let offset = (y * 10 + x) * 3
      #expect(cpu.pixels[offset..<offset + 3] == reference.pixels[offset..<offset + 3])
    }
  }
}
