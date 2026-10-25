import Roots

@MainActor
final class DesktopCursors {
  private var automatic: [Bool: CursorShape] = [:]
  private var overrides: [Bool: CursorShape] = [:]
  private let apply: (CursorShape, Bool) -> Bool

  init(
    apply: @escaping (CursorShape, Bool) -> Bool = { shape, popup in
      (DesktopSystem.surface(popup: popup) as? any DesktopCursorSurface)?.setCursor(shape) ?? false
    }
  ) {
    self.apply = apply
  }

  func set(_ shape: CursorShape?, popup: Bool) -> Bool {
    overrides[popup] = shape
    return apply(overrides[popup] ?? automatic[popup] ?? .default, popup)
  }

  func update(_ style: CursorStyle, popup: Bool) {
    automatic[popup] = CursorShape(style)
    _ = apply(overrides[popup] ?? automatic[popup] ?? .default, popup)
  }

  func reset(popup: Bool) {
    automatic[popup] = nil
    overrides[popup] = nil
  }
}
