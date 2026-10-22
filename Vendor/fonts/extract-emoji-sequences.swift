#!/usr/bin/env swift
import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#endif

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let font = directory.appendingPathComponent("NotoColorEmoji.ttf")
let data = try Data(contentsOf: font)

func u16(_ offset: Int) -> Int {
  Int(data[offset]) << 8 | Int(data[offset + 1])
}

func u32(_ offset: Int) -> Int {
  u16(offset) << 16 | u16(offset + 2)
}

func coverage(_ offset: Int) -> [Int] {
  if u16(offset) == 1 {
    return (0..<u16(offset + 2)).map { u16(offset + 4 + 2 * $0) }
  }
  precondition(u16(offset) == 2, "Unsupported coverage format")
  var result: [Int] = []
  for i in 0..<u16(offset + 2) {
    let record = offset + 4 + i * 6
    let start = u16(record)
    let end = u16(record + 2)
    precondition(u16(record + 4) == result.count, "Invalid coverage index")
    result.append(contentsOf: start...end)
  }
  return result
}

func sha256() throws -> String {
  #if canImport(CryptoKit)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  #else
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["sha256sum", font.path]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    try process.run()
    let checksum = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
      let digest = String(decoding: checksum, as: UTF8.self).split(separator: " ").first,
      digest.count == 64, digest.allSatisfy(\.isHexDigit)
    else {
      throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "sha256sum failed"])
    }
    return String(digest)
  #endif
}

var tables: [String: Int] = [:]
for i in 0..<u16(4) {
  let record = 12 + i * 16
  let tag = String(decoding: data[record..<record + 4], as: UTF8.self)
  tables[tag] = u32(record + 8)
}
let cmap = tables["cmap"]!
var sequences: [Int: [Int]] = [:]
for i in 0..<u16(cmap + 2) {
  let table = cmap + u32(cmap + 8 + i * 8)
  if u16(table) != 12 { continue }
  for j in 0..<u32(table + 12) {
    let record = table + 16 + j * 12
    let start = u32(record)
    let end = u32(record + 4)
    let glyph = u32(record + 8)
    for scalar in start...end {
      sequences[glyph + scalar - start] = [scalar]
    }
  }
}

let gsub = tables["GSUB"]!
let lookups = gsub + u16(gsub + 8)
var ligatures: [(glyph: Int, components: [Int])] = []
for i in 0..<u16(lookups) {
  let lookup = lookups + u16(lookups + 2 + 2 * i)
  if u16(lookup) != 4 { continue }
  for j in 0..<u16(lookup + 4) {
    let table = lookup + u16(lookup + 6 + 2 * j)
    precondition(u16(table) == 1, "Unsupported ligature substitution format")
    for (k, first) in coverage(table + u16(table + 2)).enumerated() {
      let group = table + u16(table + 6 + 2 * k)
      for n in 0..<u16(group) {
        let ligature = group + u16(group + 2 + 2 * n)
        let components = [first] + (0..<(u16(ligature + 2) - 1)).map { u16(ligature + 4 + 2 * $0) }
        ligatures.append((u16(ligature), components))
      }
    }
  }
}

while true {
  let count = sequences.count
  for (glyph, components) in ligatures {
    if sequences[glyph] == nil && components.allSatisfy({ sequences[$0] != nil }) {
      sequences[glyph] = components.flatMap { sequences[$0]! }
    }
  }
  if count == sequences.count { break }
}
precondition(
  ligatures.allSatisfy { $0.components.allSatisfy { sequences[$0] != nil } },
  "Unresolved ligature components")
var entries: [[Int]: Int] = [:]
for (glyph, components) in ligatures {
  entries[components.flatMap { sequences[$0]! }] = glyph
}
var output = [
  "# NotoColorEmoji.ttf sha256=" + (try sha256()),
  "# glyph-id; Unicode scalars (VS16 omitted by the font)",
]
for sequence in entries.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
  let scalars = sequence.map { String($0, radix: 16, uppercase: true) }.joined(separator: " ")
  output.append("\(entries[sequence]!);\(scalars)")
}
try (output.joined(separator: "\n") + "\n").write(
  to: directory.appendingPathComponent("EmojiSequences.txt"), atomically: true, encoding: .utf8)
