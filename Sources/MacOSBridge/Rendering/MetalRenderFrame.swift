import Roots

@MainActor public struct MetalRenderFrame: ~Copyable, ~Escapable {
  private var state: MutableRef<MetalFrameState>

  @_lifetime(&state)
  init(state: inout MetalFrameState) {
    self.state = MutableRef(&state)
  }

  public mutating func render(_ batch: borrowing UIDrawBatch) {
    state.value.render(batch.draws)
  }

  package mutating func render(_ draws: borrowing Span<DrawRect>) {
    state.value.render(draws)
  }
}
