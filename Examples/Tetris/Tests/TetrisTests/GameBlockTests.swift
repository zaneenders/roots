@_spi(Hosting) import Roots
import Testing

@testable import Tetris

@MainActor
struct GameBlockTests {
  @Test func previewsSharePanelWidthAndPauseOverlayTracksBoard() throws {
    let controller = GameController(seed: 42)
    var host = UIHost()
    let bounds = Region(0, 0, 900, 800)
    var panel: Region?
    var board: Region?
    var previewTiles: [DrawRect] = []
    func render() {
      panel = nil
      board = nil
      previewTiles = []
      host.frame(
        build: { GameBlock(controller: controller, bounds: bounds) },
        present: { batch in
          for case .rectangle(let draw) in batch where draw.glyphUV == nil {
            if draw.color == Palette.well { board = draw.region }
            if draw.color == Palette.panel, panel == nil { panel = draw.region }
            if draw.radius == 3, draw.strokeWidth == 0,
              draw.region.width == 14, draw.region.height == 14
            {
              previewTiles.append(draw)
            }
          }
        })
    }
    render()
    let previewPanel = try #require(panel)
    let boardBounds = try #require(board)
    #expect(previewPanel.width == 240)
    try #require(previewTiles.count == 12)
    let previewWidth = (previewPanel.width - 28) / 3
    for index in 0..<3 {
      let tiles = Array(previewTiles[(index * 4)..<(index * 4 + 4)])
      let minX = try #require(tiles.map(\.region.x).min())
      let maxX = try #require(tiles.map { $0.region.x + $0.region.width }.max())
      let expectedCenter = previewPanel.x + 14 + (Float(index) + 0.5) * previewWidth
      #expect(abs((minX + maxX) / 2 - expectedCenter) < 0.001)
      #expect(tiles.allSatisfy { $0.color == Palette.color(controller.game.next[index]) })
    }
    #expect(host.state(for: 10) == nil)
    controller.togglePause()
    render()
    #expect(host.state(for: 10)?.region == boardBounds)
    controller.togglePause()
    render()
    #expect(host.state(for: 10) == nil)
  }
}
