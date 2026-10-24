import Roots
// expected-error: cannot pass function of type '() async -> _Empty' to parameter expecting synchronous function type

@MainActor func invalid() {
  _ = Column(in: Region(0, 0, 100, 100)) { () async -> _Empty in BlockBuilder.buildBlock() }
}
