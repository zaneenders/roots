struct MonospaceFont: Equatable, Sendable {
  let size: Float

  init(size: Float = 20) {
    precondition(size > 0 && (size * 1.6).isFinite)
    self.size = size
  }

  var glyphWidth: Float { size }
  var glyphHeight: Float { size * 1.4 }
  // The atlas baseline is row 68 minus 3 rows of padding, at a 60-pixel font size.
  var baseline: Float { size * (65 / 60) }
  var advance: Float { size * 0.6 }
  var lineHeight: Float { size * 1.6 }

  static func columnWidth(of character: Character) -> Int {
    guard character.asciiValue == nil else { return 1 }
    return EmojiAtlas.shared.renders(character) ? 2 : 1
  }

  static func columnCount(of text: some StringProtocol) -> Int {
    text.reduce(0) { $0 + columnWidth(of: $1) }
  }

  static func prefixEnd(in text: some StringProtocol, columns: Int) -> String.Index {
    guard columns > 0 else { return text.startIndex }
    if text.utf8.prefix(columns == .max ? columns : columns + 1).allSatisfy({ $0 < 128 }) {
      return text.index(text.startIndex, offsetBy: max(0, columns), limitedBy: text.endIndex)
        ?? text.endIndex
    }
    var used = 0
    for index in text.indices {
      used += columnWidth(of: text[index])
      if used > columns { return index }
    }
    return text.endIndex
  }

  func offset(in text: some StringProtocol, atX x: Float) -> Int {
    guard !x.isNaN, x > 0 else { return 0 }
    var columns = 0
    var offset = 0
    for character in text {
      let width = Self.columnWidth(of: character)
      if x < (Float(columns) + Float(width) / 2) * advance { return offset }
      columns += width
      offset += 1
    }
    return offset
  }

  func width(of text: some StringProtocol) -> Float {
    var longestLine = 0
    var lineLength = 0
    for character in text {
      if character == "\n" {
        longestLine = max(longestLine, lineLength)
        lineLength = 0
      } else {
        lineLength += Self.columnWidth(of: character)
      }
    }
    return Float(max(longestLine, lineLength)) * advance
  }

  func height(of text: String) -> Float {
    glyphHeight + Float(text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }) * lineHeight
  }

  func truncating(_ text: String, to width: Float) -> String {
    guard !width.isNaN, width >= glyphWidth else { return "" }
    if width == .infinity { return text }
    let capacity = Int(min(Float(Int32.max), ((width - glyphWidth) / advance).rounded(.down))) + 1
    let emojiCapacity = Int(min(Float(Int32.max), (width / advance).rounded(.down)))
    var result = ""
    var copyStart = text.startIndex
    var ellipsisIndex = text.startIndex
    var lineColumns = 0
    var overflowed = false
    for index in text.indices {
      if text[index] == "\n" {
        if overflowed { copyStart = index }
        lineColumns = 0
        overflowed = false
      } else {
        let columns = Self.columnWidth(of: text[index])
        let next = lineColumns + columns
        if lineColumns <= capacity - 1 { ellipsisIndex = index }
        if !overflowed, next > (columns == 2 ? emojiCapacity : capacity) {
          result.append(contentsOf: text[copyStart..<ellipsisIndex])
          result.append("…")
          overflowed = true
        }
        lineColumns = next
      }
    }
    guard !result.isEmpty else { return text }
    if !overflowed { result.append(contentsOf: text[copyStart...]) }
    return result
  }

  func columns(in width: Float) -> Int {
    guard width.isFinite else { return 1 }
    return Int(max(1, min(Float(Int32.max), (width / advance).rounded(.down))))
  }
}
