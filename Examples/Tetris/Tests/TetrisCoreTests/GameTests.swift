import Testing

@testable import TetrisCore

struct GameTests {
  @Test func newGameHasAnEmptyBoardAndThreePreviews() {
    let game = Game(seed: 42)
    #expect(game.board.count == 200)
    #expect(game.board.allSatisfy { $0 == nil })
    #expect(game.active != nil)
    #expect(game.next.count == 3)
    #expect(game.status == .playing)
    #expect(game.score == 0 && game.lines == 0 && game.level == 1)
  }

  @Test func bagsContainEveryPieceAndAreReproducible() {
    var first = SevenBag(seed: 0)
    var second = SevenBag(seed: 0)
    for _ in 0..<20 {
      var seen: [Tetromino] = []
      for _ in 0..<7 {
        let kind = first.draw()
        #expect(kind == second.draw())
        #expect(!seen.contains(kind))
        seen.append(kind)
      }
      #expect(Tetromino.allCases.allSatisfy { seen.contains($0) })
    }
  }

  @Test func movementStopsAtBothWallsAndIgnoresInvalidDirections() throws {
    var game = Game(seed: 42)
    for _ in 0..<20 { game.move(-1) }
    #expect(try #require(game.active).cells.map(\.x).min() == 0)
    let left = game.active
    game.move(-2)
    #expect(game.active == left)
    for _ in 0..<20 { game.move(1) }
    #expect(try #require(game.active).cells.map(\.x).max() == 9)
  }

  @Test func movementCannotOverlapTheStack() {
    var game = Game(seed: 42)
    game.active = Piece(.o)
    game.board[3] = .z
    game.move(-1)
    #expect(game.active == Piece(.o))
  }

  @Test(arguments: Tetromino.allCases)
  func fourRotationsReturnToTheOriginalCells(_ kind: Tetromino) throws {
    var game = Game(seed: 42)
    game.active = Piece(kind, origin: Cell(3, 5))
    let initial = try #require(game.active)
    for _ in 0..<4 { game.rotate() }
    #expect(game.active == initial)
    game.rotate(clockwise: false)
    game.rotate()
    #expect(game.active == initial)
  }

  @Test func squareRotationDoesNotChangeCells() {
    var game = Game(seed: 42)
    game.active = Piece(.o)
    let cells = game.active?.cells
    game.rotate()
    #expect(game.active?.cells == cells)
  }

  @Test func rotationCanNudgeAwayFromAWallAndFloor() throws {
    var game = Game(seed: 42)
    game.active = Piece(.i, origin: Cell(-2, 4), rotation: 1)
    game.rotate()
    let wall = try #require(game.active)
    #expect(wall.rotation == 2 && wall.origin.x == 0)
    #expect(game.fits(wall))
    game.active = Piece(.t, origin: Cell(3, 18))
    game.rotate()
    let floor = try #require(game.active)
    #expect(floor.rotation == 1 && floor.origin.y == 17)
    #expect(game.fits(floor))
  }

  @Test func blockedRotationLeavesPieceUnchanged() throws {
    var game = Game(seed: 42)
    let active = Piece(.t, origin: Cell(3, 5))
    game.active = active
    game.board = Array(repeating: .j, count: 200)
    for cell in active.cells { game.board[cell.y * 10 + cell.x] = nil }
    game.rotate()
    #expect(try #require(game.active) == active)
  }

  @Test func gravityAccumulatesTimeWithoutAwardingDropPoints() {
    var game = Game(seed: 42)
    let initial = game.active
    game.advance(by: 0.4)
    #expect(game.active == initial)
    game.advance(by: 0.4)
    #expect(game.active?.origin.y == (initial?.origin.y ?? 0) + 1)
    #expect(game.score == 0)
  }

  @Test func invalidTimeAndLongStallsAreSafe() {
    var game = Game(seed: 42)
    let initial = game.active
    for dt in [-1.0, .nan, .infinity, 0] { game.advance(by: dt) }
    #expect(game.active == initial)
    game.advance(by: 10_000)
    #expect(game.active?.origin.y == 1)
  }

  @Test func softDropScoresAndLocksWhenBlocked() {
    var game = Game(seed: 42)
    game.active = Piece(.o, origin: Cell(3, 17))
    game.softDrop()
    #expect(game.active?.origin.y == 18)
    #expect(game.score == 1)
    game.softDrop()
    #expect(game.board.compactMap { $0 }.count == 4)
    #expect(game.score == 1)
  }

