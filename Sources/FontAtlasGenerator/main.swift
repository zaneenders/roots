import CFreeType
import Foundation

@main
struct FontAtlasGenerator {
  static let cellWidth = 66
  static let cellHeight = 90
  static let glyphWidth = 60
  static let glyphHeight = 84
  static let pad = 3
  static let columns = 32
  static let pixelSize: FT_UInt = 60
  static let baselineRow = 68

  static func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else {
      writeStderr(
        "usage: FontAtlasGenerator <font.ttf> <coverage.txt> <output.atlas>\n")
      exit(2)
    }
    let fontURL = URL(fileURLWithPath: arguments[1])
    let coverageURL = URL(fileURLWithPath: arguments[2])
    let outputURL = URL(fileURLWithPath: arguments[3])

    let scalars = try loadCoverage(coverageURL)
    var atlas = Atlas(scalars: scalars)

    var library: FT_Library?
    guard unsafe FT_Init_FreeType(&library) == 0, let library = unsafe library else {
      throw GeneratorError.freeType("FT_Init_FreeType failed")
    }
    defer { unsafe FT_Done_FreeType(library) }
    var face: FT_Face?
    let faceError = fontURL.path.withCString { pointer in
      unsafe FT_New_Face(library, pointer, 0, &face)
    }
    guard faceError == 0, let face = unsafe face else {
      throw GeneratorError.freeType("FT_New_Face failed with \(faceError)")
    }
    defer { unsafe FT_Done_Face(face) }
    guard unsafe FT_Select_Charmap(face, FT_ENCODING_UNICODE) == 0 else {
      throw GeneratorError.freeType("no unicode charmap")
    }
    guard unsafe FT_Set_Pixel_Sizes(face, 0, pixelSize) == 0 else {
      throw GeneratorError.freeType("FT_Set_Pixel_Sizes failed")
    }

    var fontRendered = 0
    var symbolRendered = 0
    for (index, scalar) in scalars.enumerated() {
      if (0x2800...0x28FF).contains(scalar) {
        atlas.paste(Self.brailleCell(scalar), index: index)
        continue
      }
      if unsafe FT_Get_Char_Index(face, scalar) == 0,
        let cell = SymbolGlyphs.cell(for: UInt32(scalar))
      {
        atlas.paste(cell, index: index)
        symbolRendered += 1
        continue
      }
      atlas.paste(try unsafe render(scalar, face: face), index: index)
      fontRendered += 1
    }
    writeStderr(
      "FontAtlasGenerator: \(scalars.count) cells (\(fontRendered) from typeface, \(symbolRendered) symbols, \(scalars.count - fontRendered - symbolRendered) braille)\n"
    )
    try Data(atlas.encoded()).write(to: outputURL)
  }

  static func writeStderr(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
  }

  static func loadCoverage(_ url: URL) throws -> [FT_ULong] {
    let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    var scalars: [FT_ULong] = []
    var seen = Set<FT_ULong>()
    for line in text.split(whereSeparator: \.isNewline) {
      guard let scalar = FT_ULong(line, radix: 16) else {
        throw GeneratorError.coverage("invalid coverage line: \(line)")
      }
      guard seen.insert(scalar).inserted else {
        throw GeneratorError.coverage("duplicate coverage scalar U+\(String(scalar, radix: 16))")
      }
      scalars.append(scalar)
    }
    guard scalars.contains(0xFFFD) else {
      throw GeneratorError.coverage("coverage must contain U+FFFD")
    }
    return scalars
  }

  static func render(_ scalar: FT_ULong, face: FT_Face) throws -> [UInt8] {
    let glyphIndex = unsafe FT_Get_Char_Index(face, scalar)
    guard glyphIndex != 0 else {
      throw GeneratorError.missingGlyph(scalar)
    }
    guard unsafe FT_Load_Glyph(face, glyphIndex, FT_LOAD_DEFAULT) == 0 else {
      throw GeneratorError.freeType("FT_Load_Glyph failed for U+\(String(scalar, radix: 16))")
    }
    guard let slot = unsafe face.pointee.glyph else {
      throw GeneratorError.freeType("no glyph slot")
    }
    guard unsafe FT_Render_Glyph(slot, FT_RENDER_MODE_NORMAL) == 0 else {
      throw GeneratorError.freeType("FT_Render_Glyph failed for U+\(String(scalar, radix: 16))")
    }
    let bitmap = unsafe slot.pointee.bitmap
    var cell = [UInt8](repeating: 0, count: cellWidth * cellHeight)
    if unsafe bitmap.width == 0 || bitmap.rows == 0 { return cell }
    let pixelMode = unsafe bitmap.pixel_mode
    guard pixelMode == FT_PIXEL_MODE_GRAY.rawValue, let buffer = unsafe bitmap.buffer else {
      throw GeneratorError.freeType("unexpected bitmap for U+\(String(scalar, radix: 16))")
    }
    let width = Int(unsafe bitmap.width)
    let rows = Int(unsafe bitmap.rows)
    let pitch = Int(unsafe bitmap.pitch)
    let left = Int(unsafe slot.pointee.bitmap_left)
    let top = Int(unsafe slot.pointee.bitmap_top)
    for row in 0..<rows {
      let y = baselineRow - top + row
      guard y >= pad, y < pad + glyphHeight else { continue }
      for column in 0..<width {
        let x = pad + left + column
        guard x >= pad, x < pad + glyphWidth else { continue }
        let value = unsafe buffer[row * pitch + column]
        if value > 0 { cell[y * cellWidth + x] = value }
      }
    }
    return cell
  }

  static func brailleCell(_ scalar: FT_ULong) -> [UInt8] {
    let bits = Int(scalar) - 0x2800
    let dotColumns = [12, 12, 12, 26, 26, 26, 12, 26]
    let dotRows = [18, 36, 54, 18, 36, 54, 72, 72]
    let leftDot: [UInt8] = [255, 255, 255, 255, 255, 102]
    let rightDot: [UInt8] = [153, 255, 255, 255, 255, 204]
    var cell = [UInt8](repeating: 0, count: cellWidth * cellHeight)
    for bit in 0..<8 where bits & (1 << bit) != 0 {
      let pattern = bit == 3 || bit == 4 || bit == 5 || bit == 7 ? rightDot : leftDot
      for dy in 0..<9 {
        for dx in 0..<6 {
          cell[(dotRows[bit] + dy) * cellWidth + dotColumns[bit] + dx] = pattern[dx]
        }
      }
    }
    return cell
  }
}

