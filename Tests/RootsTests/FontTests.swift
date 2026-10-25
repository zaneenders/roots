import Foundation
import Synchronization
import Testing

@testable import Roots

@Test func bundledAtlasHasCoverageMipsAndFallback() {
  let atlas = FontAtlas.shared
  #expect(atlas.width == 2112 && atlas.height == 4050)
  #expect(atlas.mipLevels.count == 12)
  var width = atlas.width
  var height = atlas.height
  for mip in atlas.mipLevels {
    #expect(mip.width == width && mip.height == height)
    #expect(mip.pixels.count == width * height)
    width = max(1, width / 2)
    height = max(1, height / 2)
  }
  #expect(atlas.mipLevels[0].pixels.contains { $0 > 0 && $0 < 255 })
  #expect(!atlas.contains("🙂"))
  #expect(atlas.glyphUV("🙂") == atlas.glyphUV("�"))
  #expect(atlas.glyphUV("e\u{301}") == atlas.glyphUV("é"))
  #expect(atlas.glyphUV("\u{202F}") == atlas.glyphUV(" "))
}

@Test func typefaceSpaceIsBlank() {
  let atlas = FontAtlas.shared
  let mip = atlas.mipLevels[0]
  let space = atlas.glyphUV(" ")
  let x = Int((space.x * Float(mip.width)).rounded())
  let y = Int((space.y * Float(mip.height)).rounded())
  for row in y..<(y + 84) {
    #expect(mip.pixels[(row * mip.width + x)..<(row * mip.width + x + 60)].allSatisfy { $0 == 0 })
  }
}

@Test func generatedSymbolsHaveInkAndPreserveTextPresentation() throws {
  let atlas = FontAtlas.shared
  let mip = atlas.mipLevels[0]
  let symbols =
    "↵↻⇧⌂⌃⌘⌥⏎⏵⏹✎✓✔✕✖✗➜\u{E0B0}\u{E0B1}\u{E0B2}\u{E0B3}\u{E0B4}\u{E0B6}\u{E0B8}\u{E0BA}\u{E348}\u{EACC}\u{F002}\u{F022}\u{F0C5}\u{F15B}\u{F423}☰👍✘"
  #expect(symbols.count == 35)
  for symbol in symbols {
    try #require(atlas.contains(symbol), "Missing generated symbol \(symbol)")
    let uv = atlas.glyphUV(symbol)
    #expect(uv != atlas.glyphUV("�"))
    let x = Int((uv.x * Float(mip.width)).rounded())
    let y = Int((uv.y * Float(mip.height)).rounded())
    let pixels = (y..<(y + 84)).flatMap { row in
      mip.pixels[(row * mip.width + x)..<(row * mip.width + x + 60)]
    }
    #expect(pixels.contains { $0 > 0 }, "Empty generated symbol \(symbol)")
    #expect(pixels.contains(0), "Solid generated symbol \(symbol)")
    for row in (y - 3)..<(y + 87) {
      for column in (x - 3)..<(x + 63)
      where row < y || row >= y + 84 || column < x || column >= x + 60 {
        #expect(mip.pixels[row * mip.width + column] == 0, "Glyph padding for \(symbol)")
      }
    }
  }
  #expect(!EmojiAtlas.shared.renders("✔"))
  #expect(EmojiAtlas.shared.renders("✔️"))
}

@Test func bundledFontLicenseIncludesBothUpstreamCopyrightNotices() throws {
  let url = try #require(
    Bundle.module.url(forResource: "OFL", withExtension: "txt", subdirectory: "Resources"))
  let license = try String(contentsOf: url, encoding: .utf8)
  #expect(
    license.contains(
      "Copyright 2022 The Noto Project Authors (https://github.com/notofonts/latin-greek-cyrillic)")
  )
  #expect(license.contains("Copyright 2022 Google Inc."))
  #expect(license.contains("SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007"))
}

