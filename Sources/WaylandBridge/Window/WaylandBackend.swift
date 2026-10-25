import Roots
import SwiftWayland

/// Wayland/GLES implementation of the Roots desktop contract.
/// The native host currently supports one running window session at a time.
@MainActor
public final class WaylandBackend: DesktopBackend, DesktopCursorSurface, DesktopTextInputSurface {
  private var running = false

  public init() {}
  public var primaryShortcut: KeyModifiers { .control }

  public func run(
    configuration: BackendWindowConfiguration, frame: @escaping BackendFrameHandler
  ) async throws {
    try Task.checkCancellation()
    try configuration.validate()
    let size = configuration.logicalSize
    let minimum =
      configuration.minimumSize
      ?? Size(width: min(760, size.width), height: min(640, size.height))
    try await runNative(
      configuration: .init(
        width: Int32(size.width.rounded(.up)), height: Int32(size.height.rounded(.up)),
        maxFrames: configuration.maxFrames, title: configuration.title,
        screenshotPath: configuration.screenshotPath,
        minimumWidth: Int32(minimum.width.rounded(.up)),
        minimumHeight: Int32(minimum.height.rounded(.up))),
      offscreen: configuration.offscreen, frame: frame)
  }

  /// Native surface roles, such as layer-shell bars, stay outside the shared contract.
  public func run(
    configuration: NativeWindowConfiguration, frame: @escaping BackendFrameHandler
  ) async throws {
    try await runNative(configuration: configuration, offscreen: false, frame: frame)
  }

  private func runNative(
    configuration: NativeWindowConfiguration, offscreen: Bool,
    frame: @escaping BackendFrameHandler
  ) async throws {
    try Task.checkCancellation()
    guard !running else { throw DesktopBackendError.alreadyRunning }
    running = true
    defer { running = false }
    try await NativeWindow.runAsync(configuration: configuration, surfaceless: offscreen) {
      snapshot, renderer in
      frame(snapshot.backendFrame, { renderer.render($0) })
    }
  }

  public func requestRedraw() { if running { NativeWindow.requestRedraw() } }
  public func requestClose() { if running { NativeWindow.requestClose() } }
  public func readClipboard() async -> String? {
    guard running else { return nil }
    return await NativeWindow.readClipboard()
  }
  public func writeClipboard(_ text: String) -> Bool {
    running && NativeWindow.writeClipboard(text)
  }
  public func setCursor(_ shape: CursorShape) -> Bool {
    running && NativeWindow.setCursor(shape.wayland)
  }
  public func setTextInput(_ state: TextInputState?) -> Bool {
    guard running, state?.isValid != false else { return false }
    return NativeWindow.setTextInput(state?.wayland)
  }

  package func presentPopup(
    configuration: NativePopupConfiguration, frame: @escaping BackendFrameHandler,
    onDismiss: @escaping @MainActor () -> Void
  ) -> (any DesktopSurface)? {
    guard running else { return nil }
    let surface = PopupSurface()
    guard
      NativeWindow.presentPopup(
        configuration: configuration,
        frame: { snapshot, renderer in
          frame(snapshot.backendFrame, { renderer.render($0) })
        },
        onDismiss: {
          surface.active = false
          onDismiss()
        })
    else { return nil }
    return surface
  }
}

@MainActor
private final class PopupSurface: DesktopCursorSurface, DesktopTextInputSurface {
  var active = true
  func requestRedraw() { if active { NativeWindow.requestPopupRedraw() } }
  func requestClose() { if active { NativeWindow.dismissPopup() } }
  func setCursor(_ shape: CursorShape) -> Bool {
    active && NativeWindow.setCursor(shape.wayland, popup: true)
  }
  func setTextInput(_ state: TextInputState?) -> Bool {
    guard active, state?.isValid != false else { return false }
    return NativeWindow.setTextInput(state?.wayland, popup: true)
  }
}

extension NativeWindowInput {
  public var input: Input {
    let hasPointer =
      pointerInside || primaryDown || primaryPressed
      || primaryReleased || secondaryDown || secondaryPressed
      || secondaryReleased || middleDown || middlePressed
      || middleReleased
    return Input(
      mousePosition: hasPointer ? Coordinate(x: pointerX, y: pointerY) : nil,
      pressed: primaryPressed, released: primaryReleased,
      scrollX: scrollX, scrollY: scrollY,
      scrollVelocityY: scrollVelocityY,
      keyEvents: keyEvents, focusLost: focusLost,
      secondaryDown: secondaryDown, secondaryPressed: secondaryPressed,
      secondaryReleased: secondaryReleased, middleDown: middleDown,
      middlePressed: middlePressed, middleReleased: middleReleased,
      scrollStepsX: scrollStepsX, scrollStepsY: scrollStepsY,
      scrollInvertedX: scrollInvertedX, scrollInvertedY: scrollInvertedY,
      textEvents: textEvents)
  }

  package var backendFrame: BackendFrame {
    .init(
      input: input, logicalSize: .init(width: Float(width), height: Float(height)),
      scale: Float(renderScale), timeSeconds: timeSeconds)
  }
}

extension CursorShape {
  fileprivate var wayland: WaylandCursorShape {
    switch self {
    case .default: .default
    case .contextMenu: .contextMenu
    case .help: .help
    case .pointer: .pointer
    case .progress: .progress
    case .wait: .wait
    case .cell: .cell
    case .crosshair: .crosshair
    case .text: .text
    case .verticalText: .verticalText
    case .alias: .alias
    case .copy: .copy
    case .move: .move
    case .noDrop: .noDrop
    case .notAllowed: .notAllowed
    case .grab: .grab
    case .grabbing: .grabbing
    case .eastResize: .eastResize
    case .northResize: .northResize
    case .northEastResize: .northEastResize
    case .northWestResize: .northWestResize
    case .southResize: .southResize
    case .southEastResize: .southEastResize
    case .southWestResize: .southWestResize
    case .westResize: .westResize
    case .eastWestResize: .eastWestResize
    case .northSouthResize: .northSouthResize
    case .northEastSouthWestResize: .northEastSouthWestResize
    case .northWestSouthEastResize: .northWestSouthEastResize
    case .columnResize: .columnResize
    case .rowResize: .rowResize
    case .allScroll: .allScroll
    case .zoomIn: .zoomIn
    case .zoomOut: .zoomOut
    }
  }
}

extension TextInputState {
  fileprivate var wayland: WaylandTextInputState {
    .init(
      surroundingText: surroundingText, cursor: cursor, anchor: anchor,
      cursorRectangle: cursorRectangle, changeCausedByInputMethod: changeCausedByInputMethod,
      purpose: purpose.wayland,
      hints: .init(rawValue: hints.rawValue))
  }
}

extension TextInputState.Purpose {
  fileprivate var wayland: WaylandTextInputState.Purpose {
    switch self {
    case .normal: .normal
    case .alpha: .alpha
    case .digits: .digits
    case .number: .number
    case .phone: .phone
    case .url: .url
    case .email: .email
    case .name: .name
    case .password: .password
    case .pin: .pin
    case .date: .date
    case .time: .time
    case .dateTime: .dateTime
    case .terminal: .terminal
    }
  }
}
