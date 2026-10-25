#if os(Linux)
import Roots
import WaylandBridge

@MainActor
final class DesktopCursors {
  private var automatic: [Bool: NativeCursorShape] = [:]
  private var overrides: [Bool: NativeCursorShape] = [:]
  private let apply: (NativeCursorShape, Bool) -> Bool

  init(
    apply: @escaping (NativeCursorShape, Bool) -> Bool = { NativeWindow.setCursor($0, popup: $1) }
  ) {
    self.apply = apply
  }

  func set(_ shape: NativeCursorShape?, popup: Bool) -> Bool {
    overrides[popup] = shape
    return apply(overrides[popup] ?? automatic[popup] ?? .default, popup)
  }

  func update(_ style: CursorStyle, popup: Bool) {
    automatic[popup] = switch style {
    case .default: .default
    case .pointer: .pointer
    case .text: .text
    }
    _ = apply(overrides[popup] ?? automatic[popup] ?? .default, popup)
  }

  func reset(popup: Bool) {
    automatic[popup] = nil
    overrides[popup] = nil
  }
}
#endif
