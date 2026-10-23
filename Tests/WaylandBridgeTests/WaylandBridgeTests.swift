import Foundation
@_spi(Hosting) import Roots
import Testing

@testable import SwiftWayland
@testable import WaylandBridge

@Test @MainActor func rectangleBatchCopiesOneInstanceAndReusesBoundedStorage() {
  var batch = RectangleBatch()
  let draw = DrawRect(Region(10, 20, 30, 40), Color(0.1, 0.2, 0.3, 0.4), radius: 5)
  batch.append(draw)
  let expected: [Float] = [10, 20, 30, 40, 0.1, 0.2, 0.3, 0.4, 5, 0, 0, 0, 0, 0, 0, 1, 0]
  #expect(batch.vertices.count == 17)
  for i in expected.indices { #expect(batch.vertices[i] == expected[i]) }
  let address = batch.vertices.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
  for _ in 1..<RectangleBatch.capacity { batch.append(draw) }
  #expect(batch.vertices.count == RectangleBatch.capacity * 17)
  batch.reset()
  #expect(batch.vertices.count == 0)
  batch.append(DrawRect(Region(1, 2, 3, 4), .text))
  let reused = batch.vertices.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
  #expect(address == reused && batch.count == 1)
  #expect(batch.vertices[0] == 1 && batch.vertices[3] == 4)
}

@Test @MainActor func invalidRectanglesAreNotStaged() {
  #expect(RectangleBatch.accepts(DrawRect(Region(0, 0, 1, 1), .text)))
  for region in [
    Region(0, 0, 0, 1), Region(0, 0, 1, -1), Region(.nan, 0, 1, 1), Region(0, 0, .infinity, 1),
    Region(.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude, 1),
    Region(0, .greatestFiniteMagnitude, 1, .greatestFiniteMagnitude)
  ] {
    #expect(!RectangleBatch.accepts(DrawRect(region, .text)))
  }
  #expect(!RectangleBatch.accepts(DrawRect(Region(0, 0, 1, 1), Color(0, 0, 0, .nan))))
  #expect(!RectangleBatch.accepts(DrawRect(Region(0, 0, 1, 1), .text, radius: .infinity)))
}

@Test @MainActor func clippingIncludesPixelCentersClampsAndRejectsInvalidBounds() {
  let clip = ScissorRect(Region(-2.5, 3.5, 12.75, 200), width: 100, height: 80)
  #expect(clip.x == 0 && clip.y == 3 && clip.width == 10 && clip.height == 77)
  let outside = ScissorRect(Region(200, 200, 10, 10), width: 100, height: 80)
  #expect(outside.width == 0 && outside.height == 0)
  for region in [Region(0, 0, -1, 1), Region(.nan, 0, 1, 1), Region(0, 0, .infinity, 1)] {
    let empty = ScissorRect(region, width: 100, height: 80)
    #expect(empty.width == 0 && empty.height == 0)
  }
  let fractional = ScissorRect(Region(0.1, 0.1, 0.9, 0.9), width: 100, height: 80)
  #expect(fractional.width == 1 && fractional.height == 1)
  let large = ScissorRect(Region(0, 0, .greatestFiniteMagnitude, 1), width: .max, height: 80)
  #expect(large.width == Int32.max)
}

@Test @MainActor func invalidConfigurationsFailBeforeOpeningNativeResources() {
  for configuration in [
    NativeWindowConfiguration(width: 0), NativeWindowConfiguration(height: -1),
    NativeWindowConfiguration(maxFrames: -1), NativeWindowConfiguration(maxFrames: 0)
  ] {
    #expect(throws: NativeWindowError.invalidConfiguration) {
      try NativeWindow.run(configuration: configuration, surfaceless: true) { _, _ in
        Issue.record("Invalid configurations must not invoke a frame")
      }
    }
  }
}

extension NativeSessionTests {
  @Test @MainActor func surfacelessRenderingCoversBatchingClipsScreenshotsAndCleanup() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("capture.ppm").path
    let configuration = NativeWindowConfiguration(
      width: 16, height: 16, maxFrames: 2, screenshotPath: path)
    var frames = 0
    try NativeWindow.run(configuration: configuration, surfaceless: true) { input, renderer in
      #expect(input.timeSeconds == Double(frames) / 60)
      frames += 1
      #expect(throws: NativeWindowError.alreadyRunning) {
        try NativeWindow.run(configuration: configuration, surfaceless: true) { _, _ in }
      }
      var draws = [DrawRect](repeating: DrawRect(Region(0, 0, 16, 16), Color(1, 0, 0)), count: 1025)
      draws.append(DrawRect(Region(0, 0, 16, 16), Color(0, 1, 0), clip: Region(0, 0, 8, 8)))
      draws.append(DrawRect(Region(12, 12, 4, 4), Color(0, 0, 1)))
      draws.append(DrawRect(Region(0, 0, 16, 16), .text, clip: Region(.nan, 0, 1, 1)))
      renderer.render(draws.span)
    }
    #expect(frames == 2)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    let header = Data("P6\n16 16\n255\n".utf8)
    #expect(bytes.starts(with: header))
    #expect(bytes.count == header.count + 16 * 16 * 3)
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
      let offset = header.count + (y * 16 + x) * 3
      return Array(bytes[offset..<offset + 3])
    }
    #expect(pixel(2, 2) == [0, 255, 0])
    #expect(pixel(10, 2) == [255, 0, 0])
    #expect(pixel(2, 10) == [255, 0, 0])
    #expect(pixel(14, 14) == [0, 0, 255])
    #expect(throws: (any Error).self) {
      try NativeWindow.run(
        configuration: .init(width: 16, height: 16, maxFrames: 1, screenshotPath: directory.path),
        surfaceless: true
      ) { _, _ in }
    }
    var closedFrames = 0
    try NativeWindow.run(
      configuration: .init(width: 16, height: 16, maxFrames: 3), surfaceless: true
    ) { _, _ in
      closedFrames += 1
      NativeWindow.requestClose()
    }
    #expect(closedFrames == 1)
    var reopenedFrames = 0
    try NativeWindow.run(
      configuration: .init(width: 16, height: 16, maxFrames: 2), surfaceless: true
    ) { _, _ in
      reopenedFrames += 1
    }
    #expect(reopenedFrames == 2)
  }
}

