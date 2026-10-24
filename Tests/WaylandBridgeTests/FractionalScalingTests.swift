import CEGLGLES
import Foundation
import Roots
import Testing

@testable import WaylandBridge

@Test(arguments: [UInt32(150), 180, 210])
func fractionalBufferDimensionsRoundHalfwayAwayFromZero(scale: UInt32) throws {
  let size = try BufferSize(width: 101, height: 77, fractionalScale120: scale)
  #expect(size.width == Int32((101 * scale + 60) / 120))
  #expect(size.height == Int32((77 * scale + 60) / 120))
  let half = try BufferSize(width: 3, height: 1, fractionalScale120: 180)
  #expect(half.width == 5 && half.height == 2)
}

@Test func fractionalBufferDimensionsKeepTheProtocolRatioExact() throws {
  // Double(123) / 120 * 100 falls just below 102.5.
  let size = try BufferSize(width: 100, height: 20, fractionalScale120: 123)
  #expect(size.width == 103 && size.height == 21)
  for numerator: UInt32 in 120...360 {
    for size: Int32 in [1, 20, 60, 100, 990, 1950, 4096] {
      let pixels = try BufferSize(width: size, height: size, fractionalScale120: numerator)
      #expect(pixels.width == (Int64(size) * Int64(numerator) + 60) / 120)
    }
  }
}

@Test func invalidFractionalDimensionsFailBeforeAllocation() {
  for (width, height, scale): (Int32, Int32, UInt32) in [
    (101, 77, 0), (0, 77, 150), (101, -1, 150),
    (.max, 1, 150), (1, .max, 180), (.max, .max, .max), (1, 1, 1),
  ] {
    #expect(throws: NativeWindowError.invalidConfiguration) {
      try BufferSize(width: width, height: height, fractionalScale120: scale)
    }
  }
}

@Test(arguments: [UInt32(123), 150, 180, 210])
func roundedFractionalScissorsUseActualPerAxisPixelRatio(scale: UInt32) throws {
  let size = try BufferSize(width: 17, height: 13, fractionalScale120: scale)
  let ratio = SIMD2(Double(size.width) / 17, Double(size.height) / 13)
  for region in [Region(2.25, 1.75, 7.5, 6.5), Region(0, 0, 17, 13)] {
    let scissor = ScissorRect(region, width: size.width, height: size.height, scale: ratio)
    for y: Int32 in 0..<size.height {
      for x: Int32 in 0..<size.width {
        let included =
          x >= scissor.x && x < scissor.x + scissor.width
          && y >= scissor.y && y < scissor.y + scissor.height
        #expect(
          included
            == region.contains(
              x: Float((Double(x) + 0.5) / ratio.x), y: Float((Double(y) + 0.5) / ratio.y)))
      }
    }
  }
}

extension NativeSessionTests {
  @Test(arguments: [UInt32(123), 150, 180, 210])
  func fractionalRenderingKeepsLogicalGeometryAndRoundedScreenshotSize(scale: UInt32) throws {
    var input = NativeWindowInput(width: 17, height: 13)
    input.fractionalScale120 = scale
    let size = try BufferSize(
      width: input.width, height: input.height, fractionalScale120: input.fractionalScale120)
    let renderer = NativeRenderer()
    defer { renderer.cleanup() }
    try renderer.setup(input: input)
    try renderer.beginFrame(width: input.width, height: input.height, fractionalScale120: scale)
    var viewport = [GLint](repeating: 0, count: 4)
    unsafe glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
    #expect(viewport == [0, 0, size.width, size.height])
    let region = Region(2.25, 1.75, 7.5, 6.5)
    let draws = [
      DrawRect(Region(-2, -2, 21, 17), Color(1, 0, 0)),
      DrawRect(Region(-2, -2, 21, 17), Color(0, 1, 0), clip: region),
    ]
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let data = try Data(contentsOf: path)
    let header = Data("P6\n\(size.width) \(size.height)\n255\n".utf8)
    #expect(data.starts(with: header))
    #expect(data.count == header.count + Int(size.width * size.height) * 3)
    let pixels = Array(data.dropFirst(header.count))
    for y: Int32 in 0..<size.height {
      for x: Int32 in 0..<size.width {
        let green = region.contains(
          x: Float((Double(x) + 0.5) * Double(input.width) / Double(size.width)),
          y: Float((Double(y) + 0.5) * Double(input.height) / Double(size.height)))
        let offset = Int(y * size.width + x) * 3
        #expect(Array(pixels[offset..<offset + 3]) == (green ? [0, 255, 0] : [255, 0, 0]))
      }
    }
  }
}
