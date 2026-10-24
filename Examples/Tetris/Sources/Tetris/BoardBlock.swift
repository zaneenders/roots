import Roots
import TetrisCore

struct BoardBlock: Block {
  let game: Game

  var body: some Block {
    let ghost = game.ghost
    let ghostCells = ghost?.cells ?? []
    let activeCells = game.active?.cells ?? []

    ZStack {
      Rect().radius(7).color(Palette.well)
      CellGrid(columns: Game.width, rows: Game.height) { _ in
        Rect().radius(3).stroke(width: 0.5).color(Palette.grid).padding(1)
          .frame(width: .fill, height: .fill)
      }
      CellGrid(columns: Game.width, rows: Game.height) { cell in
        if let kind = game.cell(x: cell.x, y: cell.y) {
          TileBlock(kind: kind)
        }
      }
      CellGrid(columns: Game.width, rows: Game.height) { cell in
        if let ghost, ghostCells.contains(cell) {
          Rect().radius(3).stroke(width: 1.5).color(Palette.color(ghost.kind))
            .padding(1).frame(width: .fill, height: .fill)
        }
      }
      CellGrid(columns: Game.width, rows: Game.height) { cell in
        if let active = game.active, activeCells.contains(cell) {
          TileBlock(kind: active.kind)
        }
      }
    }
    .frame(width: .fill, height: .fill)
  }
}

struct TileBlock: Block {
  let kind: Tetromino

  var body: some Block {
    ZStack(alignment: .top) {
      Rect().radius(3).color(Palette.color(kind))
      Rect().radius(1).color(Color(1, 1, 1, 0.28))
        .frame(width: .fill, height: .fixed(2))
        .padding(2).frame(width: .fill)
    }
    .padding(1).frame(width: .fill, height: .fill)
  }
}

struct PiecePreview: Block {
  let kind: Tetromino

  var body: some Block {
    let cells = kind.cells
    let minX = cells.map(\.x).min() ?? 0
    let minY = cells.map(\.y).min() ?? 0
    let columns = (cells.map(\.x).max() ?? 0) - minX + 1
    let rows = (cells.map(\.y).max() ?? 0) - minY + 1

    CellGrid(columns: columns, rows: rows) { cell in
      if cells.contains(Cell(cell.x + minX, cell.y + minY)) {
        TileBlock(kind: kind)
      }
    }
    .frame(width: .fixed(Float(columns) * 16), height: .fixed(Float(rows) * 16))
    .frame(width: .fill, height: .fill)
  }
}

private struct CellGrid<Content: Block>: Block {
  let columns: Int
  let rows: Int
  let content: @MainActor (Cell) -> Content

  init(columns: Int, rows: Int, @BlockBuilder content: @escaping @MainActor (Cell) -> Content) {
    self.columns = columns
    self.rows = rows
    self.content = content
  }

  var body: some Block {
    Grid(columns: columns, gap: 0) {
      ForEach(0..<(columns * rows)) { index in
        ZStack {
          content(Cell(index % columns, index / columns))
        }
        .frame(width: .fill, height: .fill)
      }
    }
    .frame(width: .fill, height: .fill)
  }
}
