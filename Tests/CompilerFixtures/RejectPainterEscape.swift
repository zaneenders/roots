import Roots

@MainActor func invalid() -> some Block {
  CanvasBlock(key: 1, extent: 10) { painter in
    Task { _ = painter.rect }
  }
}
