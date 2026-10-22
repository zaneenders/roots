import Testing

@testable import Roots

@Test(arguments: [Float(5), 10, 17.5, 20, 30])
func clippedTextMatchesFilteringUnclippedDraws(size: Float) {
  let font = MonospaceFont(size: size)
  let text = "ABZ 09 é🙂\nSECOND LINE\n" + String(repeating: "TEXT ", count: 20)
  var reference = UIStorage(nodeCapacity: 0, drawCapacity: 10000)
  let expectedX = reference.drawText(text, x: -3, y: -5, font: font, color: .text, clip: nil)
  for clip in [
    Rect(-1000, -1000, 2000, 2000), Rect(0, 0, 20, 15),
    Rect(-3, -5, size / 2, font.glyphHeight / 2),
    Rect(-100, -100, 1, 1), Rect(1000, 1000, 1, 1), Rect(0, 0, 0, 0),
    Rect(-3 + size / 2, -5, 1, font.glyphHeight / 2),
    Rect(-3, -5 + font.glyphHeight / 2, size / 2, 1),
    Rect(-3.25, -5.25, 0.5, 0.5),
  ] {
    var expected: [DrawRect] = []
    for draw in reference.draws where !clip.intersection(draw.rect).isEmpty {
      var draw = draw
      draw.clip = clip
      expected.append(draw)
    }
    for capacity in [0, 1, 7, 10000] {
      var clipped = UIStorage(nodeCapacity: 0, drawCapacity: capacity)
      let actualX = clipped.drawText(text, x: -3, y: -5, font: font, color: .text, clip: clip)
      #expect(actualX == expectedX)
      #expect(clipped.draws.count == min(capacity, expected.count))
      #expect(clipped.droppedDraws == max(0, expected.count - capacity))
      for index in 0..<clipped.draws.count {
        #expect(clipped.draws[index].rect == expected[index].rect)
        #expect(clipped.draws[index].color == expected[index].color)
        #expect(clipped.draws[index].radius == expected[index].radius)
        #expect(clipped.draws[index].clip == expected[index].clip)
        #expect(clipped.draws[index].glyphUV == expected[index].glyphUV)
      }
    }
  }
}