private func bundledAtlasData() throws -> Data {
  let url = try #require(Bundle.module.url(forResource: "FontAtlas", withExtension: "atlas"))
  return try Data(contentsOf: url)
}

@Test func missingGlyphsLogOnceWithAllScalarsAndPreserveFallback() throws {
  let messages = Mutex<[String]>([])
  let atlas = try FontAtlas(data: bundledAtlasData()) { message in
    messages.withLock { $0.append(message) }
  }
  let copy = atlas
  let fallback = atlas.glyphUV("�")
  for _ in 0..<3 {
    #expect(atlas.glyphUV("🙂") == fallback)
    #expect(copy.glyphUV("👩‍💻") == fallback)
    #expect(copy.glyphUV("🙂") == fallback)
  }
  #expect(
    messages.withLock { $0 } == [
      "Roots: unsupported glyph \"🙂\" (U+1F642); using U+FFFD replacement glyph\n",
      "Roots: unsupported glyph \"👩‍💻\" (U+1F469 U+200D U+1F4BB); using U+FFFD replacement glyph\n"
    ])
}

@Test func unicodeMinusHasInkAndDoesNotUseFallback() throws {
  let messages = Mutex<[String]>([])
  let atlas = try FontAtlas(data: bundledAtlasData()) { message in
    messages.withLock { $0.append(message) }
  }
  try #require(atlas.contains("−"))
  let uv = atlas.glyphUV("−")
  #expect(uv != atlas.glyphUV("�"))
  #expect(uv != atlas.glyphUV("-"))
  #expect(atlas.glyphUV("−\u{FE0E}") == uv)
  let mip = atlas.mipLevels[0]
  let x = Int((uv.x * Float(mip.width)).rounded())
  let y = Int((uv.y * Float(mip.height)).rounded())
  #expect(
    (y..<(y + 84)).contains { row in
      mip.pixels[(row * mip.width + x)..<(row * mip.width + x + 60)].contains { $0 > 0 }
    })
  for character in "−7.0% −4.9%" {
    _ = atlas.glyphUV(character)
  }
  #expect(messages.withLock { $0.isEmpty })
}

@Test func missingControlGlyphsAreEscapedAndUsePaddedCodePoints() throws {
  let messages = Mutex<[String]>([])
  let atlas = try FontAtlas(data: bundledAtlasData()) { message in
    messages.withLock { $0.append(message) }
  }
  #expect(atlas.glyphUV("\n") == atlas.glyphUV("�"))
  #expect(
    messages.withLock { $0 } == [
      "Roots: unsupported glyph \"\\n\" (U+000A); using U+FFFD replacement glyph\n"
    ])
}

@Test func supportedGlyphsAndCoverageChecksDoNotLog() throws {
  let messages = Mutex<[String]>([])
  let atlas = try FontAtlas(data: bundledAtlasData()) { message in
    messages.withLock { $0.append(message) }
  }
  #expect(!atlas.contains("🙂"))
  for character in "Aé�├─└│e\u{301}\u{202F}" {
    #expect(atlas.contains(character))
    _ = atlas.glyphUV(character)
  }
  #expect(atlas.glyphUV("e\u{301}") == atlas.glyphUV("é"))
  #expect(atlas.glyphUV("\u{202F}") == atlas.glyphUV(" "))
  #expect(messages.withLock { $0.isEmpty })
}

