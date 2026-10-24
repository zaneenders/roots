import Foundation

enum SymbolGlyphs {
  static func cell(for scalar: UInt32) -> [UInt8]? {
    var bitmap = SymbolBitmap()
    let top: Float = -5 / 3
    let middle: Float = 38 / 3
    let bottom: Float = 79 / 3
    switch scalar {
    case 0x21B5, 0x23CE:
      bitmap.stroke([(10, 5), (10, 14), (2, 14)], width: 1.4)
      bitmap.stroke([(5, 10), (1, 14), (5, 18)], width: 1.4)
    case 0x21BB:
      bitmap.arc(center: (6, 13), radius: (5, 7), from: 0, to: 300)
      bitmap.polygon([(7, 3), (11, 7), (6, 8)])
    case 0x21E7:
      bitmap.stroke(
        [(4, 20), (4, 11), (1, 11), (6, 4), (11, 11), (8, 11), (8, 20)], closed: true)
    case 0x2302:
      bitmap.stroke(
        [(1, 11), (6, 4), (11, 11), (10, 11), (10, 20), (2, 20), (2, 11)], closed: true)
      bitmap.stroke([(5, 20), (5, 15), (7, 15), (7, 20)])
    case 0x2303:
      bitmap.stroke([(2, 14), (6, 5), (10, 14)], width: 1.4)
    case 0x2318:
      for x: Float in [3, 9] {
        for y: Float in [7, 18] {
          bitmap.ellipse(center: (x, y), radius: (2, 2), width: 1.1)
        }
      }
      bitmap.stroke([(3, 7), (9, 7), (9, 18), (3, 18)], closed: true)
    case 0x2325:
      bitmap.stroke([(1, 5), (4, 5), (8, 19), (11, 19)], width: 1.4)
      bitmap.stroke([(8, 5), (11, 5)], width: 1.4)
    case 0x23F5:
      bitmap.polygon([(2, 4), (11, 12), (2, 20)])
    case 0x23F9:
      bitmap.polygon([(2, 5), (10, 5), (10, 19), (2, 19)])
    case 0x270E:
      bitmap.polygon([(2, 17), (8, 4), (11, 6), (5, 19), (1, 21)])
      bitmap.stroke([(8, 7), (4, 16)], width: 0.5, ink: false)
    case 0x2713, 0x2714:
      bitmap.stroke([(1, 13), (5, 19), (11, 4)], width: scalar == 0x2714 ? 2 : 1.1)
    case 0x2715...0x2718:
      let width: Float = scalar == 0x2716 || scalar == 0x2718 ? 2 : 1.1
      bitmap.stroke([(2, 5), (10, 19)], width: width)
      bitmap.stroke([(10, 5), (2, 19)], width: width)
    case 0x279C:
      bitmap.polygon([(0, 10), (7, 10), (7, 5), (12, 13), (7, 21), (7, 16), (0, 16)])
    case 0xE0B0, 0xE0B2:
      let left: Float = scalar == 0xE0B0 ? 0 : 12
      bitmap.polygon([(left, top), (12 - left, middle), (left, bottom)])
    case 0xE0B1, 0xE0B3:
      let left: Float = scalar == 0xE0B1 ? 1 : 11
      bitmap.stroke([(left, top), (12 - left, middle), (left, bottom)])
    case 0xE0B4, 0xE0B6:
      let right = scalar == 0xE0B4
      bitmap.polygon(
        (0...32).map { step in
          let angle = Float(step) * .pi / 32 - .pi / 2
          let x = 12 * cos(angle)
          return (right ? x : 12 - x, middle + 14 * sin(angle))
        })
    case 0xE0B8, 0xE0BA:
      let base: Float = scalar == 0xE0B8 ? 0 : 12
      bitmap.polygon([(0, top), (12, top), (base, bottom)])
    case 0xE348:
      bitmap.ellipse(center: (6, 12), radius: (5, 7), width: 1.1)
      bitmap.stroke([(6, 7), (6, 12), (9, 15)])
    case 0xEACC:
      bitmap.polygon([
        (6, 2), (7, 9), (11, 6), (8, 11), (12, 12), (8, 13), (11, 18),
        (7, 15), (6, 22), (5, 15), (1, 18), (4, 13), (0, 12), (4, 11), (1, 6), (5, 9)
      ])
    case 0xF002:
      bitmap.ellipse(center: (5, 10), radius: (4, 5), width: 1.2)
      bitmap.stroke([(8, 14), (11, 20)], width: 1.6)
    case 0xF022:
      for y: Float in [6, 12, 18] {
        bitmap.stroke([(0, y), (1, y)], width: 2)
        bitmap.stroke([(4, y), (11, y)], width: 2)
      }
    case 0xF0C5:
      bitmap.stroke([(3, 7), (11, 7), (11, 21), (3, 21)], closed: true)
      bitmap.stroke([(8, 7), (8, 3), (0, 3), (0, 17), (3, 17)])
    case 0xF15B:
      bitmap.stroke([(2, 3), (7, 3), (10, 7), (10, 21), (2, 21)], closed: true)
      bitmap.stroke([(7, 3), (7, 7), (10, 7)])
    case 0xF423:
      for step in 0..<8 {
        let angle = Float(step) * .pi / 4
        bitmap.stroke(
          [
            (6 + 4 * cos(angle), 12 + 6 * sin(angle)),
            (6 + 6 * cos(angle), 12 + 9 * sin(angle))
          ], width: 1.5)
      }
      bitmap.ellipse(center: (6, 12), radius: (4, 6))
      bitmap.ellipse(center: (6, 12), radius: (1.5, 2), ink: false)
    case 0x2630:
      for y: Float in [6, 12, 18] { bitmap.stroke([(1, y), (11, y)], width: 1.6) }
    case 0x1F44D:
      bitmap.polygon([
        (4, 20), (4, 11), (7, 7), (7, 3), (8, 2), (9, 3), (9, 9), (11, 9), (12, 11), (10, 20)
      ])
      bitmap.polygon([(0, 11), (2.5, 11), (2.5, 20), (0, 20)])
    default:
      return nil
    }
    return bitmap.pixels
  }
}

