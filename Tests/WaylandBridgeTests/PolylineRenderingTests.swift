import Foundation
import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test(arguments: [UInt32(120), 150, 180, 210, 240, 360])
  func joinedTranslucentStrokeMatchesCPUAndPreservesDrawOrder(scale120: UInt32) throws {
    let scale = Double(scale120) / 120
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: 48, height: 40)
    input.fractionalScale120 = scale120
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    let points: [Coordinate] = [
      Coordinate(x: 8, y: 8), Coordinate(x: 32, y: 28), Coordinate(x: 8, y: 28),
      Coordinate(x: 32, y: 8), Coordinate(x: 32, y: 8)
    ]
    let stroke = try #require(PolylineStroke(points: points, width: 4))
    let draws = [
      DrawRect(Region(0, 0, 48, 40), Color(0, 0, 0)),
      DrawRect(polyline: stroke, color: Color(1, 1, 1, 0.5), clip: Region(4, 4, 32, 28)),
      DrawRect(Region(40, 30, 4, 4), Color(1, 0, 0))
    ]
    try renderer.beginFrame(width: 48, height: 40, fractionalScale120: scale120)
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let width = Int(48 * scale)
    let height = Int(40 * scale)
    let data = try Data(contentsOf: path)
    let pixels = Array(data.dropFirst(Data("P6\n\(width) \(height)\n255\n".utf8).count))
    let s = Float(scale)
    let physicalStroke = try #require(
      PolylineStroke(points: points.map { Coordinate(x: $0.x * s, y: $0.y * s) }, width: 4 * s))
    let physical = [
      DrawRect(Region(0, 0, Float(width), Float(height)), Color(0, 0, 0)),
      DrawRect(
        polyline: physicalStroke, color: Color(1, 1, 1, 0.5),
        clip: Region(4 * s, 4 * s, 32 * s, 28 * s)),
      DrawRect(Region(40 * s, 30 * s, 4 * s, 4 * s), Color(1, 0, 0))
    ]
    let cpu = CPURenderer(width: width, height: height)
    cpu.render(physical.span)
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(pixels.count == cpu.pixels.count)
    #expect(maximumError <= 4)
    let crossing = ((Int(18 * scale)) * width + Int(20 * scale)) * 3
    #expect(abs(Int(pixels[crossing]) - 128) <= 1)
  }
  @Test func maximumPolylineUniformPayloadAndSinglePointRenderWithoutErrors() throws {
    let renderer = NativeRenderer()
    try renderer.setup(input: .init(width: 32, height: 32))
    defer { renderer.cleanup() }
    let points = (0..<PolylineStroke.maximumPointCount).map { index in
      Coordinate(x: Float(index % 16) + 4, y: Float(index / 16) + 4)
    }
    let stroke = try #require(PolylineStroke(points: points, width: 2))
    let dot = try #require(PolylineStroke(points: [Coordinate(x: 24, y: 24)], width: 4))
    try renderer.beginFrame(width: 32, height: 32)
    renderer.withFrame { frame in
      frame.render(
        [DrawRect(polyline: stroke, color: .accent), DrawRect(polyline: dot, color: .text)].span)
    }
    try renderer.endFrame(surfaceless: true)
  }

}
