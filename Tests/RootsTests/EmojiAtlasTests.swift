import Foundation
import Testing

@testable import Roots

@Test func bundledEmojiAtlasHasCoverageMipsAndSequences() {
  let atlas = EmojiAtlas.shared
  #expect(atlas.width == 2688)
  #expect(atlas.height % 48 == 0 && atlas.height <= 8192)
  #expect(atlas.mipLevels.count == 12)
  var width = atlas.width
  var height = atlas.height
  for mip in atlas.mipLevels {
    #expect(mip.width == width && mip.height == height)
    #expect(mip.pixels.count == width * height * 4)
    width = max(1, width / 2)
    height = max(1, height / 2)
  }
  for character: Character in ["🙂", "👍", "🚀", "❤️", "©️", "👩‍💻", "🇳🇿", "👍🏽", "1️⃣", "🏳️‍🌈", "👨‍👩‍👧‍👦"] {
    #expect(atlas.contains(character), "Missing \(character)")
  }
  #expect(!atlas.contains("A"))
  #expect(!atlas.contains("☀︎"))
  #expect(atlas.glyphUV("❤") == atlas.glyphUV("❤️"))
  #expect(atlas.glyphUV("👩‍💻") != atlas.glyphUV("👩"))
  #expect(atlas.glyphUV("👍🏽") != atlas.glyphUV("👍"))
}

@Test func emojiInkFitsTwoColumnsAndLeavesAGutter() {
  let atlas = EmojiAtlas.shared
  let mip = atlas.mipLevels[0]
  for character in "🙂👍🚀❤️✅🤖👩‍💻🇳🇿👍🏽1️⃣🏳️‍🌈👨‍👩‍👧‍👦" {
    let uv = atlas.glyphUV(character)
    #expect(abs(uv.width * Float(atlas.width) - 36) < 0.01)
    #expect(abs(uv.height * Float(atlas.height) - 42) < 0.01)
    let x0 = Int((uv.x * Float(atlas.width)).rounded())
    let y0 = Int((uv.y * Float(atlas.height)).rounded())
    var occupied: [Int] = []
    for x in 0..<36 {
      if (0..<42).contains(where: { mip.pixels[((y0 + $0) * mip.width + x0 + x) * 4 + 3] != 0 }) {
        occupied.append(x)
      }
    }
    #expect(!occupied.isEmpty)
    #expect(occupied.allSatisfy { (1..<35).contains($0) })
    #expect(occupied.count <= 32)
  }
}

@Test func emojiAtlasRejectsMalformedData() throws {
  var data = Data()
  func append(_ word: UInt32) {
    for shift in stride(from: 0, to: 32, by: 8) {
      data.append(UInt8(truncatingIfNeeded: word >> shift))
    }
  }
  for word: UInt32 in [0x4C54_4145, 2, 2688, 48, 1, 1, 4] { append(word) }
  data.append(contentsOf: "🙂".utf8)
  append(0)
  var width = 2688
  var height = 48
  while true {
    data.append(Data(repeating: 0, count: width * height * 4))
    if width == 1 && height == 1 { break }
    width = max(1, width / 2)
    height = max(1, height / 2)
  }
  #expect(try EmojiAtlas(data: data).contains("🙂"))
  for cut in [0, 4, 23, 27, 31, 35, data.count - 1] {
    #expect(throws: EmojiAtlas.AssetError.self) { _ = try EmojiAtlas(data: Data(data.prefix(cut))) }
  }
  for (offset, word): (Int, UInt32) in [
    (0, 0), (4, 1), (8, 0), (12, 8193), (16, .max), (20, 0), (24, 129), (28, .max), (32, 1)
  ] {
    var corrupt = data
    for byte in 0..<4 { corrupt[offset + byte] = UInt8(truncatingIfNeeded: word >> (byte * 8)) }
    #expect(throws: EmojiAtlas.AssetError.self) { _ = try EmojiAtlas(data: corrupt) }
  }
  #expect(throws: EmojiAtlas.AssetError.self) { _ = try EmojiAtlas(data: data + Data([0])) }
}

@Test func presentationAwareTextDrawsKeepOneQuadAndAdvancePerGrapheme() {
  let text = "A🙂👍❤️👩‍💻🇳🇿👍🏽1️⃣🏳️‍🌈✔✔️☀︎你"
  let font = MonospaceFont(size: 20)
  var storage = UIStorage(nodeCapacity: 0, drawCapacity: nil)
  let end = storage.drawText(text, x: 2, y: 3, font: font, color: .text, clip: nil)
  #expect(storage.draws.count == text.count)
  #expect(end == 2 + font.width(of: text))
  for (index, character) in text.enumerated() {
    let color = character != "A" && character != "✔" && character != "☀︎" && character != "你"
    #expect(storage.draws[index].colorGlyph == color, "\(character)")
    #expect(storage.draws[index].rect.width == (color ? 2 * font.advance : font.glyphWidth))
    #expect(storage.draws[index].rect.x == 2 + font.width(of: text.prefix(index)))
  }
}
