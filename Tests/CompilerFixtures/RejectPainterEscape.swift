import Roots

@MainActor func invalid() -> some Block {
  Canvas(key: 1, extent: 10) { painter in
    Task { _ = painter.region }
  }
}
