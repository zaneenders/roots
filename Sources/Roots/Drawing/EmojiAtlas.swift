import Foundation

public struct EmojiAtlas: Sendable {
  public struct MipLevel: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
  }

  public static let shared: EmojiAtlas = {
    do {
      guard let url = Bundle.module.url(forResource: "EmojiAtlas", withExtension: "atlas")
      else { preconditionFailure("Missing bundled emoji atlas") }
      return try EmojiAtlas(data: Data(contentsOf: url))
    } catch {
      preconditionFailure("Invalid bundled emoji atlas: \(error)")
    }
  }()

  public let mipLevels: [MipLevel]
  private let indices: [Character: Int]
  private let preferred: Set<Character>
  public var width: Int { mipLevels[0].width }
  public var height: Int { mipLevels[0].height }

  enum AssetError: Error { case invalidAtlas }

  init(data: Data) throws(AssetError) {
    var cursor = 0
    let bytes = data.bytes
    func word() throws(AssetError) -> UInt32 {
      guard bytes.byteCount - cursor >= 4 else { throw .invalidAtlas }
      defer { cursor += 4 }
      return bytes.load(fromByteOffset: cursor, as: UInt32.self, .littleEndian)
    }
    guard try word() == 0x4C54_4145, try word() == 2 else { throw .invalidAtlas }
    let width = Int(try word())
    let height = Int(try word())
    let count = Int(try word())
    let cells = Int(try word())
    guard width == 2688, height > 0, height <= 8192, height % 48 == 0,
      cells > 0, cells <= (height / 48) * 64, count > 0, count <= 20_000
    else { throw .invalidAtlas }
    var indices: [Character: Int] = [:]
    var preferred: Set<Character> = []
    for _ in 0..<count {
      let size = Int(try word())
      guard size > 0, size <= 128, bytes.byteCount - cursor >= size else { throw .invalidAtlas }
      let input = Span<UInt8>(viewing: bytes.extracting(cursor..<(cursor + size)))
      let utf8 = [UInt8](capacity: size) { output in
        for byte in input { output.append(byte) }
      }
      guard let text = String(bytes: utf8, encoding: .utf8) else { throw .invalidAtlas }
      cursor += size
      let index = Int(try word())
      guard text.count == 1, text.unicodeScalars.count <= 16, let character = text.first,
        index < cells,
        !text.unicodeScalars.contains("\u{FFFD}"),
        indices.updateValue(index, forKey: character) == nil
      else { throw .invalidAtlas }
      if text.unicodeScalars.count > 1 || text.unicodeScalars.first!.properties.isEmojiPresentation
      {
        preferred.insert(character)
      }
    }
    for (character, index) in Array(indices) {
      let scalars = Array(character.unicodeScalars)
      if scalars.count == 1 {
        let alias = Character(String(character) + "\u{FE0F}")
        indices[alias] = index
        preferred.insert(alias)
      } else {
        var aliases = [""]
        for (offset, scalar) in scalars.enumerated() {
          aliases = aliases.map { $0 + String(scalar) }
          if scalar.properties.isEmoji, scalar.value != 0x200D,
            !(0x1F1E6...0x1F1FF).contains(scalar.value),
            !(0x1F3FB...0x1F3FF).contains(scalar.value),
            offset + 1 == scalars.count || !(0x1F3FB...0x1F3FF).contains(scalars[offset + 1].value)
          {
            aliases += aliases.map { $0 + "\u{FE0F}" }
          }
        }
        for alias in aliases where alias.count == 1 {
          let key = Character(alias)
          indices[key] = index
          preferred.insert(key)
        }
      }
    }
    var levels: [MipLevel] = []
    var w = width
    var h = height
    while true {
      let size = w * h * 4
      guard bytes.byteCount - cursor >= size else { throw .invalidAtlas }
      let pixels = Array(data[cursor..<(cursor + size)])
      levels.append(MipLevel(width: w, height: h, pixels: pixels))
      cursor += size
      if w == 1 && h == 1 { break }
      w = max(1, w / 2)
      h = max(1, h / 2)
    }
    guard cursor == bytes.byteCount else { throw .invalidAtlas }
    self.mipLevels = levels
    self.indices = indices
    self.preferred = preferred
  }

  public func contains(_ character: Character) -> Bool { indices[character] != nil }

  func renders(_ character: Character) -> Bool {
    preferred.contains(character)
      || (indices[character] != nil && !FontAtlas.shared.contains(character))
  }

  public func preferredGlyphUV(_ character: Character) -> Rect? {
    guard preferred.contains(character) else { return nil }
    return glyphUV(character)
  }

  public func glyphUV(_ character: Character) -> Rect {
    guard let index = indices[character] else {
      preconditionFailure("EmojiAtlas has no glyph for \(String(character).debugDescription)")
    }
    return Rect(
      Float((index % 64) * 42 + 3) / Float(width),
      Float((index / 64) * 48 + 3) / Float(height),
      36 / Float(width), 42 / Float(height))
  }
}