@Test(arguments: [false, true]) @MainActor func nativeZeroDistanceReleaseActuallyCoastsTheList(
  coalesced: Bool
) throws {
  var input = WaylandInput(width: 100, height: 80)
  var ui = UIHost()
  @MainActor func build() -> some Block {
    ScrollColumn(key: 100, in: Region(0, 0, 100, 80)) {
      Text("")
        .size(20)
        .selectable(key: 1)
        .alignment(.leading)
        .padding(horizontal: 12)
        .frame(width: .fill, height: .fixed(1000))
        .background(.panel)
    }
  }
  for time: UInt32 in [100, 110] {
    input.axis(0, value: 5 * 256, time: time)
    input.axisSource(1)
    input.pointerFrame()
  }
  if !coalesced {
    ui.frame(input: Input(x: 10, y: 10, scrollY: input.scrollY), build: build, present: { _ in })
    input.resetEdges()
  }
  input.axis(0, value: 0, time: 120)
  input.axisSource(1)
  input.axisStop(0, time: 120)
  input.pointerFrame()
  ui.frame(
    input: Input(x: 10, y: 10, scrollY: input.scrollY, scrollVelocityY: input.scrollVelocityY),
    build: build, present: { _ in })
  let list: UInt64 = 100
  #expect(ui.state(for: list)?.scrollOffset == 10)
  input.resetEdges()
  ui.frame(build: build, present: { _ in })
  #expect((ui.state(for: list)?.scrollOffset ?? 0) > 10)
}

@Test @MainActor func glyphBatchCarriesUVsAndRejectsInvalidCoordinates() {
  var batch = RectangleBatch()
  let uv = Region(0.1, 0.2, 0.3, 0.4)
  batch.append(DrawRect(Region(1, 2, 3, 4), .text, glyphUV: uv))
  #expect(batch.vertices[9] == uv.x)
  #expect(batch.vertices[10] == uv.y)
  #expect(batch.vertices[11] == uv.width)
  #expect(batch.vertices[12] == uv.height)
  #expect(batch.vertices[13] == 1)
  for invalid in [Region(.nan, 0, 1, 1), Region(0, 0, -1, 1), Region(0, 0, 2, 1)] {
    #expect(!RectangleBatch.accepts(DrawRect(Region(0, 0, 1, 1), .text, glyphUV: invalid)))
  }
}

extension NativeSessionTests {
  @Test @MainActor func atlasTextRendersFractionalCoverageAndClipsInEGL() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try NativeWindow.run(
      configuration: .init(width: 64, height: 40, maxFrames: 1, screenshotPath: path.path),
      surfaceless: true
    ) { _, renderer in
      let uv = FontAtlas.shared.glyphUV("A")
      renderer.render(
        [
          DrawRect(Region(-10, -10, 84, 60), Color(0, 0, 0)),
          DrawRect(Region(4.25, 3.5, 17.5, 24.5), Color(1, 1, 1), glyphUV: uv),
          DrawRect(
            Region(34.25, 3.5, 17.5, 24.5), Color(1, 1, 1), clip: Region(43, 0, 21, 40), glyphUV: uv),
          DrawRect(Region(60, 36, 4, 4), Color(1, 0, 0))
        ].span)
    }
    let data = try Data(contentsOf: path)
    let header = Data("P6\n64 40\n255\n".utf8)
    #expect(data.starts(with: header))
    let pixels = Array(data.dropFirst(header.count))
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
      Array(pixels[((y * 64 + x) * 3)..<((y * 64 + x) * 3 + 3)])
    }
    #expect(
      stride(from: 0, to: pixels.count, by: 3).contains { pixels[$0] > 0 && pixels[$0] < 255 })
    var lit = false
    for y in 0..<32 {
      for x in 30..<60 {
        if x < 43 {
          #expect(pixel(x, y) == [0, 0, 0])
        } else {
          #expect(pixel(x, y) == pixel(x - 30, y))
          if pixel(x, y)[0] > 0 { lit = true }
        }
      }
    }
    #expect(lit)
    #expect(pixel(62, 38) == [255, 0, 0])
  }
}

