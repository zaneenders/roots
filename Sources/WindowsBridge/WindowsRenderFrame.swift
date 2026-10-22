import Roots
import RootsCPU

@MainActor public struct WindowsRenderFrame: ~Copyable, ~Escapable {
  private let renderer: Ref<CPURenderer>

  @_lifetime(borrow renderer)
  init(renderer: borrowing CPURenderer) {
    self.renderer = Ref(renderer)
  }

  public borrowing func render(_ batch: borrowing UIDrawBatch) {
    renderer.value.render(batch)
  }
}

public struct WindowsFrameInput: Sendable {
  public let input: Input
  public let size: SIMD2<Float>
  public let timeSeconds: Double

  public init(input: Input = Input(), size: SIMD2<Float>, timeSeconds: Double) {
    self.input = input
    self.size = size
    self.timeSeconds = timeSeconds
  }
}
