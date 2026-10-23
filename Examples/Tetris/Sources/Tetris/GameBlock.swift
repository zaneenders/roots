import Roots
import TetrisCore

struct GameBlock: Block {
  let controller: GameController
  let bounds: Region

  private var cellSize: Float {
    max(8, min(30, (bounds.height - 176) / 20, (bounds.width - 304) / 10))
  }
  private var boardWidth: Float { cellSize * 10 }
  private var boardHeight: Float { cellSize * 20 }
  private var left: Float { max(20, (bounds.width - boardWidth - 264) / 2) }
  private var top: Float { 112 }
  private var sidebar: Region { Region(left + boardWidth + 24, top, 240, boardHeight) }

  var body: some Block {
    ZStack(in: bounds) {
      Column(in: Region(left, 25, boardWidth, 66), gap: 4) {
        Text("ROOTS / PLAYGROUND")
          .size(12)
          .color(Palette.muted)
        Text("TETRIS")
          .size(36)
          .color(Palette.ink)
      }
      Column(in: Region(sidebar.x, 64, sidebar.width, 20)) {
        Text("A little game. Pure Swift.")
          .size(13)
          .color(Palette.muted)
      }
      Column(in: Region(left, top + boardHeight + 20, bounds.width - left, 20)) {
        Text("10 x 20   /   7 shapes   /   one more round")
          .size(12)
          .color(Palette.muted)
      }
      ZStack(in: Region(left, top, boardWidth, boardHeight)) {
        BoardBlock(game: controller.game)
        if controller.game.status != .playing {
          Canvas(key: 10, color: Color(0.03, 0.04, 0.07, 0.86), blocksPointer: true) { _ in }
          Column(gap: 8, alignment: .center) {
            Text(controller.game.status == .paused ? "PAUSED" : "GAME OVER")
              .size(min(26, boardWidth / 7))
              .color(Palette.ink)
            Text(controller.game.status == .paused ? "P to resume" : "R to play again")
              .size(min(14, boardWidth / 12))
              .color(Palette.muted)
          }
        }
      }
      ScrollColumn(key: 9, in: sidebar, gap: 10, showsScrollIndicator: true) {
        Column(gap: 10) {
          Column(gap: 12) {
            Text("UP NEXT")
              .size(12)
            Grid(columns: 3, gap: 0) {
              ForEach(0..<min(3, controller.game.next.count)) { index in
                PiecePreview(kind: controller.game.next[index])
              }
            }
            .frame(width: .fill, height: .fixed(52))
          }
          .padding(14)
          .frame(width: .fill)
          .background(Palette.panel)
          .color(Palette.muted)
          Text("SCORE  \(controller.game.score)")
            .size(20)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(52))
            .background(Palette.panel)
          Text("LEVEL  \(controller.game.level)    LINES  \(controller.game.lines)")
            .size(13)
            .alignment(.leading)
            .padding(horizontal: 12)
            .frame(width: .fill, height: .fixed(36))
            .background(Palette.panel)
          Button(
            key: 6, controller.game.status == .paused ? "Resume  [P]" : "Pause  [P]",
            extent: 42, color: Palette.button, size: 15
          ) {
            controller.togglePause()
          }
          Button(
            key: 7, "New game  [R]", extent: 42, color: Palette.panel,
            size: 15
          ) { controller.restart() }
          Column(gap: 4) {
            Text("HOW TO PLAY")
              .size(12)
              .color(Palette.muted)
            Column(gap: 3) {
              ForEach([
                "Left / Right   Move",
                "Up / X         Rotate CW",
                "Z              Rotate CCW",
                "Down           Soft drop",
                "Space          Hard drop",
                "P / Esc        Pause"
              ]) { row in
                Text(row)
                  .size(12)
                  .color(Palette.ink)
              }
            }
          }
        }
        .frame(width: .fill)
      }
    }
    .background(Palette.background)
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
