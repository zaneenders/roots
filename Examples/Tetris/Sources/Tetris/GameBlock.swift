import Roots
import TetrisCore

struct GameBlock: Block {
  let controller: GameController
  let bounds: Rect

  private var cellSize: Float {
    max(8, min(30, (bounds.height - 176) / 20, (bounds.width - 304) / 10))
  }
  private var boardWidth: Float { cellSize * 10 }
  private var boardHeight: Float { cellSize * 20 }
  private var left: Float { max(20, (bounds.width - boardWidth - 264) / 2) }
  private var top: Float { 112 }
  private var sidebar: Rect { Rect(left + boardWidth + 24, top, 240, boardHeight) }

  var body: some Block {
    ColumnBlock(in: bounds, gap: 0) {
      CanvasBlock(key: 1, extent: bounds.height, color: Palette.background) { paint in
        paint.drawText(
          "ROOTS / PLAYGROUND", x: left, y: 25,
          font: .init(size: 12), color: Palette.muted)
        paint.drawText(
          "TETRIS", x: left - 2, y: 47,
          font: .init(size: 36), color: Palette.ink)
        paint.drawText(
          "A little game. Pure Swift.", x: left + boardWidth + 24, y: 64,
          font: .init(size: 13), color: Palette.muted)
        paint.drawText(
          "10 x 20   /   7 shapes   /   one more round", x: left, y: top + boardHeight + 20,
          font: .init(size: 12), color: Palette.muted)
      }
    }
    ColumnBlock(in: Rect(left, top, boardWidth, boardHeight), gap: 0) {
      CanvasBlock(key: 2, extent: boardHeight, color: Palette.well) { paint in
        BoardPainter.draw(controller.game, into: &paint, cellSize: cellSize)
      }
    }
    ScrollColumnBlock(key: 9, in: sidebar, gap: 10, showsScrollIndicator: true) {
      CanvasBlock(key: 3, extent: 110, color: Palette.panel) { paint in
        BoardPainter.drawNext(controller.game.next, into: &paint)
      }
      LabelBlock(
        key: 4, "SCORE  \(controller.game.score)", extent: 52,
        color: Palette.panel, font: .init(size: 20), selectable: false)
      LabelBlock(
        key: 5, "LEVEL  \(controller.game.level)    LINES  \(controller.game.lines)", extent: 36,
        color: Palette.panel, font: .init(size: 13), selectable: false)
      ButtonBlock(
        key: 6, controller.game.status == .paused ? "Resume  [P]" : "Pause  [P]",
        extent: 42, color: Palette.button, font: .init(size: 15)
      ) {
        controller.togglePause()
      }
      ButtonBlock(
        key: 7, "New game  [R]", extent: 42, color: Palette.panel,
        font: .init(size: 15)
      ) { controller.restart() }
      CanvasBlock(key: 8, extent: 160, color: Palette.background) { paint in
        let x = paint.rect.x + 2
        let y = paint.rect.y + 8
        paint.drawText("HOW TO PLAY", x: x, y: y, font: .init(size: 12), color: Palette.muted)
        let rows = [
          "Left / Right   Move", "Up / X         Rotate CW", "Z              Rotate CCW",
          "Down           Soft drop", "Space          Hard drop", "P / Esc        Pause"
        ]
        for (index, row) in rows.enumerated() {
          paint.drawText(
            row, x: x, y: y + 25 + Float(index) * 20,
            font: .init(size: 12), color: Palette.ink)
        }
      }
    }
  }
}

enum Palette {
  static let background = Color(0.055, 0.068, 0.10)
  static let well = Color(0.035, 0.045, 0.075)
  static let panel = Color(0.095, 0.115, 0.16)
  static let button = Color(0.10, 0.30, 0.30)
  static let grid = Color(0.11, 0.14, 0.20)
  static let ink = Color(0.91, 0.94, 0.98)
  static let muted = Color(0.51, 0.60, 0.72)

