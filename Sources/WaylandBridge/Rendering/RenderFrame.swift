import Roots

@MainActor public struct RenderFrame: ~Copyable, ~Escapable {
  private let renderer: Ref<NativeRenderer>

  @_lifetime(borrow renderer)
  init(renderer: borrowing NativeRenderer) {
    self.renderer = Ref(renderer)
  }

  public borrowing func render(_ batch: borrowing UIDrawBatch) {
    renderer.value.render(batch)
  }

  package borrowing func render(_ draws: borrowing Span<DrawRect>) {
    renderer.value.render(draws)
  }
}
