import Testing

@testable import Roots

struct LayoutDistributionTests {
  @Test func distributionMatchesLevelingReference() {
    let modes: [LayoutSize] = [.fixed(10), .fit, .fill]
    let sizes: [Float] = [0, 10, 30]
    for first in modes.indices {
      for second in modes.indices {
        for third in modes.indices {
          let childModes = [modes[first], modes[second], modes[third]]
          for firstSize in sizes {
            for secondSize in sizes {
              for thirdSize in sizes {
                let measured = [firstSize, secondSize, thirdSize]
                for available: Float in [0, 5, 20, 40, 60, 100] {
                  var expected = measured
                  referenceDistribute(&expected, modes: childModes, available: available)
                  for horizontal in [false, true] {
                    var storage = UIStorage(nodeCapacity: 0, drawCapacity: 0)
                    storage.beginLayout(
                      LayoutStyle(kind: horizontal ? .row : .column, gap: 2),
                      in: horizontal ? Region(0, 0, available + 4, 100) : Region(0, 0, 100, available + 4))
                    for index in 0..<3 {
                      storage.beginLayout(
                        LayoutStyle(
                          width: horizontal ? childModes[index] : .fit,
                          height: horizontal ? .fit : childModes[index]), in: nil)
                      storage.layouts[index + 1].measured = SIMD2(repeating: measured[index])
                      _ = storage.cursors.removeLast()
                    }
                    _ = storage.cursors.removeLast()
                    storage.resolveLayouts()
                    for index in 0..<3 {
                      let region = storage.layouts[index + 1].region
                      let actual = horizontal ? region.width : region.height
                      #expect(abs(actual - expected[index]) < 0.002)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  @Test func frameResetDoesNotRetainOldChildLinks() {
    var storage = UIStorage(nodeCapacity: 0, drawCapacity: 0)
    for count in [10, 0, 1, 20, 2, 0] {
      storage.layouts.removeAll(keepingCapacity: true)
      storage.beginLayout(LayoutStyle(kind: .column), in: Region(0, 0, 100, 100))
      for _ in 0..<count {
        storage.beginLayout(LayoutStyle(width: .fixed(10), height: .fixed(5)), in: nil)
        storage.endLayout(storage.layouts.count - 1)
        _ = storage.cursors.removeLast()
      }
      storage.endLayout(0)
      _ = storage.cursors.removeLast()
      storage.resolveLayouts()
      #expect(storage.layouts.count == count + 1)
      #expect(storage.layouts[0].measured.y == Float(count * 5))
    }
  }
}

private func referenceDistribute(_ sizes: inout [Float], modes: [LayoutSize], available: Float) {
  var remaining = available - sizes.reduce(0, +)
  let growing = remaining > 0
  var candidates = sizes.indices.filter {
    if growing { return modes[$0] == .fill }
    if case .fixed = modes[$0] { return false }
    return sizes[$0] > 0
  }
  while !candidates.isEmpty && abs(remaining) > 0.001 {
    let extreme = candidates.map { sizes[$0] }.reduce(growing ? Float.infinity : 0, growing ? min : max)
    let active = candidates.filter { sizes[$0] == extreme }
    let next = candidates.map { sizes[$0] }.filter { growing ? $0 > extreme : $0 < extreme }
      .reduce(growing ? Float.infinity : 0, growing ? min : max)
    let amount =
      growing
      ? min(remaining / Float(active.count), next - extreme)
      : max(remaining / Float(active.count), next - extreme)
    for index in active { sizes[index] += amount }
    remaining -= amount * Float(active.count)
    if !growing { candidates.removeAll { sizes[$0] <= 0 } }
  }
}
