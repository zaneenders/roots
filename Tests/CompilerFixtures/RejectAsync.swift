import Roots

@MainActor func invalid() {
  _ = ColumnBlock(in: Rect(0, 0, 100, 100)) { () async -> EmptyBlock in EmptyBlock() }
}