enum GeneratorError: Error {
  case freeType(String)
  case coverage(String)
  case missingGlyph(FT_ULong)
}

struct Atlas {
  let scalars: [FT_ULong]
  let rows: Int
  var cells: [[UInt8]]

  init(scalars: [FT_ULong]) {
    self.scalars = scalars
    self.rows = (scalars.count + FontAtlasGenerator.columns - 1) / FontAtlasGenerator.columns
    self.cells = []
    cells.reserveCapacity(scalars.count)
  }

  mutating func paste(_ cell: [UInt8], index: Int) {
    cells.append(cell)
  }

  func encoded() -> [UInt8] {
    let width = FontAtlasGenerator.columns * FontAtlasGenerator.cellWidth
    let height = rows * FontAtlasGenerator.cellHeight
    var out: [UInt8] = []
    func append(_ value: UInt32) {
      out.append(UInt8(value & 0xFF))
      out.append(UInt8((value >> 8) & 0xFF))
      out.append(UInt8((value >> 16) & 0xFF))
      out.append(UInt8((value >> 24) & 0xFF))
    }
    out.append(contentsOf: [0x43, 0x41, 0x54, 0x4C])
    append(1)
    append(UInt32(width))
    append(UInt32(height))
    append(UInt32(scalars.count))
    for scalar in scalars { append(UInt32(scalar)) }
    var level = [UInt8](repeating: 0, count: width * height)
    for (index, cell) in cells.enumerated() {
      let cellX = (index % FontAtlasGenerator.columns) * FontAtlasGenerator.cellWidth
      let cellY = (index / FontAtlasGenerator.columns) * FontAtlasGenerator.cellHeight
      for y in 0..<FontAtlasGenerator.cellHeight {
        let base = (cellY + y) * width + cellX
        for x in 0..<FontAtlasGenerator.cellWidth {
          level[base + x] = cell[y * FontAtlasGenerator.cellWidth + x]
        }
      }
    }
    var w = width
    var h = height
    while true {
      out.append(contentsOf: level)
      if w == 1 && h == 1 { break }
      let nextW = max(1, w / 2)
      let nextH = max(1, h / 2)
      var next = [UInt8](repeating: 0, count: nextW * nextH)
      for y in 0..<nextH {
        for x in 0..<nextW {
          let sx = min(w - 1, x * 2)
          let sy = min(h - 1, y * 2)
          let sum =
            Int(level[sy * w + sx]) + Int(level[sy * w + min(w - 1, sx + 1)])
            + Int(level[min(h - 1, sy + 1) * w + sx])
            + Int(level[min(h - 1, sy + 1) * w + min(w - 1, sx + 1)])
          next[y * nextW + x] = UInt8((sum + 2) >> 2)
        }
      }
      level = next
      w = nextW
      h = nextH
    }
    return out
  }
}
