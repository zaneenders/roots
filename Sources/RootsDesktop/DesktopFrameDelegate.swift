import Roots

public enum DesktopFrameUpdate {
  case present
  case rebuild(pointer: SIMD2<Float>?)
}

@MainActor
public protocol DesktopFrameDelegate: AnyObject {
  func prepareFrame(input: inout Input, dt: Float)
  func frameUpdate(after input: Input) -> DesktopFrameUpdate
  func didFinishFrame(_ state: borrowing UIState)
  var needsAnimationFrame: Bool { get }
}

extension DesktopFrameDelegate {
  public func prepareFrame(input: inout Input, dt: Float) {}
  public func frameUpdate(after input: Input) -> DesktopFrameUpdate { .present }
  public func didFinishFrame(_ state: borrowing UIState) {}
  public var needsAnimationFrame: Bool { false }
}
