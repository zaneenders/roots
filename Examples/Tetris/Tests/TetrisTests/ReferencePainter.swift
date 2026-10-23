import Roots
import TetrisCore

@testable import Tetris

// Keep the original canvas renderer as a pixel-parity oracle for the block implementation.
@MainActor
enum ReferencePainter {
  static func draw(_ game: Game, into context: inout UIPaintContext, cellSize: Float) {
    let region = context.region
    context.withOrigin(x: region.x, y: region.y) { context in
      for row in 0..<Game.height {
        for column in 0..<Game.width {
          let cell = Cell(column, row)
          context.strokeRect(
            tileRegion(cell, size: cellSize), color: Palette.grid, radius: 3, width: 0.5)
          if let kind = game.cell(x: column, y: row) {
            tile(cell, kind: kind, size: cellSize, into: &context)
          }
        }
      }
      if let ghost = game.ghost {
        for cell in ghost.cells {
          context.strokeRect(
            tileRegion(cell, size: cellSize), color: Palette.color(ghost.kind),
            radius: 3, width: 1.5)
        }
      }
      if let active = game.active {
        for cell in active.cells { tile(cell, kind: active.kind, size: cellSize, into: &context) }
      }

    }
  }

  static func drawPreview(_ kind: Tetromino, into context: inout UIPaintContext) {
    let cells = kind.cells
    let minX = cells.map(\.x).min() ?? 0
    let minY = cells.map(\.y).min() ?? 0
    let maxX = cells.map(\.x).max() ?? 0
    let maxY = cells.map(\.y).max() ?? 0
    let tileSize: Float = 16
    let width = Float(maxX - minX + 1) * tileSize
    let height = Float(maxY - minY + 1) * tileSize
    let center = context.region.center
    context.withOrigin(x: center.x - width / 2, y: center.y - height / 2) { context in
      for cell in cells {
        tile(Cell(cell.x - minX, cell.y - minY), kind: kind, size: tileSize, into: &context)
      }
    }
  }

  private static func tileRegion(_ cell: Cell, size: Float) -> Region {
    Region(Float(cell.x) * size + 1, Float(cell.y) * size + 1, size - 2, size - 2)
  }

  private static func tile(
    _ cell: Cell, kind: Tetromino, size: Float, into context: inout UIPaintContext
  ) {
    let region = tileRegion(cell, size: size)
    context.fillRect(region, color: Palette.color(kind), radius: 3)
    context.fillRect(
      Region(region.x + 2, region.y + 2, region.width - 4, 2),
      color: Color(1, 1, 1, 0.28), radius: 1)
  }
}