@Test func stackedAcuteAccentsHaveTheirOwnGlyphWithoutLogging() throws {
  let messages = Mutex<[String]>([])
  let atlas = try FontAtlas(data: bundledAtlasData()) { message in
    messages.withLock { $0.append(message) }
  }
  let character: Character = "é\u{301}"
  try #require(atlas.contains(character))
  let uv = atlas.glyphUV(character)
  #expect(uv != atlas.glyphUV("�"))
  #expect(uv != atlas.glyphUV("é"))
  #expect(atlas.glyphUV("e\u{301}\u{301}") == uv)
  #expect(atlas.glyphUV("é\u{301}\u{FE0E}") == uv)
  let mip = atlas.mipLevels[0]
  let x = Int((uv.x * Float(mip.width)).rounded())
  let y = Int((uv.y * Float(mip.height)).rounded())
  let base = atlas.glyphUV("é")
  let baseX = Int((base.x * Float(mip.width)).rounded())
  let baseY = Int((base.y * Float(mip.height)).rounded())
  var hasExtraInk = false
  for row in 0..<84 {
    for column in 0..<60 {
      let pixel = mip.pixels[(y + row) * mip.width + x + column]
      let basePixel = mip.pixels[(baseY + row) * mip.width + baseX + column]
      #expect(pixel >= basePixel)
      if pixel > basePixel { hasExtraInk = true }
    }
  }
  #expect(hasExtraInk)
  for row in (y - 3)..<(y + 87) {
    for column in (x - 3)..<(x + 63)
    where row < y || row >= y + 84 || column < x || column >= x + 60 {
      #expect(mip.pixels[row * mip.width + column] == 0)
    }
  }
  var storage = UIStorage(nodeCapacity: 0, drawCapacity: nil)
  let font = MonospaceFont(size: 20)
  let end = storage.drawText(String(character), x: 0, y: 0, font: font, color: .text, clip: nil)
  #expect(end == font.advance)
  #expect(storage.draws.count == 1)
  #expect(storage.draws[0].rectangle.glyphUV == uv)
  #expect(!storage.draws[0].rectangle.colorGlyph)
  #expect(messages.withLock { $0.isEmpty })
}

@Test func concurrentMissingGlyphLookupsLogOnlyOnce() async throws {
  let messages = Mutex<[String]>([])
  let atlas = try FontAtlas(data: bundledAtlasData()) { message in
    messages.withLock { $0.append(message) }
  }
  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<64 {
      group.addTask { _ = atlas.glyphUV("🙂") }
    }
  }
  #expect(messages.withLock { $0.count } == 1)
}

@Test(arguments: [UInt32(1), 2]) func atlasRejectsMalformedData(version: UInt32) throws {
  var data = Data()
  func append(_ word: UInt32) {
    for shift in stride(from: 0, to: 32, by: 8) {
      data.append(UInt8(truncatingIfNeeded: word >> shift))
    }
  }
  for word: UInt32 in [0x4C54_4143, version, 2112, 90, 1] { append(word) }
  if version == 2 { append(1) }
  append(0xFFFD)
  let scalarOffset = version == 1 ? 20 : 24
  var width = 2112
  var height = 90
  while true {
    data.append(Data(repeating: 0, count: width * height))
    if width == 1 && height == 1 { break }
    width = max(1, width / 2)
    height = max(1, height / 2)
  }
  #expect(try FontAtlas(data: data).contains("�"))
  for cut in [0, 4, 19, 23, data.count - 1] {
    #expect(throws: FontAtlas.AssetError.self) { _ = try FontAtlas(data: Data(data.prefix(cut))) }
  }
  var invalidWords: [(Int, UInt32)] = [
    (0, 0), (4, 3), (8, 0), (12, 4097), (16, .max), (scalarOffset, 0xD800), (scalarOffset, 65)
  ]
  if version == 2 { invalidWords += [(20, 0), (20, 17), (20, .max)] }
  for (offset, word) in invalidWords {
    var corrupt = data
    for byte in 0..<4 { corrupt[offset + byte] = UInt8(truncatingIfNeeded: word >> (byte * 8)) }
    #expect(throws: FontAtlas.AssetError.self) { _ = try FontAtlas(data: corrupt) }
  }
  #expect(throws: FontAtlas.AssetError.self) { _ = try FontAtlas(data: data + Data([0])) }
}

