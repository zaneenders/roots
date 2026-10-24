import Foundation
import Observation
import Testing

@_spi(Hosting) @testable import Roots
@testable import RootsDesktop

#if os(macOS)
import Darwin
#else
import Glibc
#endif

/// Opt in with ROOTS_LAYOUT_PERF=1; use a release runner without concurrent builds.
@MainActor
struct LayoutPerformanceTests {
  @Test func steadyState() throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["ROOTS_LAYOUT_PERF"] == "1" else { return }
    let frames = Int(environment["ROOTS_LAYOUT_FRAMES"] ?? "20000") ?? 0
    let samples = Int(environment["ROOTS_LAYOUT_SAMPLES"] ?? "3") ?? 0
    let scenario = environment["ROOTS_LAYOUT_SCENARIO"] ?? "fixed"
    let mode = environment["ROOTS_LAYOUT_MODE"] ?? "host"
    try #require(frames > 0 && samples > 0)
    try #require(["fixed", "scroll", "nested"].contains(scenario))
    try #require(["host", "runtime", "phases"].contains(mode))
    let model = LayoutModel()
    let viewport = Viewport(size: .init(width: 800, height: 12000))
    var host = UIHost(drawCapacity: nil)
    let runtime = DesktopRuntime(
      content: { LayoutContent(model: model, scenario: scenario, bounds: $0.bounds) },
      primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {})
    defer { runtime.stop() }
    var storage = UIStorage(nodeCapacity: 1024, drawCapacity: nil)
    var draws = 0
    let clock = ContinuousClock()
    var phases = [Duration](repeating: .zero, count: 4)
    func frame() {
      switch mode {
      case "host":
        host.frame(
          dt: 0, build: { LayoutContent(model: model, scenario: scenario, bounds: viewport.bounds) },
          present: { draws += $0.count })
      case "runtime":
        runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { draws += $0.count })
      default:
        phases[0] += clock.measure {
          storage.epoch += 1
          storage.order.removeAll()
          storage.cursors.removeAll()
          storage.layouts.removeAll(keepingCapacity: true)
          storage.backgrounds.removeAll(keepingCapacity: true)
          storage.focusAfterLayout = nil
          storage.selectionGroupKeys.removeAll(keepingCapacity: true)
          storage.draws.removeAll()
          storage.droppedDraws = 0
          var frame = UIFrame(storage: &storage)
          LayoutContent(model: model, scenario: scenario, bounds: viewport.bounds)._build(into: &frame)
        }
        phases[1] += clock.measure { storage.resolveLayouts() }
        phases[2] += clock.measure {
          storage.finish(input: Input(), dt: 0, primaryShortcut: .control, onKey: nil, onCopy: nil)
        }
        phases[3] += clock.measure { storage.paint() }
        draws += storage.draws.count
        storage.draws.removeAll()
      }
    }
    for _ in 0..<100 { frame() }
    for sample in 0..<samples {
      draws = 0
      phases = [Duration](repeating: .zero, count: 4)
      let cpuStart = cpuSeconds()
      let elapsed = clock.measure { for _ in 0..<frames { frame() } }
      let cpu = cpuSeconds() - cpuStart
      #expect(draws == frames * 1024)
      print(
        "LAYOUT_PERF scenario=\(scenario) mode=\(mode) sample=\(sample) frames=\(frames) "
          + "wall_us=\(microseconds(elapsed) / Double(frames)) cpu_us=\(cpu * 1e6 / Double(frames)) seconds=\(microseconds(elapsed) / 1e6) "
          + "draws=\(draws / frames) "
          + "build_us=\(microseconds(phases[0]) / Double(frames)) "
          + "layout_us=\(microseconds(phases[1]) / Double(frames)) "
          + "input_us=\(microseconds(phases[2]) / Double(frames)) "
          + "paint_us=\(microseconds(phases[3]) / Double(frames))")
    }
  }
}

private func microseconds(_ duration: Duration) -> Double {
  let value = duration.components
  return Double(value.seconds) * 1e6 + Double(value.attoseconds) / 1e12
}

@MainActor @Observable
private final class LayoutModel {
  var color = Color.accent
}

private struct LayoutContent: Block {
  let model: LayoutModel
  let scenario: String
  let bounds: Region

  var body: some Block {
    if scenario == "scroll" {
      Scroll(key: 10000, in: bounds) { column }
    } else {
      Stack(in: bounds, alignment: .topLeading) { column }
    }
  }

  @BlockBuilder var column: some Block {
    if scenario == "nested" {
      Column(gap: 0) {
        ForEach(0..<64) { row in
          Row(gap: 0) {
            ForEach(0..<8) { cell in
              Canvas(key: UInt64(row * 8 + cell + 1), extent: 20) { context in
                context.fillRect(context.region, color: model.color)
              }
            }
          }
        }
      }
    } else {
      Column(gap: 0) {
        ForEach(1..<513) { key in
          Canvas(key: UInt64(key), extent: 20) { context in
            context.fillRect(context.region, color: model.color)
          }
        }
      }
    }
  }
}

private func cpuSeconds() -> Double {
  var usage = rusage()
  #if os(macOS)
  _ = unsafe getrusage(RUSAGE_SELF, &usage)
  #else
  _ = unsafe getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
  #endif
  return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
    + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}
