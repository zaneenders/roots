import Foundation
import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct BlockPerformanceTests {
  @Test func pairedLowering() {
    guard ProcessInfo.processInfo.environment["ROOTS_BLOCK_PERF"] == "1" else { return }
    let keys = Array(UInt64(1)...512)
    let clock = ContinuousClock()
    var imperative = UIStore(drawCapacity: nil)
    var composed = UIHost(drawCapacity: nil)
    var checksum = 0
    func legacyFrame() {
      imperative.frame(
        dt: 0,
        build: { frame in
          frame.beginColumn(in: Rect(0, 0, 100, 20000), gap: 0)
          for key in keys { frame.label(key: key, "", extent: 20, selectable: false) }
          frame.end()
        }, present: { checksum += $0.count })
    }
    func blockFrame() {
      composed.frame(
        dt: 0,
        build: {
          ColumnBlock(in: Rect(0, 0, 100, 20000), gap: 0) {
            ForEachBlock(keys) { LabelBlock(key: $0, "", extent: 20, selectable: false) }
          }
        }, present: { checksum += $0.count })
    }
    for _ in 0..<100 {
      legacyFrame()
      blockFrame()
    }
    var legacySamples: [Duration] = []
    var blockSamples: [Duration] = []
    for sample in 0..<6 {
      var legacyTime: Duration = .zero
      var blockTime: Duration = .zero
      func legacy() { legacyTime = clock.measure { for _ in 0..<1000 { legacyFrame() } } }
      func blocks() { blockTime = clock.measure { for _ in 0..<1000 { blockFrame() } } }
      if sample.isMultiple(of: 2) {
        legacy()
        blocks()
      } else {
        blocks()
        legacy()
      }
      legacySamples.append(legacyTime)
      blockSamples.append(blockTime)
      print(
        "BLOCK_PERF sample=\(sample) frames=1000 nodes=512 imperative=\(legacyTime) blocks=\(blockTime)"
      )
    }
    legacySamples.sort()
    blockSamples.sort()
    let legacyMedian = (legacySamples[2] + legacySamples[3]) / 2
    let blockMedian = (blockSamples[2] + blockSamples[3]) / 2
    #expect(blockMedian <= legacyMedian * 1.2, "Block lowering regressed more than 20%")
    #expect(checksum == 512 * (200 + 12000))
    #expect(composed.liveCount == imperative.liveCount)
    #expect(composed.state(for: 512)?.rect == Rect(0, 10220, 100, 20))
  }
}