@Test func fontMeasurementsAndDrawingShareFractionalSize() {
  let font = MonospaceFont(size: 17.5)
  #expect(font.advance == 10.5)
  #expect(font.glyphHeight == 24.5)
  #expect(font.lineHeight == 28)
  #expect(font.width(of: "Aé🙂\nx") == 42)
  #expect(font.height(of: "Aé🙂\nx") == 52.5)
  #expect(font.columns(in: 31.4) == 2)
  #expect(font.columns(in: 31.5) == 3)
  #expect(font.columns(in: -1) == 1)
  var storage = UIStorage(nodeCapacity: 0, drawCapacity: nil)
  let end = storage.drawText("Aé🙂\nx", x: 2, y: 3, font: font, color: .text, clip: nil)
  #expect(end == 2 + font.advance)
  #expect(storage.draws.count == 4)
  #expect(storage.draws[0].rectangle.region == Region(2, 3, 17.5, 24.5))
  #expect(storage.draws[2].rectangle.colorGlyph == true)
  #expect(storage.draws[2].rectangle.glyphUV == EmojiAtlas.shared.glyphUV("🙂"))
  #expect(storage.draws[3].rectangle.region.y == 3 + font.lineHeight)
}

@Test func explicitFontRefreshesLabelGeometry() {
  var ui = UIStore()
  for size: Float in [15, 22.5, 15] {
    let font = MonospaceFont(size: size)
    ui.frame(
      build: { frame in
        frame.beginColumn(in: Region(0, 0, 200, 100))
        frame.label(key: 1, "A\nA", extent: 100, font: font)
        frame.end()
      },
      present: { draws in
        #expect(draws.count == 3)
        #expect(
          draws[1].rectangle.region == Region(12, (100 - font.height(of: "A\nA")) / 2, size, font.glyphHeight))
        #expect(draws[2].rectangle.region.y == draws[1].rectangle.region.y + font.lineHeight)
        #expect(draws[1].rectangle.glyphUV == draws[2].rectangle.glyphUV)
      })
  }
}

@Test(arguments: [Float(0), -1, .nan, .infinity, .greatestFiniteMagnitude])
func invalidFontSizesAreRejected(size: Float) async {
  let bits = size.bitPattern
  await #expect(processExitsWith: .failure) { [bits = bits as UInt32] in
    await MainActor.run { _ = Button(key: 1, "", size: Float(bitPattern: bits)) }
  }
}

@Test func tailTruncationFitsRasterBoundsAndPreservesGraphemesAndNewlines() {
  let font = MonospaceFont(size: 20)
  #expect(font.truncating("ABCDE", to: 56) == "ABC…")
  #expect(font.truncating("ABCDE", to: 55.5) == "AB…")
  #expect(font.truncating("ABCD", to: 56) == "ABCD")
  #expect(font.truncating("ABCDE", to: 20) == "…")
  #expect(font.truncating("ABCDE", to: 19.5).isEmpty)
  #expect(font.truncating("Aé🙂DE\nB\n", to: 44) == "Aé…\nB\n")
  #expect(font.truncating("ABCDE", to: .infinity) == "ABCDE")
  #expect(font.truncating("ABCDE", to: .nan).isEmpty)
  #expect(font.truncating("ABCDE", to: -1).isEmpty)
  let fractional = MonospaceFont(size: 17.5)
  #expect(fractional.truncating("ABCDE", to: 38.5) == "AB…")
}

@Test func fontWidthCountsGraphemesAndSplitsLFCRLFAndCR() {
  let font = MonospaceFont(size: 17.5)
  for (text, columns) in [
    ("", 0), ("\n\n", 0), ("\nABC\nx\n", 3), ("A\nBC", 2),
    ("e\u{301}👩‍💻🇳🇿", 5), ("\r\n", 0), ("A\r\nB\n", 1), ("A\rB\u{2028}C", 3)
  ] {
    #expect(font.width(of: text) == Float(columns) * font.advance)
  }
}

