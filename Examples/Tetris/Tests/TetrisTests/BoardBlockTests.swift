@_spi(Hosting) import Roots
import RootsCPU
import Testing

@testable import Tetris
@testable import TetrisCore

@MainActor
struct BoardBlockTests {
  @Test func boardLayersUseAllGridSlotsAndPaintActiveAboveGhost() throws {
    let game = fixture(overlappingGhost: true)
    let bounds = Region(10, 20, 160, 320)
    var host = UIHost()
    var draws: [DrawRect] = []
    host.frame(
      build: { Stack(in: bounds) { BoardBlock(game: game) } },
      present: { batch in
        for case .rectangle(let draw) in batch { draws.append(draw) }
      })
    try #require(draws.count == 221)
    #expect(draws[0].region == bounds)
    #expect(draws[0].color == Palette.well)
    let grid = Array(draws[1...200])
    #expect(grid.allSatisfy { $0.color == Palette.grid && $0.strokeWidth == 0.5 })
    #expect(grid[0].region == Region(11, 21, 14, 14))
    #expect(grid[199].region == Region(155, 325, 14, 14))

    let ghost = Array(draws[209...212])
    let active = Array(draws[213...220]).enumerated().compactMap { index, draw in
      index.isMultiple(of: 2) ? draw : nil
    }
    #expect(ghost.allSatisfy { $0.strokeWidth == 1.5 && $0.color == Palette.color(.o) })
    #expect(active.map(\.region) == ghost.map(\.region))
    #expect(active.allSatisfy { $0.strokeWidth == 0 && $0.color == Palette.color(.o) })
  }

  @Test func emptyGameOverBoardDrawsOnlyWellAndGrid() {
    var game = Game(seed: 42)
    game.active = nil
    game.status = .gameOver
    var host = UIHost()
    host.frame(
      build: { Stack(in: Region(0, 0, 160, 320)) { BoardBlock(game: game) } },
      present: { batch in
        #expect(batch.count == 201)
        guard case .rectangle(let background) = batch[0] else {
          Issue.record("Expected board background"); return
        }
        #expect(background.color == Palette.well)
        for index in 1..<batch.count {
          guard case .rectangle(let draw) = batch[index] else {
            Issue.record("Expected grid rectangle"); return
          }
          #expect(draw.color == Palette.grid)
          #expect(draw.strokeWidth == 0.5)
        }
      })
  }

  @Test(arguments: [Float(8), 16, 29.25, 30])
  func boardMatchesOriginalPainter(size: Float) {
    let game = fixture()
    let bounds = Region(5, 7, size * 10, size * 20)
    let width = Int(bounds.x + bounds.width) + 4
    let height = Int(bounds.y + bounds.height) + 4
    let actual = CPURenderer(width: width, height: height)
    let expected = CPURenderer(width: width, height: height)
    var host = UIHost()
    var reference = UIHost()
    host.frame(
      build: { Stack(in: bounds) { BoardBlock(game: game) } },
      present: { actual.render($0) })
    reference.frame(
      build: {
        Stack(in: bounds) {
          Canvas(key: 1, color: Palette.well) { context in
            ReferencePainter.draw(game, into: &context, cellSize: size)
          }
        }
      }, present: { expected.render($0) })
    #expect(actual.pixels.elementsEqual(expected.pixels))
  }

  @Test(arguments: Tetromino.allCases)
  func previewMatchesOriginalPainter(kind: Tetromino) {
    let bounds = Region(5, 7, 72, 52)
    let actual = CPURenderer(width: 84, height: 66)
    let expected = CPURenderer(width: 84, height: 66)
    var host = UIHost()
    var reference = UIHost()
    host.frame(
      build: { Stack(in: bounds) { PiecePreview(kind: kind) } },
      present: { actual.render($0) })
    reference.frame(
      build: {
        Stack(in: bounds) {
          Canvas(key: 1, color: Color(0, 0, 0, 0)) { context in
            ReferencePainter.drawPreview(kind, into: &context)
          }
        }
      }, present: { expected.render($0) })
    #expect(actual.pixels.elementsEqual(expected.pixels))
  }

  @Test func overlayPreservesDrawingParity() {
    let game = fixture()
    let bounds = Region(0, 0, 10 * 16, 20 * 16)
    let actual = CPURenderer(width: 160, height: 320)
    let expected = CPURenderer(width: 160, height: 320)
    var host = UIHost()
    var reference = UIHost()
    host.frame(
      build: {
        Stack(in: bounds) {
          BoardBlock(game: game)
          Rectangle().color(Color(0.03, 0.04, 0.07, 0.86))
        }
      }, present: { actual.render($0) })
    reference.frame(
      build: {
        Stack(in: bounds) {
          Canvas(key: 1, color: Palette.well) { context in
            ReferencePainter.draw(game, into: &context, cellSize: 16)
          }
          Rectangle().color(Color(0.03, 0.04, 0.07, 0.86))
        }
      }, present: { expected.render($0) })
    #expect(actual.pixels.elementsEqual(expected.pixels))
  }

  private func fixture(overlappingGhost: Bool = false) -> Game {
    var game = Game(seed: 42)
    game.board[19 * Game.width + 2] = .j
    game.board[19 * Game.width + 7] = .l
    game.board[18 * Game.width + 1] = .s
    game.board[17 * Game.width + 8] = .z
    game.active = Piece(.o, origin: Cell(3, overlappingGhost ? 18 : 2))
    return game
  }
}
