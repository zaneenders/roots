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
