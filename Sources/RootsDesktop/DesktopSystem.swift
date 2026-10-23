import Roots

#if os(macOS)
import MacOSBridge
#elseif os(Linux)
import WaylandBridge
#endif

@MainActor
public enum DesktopSystem {
  public static var primaryShortcut: KeyModifiers {
    #if os(macOS)
    .super
    #else
    .control
    #endif
  }

  public static func requestRedraw() {
    #if os(macOS)
    MacOSWindow.requestRedraw()
    #else
    NativeWindow.requestRedraw()
    #endif
  }

  public static func writeClipboard(_ text: String) -> Bool {
    #if os(macOS)
    MacOSWindow.writeClipboard(text)
    #else
    NativeWindow.writeClipboard(text)
    #endif
  }

  public static func requestClose() {
    #if os(macOS)
    MacOSWindow.requestClose()
    #else
    NativeWindow.requestClose()
    #endif
  }

  public static func readClipboard() async -> String? {
    #if os(macOS)
    await MacOSWindow.readClipboard()
    #else
    await NativeWindow.readClipboard()
    #endif
  }

  static func run<Content: Block>(
    _ window: DesktopWindow<Content>, runtime: DesktopRuntime<Content>
  ) async throws {
    #if os(macOS)
    let configuration = WindowConfiguration(
      logicalSize: window.size, title: window.title, maxFrames: window.maxFrames,
      screenshotPath: window.screenshotPath)
    let frame: @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void = {
      snapshot, renderer in
      let scale =
        snapshot.logicalSize.x > 0 ? Float(snapshot.drawableSize.x) / snapshot.logicalSize.x : 1
      runtime.frame(
        input: snapshot.input, viewport: Viewport(size: snapshot.logicalSize, scale: scale),
        time: snapshot.timeSeconds,
        present: { renderer.render($0) })
    }
    if window.offscreen {
      try await MacOSWindow.renderOffscreen(configuration: configuration, frame: frame)
    } else {
      try await MacOSWindow.runAsync(configuration: configuration, frame: frame)
    }
    #else
    try await run(
      configuration: .init(
        width: Int32(window.size.x.rounded(.up)), height: Int32(window.size.y.rounded(.up)),
        maxFrames: window.maxFrames, title: window.title, screenshotPath: window.screenshotPath,
        minimumWidth: min(760, Int32(window.size.x.rounded(.up))),
        minimumHeight: min(640, Int32(window.size.y.rounded(.up)))),
      runtime: runtime, offscreen: window.offscreen)
    #endif
  }

  #if os(Linux)
  static func run<Content: Block>(
    configuration: NativeWindowConfiguration, runtime: DesktopRuntime<Content>,
    offscreen: Bool = false
  ) async throws {
    try await NativeWindow.runAsync(configuration: configuration, surfaceless: offscreen) {
      snapshot, renderer in
      frame(snapshot, renderer: renderer, runtime: runtime)
    }
  }

  static func input(_ snapshot: NativeWindowInput) -> Input {
    let hasPointer =
      snapshot.pointerInside || snapshot.primaryDown || snapshot.primaryPressed
      || snapshot.primaryReleased
    return Input(
      x: hasPointer ? snapshot.pointerX : -1, y: hasPointer ? snapshot.pointerY : -1,
      pressed: snapshot.primaryPressed, released: snapshot.primaryReleased,
      scrollX: snapshot.scrollX, scrollY: snapshot.scrollY,
      scrollVelocityY: snapshot.scrollVelocityY,
      keyEvents: snapshot.keyEvents, focusLost: snapshot.focusLost)
  }

  static func frame<Content: Block>(
    _ snapshot: NativeWindowInput, renderer: borrowing RenderFrame,
    runtime: DesktopRuntime<Content>
  ) {
    runtime.frame(
      input: input(snapshot),
      viewport: Viewport(
        size: .init(Float(snapshot.width), Float(snapshot.height)),
        scale: Float(snapshot.bufferScale)),
      time: snapshot.timeSeconds, present: { renderer.render($0) })
  }
  #endif
}
