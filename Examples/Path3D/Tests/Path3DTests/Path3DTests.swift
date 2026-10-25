import Foundation
@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import Path3D
@testable import RootsDesktop

@MainActor struct Path3DTests {
  @Test func knotIsClosedAndHasRealElevation() {
    let geometry = Path3DGeometry()
    #expect(geometry.samples.count == 1_025)
    let delta = geometry.samples[0].position - geometry.samples.last!.position
    #expect((delta * delta).sum() < 0.000001)
    #expect(geometry.samples.map(\.position.y).max()! - geometry.samples.map(\.position.y).min()! > 0.9)
    for sample in geometry.samples {
      #expect(sample.position.x.isFinite && sample.position.y.isFinite && sample.position.z.isFinite)
    }
  }

  @Test func playbackAndZoomRetainGeometryButOrbitReprojects() {
    let model = Path3DModel()
    var host = UIHost()
    var identities: [ObjectIdentifier] = []
    for frame in 0..<10 {
      model.advance(1 / 60)
      if frame == 5 { model.zoom(5) }
      host.frame(
        build: { Path3DPage(model: model, bounds: Region(0, 0, 800, 600)) },
        present: { batch in
          var current: [ObjectIdentifier] = []
          for command in batch {
            guard case .rectangle(let draw) = command, let path = draw.polyline else { continue }
            #expect(draw.isValid)
            current.append(ObjectIdentifier(path))
          }
          #expect(current.count > 100)
          if frame == 0 { identities = current } else { #expect(current == identities) }
        })
      #expect(host.droppedDraws == 0)
    }
    #expect(model.projectionRevision == 1)
    model.orbiting = true
    model.advance(0.1)
    host.frame(build: { Path3DPage(model: model, bounds: Region(0, 0, 800, 600)) }, present: { _ in })
    #expect(model.projectionRevision == 2)
    model.playing = false
    model.orbiting = false
    let progress = model.progress
    model.advance(0.1)
    #expect(model.progress == progress)
    #expect(!model.needsAnimation)
  }

  @Test func cameraBoundsKeepGeometryInFrontOfNearPlaneAndPickingUsesSourceSamples() throws {
    let geometry = Path3DGeometry()
    var projection = Path3DProjection()
    for pitch: Float in [-0.15, 0.5, 1.25] {
      for yaw: Float in [0, 1, 2, 3, 4, 5] {
        let camera = Path3DCamera(yaw: yaw, pitch: pitch)
        projection.update(geometry: geometry, camera: camera)
        #expect(projection.runs.count == 128)
        #expect(zip(projection.runs, projection.runs.dropFirst()).allSatisfy { $0.depth >= $1.depth })
        for sample in geometry.samples {
          let p = camera.project(sample.position)
          #expect(p.depth > 1 && p.point.x.isFinite && p.point.y.isFinite)
        }
      }
    }
    let camera = Path3DCamera(yaw: 0.45, pitch: 0.5)
    projection.update(geometry: geometry, camera: camera)
    let transform = camera.transform(in: Region(0, 0, 800, 600), zoom: 1)
    let phase: Float = 0.08
    let screen = transform.apply(camera.project(geometry.position(at: phase)).point)
    let picked = projection.pick(screen, transform: transform, clip: Region(0, 0, 800, 600))
    let hit = try #require(picked)
    #expect(abs(hit.progress - phase) < 0.001)
    let clipped = projection.pick(screen, transform: transform, clip: Region(0, 0, 1, 1))
    #expect(clipped == nil)
  }

  @Test func orbitDragZoomResetAndResponsiveFrames() {
    let model = Path3DModel()
    let region = Region(0, 0, 600, 400)
    model.pointer(.init(phase: .pressed, position: .zero, region: region))
    model.pointer(.init(phase: .dragged, position: .init(x: 100, y: 10_000), region: region))
    model.pointer(.init(phase: .released, position: .zero, region: region))
    #expect(model.pitch == 1.25 && model.yaw != 0.45)
    for _ in 0..<20 { model.zoom(10_000) }
    #expect(model.zoomLevel == 1.8)
    model.zoom(.nan)
    #expect(model.zoomLevel == 1.8)
    model.reset()
    #expect(model.zoomLevel == 1 && model.pitch == 0.5 && model.yaw == 0.45)
    var host = UIHost()
    for width: Float in [1000, 640, 480, 1] {
      host.frame(
        build: { Path3DPage(model: model, bounds: Region(0, 0, width, 600)) },
        present: { batch in
          for command in batch {
            if case .rectangle(let draw) = command { #expect(draw.isValid) }
          }
        })
      #expect(host.droppedDraws == 0)
    }
  }

  @Test func pausedSceneStopsRequestingAnimationFrames() async throws {
    let model = Path3DModel()
    model.playing = false
    model.orbiting = false
    var redraws = 0
    let runtime = DesktopRuntime(
      content: { Path3DPage(model: model, bounds: $0.bounds) }, primaryShortcut: .control,
      onCopy: { _ in }, requestRedraw: { redraws += 1 },
      frameCallbacks: .init(prepare: { _, dt in model.advance(dt) }, needsAnimationFrame: { model.needsAnimation }))
    defer { runtime.stop() }
    let viewport = Viewport(size: .init(width: 800, height: 600))
    for index in 0..<60 {
      runtime.frame(input: Input(), viewport: viewport, time: Double(index) / 60, present: { _ in })
    }
    try await Task.sleep(for: .milliseconds(10))
    #expect(!runtime.needsAnimationFrame)
    #expect(redraws == 0)
    model.playing = true
    runtime.frame(input: Input(), viewport: viewport, time: 1, present: { _ in })
    #expect(runtime.needsAnimationFrame)
    model.playing = false
    for index in 61..<90 {
      runtime.frame(input: Input(), viewport: viewport, time: Double(index) / 60, present: { _ in })
    }
    try await Task.sleep(for: .milliseconds(10))
    let settled = redraws
    runtime.frame(input: Input(), viewport: viewport, time: 2, present: { _ in })
    try await Task.sleep(for: .milliseconds(10))
    #expect(!runtime.needsAnimationFrame && redraws == settled)
  }

  @Test func cpuPreview() throws {
    guard let path = ProcessInfo.processInfo.environment["ROOTS_PATH3D_PREVIEW"] else { return }
    let model = Path3DModel()
    let cpu = CPURenderer(width: 480, height: 400)
    var host = UIHost()
    host.frame(build: { Path3DPage(model: model, bounds: Region(0, 0, 480, 400)) }, present: { cpu.render($0) })
    try cpu.writePPM(to: path)
  }
}

#if os(Linux)
@testable import WaylandBridge

extension Path3DTests {
  @Test func path3DRenderingBenchmark() throws {
    guard ProcessInfo.processInfo.environment["ROOTS_PATH3D_BENCHMARK"] == "1" else { return }
    let renderer = NativeRenderer()
    var input = NativeWindowInput(width: 1000, height: 800)
    input.fractionalScale120 = 240
    try renderer.setup(input: input)
    defer { renderer.cleanup() }
    for fast in [false, true, false, true] {
      let model = Path3DModel(rendering: fast ? .ribbon : .analytic)
      var host = UIHost()
      var times: [Double] = []
      var debugProjection = Path3DProjection()
      debugProjection.update(geometry: model.geometry, camera: model.camera, rendering: fast ? .ribbon : .analytic)
      let scale = model.camera.transform(in: Region(20, 125, 960, 655), zoom: 1).scale * 2
      let ribbons = debugProjection.runs.filter { $0.body.usesRibbon(tint: Color(1, 1, 1), scale: scale) }.count
      print(
        "PATH3D paths ribbons=\(ribbons) shadow=\(debugProjection.shadow?.usesRibbon(tint: Color(1, 1, 1), scale: scale) == true)"
      )
      for index in 0..<35 {
        model.advance(1 / 60)
        let start = ContinuousClock.now
        try renderer.beginFrame(width: 1000, height: 800, fractionalScale120: 240)
        renderer.withFrame { frame in
          host.frame(
            build: { Path3DPage(model: model, bounds: Region(0, 0, 1000, 800)) },
            present: { frame.render($0) })
        }
        try renderer.endFrame(surfaceless: true)
        if index >= 5 {
          let elapsed = start.duration(to: .now).components
          times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
      }
      times.sort()
      print("PATH3D EGL glFinish ribbon=\(fast) pixels=2000x1600 frames=30 p50_ms=\(times[15]) p95_ms=\(times[28])")
      #expect(host.droppedDraws == 0)
    }
  }
}
#endif
