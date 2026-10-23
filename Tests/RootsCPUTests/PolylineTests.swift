import Roots
import RootsCPU
import Testing

@Test func joinedAndSelfCrossingTranslucentStrokesBlendOnlyOnce() throws {
  for points: [SIMD2<Float>] in [
    [.init(8, 8), .init(24, 8), .init(24, 24)],
    [.init(8, 8), .init(24, 24), .init(8, 24), .init(24, 8)],
    [.init(8, 8), .init(8, 8), .init(24, 24)],
    [.init(8, 8)]
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
  let stroke = try #require(PolylineStroke(points: [.init(16, 16)], width: 8))
  let strokeCPU = CPURenderer(width: 32, height: 32)
  let circleCPU = CPURenderer(width: 32, height: 32)
  strokeCPU.render([DrawRect(polyline: stroke, color: .accent)].span)
  circleCPU.render([DrawRect(Region(12, 12, 8, 8), .accent, radius: 4)].span)
  #expect(strokeCPU.pixels == circleCPU.pixels)
}
