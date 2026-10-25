import Roots

// A backend implemented by a separate package needs only Roots' public API.
@MainActor
final class ExternalBackend: DesktopBackend, DesktopCursorSurface {
  var primaryShortcut: KeyModifiers { .control }
  func run(configuration: BackendWindowConfiguration, frame: @escaping BackendFrameHandler) async throws {
    try configuration.validate()
    try Task.checkCancellation()
    frame(.init(input: Input(), logicalSize: configuration.logicalSize, scale: 1.5, timeSeconds: 0)) {
      draws in
      for draw in draws { _ = draw.region }
      _ = FontAtlas.shared.mipLevels
      _ = EmojiAtlas.shared.mipLevels
    }
  }
  func requestRedraw() {}
  func requestClose() {}
  func readClipboard() async -> String? { nil }
  func writeClipboard(_ text: String) -> Bool { false }
  func setCursor(_ shape: CursorShape) -> Bool { false }
}
