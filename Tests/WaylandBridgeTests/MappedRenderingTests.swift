import CEGLGLES
import Foundation
import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test func mappedBuffersReuseStorageWithoutChangingEarlierScreenshots() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = NativeRenderer()
    let input = NativeWindowInput(width: 17, height: 13)
    try renderer.setup(input: input)
    defer { renderer.cleanup() }

    var snapshots: [(URL, Data)] = []
    for (index, count) in [1, 1025, 3, 2049, 0].enumerated() {
      try renderer.beginFrame(width: input.width, height: input.height)
      let color = index % 2 == 0 ? Color(1, 0, 0) : Color(0, 1, 0)
      let draws = [DrawRect](repeating: DrawRect(Rect(0, 0, 17, 13), color), count: count)
      renderer.withFrame { frame in
        frame.render(draws.span)
        frame.render(draws.span)
      }
      try renderer.endFrame(surfaceless: true)
      var binding: GLint = -1
      unsafe glGetIntegerv(GLenum(GL_ARRAY_BUFFER_BINDING), &binding)
      var mapped: GLint = -1
      unsafe glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_MAPPED), &mapped)
      #expect(binding > 0 && mapped == GL_FALSE)

      let path = directory.appendingPathComponent("\(index).ppm")
      try renderer.screenshot(to: path.path)
      unsafe glGetIntegerv(GLenum(GL_PIXEL_PACK_BUFFER_BINDING), &binding)
      #expect(binding == 0)
      let data = try Data(contentsOf: path)
      let header = Data("P6\n17 13\n255\n".utf8)
      #expect(data.starts(with: header))
      #expect(data.count == header.count + 17 * 13 * 3)
      if count > 0 {
        let expected: [UInt8] = index % 2 == 0 ? [255, 0, 0] : [0, 255, 0]
        #expect(Array(data[header.count..<header.count + 3]) == expected)
      }
      snapshots.append((path, data))
    }
    renderer.cleanup()
    for (path, data) in snapshots { #expect(try Data(contentsOf: path) == data) }
  }

  @Test func uploadErrorPropagatesAtFrameEndAndNextFrameRecovers() throws {
    let renderer = NativeRenderer()
    try renderer.setup(
      input: .init(width: 8, height: 8))
    defer { renderer.cleanup() }
    try renderer.beginFrame(width: 8, height: 8)
    glEnable(GLenum(GL_ARRAY_BUFFER))
    let draws = [DrawRect(Rect(0, 0, 8, 8), Color(1, 0, 0))]
    renderer.withFrame { $0.render(draws.span) }
    #expect(throws: NativeWindowError.rendering) { try renderer.endFrame(surfaceless: true) }
    var mapped: GLint = -1
    unsafe glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_MAPPED), &mapped)
    #expect(mapped == GL_FALSE)
    try renderer.beginFrame(width: 8, height: 8)
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    #expect(glGetError() == GL_NO_ERROR)
  }

  @Test func failedScreenshotWriteLeavesReadbackUnmappedAndReusable() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = NativeRenderer()
    try renderer.setup(
      input: .init(width: 8, height: 8))
    defer { renderer.cleanup() }
    try renderer.beginFrame(width: 8, height: 8)
    renderer.withFrame { frame in
      let draws = [DrawRect(Rect(0, 0, 8, 8), Color(0, 0, 1))]
      frame.render(draws.span)
    }
    try renderer.endFrame(surfaceless: true)
    #expect(throws: (any Error).self) { try renderer.screenshot(to: directory.path) }
    var binding: GLint = -1
    unsafe glGetIntegerv(GLenum(GL_PIXEL_PACK_BUFFER_BINDING), &binding)
    #expect(binding == 0)
    let path = directory.appendingPathComponent("recovered.ppm")
    try renderer.screenshot(to: path.path)
    let data = try Data(contentsOf: path)
    #expect(data.suffix(3) == Data([0, 0, 255]))
    #expect(glGetError() == GL_NO_ERROR)
  }
}

extension NativeSessionTests {
  @Test func colorEmojiMatchesCPUWithSequencesClippingAndOpacity() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var draws = [DrawRect(Rect(0, 0, 240, 60), Color(14 / 255, 20 / 255, 30 / 255))]
    for (index, character) in "🙂👍🏽👩‍💻🇳🇿❤️1️⃣".enumerated() {
      draws.append(
        DrawRect(
          Rect(Float(index) * 36, 4, 30, 42), Color(1, 0, 0, index.isMultiple(of: 2) ? 1 : 0.5),
          clip: Rect(0, 12, 240, 40), glyphUV: EmojiAtlas.shared.glyphUV(character),
          colorGlyph: true))
    }
    let cpu = CPURenderer(width: 240, height: 60)
    cpu.render(draws.span)
    try NativeWindow.run(
      configuration: .init(width: 240, height: 60, maxFrames: 1, screenshotPath: path.path),
      surfaceless: true
    ) { _, renderer in renderer.render(draws.span) }
    let data = try Data(contentsOf: path)
    let header = Data("P6\n240 60\n255\n".utf8)
    #expect(data.starts(with: header))
    let pixels = Array(data.dropFirst(header.count))
    #expect(pixels.count == cpu.pixels.count)
    let largestError = zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
    #expect(largestError <= 2)
  }
}

extension NativeSessionTests {
  @Test func transparentClearIsPremultipliedAndOpaqueDefaultIsUnchanged() throws {
    let renderer = NativeRenderer()
    let input = NativeWindowInput(width: 8, height: 8)
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    try renderer.beginFrame(width: 8, height: 8, transparent: true)
    let draws = [DrawRect(Rect(0, 0, 4, 8), Color(1, 0, 0, 0.5))]
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
    unsafe glReadPixels(0, 0, 8, 8, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
    #expect(abs(Int(pixels[0]) - 128) <= 1 && abs(Int(pixels[3]) - 128) <= 1)
    #expect(Array(pixels[24..<28]) == [0, 0, 0, 0])
    try renderer.beginFrame(width: 8, height: 8)
    try renderer.endFrame(surfaceless: true)
    unsafe glReadPixels(0, 0, 8, 8, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
    #expect(pixels[3] == 255 && pixels[0] > 0)
  }
}