@Test @MainActor func bufferDimensionsAreCheckedBeforeNativeAllocation() throws {
  let size = try BufferSize(width: 640, height: 480, scale: 2)
  #expect(size.width == 1280 && size.height == 960)
  let largest = try BufferSize(width: .max, height: 1, scale: 1)
  #expect(largest.width == .max)
  for (width, height, scale): (Int32, Int32, Int32) in [
    (0, 10, 1), (10, -1, 1), (10, 10, 0), (10, 10, -1), (.max, 1, 2), (1, .max, 2)
  ] {
    #expect(throws: NativeWindowError.invalidConfiguration) {
      _ = try BufferSize(width: width, height: height, scale: scale)
    }
  }
}

@Test @MainActor func hidpiClipsRoundInPhysicalPixelsAndInputStaysLogical() {
  let clip = ScissorRect(Region(1.25, 2.25, 4.5, 3.5), width: 200, height: 160, scale: 2)
  #expect(clip.x == 2 && clip.y == 4 && clip.width == 9 && clip.height == 7)
  let edge = ScissorRect(Region(95, 75, 20, 20), width: 200, height: 160, scale: 2)
  #expect(edge.x == 190 && edge.y == 150 && edge.width == 10 && edge.height == 10)
  for scale: Float in [0, -1, .nan, .infinity] {
    let empty = ScissorRect(Region(0, 0, 10, 10), width: 200, height: 160, scale: scale)
    #expect(empty.width == 0 && empty.height == 0)
  }
  var input = WaylandInput(width: 100, height: 80)
  input.bufferScale = 2
  input.pointerX = 12.5
  input.pointerY = 24.5
  input.axis(0, value: 3 * 256, time: 100)
  #expect(input.scrollY == 3)
  input.resetEdges()
  #expect(input.width == 100 && input.height == 80 && input.bufferScale == 2)
  #expect(input.pointerX == 12.5 && input.pointerY == 24.5)
}

extension NativeSessionTests {
  @Test(arguments: [Int32(1), 2, 3])
  func scaledRenderingUsesPhysicalViewportClipsAndScreenshots(scale: Int32) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("scaled.ppm").path
    var input = NativeWindowInput(width: 16, height: 16)
    input.bufferScale = scale
    let renderer = NativeRenderer()
    defer { renderer.cleanup() }
    try renderer.setup(input: input)
    try renderer.beginFrame(width: input.width, height: input.height, bufferScale: scale)
    let draws = [
      DrawRect(Region(0, 0, 16, 16), Color(1, 0, 0)),
      DrawRect(Region(0, 0, 16, 16), Color(0, 1, 0), clip: Region(2, 3, 5, 4)),
      DrawRect(Region(12, 12, 4, 4), Color(0, 0, 1))
    ]
    renderer.withFrame { $0.render(draws.span) }
    try renderer.endFrame(surfaceless: true)
    try renderer.screenshot(to: path)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    let width = 16 * Int(scale)
    let header = Data("P6\n\(width) \(width)\n255\n".utf8)
    #expect(bytes.starts(with: header))
    #expect(bytes.count == header.count + width * width * 3)
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
      let offset = header.count + (y * width + x) * 3
      return Array(bytes[offset..<offset + 3])
    }
    #expect(pixel(2 * Int(scale), 3 * Int(scale)) == [0, 255, 0])
    #expect(pixel(7 * Int(scale) - 1, 7 * Int(scale) - 1) == [0, 255, 0])
    #expect(pixel(7 * Int(scale), 4 * Int(scale)) == [255, 0, 0])
    #expect(pixel(3 * Int(scale), 7 * Int(scale)) == [255, 0, 0])
    #expect(pixel(14 * Int(scale), 14 * Int(scale)) == [0, 0, 255])
  }
}

@Test @MainActor func synchronousWaylandSessionsRequireAsyncEntryPoint() {
  #expect(throws: NativeWindowError.requiresAsyncSession) {
    try NativeWindow.run { _, _ in Issue.record("Native run must not block the main actor") }
  }
}

@Test(arguments: [Float(1), 2]) func fractionalScissorsMatchHalfOpenPixelCenters(scale: Float) {
  let parent = Region(1.75, 0.5, 1.5, 6)
  for region in [parent, parent.intersection(Region(2.25, 1.75, 4, 2.5)), Region(0.5, 0.5, 1, 1)] {
    let scissor = ScissorRect(region, width: 16, height: 16, scale: scale)
    for y: Int32 in 0..<16 {
      for x: Int32 in 0..<16 {
        let included =
          x >= scissor.x && x < scissor.x + scissor.width
          && y >= scissor.y && y < scissor.y + scissor.height
        #expect(included == region.contains(x: (Float(x) + 0.5) / scale, y: (Float(y) + 0.5) / scale))
      }
    }
  }
}
