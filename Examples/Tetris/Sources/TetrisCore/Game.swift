public struct Game: Sendable {
  public static let width = 10
  public static let height = 20

  public enum Status: Equatable, Sendable { case playing, paused, gameOver }

  public internal(set) var board: [Tetromino?]
  public internal(set) var active: Piece?
  public internal(set) var next: [Tetromino]
  public internal(set) var score = 0
  public internal(set) var lines = 0
  public internal(set) var status: Status = .playing
  private var bag: SevenBag
  private var seed: UInt64
  private var elapsed: Double = 0

  public init(seed: UInt64) {
    self.seed = seed
    bag = SevenBag(seed: seed)
    board = Array(repeating: nil, count: Self.width * Self.height)
    next = []
    active = nil
    spawn()
  }

  public var level: Int { lines / 10 + 1 }
  public var gravityInterval: Double { max(0.08, 0.8 - Double(level - 1) * 0.06) }

  public func cell(x: Int, y: Int) -> Tetromino? {
    guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return nil }
    return board[y * Self.width + x]
  }

  public var ghost: Piece? {
    guard var piece = active else { return nil }
    while fits(piece.moved(y: 1)) { piece = piece.moved(y: 1) }
    return piece
  }

  public mutating func move(_ direction: Int) {
    guard status == .playing, direction == -1 || direction == 1, let active else { return }
    let moved = active.moved(x: direction)
    if fits(moved) { self.active = moved }
  }

  public mutating func rotate(clockwise: Bool = true) {
    guard status == .playing, var rotated = active else { return }
    rotated.rotation = (rotated.rotation + (clockwise ? 1 : 3)) % 4
    for offset in [
      Cell(0, 0), Cell(-1, 0), Cell(1, 0), Cell(-2, 0), Cell(2, 0), Cell(0, -1), Cell(0, -2)
    ] {
      let candidate = rotated.moved(x: offset.x, y: offset.y)
      if fits(candidate) {
        active = candidate
        return
      }
    }
  }

  public mutating func softDrop() {
    guard status == .playing, let active else { return }
    let moved = active.moved(y: 1)
    if fits(moved) {
      self.active = moved
      score += 1
      elapsed = 0
    } else {
      lock()
    }
  }

  public mutating func hardDrop() {
    guard status == .playing, let active, let ghost else { return }
    score += (ghost.origin.y - active.origin.y) * 2
    self.active = ghost
    lock()
  }

  public mutating func advance(by seconds: Double) {
    guard status == .playing, seconds.isFinite, seconds > 0 else { return }
    elapsed += min(seconds, 1)
    while elapsed >= gravityInterval, status == .playing, let active {
      elapsed -= gravityInterval
      let moved = active.moved(y: 1)
      if fits(moved) { self.active = moved } else { lock() }
    }
  }

  public mutating func pause() {
    guard status == .playing else { return }
    status = .paused
    elapsed = 0
  }

  public mutating func togglePause() {
    switch status {
    case .playing: pause()
    case .paused: status = .playing
    case .gameOver: break
    }
  }

  public mutating func restart(seed: UInt64? = nil) {
    self = Game(seed: seed ?? self.seed)
  }

  func fits(_ piece: Piece) -> Bool {
    piece.cells.allSatisfy {
      (0..<Self.width).contains($0.x) && (0..<Self.height).contains($0.y)
        && board[$0.y * Self.width + $0.x] == nil
    }
  }

  private mutating func lock() {
    guard let active else { return }
    for cell in active.cells { board[cell.y * Self.width + cell.x] = active.kind }
    let scoringLevel = level
    var kept: [Tetromino?] = []
    for row in 0..<Self.height {
      let cells = board[(row * Self.width)..<((row + 1) * Self.width)]
      if cells.contains(nil) { kept.append(contentsOf: cells) }
    }
    let cleared = (board.count - kept.count) / Self.width
    board = Array(repeating: nil, count: cleared * Self.width) + kept
    score += [0, 100, 300, 500, 800][cleared] * scoringLevel
    lines += cleared
    elapsed = 0
    spawn()
  }

  private mutating func spawn() {
    while next.count < 4 { next.append(bag.draw()) }
    let piece = Piece(next.removeFirst())
    if fits(piece) {
      active = piece
    } else {
      active = nil
      status = .gameOver
    }
  }
}
