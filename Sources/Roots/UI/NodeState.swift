public struct NodeState: Sendable {
  public let key: UInt64
  public let clicks: Int
  public let hovered: Bool
  public let focused: Bool
  public let hoverAnimation: Float
  public let rect: Rect
  public let scrollOffset: Float
}
