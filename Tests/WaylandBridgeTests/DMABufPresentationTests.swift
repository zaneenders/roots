import CEGLGLES
import DesktopTestSupport
import Foundation
import Roots
import RootsCPU
import Testing

@testable import WaylandBridge

extension NativeSessionTests {
  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    }, arguments: [1, 12])
  func exportedTexturesPresentWithoutAnEGLWindowSurface(frameLimit: Int32) async throws {
    let deadline = Task {
      try? await Task.sleep(for: .seconds(5))
      if !Task.isCancelled { NativeWindow.requestClose() }
    }
    defer { deadline.cancel() }
    var frames = 0
    try await NativeWindow.runAsync(
      configuration: .init(
        width: 160, height: 120, maxFrames: frameLimit, title: "Swift dma-buf experiment",
        minimumWidth: 0, minimumHeight: 0)
    ) { input, frame in
      var framebuffer: GLint = 0
      unsafe glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &framebuffer)
      #expect(framebuffer != 0)
      let draws = [
        DrawRect(Region(0, 0, Float(input.width), Float(input.height)), Color(0.1, 0.2, 0.4)),
        DrawRect(Region(8 + Float(frames * 4), 8, 32, 24), Color(1, 0, 0)),
        DrawRect(Region(8, Float(input.height) - 32, 32, 24), Color(0, 1, 0))
      ]
      frame.render(draws.span)
      frames += 1
    }
    #expect(frames == Int(frameLimit))
    try await NativeWindow.runAsync(
      configuration: .init(width: 16, height: 16, maxFrames: 1), surfaceless: true
    ) {
      _, _ in
    }
  }
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  func dmabufRingSurvivesResizeScaleAndPopupReopen() async throws {
    let host = NativeHost(
      configuration: .init(height: 26, topBar: true))
    defer { host.cleanup() }
    try await host.connect()
    try host.setupRenderer(surfaceless: false)
    let deadline = Task {
      try? await Task.sleep(for: .seconds(5))
      if !Task.isCancelled { host.requestClose() }
    }
    defer { deadline.cancel() }
    let started = ContinuousClock.now
    var frames: Int32 = 0
    while frames == 0 && host.running {
      if host.canRender {
        _ = try NativeWindow.renderFrame(
          host, surfaceless: false, started: started, frameCount: &frames, frame: { _, _ in })
        try host.renderer.releaseCurrent()
      } else {
        try await host.dispatchAsync()
      }
    }
    #expect(frames == 1)
    for scale: Int32 in [1, 2, 1] {
      try host.renderer.makeCurrent()
      var ready = false
      while !ready && host.running {
        ready = try host.renderer.preparePresentation(
          width: 120 + scale * 8, height: 26, bufferScale: scale)
        try host.renderer.releaseCurrent()
        if !ready {
          #expect(!host.canRender)
          try await host.dispatchAsync()
          try host.renderer.makeCurrent()
        }
      }
      #expect(ready)
      try host.renderer.makeCurrent()
      try host.renderer.beginFrame(
        width: 120 + scale * 8, height: 26, bufferScale: scale, transparent: true)
      try host.renderer.endFrame(surfaceless: false)
      try host.renderer.swapBuffers()
      try host.renderer.releaseCurrent()
    }
    var popupFrames = 0
    var dismissals = 0
    for _ in 0..<2 {
      let before = popupFrames
      try host.presentPopup(
        configuration: .init(x: 0, y: 0, anchorWidth: 20, anchorHeight: 26, width: 120, height: 80),
        grab: false,
        frame: { input, frame in
          let draws = [
            DrawRect(Region(0, 0, Float(input.width), Float(input.height)), Color(0, 0.5, 1, 0.5))
          ]
          frame.render(draws.span)
          popupFrames += 1
        }, onDismiss: { dismissals += 1 })
      while popupFrames == before && host.running {
        if host.canRender {
          _ = try NativeWindow.renderFrame(
            host, surfaceless: false, started: started, frameCount: &frames, frame: { _, _ in })
          try host.renderer.releaseCurrent()
        } else {
          try await host.dispatchAsync()
        }
      }
      #expect(popupFrames > before)
      host.dismissPopup()
      host.dismissPopup()
      host.requestRedraw()
    }
    #expect(dismissals == 2 && host.running)
    host.cleanup()
    host.cleanup()
    #expect(unsafe eglGetCurrentContext() == nil)
  }
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  func dmabufFramebufferPreservesGlyphsClippingAndPremultipliedAlpha() async throws {
    let host = NativeHost(configuration: .init(height: 26, topBar: true))
    defer { host.cleanup() }
    try await host.connect()
    try host.setupRenderer(surfaceless: false)
    let end = ContinuousClock.now.advanced(by: .seconds(5))
    var ready = false
    while !ready && ContinuousClock.now < end {
      try host.renderer.makeCurrent()
      ready = try host.renderer.preparePresentation(width: 96, height: 48, bufferScale: 1)
      try host.renderer.releaseCurrent()
      if !ready { try await host.dispatchAsync() }
    }
    try #require(ready)
    try host.renderer.makeCurrent()
    try host.renderer.beginFrame(width: 96, height: 48, transparent: true)
    let alphaDraws = [DrawRect(Region(0, 0, 8, 8), Color(1, 0, 0, 0.5))]
    host.renderer.withFrame { $0.render(alphaDraws.span) }
    try host.renderer.endFrame(surfaceless: true)
    var rgba = [UInt8](repeating: 0, count: 4)
    unsafe glReadPixels(4, 44, 1, 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &rgba)
    #expect(abs(Int(rgba[0]) - 128) <= 1 && abs(Int(rgba[3]) - 128) <= 1)
    let draws = [
      DrawRect(Region(0, 0, 96, 48), Color(0, 0, 0)),
      DrawRect(Region(0, 0, 24, 48), Color(0, 1, 0, 0.5), clip: Region(8, 8, 16, 24)),
      DrawRect(Region(28, 4, 20, 36), .text, glyphUV: FontAtlas.shared.glyphUV("A")),
      DrawRect(
        Region(56, 4, 32, 36), .text, glyphUV: EmojiAtlas.shared.glyphUV("🙂"), colorGlyph: true)
    ]
    try host.renderer.beginFrame(width: 96, height: 48)
    host.renderer.withFrame { $0.render(draws.span) }
    try host.renderer.endFrame(surfaceless: true)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    try host.renderer.screenshot(to: path.path)
    let cpu = CPURenderer(width: 96, height: 48)
    cpu.render(draws.span)
    let pixels = Array(try Data(contentsOf: path).dropFirst(Data("P6\n96 48\n255\n".utf8).count))
    #expect(pixels.count == cpu.pixels.count)
    #expect(zip(pixels, cpu.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0 <= 4)
  }
}
