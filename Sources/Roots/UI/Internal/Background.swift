struct BackgroundRegion {
  let node: Int
  let depth: Int
  let layouts: Range<Int>
  let nodes: Range<Int>
}

extension UIStorage {
  mutating func resolveBackgrounds() {
    for background in backgrounds {
      var bounds: Region?
      func include(_ region: Region) {
        guard !region.isEmpty else { return }
        guard let previous = bounds else {
          bounds = region
          return
        }
        let x = min(previous.x, region.x)
        let y = min(previous.y, region.y)
        bounds = Region(
          x, y, max(previous.x + previous.width, region.x + region.width) - x,
          max(previous.y + previous.height, region.y + region.height) - y)
      }
      for index in background.layouts where layouts[index].depth == background.depth {
        include(layouts[index].region)
      }
      for index in background.nodes {
        let node = nodes[order[index]]
        if node.cursorDepth == background.depth { include(node.layoutRegion) }
      }
      let region = bounds ?? Region(0, 0, 0, 0)
      nodes[background.node].region = region
      nodes[background.node].layoutRegion = region
    }
  }
}
