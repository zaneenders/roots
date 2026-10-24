import Roots

public struct PublicPanel<Content: Block>: Block {
  let content: Content
  public init(@BlockBuilder content: () -> Content) { self.content = content() }
  public var body: some Block {
    Column(in: Region(0, 0, 120, 100)) { content }
  }
}

public struct PublicLeaf: Block {
  public typealias Body = Never
  public init() {}
  public borrowing func _build(into frame: inout UIFrame) {
    Text("Public")._build(into: &frame)
  }
}
