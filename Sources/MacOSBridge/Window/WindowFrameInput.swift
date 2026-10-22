import Roots

public struct WindowFrameInput: Sendable {
  public let input: Input
  public let logicalSize: SIMD2<Float>
  public let drawableSize: SIMD2<Int32>
  public let timeSeconds: Double

  public init(
    input: Input = Input(), logicalSize: SIMD2<Float>, drawableSize: SIMD2<Int32>,
    timeSeconds: Double
  ) {
    self.input = input
    self.logicalSize = logicalSize
    self.drawableSize = drawableSize
    self.timeSeconds = timeSeconds
  }
}