  static func color(_ kind: Tetromino) -> Color {
    switch kind {
    case .i: Color(0.29, 0.82, 0.88)
    case .o: Color(0.97, 0.80, 0.32)
    case .t: Color(0.70, 0.49, 0.95)
    case .s: Color(0.40, 0.81, 0.55)
    case .z: Color(0.95, 0.39, 0.48)
    case .j: Color(0.34, 0.56, 0.96)
    case .l: Color(0.98, 0.61, 0.31)
    }
  }
}

@MainActor
enum BoardPainter {
  static func draw(_ game: Game, into paint: inout UIPaintContext, cellSize: Float) {
    let rect = paint.rect
    paint.withOrigin(x: rect.x, y: rect.y) { paint in
      for row in 0..<Game.height {
        for column in 0..<Game.width {
          let cell = Cell(column, row)
          paint.strokeRect(
            tileRect(cell, size: cellSize), color: Palette.grid, radius: 3, width: 0.5)
          if let kind = game.cell(x: column, y: row) {
            tile(cell, kind: kind, size: cellSize, into: &paint)
          }
        }
      }
      if let ghost = game.ghost {
        for cell in ghost.cells {
          paint.strokeRect(
            tileRect(cell, size: cellSize), color: Palette.color(ghost.kind),
            radius: 3, width: 1.5)
        }
      }
      if let active = game.active {
        for cell in active.cells { tile(cell, kind: active.kind, size: cellSize, into: &paint) }
      }
      if game.status != .playing {
        let width = cellSize * 10
        let height = cellSize * 20
        paint.fillRect(Rect(0, 0, width, height), color: Color(0.03, 0.04, 0.07, 0.86))
        let title = game.status == .paused ? "PAUSED" : "GAME OVER"
        let detail = game.status == .paused ? "P to resume" : "R to play again"
        let titleFont = MonospaceFont(size: min(26, width / 7))
        let detailFont = MonospaceFont(size: min(14, width / 12))
        paint.drawText(
          title, x: (width - Float(title.count) * titleFont.advance) / 2,
          y: height / 2 - 26, font: titleFont, color: Palette.ink)
        paint.drawText(
          detail, x: (width - Float(detail.count) * detailFont.advance) / 2,
          y: height / 2 + 14, font: detailFont, color: Palette.muted)
      }
    }
  }

  static func drawNext(_ pieces: [Tetromino], into paint: inout UIPaintContext) {
    let rect = paint.rect
    paint.drawText(
      "UP NEXT", x: rect.x + 14, y: rect.y + 12,
      font: .init(size: 12), color: Palette.muted)
    for (index, kind) in pieces.prefix(3).enumerated() {
      let cells = kind.cells
      let minX = cells.map(\.x).min() ?? 0
      let minY = cells.map(\.y).min() ?? 0
      let maxX = cells.map(\.x).max() ?? 0
      let tileSize: Float = 16
      let x = rect.x + 10 + Float(index) * 75 + (70 - Float(maxX - minX + 1) * tileSize) / 2
      paint.withOrigin(x: x, y: rect.y + 48) { paint in
        for cell in cells {
          tile(Cell(cell.x - minX, cell.y - minY), kind: kind, size: tileSize, into: &paint)
        }
      }
    }
  }

  private static func tileRect(_ cell: Cell, size: Float) -> Rect {
    Rect(Float(cell.x) * size + 1, Float(cell.y) * size + 1, size - 2, size - 2)
  }

  private static func tile(
    _ cell: Cell, kind: Tetromino, size: Float, into paint: inout UIPaintContext
  ) {
    let rect = tileRect(cell, size: size)
    paint.fillRect(rect, color: Palette.color(kind), radius: 3)
    paint.fillRect(
      Rect(rect.x + 2, rect.y + 2, rect.width - 4, 2),
      color: Color(1, 1, 1, 0.28), radius: 1)
  }
}
