import Foundation
import Synchronization

public struct FontAtlas: Sendable {
  public struct MipLevel: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
  }

  public static let shared: FontAtlas = {
    do {
      guard let url = Bundle.module.url(forResource: "FontAtlas", withExtension: "atlas")
      else { preconditionFailure("Missing bundled font atlas") }
      return try FontAtlas(data: Data(contentsOf: url))
    } catch {
      preconditionFailure("Invalid bundled font atlas: \(error)")
    }
  }()

  public let mipLevels: [MipLevel]
  private let indices: [Character: Int]
  private let fallback: Int
  private let missingGlyphLogger: MissingGlyphLogger
  public var width: Int { mipLevels[0].width }
  public var height: Int { mipLevels[0].height }

  enum AssetError: Error { case invalidAtlas }

  init(
    data: Data,
    logMissingGlyph: @escaping @Sendable (String) -> Void = {
      try? FileHandle.standardError.write(contentsOf: Data($0.utf8))
    }
  ) throws(AssetError) {
    var cursor = 0
    let bytes = data.bytes
    func word() throws(AssetError) -> UInt32 {
      guard bytes.byteCount - cursor >= 4 else { throw .invalidAtlas }
      defer { cursor += 4 }
      return bytes.load(fromByteOffset: cursor, as: UInt32.self, .littleEndian)
    }
    guard try word() == 0x4C54_4143, try word() == 1 else { throw .invalidAtlas }
    let width = Int(try word())
    let height = Int(try word())
    let count = Int(try word())
    guard width == 2112, height > 0, height <= 4096, height % 90 == 0,
      count > 0, count <= (height / 90) * 32
    else { throw .invalidAtlas }
    var indices: [Character: Int] = [:]
    for index in 0..<count {
      guard let scalar = UnicodeScalar(try word()),
        indices.updateValue(index, forKey: Character(String(scalar))) == nil
      else { throw .invalidAtlas }
    }
    guard let fallback = indices["�"] else { throw .invalidAtlas }
    if let space = indices[" "] {
      for value: UInt32 in [
        0xA0, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009,
        0x200A, 0x202F, 0x205F,
        0x3000
      ] {
        if let scalar = UnicodeScalar(value) { indices[Character(String(scalar))] = space }
      }
    }
    for (character, index) in Array(indices) {
      if character.unicodeScalars.count == 1 {
        indices[Character(String(character) + "\u{FE0E}")] = index
      }
    }
    var levels: [MipLevel] = []
    var w = width
    var h = height
    while true {
      let size = w * h
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
    self.fallback = fallback
    self.missingGlyphLogger = MissingGlyphLogger(write: logMissingGlyph)
  }

  public func contains(_ character: Character) -> Bool { indices[character] != nil }

  public func glyphUV(_ character: Character) -> Region {
    let index: Int
    if let supported = indices[character] {
      index = supported
    } else {
      missingGlyphLogger.report(character)
      index = fallback
    }
    return glyphUV(index: index)
  }

  func glyphUVIfPresent(_ character: Character) -> Region? {
    indices[character].map { glyphUV(index: $0) }
  }

  private func glyphUV(index: Int) -> Region {
    Region(
      Float((index % 32) * 66 + 3) / Float(width),
      Float((index / 32) * 90 + 3) / Float(height),
      60 / Float(width), 84 / Float(height))
  }
}

private final class MissingGlyphLogger: Sendable {
  private let reported = Mutex<Set<Character>>([])
  private let write: @Sendable (String) -> Void

  init(write: @escaping @Sendable (String) -> Void) {
    self.write = write
  }

  func report(_ character: Character) {
    guard reported.withLock({ $0.insert(character).inserted }) else { return }
    let scalars = character.unicodeScalars.map {
      let hex = String($0.value, radix: 16, uppercase: true)
      return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }.joined(separator: " ")
    write(
      "Roots: unsupported glyph \(String(character).debugDescription) (\(scalars)); using U+FFFD replacement glyph\n"
    )
  }
}
