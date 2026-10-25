/// A native surface controlled by a Roots host. Commands never invoke a frame inline.
@MainActor
public protocol DesktopSurface: AnyObject {
  /// Coalesces invalidations and schedules a frame when the surface can present.
  func requestRedraw()
  func requestClose()
}

/// Native windowing and presentation, independent of the application's block type.
///
/// A backend owns its event loop, render targets, frame pacing, and native resources.
/// `run` must honor task cancellation and finish cleanup before returning or throwing.
/// It must not retain or invoke the frame handler after returning. Native input edges
/// are delivered once, coordinates are logical units, and time is monotonic seconds
/// (or deterministic frame time for bounded/offscreen rendering).
/// Surface commands outside a running native session do nothing.
@MainActor
public protocol DesktopBackend: DesktopSurface {
  var primaryShortcut: KeyModifiers { get }

  /// Unsupported offscreen or screenshot requests throw `unsupportedFeature`.
  func run(
    configuration: BackendWindowConfiguration, frame: @escaping BackendFrameHandler
  ) async throws

  func readClipboard() async -> String?
  @discardableResult func writeClipboard(_ text: String) -> Bool
}

/// Optional cursor support. False means the shape could not currently be applied.
@MainActor
public protocol DesktopCursorSurface: DesktopSurface {
  @discardableResult func setCursor(_ shape: CursorShape) -> Bool
}

/// Optional input-method support. Nil disables the current text-input session.
/// False means unsupported or unavailable; key events remain available separately.
@MainActor
public protocol DesktopTextInputSurface: DesktopSurface {
  @discardableResult func setTextInput(_ state: TextInputState?) -> Bool
}

/// The render function is synchronous and nonescaping. Encode or copy the draws
/// into backend-owned storage before returning; neither it nor the batch may escape.
public typealias BackendFrameHandler =
  @MainActor (
    BackendFrame, _ render: @MainActor (borrowing UIDrawBatch) -> Void
  ) -> Void

public struct BackendFrame: Sendable {
  public let input: Input
  public let logicalSize: Size
  /// Pixels per logical unit, including fractional scaling before buffer rounding.
  public let scale: Float
  public let timeSeconds: Double

  public init(input: Input, logicalSize: Size, scale: Float, timeSeconds: Double) {
    self.input = input
    self.logicalSize = logicalSize
    self.scale = scale
    self.timeSeconds = timeSeconds
  }
}

public enum DesktopBackendError: Error, Equatable {
  case invalidConfiguration
  case alreadyRunning
  case unavailable
  case unsupportedFeature(String)
}
