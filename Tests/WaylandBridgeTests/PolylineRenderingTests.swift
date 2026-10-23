import Foundation
import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test(arguments: [Int32(1), 2, 3])
  func joinedTranslucentStrokeMatchesCPUAndPreservesDrawOrder(scale: Int32) throws {
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: 48, height: 40)
    input.bufferScale = scale
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    let points: [SIMD2<Float>] = [
      .init(8, 8), .init(32, 28), .init(8, 28), .init(32, 8), .init(32, 8)
    ]
    let stroke = try #require(PolylineStroke(points: points, width: 4))
    let draws = [
      DrawRect(Rect(0, 0, 48, 40), Color(0, 0, 0)),
      DrawRect(polyline: stroke, color: Color(1, 1, 1, 0.5), clip: Rect(4, 4, 32, 28)),
      DrawRect(Rect(40, 30, 4, 4), Color(1, 0, 0))
    ]
    try renderer.beginFrame(width: 48, height: 40, bufferScale: scale)
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let width = 48 * Int(scale)
    let height = 40 * Int(scale)
    let data = try Data(contentsOf: path)
    let pixels = Array(data.dropFirst(Data("P6\n\(width) \(height)\n255\n".utf8).count))
    let s = Float(scale)
    let physicalStroke = try #require(PolylineStroke(points: points.map { $0 * s }, width: 4 * s))
    let physical = [
      DrawRect(Rect(0, 0, Float(width), Float(height)), Color(0, 0, 0)),
      DrawRect(
        polyline: physicalStroke, color: Color(1, 1, 1, 0.5),
        clip: Rect(4 * s, 4 * s, 32 * s, 28 * s)),
      DrawRect(Rect(40 * s, 30 * s, 4 * s, 4 * s), Color(1, 0, 0))
    ]
    let cpu = CPURenderer(width: width, height: height)
    cpu.render(physical.span)
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(pixels.count == cpu.pixels.count)
    #expect(maximumError <= 4)
    let crossing = ((18 * Int(scale)) * width + 20 * Int(scale)) * 3
    #expect(abs(Int(pixels[crossing]) - 128) <= 1)
  }
  @Test func maximumPolylineUniformPayloadAndSinglePointRenderWithoutErrors() throws {
    let renderer = NativeRenderer()
    try renderer.setup(input: .init(width: 32, height: 32))
    defer { renderer.cleanup() }
    let points = (0..<PolylineStroke.maximumPointCount).map { index in
      SIMD2<Float>(Float(index % 16) + 4, Float(index / 16) + 4)
    }
    let stroke = try #require(PolylineStroke(points: points, width: 2))
    let dot = try #require(PolylineStroke(points: [.init(24, 24)], width: 4))
    try renderer.beginFrame(width: 32, height: 32)
    renderer.withFrame { frame in
      frame.render(
        [DrawRect(polyline: stroke, color: .accent), DrawRect(polyline: dot, color: .text)].span)
    }
    try renderer.endFrame(surfaceless: true)
  }

}