@Test func tailTruncationKeepsUnchangedSpansAndExtendedGraphemes() {
  let font = MonospaceFont(size: 20)
  for (text, expected) in [
    ("", ""), ("\n\n", "\n\n"), ("ABC\n\nAB\n", "ABC\n\nAB\n"),
    ("e\u{301}👩‍💻🇳🇿X", "e\u{301}…"), ("A\r\nB", "A\r\nB"), ("A\r\nBC", "A\r\nBC"),
    ("ABCD\n", "AB…\n"), ("ABCD\nWXYZ", "AB…\nWX…"),
    ("A\n\nBCDEF\nZ\n12345\n", "A\n\nBC…\nZ\n12…\n")
  ] {
    let truncated = font.truncating(text, to: 44)
    #expect(truncated.utf8.elementsEqual(expected.utf8))
  }
  #expect(font.truncating("\nLONG\n\nTAIL", to: 20) == "\n…\n\n…")
}

@Test func tailTruncationReusesStorageWhenEveryLineFits() {
  let font = MonospaceFont(size: 17.5)
  let line = (0..<40).map { "Label \($0) 👩‍💻" }.joined(separator: " · ")
  let multiline = "\n\(line)\nshort\n\(line)\n\n"
  let width = font.glyphWidth + font.width(of: line)
  for text in [line, multiline] {
    let truncated = font.truncating(text, to: width)
    #expect(truncated.isTriviallyIdentical(to: text))
  }
}

@Test func fontScanningMatchesSplitSemanticsAtWidthBoundaries() {
  let texts = [
    "", "\n", "\n\n", "A", "ABCDE", "\nABCDE", "ABCDE\n", "A\nABCDE\n\nBC\n",
    "ABCDE\nFGHIJ", "e\u{301}👩‍💻🇳🇿👍🏽X", "A\r\nBC\nDE\r\n", "A\rB\u{2028}C",
    "…\nA…B", String(repeating: "A", count: 300), String(repeating: "👩‍💻e\u{301}", count: 100)
  ]
  for size: Float in [
    .leastNonzeroMagnitude, .leastNormalMagnitude, 0.25, 17.5, 20, .greatestFiniteMagnitude / 2
  ] {
    let font = MonospaceFont(size: size)
    var widths: [Float] = [
      -.infinity, -1, -0.0, 0, .leastNonzeroMagnitude, .nan, .infinity, .greatestFiniteMagnitude
    ]
    for columns in 1...6 {
      let boundary = font.glyphWidth + Float(columns - 1) * font.advance
      widths.append(contentsOf: [boundary.nextDown, boundary, boundary.nextUp])
    }
    for text in texts {
      let newlines: Set<Character> = ["\n", "\r\n", "\r"]
      let lines = text.split(omittingEmptySubsequences: false, whereSeparator: newlines.contains)
      let separators = text.filter(newlines.contains).map(String.init)
      #expect(
        font.width(of: text) == Float(lines.map { MonospaceFont.columnCount(of: $0) }.max() ?? 0)
          * font.advance)
      for width in widths {
        let expected: String
        if width.isNaN || width < font.glyphWidth {
          expected = ""
        } else if width == .infinity {
          expected = text
        } else {
          let capacity =
            Int(min(Float(Int32.max), ((width - font.glyphWidth) / font.advance).rounded(.down)))
            + 1
          let truncated = lines.map { line in
            var used = 0
            let fits = line.allSatisfy { character in
              let count = MonospaceFont.columnWidth(of: character)
              used += count
              return count == 2
                ? used <= Int(min(Float(Int32.max), (width / font.advance).rounded(.down)))
                : used <= capacity
            }
            let end = MonospaceFont.prefixEnd(in: line, columns: capacity - 1)
            return fits ? String(line) : String(line[..<end]) + "…"
          }
          expected = truncated.enumerated().map { index, line in
            (index == 0 ? "" : separators[index - 1]) + line
          }.joined()
        }
        #expect(font.truncating(text, to: width).utf8.elementsEqual(expected.utf8))
      }
    }
  }
}

