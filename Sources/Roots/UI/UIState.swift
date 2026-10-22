@MainActor
public struct UIState: ~Copyable, ~Escapable {
  private let host: Ref<UIHost>

  @_lifetime(borrow host)
  init(host: borrowing UIHost) {
    self.host = Ref(host)
  }

  public var liveCount: Int { host.value.liveCount }
  public var droppedDraws: Int { host.value.droppedDraws }
  public var needsAnimationFrame: Bool { host.value.needsAnimationFrame }
  public var selectedText: String? { host.value.selectedText }

  public func state(for key: UInt64) -> NodeState? { host.value.state(for: key) }
}
