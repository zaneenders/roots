import Roots

public enum DesktopFrameUpdate {
  case present
  case rebuild(pointer: SIMD2<Float>?)
}

@MainActor
struct DesktopFrameCallbacks {
  var prepare: (@MainActor (inout Input, Float) -> Void)?
  var update: (@MainActor (Input) -> DesktopFrameUpdate)?
  var finish: (@MainActor (borrowing UIState) -> Void)?
  var needsAnimationFrame: (@MainActor () -> Bool)?
}
