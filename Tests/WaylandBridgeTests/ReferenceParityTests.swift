import CEGLGLES
import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test(arguments: [Int32(1), 2])
  func fractionalAndNestedClipsMatchCPU(scale: Int32) throws {
    var ui = UIHost()
    var draws: [DrawRect] = []
    ui.frame(
      build: {
        RowBlock(in: Region(0, 0, 8, 8)) {
          Canvas(key: 1, extent: 8) { context in
            context.withClip(Region(1.75, 0, 1.5, 8)) { clipped in
              clipped.fillRect(Region(-4, -4, 16, 16), color: Color(1, 0, 0))
              clipped.withClip(Region(2.25, 1.75, 4, 2.5)) { nested in
                nested.fillRect(Region(-4, -4, 16, 16), color: Color(0, 1, 0))
              }
            }
          }
        }
      }, present: { batch in for draw in batch.draws { draws.append(draw) } })
    try expectReferenceParity(draws, width: 8, height: 8, scale: scale)
  }

  @Test(arguments: [Int32(7), 8, 9], [false, true])
  func clearAndRoundedCoverageMatchCPUAtOddAndEvenHeights(height: Int32, textureTarget: Bool) throws {
    try expectReferenceParity([], width: 8, height: height, textureTarget: textureTarget)
    try expectReferenceParity(
      [DrawRect(Region(1, 1, 6, 5), Color(1, 0, 0), radius: 2)], width: 8, height: height,
      textureTarget: textureTarget)
  }

  private func expectReferenceParity(
    _ draws: [DrawRect], width: Int32, height: Int32, scale: Int32 = 1, textureTarget: Bool = true
  ) throws {
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: width, height: height)
    input.bufferScale = scale
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    var texture: GLuint = 0
    var framebuffer: GLuint = 0
    if textureTarget {
      unsafe glGenTextures(1, &texture)
      glBindTexture(GLenum(GL_TEXTURE_2D), texture)
      glTexImage2D(
        GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, width * scale, height * scale, 0,
        GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
      unsafe glGenFramebuffers(1, &framebuffer)
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
      glFramebufferTexture2D(
        GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
      #expect(glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE))
    }
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
      unsafe glDeleteFramebuffers(1, &framebuffer)
      unsafe glDeleteTextures(1, &texture)
    }
    try renderer.beginFrame(width: width, height: height, bufferScale: scale)
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try renderer.screenshot(to: path.path)
    let w = Int(width * scale)
    let h = Int(height * scale)
    let bytes = try Data(contentsOf: path)
    let pixels = Array(bytes.dropFirst(Data("P6\n\(w) \(h)\n255\n".utf8).count))
    let s = Float(scale)
    let physical = draws.map { draw in
      var draw = draw
      draw.region = Region(draw.region.x * s, draw.region.y * s, draw.region.width * s, draw.region.height * s)
      draw.radius *= s
      draw.clip = draw.clip.map { Region($0.x * s, $0.y * s, $0.width * s, $0.height * s) }
      return draw
    }
    let cpu = CPURenderer(
      width: w, height: h, fragmentOrigin: textureTarget ? .bottomLeft : .topLeft)
    cpu.render(physical.span)
    #expect(pixels.count == cpu.pixels.count)
    let maximumError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(maximumError <= 1)
  }
}
