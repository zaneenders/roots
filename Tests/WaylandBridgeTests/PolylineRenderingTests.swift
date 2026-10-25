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
  @Test func maximumPolylineTexturePayloadAndSinglePointRenderWithoutErrors() throws {
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

  @Test(arguments: [UInt32(120), 150, 240])
  func retainedColoredPathsMatchCPUAndReuseUploads(scale120: UInt32) throws {
    let points = (0..<1_024).map { index in
      let t = Float(index) / 1_023
      return Coordinate(x: t * 30, y: sin(t * 12) * 6)
    }
    let colors = points.indices.map { index in
      let t = Float(index) / Float(points.count - 1)
      return Color(1 - t, t, 0.5, 0.5)
    }
    let stroke = try #require(PolylineStroke(points: points, width: 3, colors: colors))
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: 64, height: 64)
    input.fractionalScale120 = scale120
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    let transform = PathTransform(translation: .init(x: 12, y: 15), scale: 1.3, rotation: 0.4)
    let clip = Region(8, 9, 44, 42)
    let draws = [
      DrawRect(Region(0, 0, 64, 64), Color(0, 0, 0)),
      DrawRect(polyline: stroke, transform: transform, clip: clip),
      DrawRect(Region(54, 54, 4, 4), Color(1, 0, 0))
    ]
    for _ in 0..<3 {
      try renderer.beginFrame(width: 64, height: 64, fractionalScale120: scale120)
      renderer.withFrame { $0.render(draws.span) }
      try renderer.endFrame(surfaceless: true)
    }
    #expect(renderer.polylineUploads == 1)
    #expect(renderer.cachedPolylineCount == 1)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let scale = Float(scale120) / 120
    let size = Int(64 * scale)
    let data = try Data(contentsOf: path)
    let pixels = Array(data.dropFirst(Data("P6\n\(size) \(size)\n255\n".utf8).count))
    let cpu = CPURenderer(width: size, height: size, fragmentOrigin: .bottomLeft)
    cpu.render(
      [
        DrawRect(Region(0, 0, Float(size), Float(size)), Color(0, 0, 0)),
        DrawRect(
          polyline: stroke, transform: PathTransform(scale: scale).concatenating(transform),
          clip: Region(clip.x * scale, clip.y * scale, clip.width * scale, clip.height * scale)),
        DrawRect(Region(54 * scale, 54 * scale, 4 * scale, 4 * scale), Color(1, 0, 0))
      ].span)
    #expect(pixels.count == cpu.pixels.count)
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(maximumError <= 4)
    try renderer.beginFrame(width: 64, height: 64)
    renderer.withFrame { $0.render([DrawRect(polyline: stroke, transform: .init(scale: 0.5))].span) }
    try renderer.endFrame(surfaceless: true)
    #expect(renderer.polylineUploads == 1)
    try renderer.beginFrame(width: 64, height: 64)
    try renderer.endFrame(surfaceless: true)
    #expect(renderer.cachedPolylineCount == 0)
  }

  @Test func longColoredCrossingsBlendOnceAcrossChunks() throws {
    let points = (0..<257).map { index in
      Coordinate(x: index % 2 == 0 ? 8 : 24, y: index % 2 == 0 ? 8 : 24)
    }
    let stroke = try #require(
      PolylineStroke(
        points: points, width: 6,
        colors: points.map { _ in Color(1, 1, 1, 0.5) }))
    let renderer = NativeRenderer()
    try renderer.setup(input: .init(width: 32, height: 32))
    defer { renderer.cleanup() }
    let draws = [DrawRect(Region(0, 0, 32, 32), Color(0, 0, 0)), DrawRect(polyline: stroke)]
    try renderer.beginFrame(width: 32, height: 32)
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let pixels = Array(try Data(contentsOf: path).dropFirst(Data("P6\n32 32\n255\n".utf8).count))
    #expect(abs(Int(pixels.max() ?? 0) - 128) <= 1)
  }

  @Test(arguments: [UInt32(120), 180, 240])
  func ribbonsMatchCPUAndDoNotReupload(scale120: UInt32) throws {
    let points = (0..<257).map { i in Coordinate(x: Float(i) / 8, y: sin(Float(i) / 256 * 2) * 10) }
    let colors = points.indices.map { i in Color(Float(i) / 256, 0.5, 1 - Float(i) / 256, 0.5) }
    let stroke = try #require(PolylineStroke(points: points, width: 3, colors: colors, rendering: .ribbon))
    #expect(stroke.ribbon != nil)
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: 64, height: 64)
    input.fractionalScale120 = scale120
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    let transform = PathTransform(translation: .init(x: 12, y: 15), scale: 1.2, rotation: 0.4)
    let draw = DrawRect(polyline: stroke, transform: transform, clip: Region(4, 4, 54, 54))
    let draws = [DrawRect(Region(0, 0, 64, 64), Color(0, 0, 0)), draw,
      DrawRect(Region(54, 54, 4, 4), Color(1, 0, 0))]
    for _ in 0..<3 {
      try renderer.beginFrame(width: 64, height: 64, fractionalScale120: scale120)
      renderer.withFrame { $0.render(draws.span) }
      try renderer.endFrame(surfaceless: true)
    }
    #expect(renderer.ribbonUploads == 1)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let scale = Float(scale120) / 120
    let size = Int(64 * scale)
    let pixels = Array(try Data(contentsOf: path).dropFirst(Data("P6\n\(size) \(size)\n255\n".utf8).count))
    let cpu = CPURenderer(width: size, height: size, fragmentOrigin: .bottomLeft)
    cpu.render([
      DrawRect(Region(0, 0, Float(size), Float(size)), Color(0, 0, 0)),
      DrawRect(polyline: stroke, transform: PathTransform(scale: scale).concatenating(transform),
        clip: Region(4 * scale, 4 * scale, 54 * scale, 54 * scale)),
      DrawRect(Region(54 * scale, 54 * scale, 4 * scale, 4 * scale), Color(1, 0, 0))].span)
    let errors = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }
    #expect(pixels.count == cpu.pixels.count)
    #expect(errors.max() ?? 0 <= 5)
  }

  @Test func longPathGPUComparison() throws {
    guard ProcessInfo.processInfo.environment["ROOTS_RIBBON_BENCHMARK"] == "1" else { return }
    let renderer = NativeRenderer()
    try renderer.setup(input: .init(width: 1000, height: 800))
    defer { renderer.cleanup() }
    let points = (0...1_024).map { i in
      let t = Float(i) / 1_024 * 2 * Float.pi
      return Coordinate(x: cos(2 * t) * (200 + 80 * cos(3 * t)), y: sin(2 * t) * (200 + 80 * cos(3 * t)))
    }
    let colors = points.indices.map { _ in Color(0.3, 0.8, 1, 0.2) }
    let analytic = try #require(PolylineStroke(points: points, width: 12, colors: colors, rendering: .analytic))
    let ribbon = try #require(PolylineStroke(points: points, width: 12, colors: colors, rendering: .ribbon))
    #expect(ribbon.ribbon != nil)
    for fast in [false, true, false, true] {
      let draw = DrawRect(polyline: fast ? ribbon : analytic, transform: .init(translation: .init(x: 500, y: 400)))
      var times: [Double] = []
      for frame in 0..<35 {
        let start = ContinuousClock.now
        try renderer.beginFrame(width: 1000, height: 800, fractionalScale120: 240)
        renderer.withFrame { $0.render([draw].span) }
        try renderer.endFrame(surfaceless: true)
        if frame >= 5 {
          let elapsed = start.duration(to: .now).components
          times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
      }
      times.sort()
      print("RIBBON EGL glFinish ribbon=\(fast) pixels=2000x1600 frames=30 p50_ms=\(times[15]) p95_ms=\(times[28])")
    }
  }

}
