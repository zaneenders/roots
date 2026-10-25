import Testing

@testable import Roots

@Test func ribbonsAreExplicitAboutTransparencyAndFallbacks() throws {
  let points: [Coordinate] = [.init(x: 0, y: 0), .init(x: 20, y: 0), .init(x: 40, y: 3)]
  let automatic = try #require(PolylineStroke(points: points, width: 3))
  #expect(automatic.ribbon != nil)
  #expect(automatic.usesRibbon(tint: Color(1, 1, 1)))
  #expect(!automatic.usesRibbon(tint: Color(1, 1, 1, 0.5)))
  let transparent = points.map { _ in Color(1, 0, 0, 0.5) }
  #expect(PolylineStroke(points: points, width: 3, colors: transparent)?.ribbon == nil)
  let explicit = try #require(PolylineStroke(points: points, width: 3, colors: transparent, rendering: .ribbon))
  #expect(explicit.usesRibbon(tint: Color(1, 1, 1, 0.5)))
  #expect(PolylineStroke(points: points, width: 3, rendering: .analytic)?.ribbon == nil)
  #expect(PolylineStroke(points: [.zero], width: 3)?.ribbon == nil)
  #expect(PolylineStroke(points: [.zero, .zero], width: 3)?.ribbon == nil)
  #expect(PolylineStroke(points: [.zero, .init(x: 10, y: 0), .zero], width: 3)?.ribbon == nil)
}

@Test func ribbonTrianglesAreFiniteAndGrowLinearly() throws {
  let points = (0..<1_024).map { Coordinate(x: Float($0), y: Float($0) / 10) }
  let stroke = try #require(PolylineStroke(points: points, width: 4, rendering: .ribbon))
  let ribbon = try #require(stroke.ribbon)
  #expect(ribbon.vertices.count == (points.count - 1) * 6 + 72)
  #expect(ribbon.minimumScale.isFinite)
  for vertex in ribbon.vertices {
    for axis in 0..<4 { #expect(vertex.geometry[axis].isFinite && vertex.edge[axis].isFinite) }
  }
  let left = ribbon.vertices[0].geometry
  let right = ribbon.vertices[1].geometry
  #expect(left.x == right.x && left.y == right.y)
  #expect(left.z == -right.z && left.w == -right.w)
}