  @Test func ghostAndHardDropAgreeAndSpawnThePreview() throws {
    var game = Game(seed: 42)
    game.active = Piece(.o)
    let ghost = try #require(game.ghost)
    let next = game.next[0]
    #expect(ghost.origin.y == 18)
    game.hardDrop()
    for cell in ghost.cells { #expect(game.cell(x: cell.x, y: cell.y) == .o) }
    #expect(game.score == 36)
    #expect(game.active?.kind == next && game.next.count == 3)
  }

  @Test func ghostStopsAboveOccupiedCells() throws {
    var game = Game(seed: 42)
    game.active = Piece(.o)
    game.board[10 * 10 + 4] = .i
    let ghost = try #require(game.ghost)
    #expect(ghost.origin.y == 8)
    #expect(game.fits(ghost))
    #expect(!game.fits(ghost.moved(y: 1)))
  }

  @Test func clearingARowCompactsTheBoardAndScores() {
    var game = Game(seed: 42)
    for x in 0..<6 { game.board[19 * 10 + x] = .j }
    game.board[18 * 10] = .t
    game.active = Piece(.i, origin: Cell(6, 18))
    game.hardDrop()
    #expect(game.lines == 1 && game.score == 100)
    #expect(game.cell(x: 0, y: 19) == .t)
    #expect(game.board.compactMap { $0 }.count == 1)
  }

  @Test(arguments: [1, 2, 3, 4])
  func simultaneousClearsUseTheScoringTable(_ rows: Int) {
    var game = Game(seed: 42)
    for y in (20 - rows)..<20 {
      for x in 0..<10 where x != 5 { game.board[y * 10 + x] = .l }
    }
    game.active = Piece(.i, origin: Cell(3, 16), rotation: 1)
    game.hardDrop()
    #expect(game.lines == rows)
    #expect(game.score == [0, 100, 300, 500, 800][rows])
    #expect(game.board.compactMap { $0 }.count == 4 - rows)
  }

  @Test func levelIncreasesAfterTenLinesAndUsesThePreviousLevelForScoring() {
    var game = Game(seed: 42)
    game.lines = 9
    for x in 0..<6 { game.board[19 * 10 + x] = .s }
    game.active = Piece(.i, origin: Cell(6, 18))
    let interval = game.gravityInterval
    game.hardDrop()
    #expect(game.lines == 10 && game.level == 2 && game.score == 100)
    #expect(game.gravityInterval < interval)
    for x in 0..<6 { game.board[19 * 10 + x] = .s }
    game.active = Piece(.i, origin: Cell(6, 18))
    game.hardDrop()
    #expect(game.score == 300)
  }

  @Test func blockedSpawnEndsTheGameWithoutOverwritingTheStack() {
    var game = Game(seed: 42)
    game.next = [.o, .t, .j]
    game.board[4] = .z
    game.active = Piece(.o, origin: Cell(3, 18))
    game.hardDrop()
    #expect(game.status == .gameOver && game.active == nil && game.ghost == nil)
    #expect(game.board[4] == .z)
    let board = game.board
    game.move(1)
    game.rotate()
    game.hardDrop()
    game.togglePause()
    game.advance(by: 1)
    #expect(game.board == board && game.status == .gameOver)
  }

  @Test func pauseFreezesAllGameplayAndDiscardsAccumulatedTime() {
    var game = Game(seed: 42)
    game.advance(by: 0.7)
    game.pause()
    let active = game.active
    game.move(1)
    game.rotate()
    game.softDrop()
    game.hardDrop()
    game.advance(by: 1)
    #expect(game.active == active && game.score == 0 && game.status == .paused)
    game.togglePause()
    game.advance(by: 0.2)
    #expect(game.active == active)
  }

  @Test func restartResetsBoardScoreQueueStatusAndGravity() {
    var game = Game(seed: 42)
    game.hardDrop()
    game.advance(by: 0.7)
    game.pause()
    game.restart()
    let fresh = Game(seed: 42)
    #expect(game.board == fresh.board && game.active == fresh.active && game.next == fresh.next)
    #expect(game.score == 0 && game.lines == 0 && game.status == .playing)
    game.advance(by: 0.2)
    #expect(game.active == fresh.active)
    game.restart(seed: 100)
    #expect(game.active == Game(seed: 100).active)
  }

  @Test func manySeededCommandsKeepAllActiveCellsInBoundsAndOutOfTheStack() {
    for seed: UInt64 in 0..<30 {
      var game = Game(seed: seed)
      for turn in 0..<100 {
        game.move(turn.isMultiple(of: 2) ? -1 : 1)
        game.rotate(clockwise: turn.isMultiple(of: 3))
        game.advance(by: 0.3)
        if let active = game.active { #expect(game.fits(active)) }
        game.hardDrop()
        #expect(game.board.count == 200)
        if game.status == .gameOver { break }
      }
    }
  }
}
