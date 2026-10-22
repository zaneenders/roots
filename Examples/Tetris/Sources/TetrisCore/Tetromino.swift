/// Integer board coordinates. The origin is the upper-left cell; y increases downwards.
public struct Cell: Equatable, Sendable {
  public var x: Int
  public var y: Int

  public init(_ x: Int, _ y: Int) {
    self.x = x
    self.y = y
  }
}

public enum Tetromino: CaseIterable, Sendable {
  case i, o, t, s, z, j, l

  public var cells: [Cell] {
    switch self {
    case .i: [Cell(0, 1), Cell(1, 1), Cell(2, 1), Cell(3, 1)]
    case .o: [Cell(1, 0), Cell(2, 0), Cell(1, 1), Cell(2, 1)]
    case .t: [Cell(1, 0), Cell(0, 1), Cell(1, 1), Cell(2, 1)]
    case .s: [Cell(1, 0), Cell(2, 0), Cell(0, 1), Cell(1, 1)]
    case .z: [Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(2, 1)]
    case .j: [Cell(0, 0), Cell(0, 1), Cell(1, 1), Cell(2, 1)]
    case .l: [Cell(2, 0), Cell(0, 1), Cell(1, 1), Cell(2, 1)]
    }
  }
}

public struct Piece: Equatable, Sendable {
  public var kind: Tetromino
  public var origin: Cell
  public var rotation: Int

  public init(_ kind: Tetromino, origin: Cell = Cell(3, 0), rotation: Int = 0) {
    self.kind = kind
    self.origin = origin
    self.rotation = ((rotation % 4) + 4) % 4
  }

  public var cells: [Cell] {
    kind.cells.map { cell in
      var cell = cell
      if kind != .o {
        let side = kind == .i ? 4 : 3
        for _ in 0..<rotation { cell = Cell(side - 1 - cell.y, cell.x) }
      }
      return Cell(cell.x + origin.x, cell.y + origin.y)
    }
  }

  func moved(x: Int = 0, y: Int = 0) -> Self {
    var piece = self
    piece.origin.x += x
    piece.origin.y += y
    return piece
  }
}

/// A deliberately small, reproducible randomizer: every bag contains all seven kinds.
struct SevenBag: Sendable {
  private var state: UInt64
  private var remaining: [Tetromino] = []

  init(seed: UInt64) { state = seed }

  mutating func draw() -> Tetromino {
    if remaining.isEmpty {
      remaining = Tetromino.allCases
      for index in stride(from: remaining.count - 1, through: 1, by: -1) {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        remaining.swapAt(index, Int(value % UInt64(index + 1)))
      }
    }
    return remaining.removeLast()
  }
}
