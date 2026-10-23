public struct TextRun: Sendable {
  public var text: String
  public var color: Color
  public var background: Color?

  public init(_ text: String, color: Color = .text, background: Color? = nil) {
    self.text = text
    self.color = color
    self.background = background
  }
}

public struct TextLine: Sendable {
  public var runs: [TextRun]
  public var x: Float
  public var y: Float
  public var font: MonospaceFont
  public var background: Color?

  public init(
    _ runs: [TextRun], x: Float = 12, y: Float, font: MonospaceFont = MonospaceFont(),
    background: Color? = nil
  ) {
    self.runs = runs
    self.x = x
    self.y = y
    self.font = font
    self.background = background
  }
}

struct TextLayout {
  struct Line {
    var content: TextLine
    var paintRuns: [TextRun]
    var start: Int
    var count: Int
    var columns: [Int]?

    func column(at offset: Int) -> Int {
      guard let columns else { return offset }
      return columns[min(offset, count)] + max(0, offset - count)
    }
    var endUTF8: Int
    var endsInCarriageReturn: Bool
  }
  struct Update {
    var reusedLineCount: Int
    var preservesSelection: Bool
  }

  private var source: [TextLine] = []
  private(set) var lines: [Line] = []
  private(set) var text = ""

  func reuses(_ content: [TextLine]) -> Bool { source.isTriviallyIdentical(to: content) }

  init(_ content: [TextLine]) {
    update(content)
  }

  @discardableResult
  mutating func update(_ content: [TextLine], selectionEnd: Int = 0) -> Update {
    if reuses(content) { return Update(reusedLineCount: lines.count, preservesSelection: true) }
    var prefix = 0
    while prefix < min(source.count, content.count), Self.sameLine(source[prefix], content[prefix]) { prefix += 1 }
    while prefix > 0, lines[prefix - 1].endsInCarriageReturn { prefix -= 1 }
    let keptUTF8 = prefix > 0 ? lines[prefix - 1].endUTF8 : 0
    let keptCount = prefix > 0 ? lines[prefix - 1].start + lines[prefix - 1].count : 0
    var start = keptCount
    lines.removeSubrange(prefix...)
    lines.reserveCapacity(content.count)
    var suffix = ""
    for line in content.dropFirst(prefix) {
      if !lines.isEmpty {
        suffix += "\n"
        if lines.last?.endsInCarriageReturn != true { start += 1 }
      }
      var value = line.runs.first?.text ?? ""
      for run in line.runs.dropFirst() { value += run.text }
      suffix += value
      let count = value.count
      var columns: [Int]?
      var column = 0
      if !value.utf8.allSatisfy({ $0 < 128 }) {
        for (offset, character) in value.enumerated() {
          let width = MonospaceFont.columnWidth(of: character)
          if width == 2, columns == nil { columns = Array(0...offset) }
          column += width
          columns?.append(column)
        }
      }
      lines.append(
        Line(
          content: line, paintRuns: Self.graphemeRuns(line.runs, in: value), start: start,
          count: count,
          columns: columns, endUTF8: keptUTF8 + suffix.utf8.count,
          endsInCarriageReturn: value.last == "\r"))
      start += count
    }
    let preservesSelection =
      selectionEnd <= keptCount
      || suffixPreservesSelection(suffix, afterUTF8: keptUTF8, count: selectionEnd - keptCount)
    let cut = text.utf8.index(text.utf8.startIndex, offsetBy: keptUTF8)
    text.removeSubrange(cut...)
    text += suffix
    source = content
    return Update(reusedLineCount: prefix, preservesSelection: preservesSelection)
  }

  private static func graphemeRuns(_ source: [TextRun], in text: String) -> [TextRun] {
    guard source.count > 1 else { return source }
    var runs = source
    var offset = text.startIndex
    var boundary = offset
    for index in runs.indices {
      let end = text.utf8.index(offset, offsetBy: runs[index].text.utf8.count)
      var next = boundary
      while next < end { text.formIndex(after: &next) }
      if boundary != offset || next != end {
        runs[index].text = String(text[boundary..<next])
      }
      offset = end
      boundary = next
    }
    return runs
  }

  private func suffixPreservesSelection(_ suffix: String, afterUTF8 offset: Int, count: Int) -> Bool {
    let cut = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
    var previous = text[cut...].makeIterator()
    var next = suffix.makeIterator()
    for _ in 0..<count {
      guard let lhs = previous.next(), let rhs = next.next(),
        lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
      else { return false }
    }
    return true
  }

  private static func sameLine(_ lhs: TextLine, _ rhs: TextLine) -> Bool {
    lhs.x == rhs.x && lhs.y == rhs.y && lhs.font == rhs.font && lhs.background == rhs.background
      && (lhs.runs.isTriviallyIdentical(to: rhs.runs)
        || lhs.runs.elementsEqual(rhs.runs) {
          $0.color == $1.color && $0.background == $1.background
            && ($0.text.isTriviallyIdentical(to: $1.text)
              || $0.text.utf8.elementsEqual($1.text.utf8))
        })
  }

  func offset(x: Float, y: Float) -> Int {
    guard x.isFinite, y.isFinite,
      let line = lines.min(by: {
        distance(y, to: $0.content) < distance(y, to: $1.content)
      })
    else { return 0 }
    let column = ((x - line.content.x) / line.content.font.advance).rounded()
    if let columns = line.columns {
      let x = (x - line.content.x) / line.content.font.advance
      let offset =
        (0..<line.count).first { x < Float(columns[$0] + columns[$0 + 1]) / 2 } ?? line.count
      return line.start + offset
    }
    return line.start + Int(max(0, min(Float(line.count), column)))
  }

  private func distance(_ y: Float, to line: TextLine) -> Float {
    max(line.y - y, y - line.y - line.font.glyphHeight, 0)
  }
}
