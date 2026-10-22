import CFreeType
import Foundation

@main
struct EmojiAtlasGenerator {
  static let cellWidth = 42
  static let cellHeight = 48
  static let glyphWidth = 36
  static let glyphHeight = 42
  static let pad = 3
  static let columns = 64

  static func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else {
      writeStderr(
        "usage: EmojiAtlasGenerator <NotoColorEmoji.ttf> <sequences.txt> <output.atlas>\n")
      exit(2)
    }
    let fontURL = URL(fileURLWithPath: arguments[1])
    let sequenceURL = URL(fileURLWithPath: arguments[2])
    let outputURL = URL(fileURLWithPath: arguments[3])

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
    let fixedSizes = Int(unsafe face.pointee.num_fixed_sizes)
    guard fixedSizes > 0, unsafe FT_Select_Size(face, FT_Int(fixedSizes - 1)) == 0 else {
      throw GeneratorError.freeType("no embedded bitmap strike")
    }

    var entries: [(String, FT_UInt)] = []
    var glyphIndex = FT_UInt(0)
    var code = unsafe FT_Get_First_Char(face, &glyphIndex)
    while glyphIndex != 0 {
      if isEmojiScalar(code), let scalar = UnicodeScalar(UInt32(code)) {
        entries.append((String(scalar), glyphIndex))
      }
      code = unsafe FT_Get_Next_Char(face, code, &glyphIndex)
    }
    let text = try String(contentsOf: sequenceURL, encoding: .utf8)
    for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
      let fields = line.split(separator: ";")
      guard fields.count == 2, let glyph = FT_UInt(fields[0]),
        glyph > 0, glyph < (unsafe face.pointee.num_glyphs)
      else { throw GeneratorError.invalidSequences }
      let scalars = fields[1].split(separator: " ").compactMap {
        UInt32($0, radix: 16).flatMap(UnicodeScalar.init)
      }
      let sequence = String(String.UnicodeScalarView(scalars))
      guard scalars.count > 1 else { throw GeneratorError.invalidSequences }
      guard sequence.count == 1 else { continue }
      entries.append((sequence, glyph))
    }
    var cells: [[UInt8]] = []
    var cellIndices: [FT_UInt: Int] = [:]
    for (_, glyph) in entries where cellIndices[glyph] == nil {
      cellIndices[glyph] = cells.count
      cells.append(try unsafe render(glyph, face: face))
    }
    let rows = (cells.count + columns - 1) / columns
    let width = columns * cellWidth
    let height = rows * cellHeight
    var out: [UInt8] = []
    func append(_ value: UInt32) {
      out.append(UInt8(value & 0xFF))
      out.append(UInt8((value >> 8) & 0xFF))
      out.append(UInt8((value >> 16) & 0xFF))
      out.append(UInt8((value >> 24) & 0xFF))
    }
    out.append(contentsOf: [0x45, 0x41, 0x54, 0x4C])
    append(2)
    append(UInt32(width))
    append(UInt32(height))
    append(UInt32(entries.count))
    append(UInt32(cells.count))
    for (sequence, glyph) in entries {
      append(UInt32(sequence.utf8.count))
      out.append(contentsOf: sequence.utf8)
      append(UInt32(cellIndices[glyph]!))
    }
    var level = [UInt8](repeating: 0, count: width * height * 4)
    for (index, cell) in cells.enumerated() {
      let cellX = (index % columns) * cellWidth
      let cellY = (index / columns) * cellHeight
      for y in 0..<cellHeight {
        let base = ((cellY + y) * width + cellX) * 4
        let source = y * cellWidth * 4
        for x in 0..<cellWidth {
          level[base + x * 4] = cell[source + x * 4]
          level[base + x * 4 + 1] = cell[source + x * 4 + 1]
          level[base + x * 4 + 2] = cell[source + x * 4 + 2]
          level[base + x * 4 + 3] = cell[source + x * 4 + 3]
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
      var next = [UInt8](repeating: 0, count: nextW * nextH * 4)
      for y in 0..<nextH {
        for x in 0..<nextW {
          let sx = min(w - 1, x * 2)
          let sy = min(h - 1, y * 2)
          for channel in 0..<4 {
            let sum =
              Int(level[(sy * w + sx) * 4 + channel])
              + Int(level[(sy * w + min(w - 1, sx + 1)) * 4 + channel])
              + Int(level[(min(h - 1, sy + 1) * w + sx) * 4 + channel])
              + Int(level[(min(h - 1, sy + 1) * w + min(w - 1, sx + 1)) * 4 + channel])
            next[(y * nextW + x) * 4 + channel] = UInt8((sum + 2) >> 2)
          }
        }
      }
      level = next
      w = nextW
      h = nextH
    }
    writeStderr(
      "EmojiAtlasGenerator: \(entries.count) graphemes, \(cells.count) emoji cells, atlas \(width)\u{d7}\(height) RGBA\n"
    )
    try Data(out).write(to: outputURL)
  }

  static func isEmojiScalar(_ scalar: FT_ULong) -> Bool {
    guard let scalar = UnicodeScalar(UInt32(scalar)) else { return false }
    return scalar.properties.isEmoji && scalar.value > 0x39
      && !(0x1F1E6...0x1F1FF).contains(scalar.value)
      && !(0x1F3FB...0x1F3FF).contains(scalar.value)
  }

  static func render(_ glyphIndex: FT_UInt, face: FT_Face) throws -> [UInt8] {
    guard unsafe FT_Load_Glyph(face, glyphIndex, FT_Int(FT_LOAD_COLOR)) == 0 else {
      throw GeneratorError.freeType("FT_Load_Glyph failed for glyph \(glyphIndex)")
    }
    let bitmap = unsafe face.pointee.glyph!.pointee.bitmap
    let pixelMode = unsafe bitmap.pixel_mode
    guard pixelMode == FT_PIXEL_MODE_BGRA.rawValue, let buffer = unsafe bitmap.buffer else {
      throw GeneratorError.freeType("no color bitmap for glyph \(glyphIndex)")
    }
    let sourceWidth = Int(unsafe bitmap.width)
    let sourceHeight = Int(unsafe bitmap.rows)
    let pitch = Int(unsafe bitmap.pitch)
    let scale = min(
      Float(glyphWidth) * 0.88 / Float(sourceWidth), Float(glyphHeight) / Float(sourceHeight))
    let targetWidth = Int((Float(sourceWidth) * scale).rounded(.down))
    let targetHeight = Int((Float(sourceHeight) * scale).rounded(.down))
    let offsetX = pad + (glyphWidth - targetWidth) / 2
    let offsetY = pad + (glyphHeight - targetHeight) / 2
    var cell = [UInt8](repeating: 0, count: cellWidth * cellHeight * 4)
    for y in 0..<targetHeight {
      let sourceY0 = Float(y) / scale
      let sourceY1 = Float(y + 1) / scale
      for x in 0..<targetWidth {
        let sourceX0 = Float(x) / scale
        let sourceX1 = Float(x + 1) / scale
        var sum = [Float](repeating: 0, count: 4)
        var weight = Float(0)
        var sy = Int(sourceY0)
        while Float(sy) < sourceY1 && sy < sourceHeight {
          let rowWeight = min(Float(sy + 1), sourceY1) - max(Float(sy), sourceY0)
          var sx = Int(sourceX0)
          while Float(sx) < sourceX1 && sx < sourceWidth {
            let columnWeight = min(Float(sx + 1), sourceX1) - max(Float(sx), sourceX0)
            let w = rowWeight * columnWeight
            let base = sy * pitch + sx * 4
            for channel in 0..<4 { sum[channel] += Float(unsafe buffer[base + channel]) * w }
            weight += w
            sx += 1
          }
          sy += 1
        }
        guard weight > 0 else { continue }
        let cellX = offsetX + x
        let cellY = offsetY + y
        let base = (cellY * cellWidth + cellX) * 4
        for channel in 0..<4 {
          cell[base + channel] = UInt8(max(0, min(255, (sum[channel] / weight).rounded())))
        }
      }
    }
    return cell
  }

  static func writeStderr(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
  }
}

enum GeneratorError: Error {
  case freeType(String)
  case invalidSequences
}
