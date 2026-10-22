import Foundation
import Testing

@testable import WaylandBridge

@Test func embeddedShadersMatchEditableFiles() throws {
  let shaders = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/WaylandBridge/Shaders")
  let vertex = try String(
    contentsOf: shaders.appendingPathComponent("Rectangle.vert"), encoding: .utf8)
  let fragment = try String(
    contentsOf: shaders.appendingPathComponent("Rectangle.frag"), encoding: .utf8)
  #expect(NativeShaders.vertexSource == vertex)
  #expect(NativeShaders.fragmentSource == fragment)
  #expect(
    PolylineShaders.vertexSource
      == (try String(contentsOf: shaders.appendingPathComponent("Polyline.vert"), encoding: .utf8)))
  #expect(
    PolylineShaders.fragmentSource
      == (try String(contentsOf: shaders.appendingPathComponent("Polyline.frag"), encoding: .utf8)))
}