@Test func textOverflowRefreshesEachFrameWithoutAffectingFocusOrFontSize() {
  var ui = UIStore()
  let font = MonospaceFont(size: 20)
  for overflow: TextOverflow in [.truncateTail, .clip, .truncateTail] {
    ui.frame(
      build: { frame in
        frame.beginColumn(in: Region(0, 0, 80, 40))
        let button = frame.button(key: 1, "ABCDE", font: font, textOverflow: overflow)
        frame.focus(button)
        frame.end()
      },
      present: { draws in
        var glyphs: [Region] = []
        for draw in draws.rectangles where draw.glyphUV != nil {
          glyphs.append(draw.region)
          #expect(draw.region.width == font.glyphWidth)
          if overflow == .truncateTail {
            #expect(draw.region.x + draw.region.width <= 68)
            if glyphs.count == 4 { #expect(draw.glyphUV == FontAtlas.shared.glyphUV("…")) }
          }
        }
        #expect(glyphs.count == (overflow == .truncateTail ? 4 : 5))
      })
    #expect(ui.state(for: ui.handle(for: 1)!)?.focused == true)
  }
}

@Test func extendedLatinGreekAndCyrillicUseTheBundledTypeface() {
  for character in "©®ñøǽΩωΔЖЯёж" {
    #expect(FontAtlas.shared.contains(character))
  }
  #expect(FontAtlas.shared.glyphUV("✔︎") == FontAtlas.shared.glyphUV("✔"))
}

@Test func emojiColumnsDriveWidthTruncationAndHitTesting() {
  let font = MonospaceFont(size: 20)
  #expect(font.width(of: "A🙂B") == 48)
  #expect(font.truncating("🙂", to: 24) == "🙂")
  #expect(font.truncating("A🙂B", to: 44) == "A…")
  #expect(font.offset(in: "A🙂B", atX: 13) == 1)
  #expect(font.offset(in: "A🙂B", atX: 23) == 1)
  #expect(font.offset(in: "A🙂B", atX: 25) == 2)
  #expect(MonospaceFont.columnWidth(of: "✔") == 1)
  #expect(MonospaceFont.columnWidth(of: "✔️") == 2)
  #expect(MonospaceFont.columnWidth(of: "☀︎") == 1)
}

@Test func columnPrefixesKeepGraphemeBoundariesAndHandleExtremeBudgets() {
  let text = "Ae\u{301}🙂B"
  for (columns, expected) in [
    (0, ""), (1, "A"), (2, "Ae\u{301}"), (3, "Ae\u{301}"), (4, "Ae\u{301}🙂"), (Int.max, text)
  ] {
    #expect(String(text[..<MonospaceFont.prefixEnd(in: text, columns: columns)]) == expected)
  }
  let ascii = "ABC"
  #expect(MonospaceFont.prefixEnd(in: ascii, columns: .max) == ascii.endIndex)
}

@Test func columnPrefixesCountCRLFGraphemesBeforeWideEmoji() {
  for text in ["", "ABC", "\r\n\r\n🙂", "A\r\n🙂B", "\r🙂", "\n🙂", "\r\n\r\n"] {
    for columns in [-1, 0, 1, 2, 3, 4, 5, Int.max] {
      var expected = ""
      var used = 0
      for character in text {
        let width = MonospaceFont.columnWidth(of: character)
        if width > columns - used { break }
        expected.append(character)
        used += width
      }
      let end = MonospaceFont.prefixEnd(in: text, columns: columns)
      #expect(String(text[..<end]) == expected)
      let padded = "prefix" + text + "suffix"
      let start = padded.index(padded.startIndex, offsetBy: 6)
      let slice = padded[start..<padded.index(start, offsetBy: text.count)]
      let sliceEnd = MonospaceFont.prefixEnd(in: slice, columns: columns)
      #expect(String(slice[..<sliceEnd]) == expected)
    }
  }
  let text = "\r\n\r\n🙂"
  let end = MonospaceFont.prefixEnd(in: text, columns: 3)
  #expect(String(text[..<end]) == "\r\n\r\n")
}
