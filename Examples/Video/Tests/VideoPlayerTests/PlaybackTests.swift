import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import VideoPlayer

@Test func playbackClockPreservesTimestampsAcrossPause() {
  let now = ContinuousClock.now
  var clock = PlaybackClock()
  clock.reset(at: now)
  #expect(clock.deadline(for: 0.125) == now + .milliseconds(125))
  clock.pause(at: now + .seconds(1))
  clock.resume(at: now + .seconds(4))
  #expect(clock.deadline(for: 1.5) == now + .milliseconds(4500))
}

@Test func decoderReadsLocalFramesDrainsAndReopens() async throws {
  // A tiny, generated Y4M file avoids a binary fixture or ffmpeg CLI test dependency.
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString + ".y4m")
  var file = Data("YUV4MPEG2 W4 H2 F25:1 Ip A1:1 C420jpeg\n".utf8)
  for luma: UInt8 in [16, 81, 235] {
    file.append(Data("FRAME\n".utf8))
    file.append(contentsOf: [UInt8](repeating: luma, count: 8))
    file.append(contentsOf: [128, 128, 128, 128])
  }
  try file.write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  let decoder = Decoder()
  for _ in 0..<2 {
    try await decoder.open(path.path)
    var timestamps: [Double] = []
    while let frame = try await decoder.next() {
      #expect(frame.image.width == 4 && frame.image.height == 2)
      #expect(frame.image.planes.count == 3)
      timestamps.append(frame.seconds)
    }
    #expect(timestamps.count == 3)
    for (actual, expected) in zip(timestamps, [0, 0.04, 0.08]) {
      #expect(abs(actual - expected) < 0.00001)
    }
    await decoder.close()
  }
}

@Test func decoderReportsMissingAndCorruptFiles() async throws {
  let decoder = Decoder()
  do {
    try await decoder.open("/does/not/exist/roots-video.mp4")
    Issue.record("Missing file opened")
  } catch { #expect(error is DecodeError) }
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try Data("not a movie".utf8).write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  do {
    try await decoder.open(path.path)
    Issue.record("Corrupt file opened")
  } catch { #expect(error is DecodeError) }
  await decoder.close()
}

@Test @MainActor func decodedFrameRendersThroughRoots() async throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString + ".y4m")
  var file = Data("YUV4MPEG2 W4 H2 F25:1 Ip A1:1 C420jpeg\nFRAME\n".utf8)
  file.append(contentsOf: [UInt8](repeating: 235, count: 8))
  file.append(contentsOf: [128, 128, 128, 128])
  try file.write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  let decoder = Decoder()
  try await decoder.open(path.path)
  let decoded = try #require(await decoder.next())
  await decoder.close()
  let source = ImageSource(decoded.image)
  let renderer = CPURenderer(width: 4, height: 2)
  var host = UIHost()
  host.frame(
    build: { Column(in: Region(0, 0, 4, 2)) { Video(source, key: 1) } },
    present: { renderer.render($0) })
  #expect(renderer.pixels.allSatisfy { $0 >= 254 })
}

@Test func decoderConvertsRGBWithoutAnRGBAHandoff() async throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString + ".ppm")
  var file = Data("P6\n4 2\n255\n".utf8)
  file.append(contentsOf: [UInt8](repeating: 255, count: 4 * 2 * 3))
  try file.write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  let decoder = Decoder()
  try await decoder.open(path.path)
  let frame = try #require(await decoder.next())
  #expect(frame.image.format == .yuv420p)
  #expect(frame.image.planes[0].bytes.count == 8)
  #expect(try await decoder.next() == nil)
  await decoder.close()
}

@Test @MainActor func playerPauseRestartAndCloseDoNotPublishStaleFrames() async throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString + ".y4m")
  var file = Data("YUV4MPEG2 W4 H2 F5:1 Ip A1:1 C420jpeg\n".utf8)
  for luma: UInt8 in [16, 81, 145, 235] {
    file.append(Data("FRAME\n".utf8))
    file.append(contentsOf: [UInt8](repeating: luma, count: 8))
    file.append(contentsOf: [128, 128, 128, 128])
  }
  try file.write(to: path)
  defer { try? FileManager.default.removeItem(at: path) }
  let player = Player(path: path.path)
  player.start()
  defer { player.stop() }
  let deadline = ContinuousClock.now + .seconds(3)
  while player.source.frame == nil && ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  let first = try #require(player.source.frame)
  player.togglePause()
  try await Task.sleep(for: .milliseconds(250))
  #expect(player.source.frame === first)
  player.restart()
  #expect(player.source.frame == nil)
  let restartDeadline = ContinuousClock.now + .seconds(3)
  while player.source.frame == nil && ContinuousClock.now < restartDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(player.source.frame != nil)
  player.stop()
  let stopped = player.source.frame
  try await Task.sleep(for: .milliseconds(250))
  #expect(player.source.frame === stopped)
}