private struct SymbolBitmap {
  private static let scale = 4
  private static let width = FontAtlasGenerator.cellWidth * scale
  private var samples = [Bool](
    repeating: false,
    count: FontAtlasGenerator.cellWidth * FontAtlasGenerator.cellHeight * scale * scale)

  var pixels: [UInt8] {
    var result = [UInt8](
      repeating: 0, count: FontAtlasGenerator.cellWidth * FontAtlasGenerator.cellHeight)
    for y in 0..<FontAtlasGenerator.cellHeight {
      for x in 0..<FontAtlasGenerator.cellWidth {
        var count = 0
        for dy in 0..<Self.scale {
          for dx in 0..<Self.scale
          where samples[(y * Self.scale + dy) * Self.width + x * Self.scale + dx] {
            count += 1
          }
        }
        result[y * FontAtlasGenerator.cellWidth + x] = UInt8((count * 255 + 8) / 16)
      }
    }
    return result
  }

  mutating func stroke(
    _ points: [(Float, Float)], width: Float = 1.1, closed: Bool = false, ink: Bool = true
  ) {
    let points = closed ? points + [points[0]] : points
    paint(ink: ink) { x, y in
      for i in 1..<points.count {
        let (ax, ay) = points[i - 1]
        let (bx, by) = points[i]
        let dx = bx - ax
        let dy = by - ay
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(1, max(0, ((x - ax) * dx + (y - ay) * dy) / length))
        let ex = x - ax - t * dx
        let ey = y - ay - t * dy
        if ex * ex + ey * ey <= width * width / 4 { return true }
      }
      return false
    }
  }

  mutating func polygon(_ points: [(Float, Float)]) {
    paint { x, y in
      var inside = false
      var previous = points.last!
      for point in points {
        if (point.1 > y) != (previous.1 > y),
          x < (previous.0 - point.0) * (y - point.1) / (previous.1 - point.1) + point.0
        {
          inside.toggle()
        }
        previous = point
      }
      return inside
    }
  }

  mutating func ellipse(
    center: (Float, Float), radius: (Float, Float), width: Float? = nil, ink: Bool = true
  ) {
    paint(ink: ink) { x, y in
      let dx = x - center.0
      let dy = y - center.1
      let outerX = radius.0 + (width ?? 0) / 2
      let outerY = radius.1 + (width ?? 0) / 2
      guard dx * dx / (outerX * outerX) + dy * dy / (outerY * outerY) <= 1 else { return false }
      guard let width else { return true }
      let innerX = radius.0 - width / 2
      let innerY = radius.1 - width / 2
      return innerX <= 0 || innerY <= 0
        || dx * dx / (innerX * innerX) + dy * dy / (innerY * innerY) >= 1
    }
  }

  mutating func arc(center: (Float, Float), radius: (Float, Float), from: Float, to: Float) {
    stroke(
      (0...32).map { step in
        let angle = (from + (to - from) * Float(step) / 32) * .pi / 180
        return (center.0 + radius.0 * cos(angle), center.1 + radius.1 * sin(angle))
      })
  }

  private mutating func paint(ink: Bool = true, _ contains: (Float, Float) -> Bool) {
    let pad = FontAtlasGenerator.pad * Self.scale
    for y in pad..<((FontAtlasGenerator.pad + FontAtlasGenerator.glyphHeight) * Self.scale) {
      for x in pad..<((FontAtlasGenerator.pad + FontAtlasGenerator.glyphWidth) * Self.scale) {
        let index = y * Self.width + x
        if samples[index] != ink,
          contains(
            (Float(x) / Float(Self.scale) + 0.125 - 3) / 3,
            (Float(y) / Float(Self.scale) + 0.125 - 8) / 3)
        {
          samples[index] = ink
        }
      }
    }
  }
}
