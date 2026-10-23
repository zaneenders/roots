import Roots

@MainActor func invalid() {
  _ = Column(in: Region(0, 0, 100, 100)) { () async -> EmptyBlock in EmptyBlock() }
}
