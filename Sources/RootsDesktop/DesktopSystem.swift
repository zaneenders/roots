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
        logicalSize: SIMD2(window.size.width, window.size.height), title: window.title,
        maxFrames: window.maxFrames,
      screenshotPath: window.screenshotPath)
    let frame: @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void = {
      snapshot, renderer in
      let scale =
        snapshot.logicalSize.x > 0 ? Float(snapshot.drawableSize.x) / snapshot.logicalSize.x : 1
      runtime.frame(
        input: snapshot.input, viewport: Viewport(
          size: .init(width: snapshot.logicalSize.x, height: snapshot.logicalSize.y), scale: scale),
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
        width: Int32(window.size.width.rounded(.up)), height: Int32(window.size.height.rounded(.up)),
        maxFrames: window.maxFrames, title: window.title, screenshotPath: window.screenshotPath,
        minimumWidth: min(760, Int32(window.size.width.rounded(.up))),
        minimumHeight: min(640, Int32(window.size.height.rounded(.up)))),
      runtime: runtime, offscreen: window.offscreen)
    #endif
  }

  #if os(Linux)
  static var cursors = DesktopCursors()
  private static var isRunning = false

  /// Overrides hit-tested cursor selection until `setCursor(nil, popup:)` or surface closure.
  /// Returns false if the native backend cannot apply the request; the override is retained.
  @discardableResult
  public static func setCursor(_ shape: NativeCursorShape?, popup: Bool = false) -> Bool {
    cursors.set(shape, popup: popup)
  }

  @discardableResult
  public static func setTextInput(_ state: NativeTextInputState?, popup: Bool = false) -> Bool {
    NativeWindow.setTextInput(state, popup: popup)
  }

  static func run<Content: Block>(
    configuration: NativeWindowConfiguration, runtime: DesktopRuntime<Content>,
    offscreen: Bool = false
  ) async throws {
    guard !isRunning else { throw NativeWindowError.alreadyRunning }
    isRunning = true
    defer {
      isRunning = false
      cursors.reset(popup: false)
      cursors.reset(popup: true)
    }
    try await NativeWindow.runAsync(configuration: configuration, surfaceless: offscreen) {
      snapshot, renderer in
      frame(snapshot, renderer: renderer, runtime: runtime)
    }
  }

  static func input(_ snapshot: NativeWindowInput) -> Input {
    let hasPointer =
      snapshot.pointerInside || snapshot.primaryDown || snapshot.primaryPressed
      || snapshot.primaryReleased || snapshot.secondaryDown || snapshot.secondaryPressed
      || snapshot.secondaryReleased || snapshot.middleDown || snapshot.middlePressed
      || snapshot.middleReleased
    return Input(
      mousePosition: hasPointer ? Coordinate(x: snapshot.pointerX, y: snapshot.pointerY) : nil,
      pressed: snapshot.primaryPressed, released: snapshot.primaryReleased,
      scrollX: snapshot.scrollX, scrollY: snapshot.scrollY,
      scrollVelocityY: snapshot.scrollVelocityY,
      keyEvents: snapshot.keyEvents, focusLost: snapshot.focusLost,
      secondaryDown: snapshot.secondaryDown, secondaryPressed: snapshot.secondaryPressed,
      secondaryReleased: snapshot.secondaryReleased, middleDown: snapshot.middleDown,
      middlePressed: snapshot.middlePressed, middleReleased: snapshot.middleReleased,
      scrollStepsX: snapshot.scrollStepsX, scrollStepsY: snapshot.scrollStepsY,
      scrollInvertedX: snapshot.scrollInvertedX, scrollInvertedY: snapshot.scrollInvertedY,
      textEvents: snapshot.textEvents)
  }

  static func frame<Content: Block>(
    _ snapshot: NativeWindowInput, renderer: borrowing RenderFrame,
    runtime: DesktopRuntime<Content>, popup: Bool = false
  ) {
    runtime.frame(
      input: input(snapshot),
      viewport: Viewport(
        size: .init(width: Float(snapshot.width), height: Float(snapshot.height)),
        scale: Float(snapshot.renderScale)),
      time: snapshot.timeSeconds, present: { renderer.render($0) })
    cursors.update(runtime.cursorStyle, popup: popup)
  }
  #endif
}
