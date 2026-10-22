import CEGLGLES
import DesktopTestSupport
import Foundation
import Roots
import Testing

@testable import WaylandBridge

@Test @MainActor func popupRejectsInvalidOrUnconnectedPresentationsWithoutCallingDismissal() {
  let host = NativeHost(configuration: .init())
  defer { host.cleanup() }
  var dismissed = false
  #expect(throws: NativeWindowError.invalidConfiguration) {
    try host.presentPopup(
      configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 0, height: 100),
      frame: { _, _ in }, onDismiss: { dismissed = true })
  }
  #expect(throws: NativeWindowError.invalidConfiguration) {
    try host.presentPopup(
      configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 100, height: 100),
      frame: { _, _ in }, onDismiss: { dismissed = true })
  }
  #expect(!dismissed)
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland compositor is unavailable") { try await WaylandAvailability.compositor },
    arguments: [false, true])
  func popupDismissalDoesNotWaitForBufferAvailability(alreadyWaiting: Bool) async throws {
    let host = NativeHost(configuration: .init())
    defer { host.cleanup() }
    try await host.connect()
    var dismissals = 0
    try host.presentPopup(
      configuration: .init(x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 40, height: 30),
      grab: false, frame: { _, _ in Issue.record("Dismissal must not render") },
      onDismiss: { dismissals += 1 })
    _ = host.beginFrame()
    host.connection.waitForDMABufBuffer()
    #expect(!host.canRender)
    if !alreadyWaiting { host.requestPopupDismissal() }
    var started = false
    let dispatch = Task {
      started = true
      while host.connection.popupInput != nil { try await host.dispatchAsync() }
    }
    defer { dispatch.cancel() }
    let deadline = Task {
      try await Task.sleep(for: .seconds(2))
      dispatch.cancel()
    }
    defer { deadline.cancel() }
    while !started { await Task.yield() }
    if alreadyWaiting { host.requestPopupDismissal() }
    try await dispatch.value
    #expect(dismissals == 1 && host.connection.popupInput == nil)
    #expect(host.canRender && host.running)
    host.dismissPopup()
    #expect(dismissals == 1)
  }

  @Test(
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  func popupOnlyRedrawsWaitForCompositorAndAllowMainActorTimers() async throws {
    let host = NativeHost(configuration: .init(height: 26, topBar: true))
    defer { host.cleanup() }
    try await host.connect()
    try host.setupRenderer(surfaceless: false)
    var frameCount: Int32 = 0
    let started = ContinuousClock.now
    _ = try NativeWindow.renderFrame(
      host, surfaceless: false, started: started, frameCount: &frameCount, frame: { _, _ in })
    try host.renderer.releaseCurrent()
    var popupFrames = 0
    var timerRan = false
    var timer: Task<Void, Never>?
    let deadline = Task {
      try? await Task.sleep(for: .seconds(5))
      host.requestClose()
    }
    defer {
      deadline.cancel()
      timer?.cancel()
    }
    try host.presentPopup(
      configuration: .init(x: 0, y: 0, anchorWidth: 20, anchorHeight: 26, width: 120, height: 80),
      grab: false,
      frame: { _, _ in
        popupFrames += 1
        if popupFrames == 1 {
          timer = Task {
            try? await Task.sleep(for: .milliseconds(5))
            timerRan = true
          }
        }
        host.requestRedraw()
      }, onDismiss: {})
    while host.running && popupFrames < 12 {
      if host.canRender {
        _ = try NativeWindow.renderFrame(
          host, surfaceless: false, started: started, frameCount: &frameCount, frame: { _, _ in })
        try host.renderer.releaseCurrent()
        if popupFrames > 0 {
          #expect(!host.connection.frameReady)
          #expect(host.connection.redrawRequested)
        }
      } else {
        try await host.dispatchAsync()
      }
    }
    #expect(popupFrames == 12)
    #expect(timerRan)
  }

  @Test(
    .enabled("Wayland layer-shell/dma-buf presentation is unavailable") {
      try await WaylandAvailability.layerPresentation
    })
  func layerPopupRendersReopensAndReleasesOnlyItsOwnEGLResources() async throws {
    let host = NativeHost(configuration: .init(height: 26, topBar: true, topBarOverlayHeight: 32))
    defer { host.cleanup() }
    try await host.connect()
    try host.setupRenderer(surfaceless: false)
    var parentFrames: Int32 = 0
    let started = ContinuousClock.now
    while parentFrames == 0 && host.running {
      if host.canRender {
        _ = try NativeWindow.renderFrame(
          host, surfaceless: false, started: started, frameCount: &parentFrames, frame: { _, _ in })
        try host.renderer.releaseCurrent()
      } else {
        try await host.dispatchAsync()
      }
    }
    var frames = 0
    var dismissals = 0
    let deadline = Task {
      try? await Task.sleep(for: .seconds(5))
      host.requestClose()
    }
    defer { deadline.cancel() }
    for _ in 0..<3 {
      let before = frames
      try host.presentPopup(
        configuration: .init(
          x: host.input.width - 30, y: 0, anchorWidth: 20, anchorHeight: 28, width: 300, height: 240
        ),
        grab: false,
        frame: { input, renderer in
          #expect(input.width == 300 && input.height == 240)
          #expect(input.bufferScale == host.input.bufferScale)
          let draws = [DrawRect(Rect(0, 0, 300, 240), Color(0.1, 0.2, 0.3))]
          renderer.render(draws.span)
          frames += 1
        }, onDismiss: { dismissals += 1 })
      while frames == before && host.running {
        _ = host.beginFrame()
        try await host.dispatchAsync()
        host.renderPopup()
      }
      #expect(frames > before)
      host.dismissPopup()
      host.dismissPopup()
      host.requestRedraw()
      let previous = parentFrames
      while parentFrames == previous && host.running {
        if host.canRender {
          _ = try NativeWindow.renderFrame(
            host, surfaceless: false, started: started, frameCount: &parentFrames,
            frame: { _, _ in })
          try host.renderer.releaseCurrent()
        } else {
          try await host.dispatchAsync()
        }
      }
    }
    #expect(dismissals == 3)
    #expect(host.running)
  }
}
