import AppKit
import MetalKit

@MainActor final class MacOSWindowHost: NSObject, NSWindowDelegate, MTKViewDelegate {
  let window: NSWindow
  let view: MacOSInputView
  let renderer: MetalRenderer
  var input = MacOSInputState()
  private let configuration: WindowConfiguration
  private let frame: @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void
  private let started = ContinuousClock.now
  private let completions: AsyncStream<MetalFrameCompletion>.Continuation
  private var completionTask: Task<Void, Never>?
  private var closing = false
  private var drawing = false
  private var redrawRequested = true
  private var submittedFrames: Int32 = 0
  private(set) var finished = false
  private(set) var error: (any Error)?

  init(
    configuration: WindowConfiguration,
    frame: @escaping @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void
  ) throws {
    self.configuration = configuration
    self.frame = frame
    renderer = try MetalRenderer()
    let size = NSSize(
      width: Double(configuration.logicalSize.x), height: Double(configuration.logicalSize.y))
    window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    view = MacOSInputView(frame: NSRect(origin: .zero, size: size), device: renderer.device)
    let (stream, continuation) = AsyncStream<MetalFrameCompletion>.makeStream()
    completions = continuation
    super.init()
    window.isReleasedWhenClosed = false
    window.title = configuration.title
    window.contentMinSize = NSSize(width: 360, height: 260)
    window.contentView = view
    window.delegate = self
    window.acceptsMouseMovedEvents = true
    window.center()
    view.host = self
    view.delegate = self
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = false
    view.preferredFramesPerSecond = 60
    view.isPaused = configuration.maxFrames == 0
    view.autoResizeDrawable = true
    completionTask = Task { [weak self] in
      for await completion in stream {
        guard let self else { return }
        do {
          if let image = try renderer.complete(completion), let path = configuration.screenshotPath
          {
            try image.write(to: URL(fileURLWithPath: path))
          }
        } catch {
          if self.error == nil { self.error = error }
          requestClose()
        }
        finishCloseIfReady()
      }
    }
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    NSApplication.shared.activate()
    requestRedraw()
  }

  func requestRedraw() {
    guard !closing else { return }
    redrawRequested = true
    view.isPaused = false
  }

  func draw(in view: MTKView) {
    guard !closing, !drawing, renderer.hasFreeSlot, view.bounds.width > 0, view.bounds.height > 0,
      let drawable = view.currentDrawable
    else { return }
    redrawRequested = false
    drawing = true
    defer {
      drawing = false
      finishCloseIfReady()
    }
    let size = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
    let duration = started.duration(to: .now).components
    let time =
      configuration.maxFrames > 0
      ? Double(submittedFrames) / 60
      : Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    let snapshot = WindowFrameInput(
      input: input.input, logicalSize: size,
      drawableSize: .init(Int32(drawable.texture.width), Int32(drawable.texture.height)),
      timeSeconds: time)
    let final = configuration.maxFrames > 0 && submittedFrames == configuration.maxFrames - 1
    do {
      let submitted = try renderer.submit(
        logicalSize: size, target: drawable.texture, drawable: drawable,
        readback: final && configuration.screenshotPath != nil, completions: completions
      ) {
        input.consumeEdges()
        frame(snapshot, &$0)
      }
      if submitted {
        submittedFrames += 1
        if final {
          requestClose()
        } else if configuration.maxFrames == 0 && !redrawRequested {
          view.isPaused = true
        }
      }
    } catch {
      self.error = error
      requestClose()
    }
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { requestRedraw() }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    requestClose()
    return false
  }
  func windowDidResignKey(_ notification: Notification) {
    input.loseFocus()
    requestRedraw()
  }
  func windowDidBecomeKey(_ notification: Notification) {
    window.makeFirstResponder(view)
    requestRedraw()
  }

  func requestClose() {
    closing = true
    view.isPaused = true
    input.loseFocus()
    finishCloseIfReady()
  }

  private func finishCloseIfReady() {
    guard closing, !drawing, !renderer.hasPendingFrames, !finished else { return }
    finished = true
    completions.finish()
    window.orderOut(nil)
    NSApplication.shared.stop(nil)
    if let event = NSEvent.otherEvent(
      with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
    {
      NSApplication.shared.postEvent(event, atStart: false)
    }
  }

  func cleanup() {
    precondition(!renderer.hasPendingFrames)
    view.isPaused = true
    view.delegate = nil
    view.host = nil
    window.delegate = nil
    window.close()
    completions.finish()
    completionTask?.cancel()
    completionTask = nil
  }
}

@MainActor final class MacOSApplicationDelegate: NSObject, NSApplicationDelegate {
  weak var host: MacOSWindowHost?
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    host?.requestClose()
    return .terminateCancel
  }
  @objc func quit(_ sender: Any?) { host?.requestClose() }
}
