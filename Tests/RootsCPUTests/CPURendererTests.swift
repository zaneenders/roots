import Roots
import RootsCPU
import Testing

private func pixel(_ renderer: CPURenderer, x: Int, y: Int) -> [UInt8] {
  let start = (y * renderer.width + x) * 3
  return Array(renderer.pixels[start..<start + 3])
}

@Test func cpuRendererClipsAndCompositesInDrawOrder() {
  let renderer = CPURenderer(width: 4, height: 3)
  let draws = [
    DrawRect(Rect(-1, -1, 3, 3), Color(1, 0, 0)),
    DrawRect(Rect(1, 1, 4, 3), Color(0, 0, 1, 0.5))
  ]
  renderer.render(draws.span)
  #expect(
    renderer.pixels == [
      255, 0, 0, 220, 0, 17, 26, 11, 24, 9, 12, 26,
      220, 0, 17, 160, 0, 94, 15, 6, 126, 5, 6, 127,
      26, 11, 24, 15, 6, 126, 21, 5, 135, 5, 6, 136
    ])

  renderer.render([DrawRect]().span)
  #expect(renderer.pixels == Array(repeating: [UInt8(10), 13, 18], count: 12).flatMap { $0 })
}

@Test func cpuRendererRoundsCornersAndClampsRadius() {
  let renderer = CPURenderer(width: 6, height: 6)
  renderer.render([DrawRect(Rect(1, 1, 4, 4), Color(0, 1, 0), radius: 100)].span)
  let shape = [
    "......",
    "..##..",
    ".####.",
    ".####.",
    "..##..",
    "......"
  ]
  for (y, row) in shape.enumerated() {
    for (x, cell) in row.enumerated() {
      #expect((pixel(renderer, x: x, y: y)[1] > 127) == (cell == "#"))
    }
  }
}

@Test func cpuRendererIgnoresInvalidAndEmptyGeometry() {
  let renderer = CPURenderer(width: 2, height: 2)
  let draws = [
    DrawRect(Rect(.nan, 0, 2, 2), .accent),
    DrawRect(Rect(0, .infinity, 2, 2), .accent),
    DrawRect(Rect(0, 0, .infinity, 2), .accent),
    DrawRect(Rect(0, 0, 2, .nan), .accent),
    DrawRect(Rect(0, 0, 0, 2), .accent),
    DrawRect(Rect(0, 0, 2, -1), .accent),
    DrawRect(Rect(10, 10, 2, 2), .accent)
  ]
  renderer.render(draws.span)
  #expect(renderer.pixels == [10, 13, 18, 10, 13, 18, 10, 13, 18, 10, 13, 18])
}

@Test func cpuViewportClipPreservesOriginalRoundedShapeAndResetsBetweenDraws() {
  let renderer = CPURenderer(width: 6, height: 6)
  renderer.render(
    [
      DrawRect(Rect(1, 1, 4, 4), Color(0, 1, 0), radius: 2, clip: Rect(0, 2, 6, 2)),
      DrawRect(Rect(0, 0, 1, 1), Color(1, 0, 0))
    ].span)
  let reference = CPURenderer(width: 6, height: 6)
  reference.render([DrawRect(Rect(1, 1, 4, 4), Color(0, 1, 0), radius: 2)].span)
  let overlay = CPURenderer(width: 6, height: 6)
  overlay.render([DrawRect(Rect(0, 0, 1, 1), Color(1, 0, 0))].span)
  for y in 0..<6 {
    for x in 0..<6 {
      let expected = (2..<4).contains(y) ? pixel(reference, x: x, y: y) : pixel(overlay, x: x, y: y)
      #expect(pixel(renderer, x: x, y: y) == expected)
    }
  }
}

@Test func cpuRendererRejectsEmptyInvalidAndDisjointViewportClips() {
  let renderer = CPURenderer(width: 2, height: 2)
  for clip in [
    Rect(0, 0, 0, 2), Rect(0, 0, -1, 2), Rect(0, 0, 2, -1),
    Rect(0, 0, .nan, 2), Rect(.infinity, 0, 2, 2), Rect(5, 5, 2, 2)
  ] {
    renderer.render([DrawRect(Rect(0, 0, 2, 2), .accent, clip: clip)].span)
    #expect(renderer.pixels == [10, 13, 18, 10, 13, 18, 10, 13, 18, 10, 13, 18])
  }
}

@Test func cpuAtlasTextUsesAntialiasingClippingAndDrawOrder() {
  let font = MonospaceFont(size: 17.5)
  let glyph = DrawRect(
    Rect(3.25, 2.5, font.glyphWidth, font.glyphHeight), Color(1, 1, 1),
    glyphUV: FontAtlas.shared.glyphUV("A"))
  let full = CPURenderer(width: 32, height: 32)
  full.render([glyph].span)
  #expect(
    stride(from: 0, to: full.pixels.count, by: 3).contains {
      full.pixels[$0] > 10 && full.pixels[$0] < 255
    })
  var clipped = glyph
  clipped.clip = Rect(10, 0, 22, 32)
  let renderer = CPURenderer(width: 32, height: 32)
  renderer.render(
    [clipped, DrawRect(Rect(28, 28, 4, 4), Color(1, 0, 0), clip: Rect(28, 28, 4, 4))].span)
  for y in 0..<28 {
    for x in 0..<32 {
      #expect(pixel(renderer, x: x, y: y) == (x < 10 ? [10, 13, 18] : pixel(full, x: x, y: y)))
    }
  }
  #expect(pixel(renderer, x: 30, y: 30) == [255, 0, 0])
  renderer.render(
    [DrawRect(Rect(0, 0, 30, 30), .text, glyphUV: FontAtlas.shared.glyphUV(" "))].span)
  #expect(renderer.pixels == Array(repeating: [UInt8(10), 13, 18], count: 32 * 32).flatMap { $0 })
}

@Test func cpuRendererRejectsNonfiniteColorsAndRadius() {
  let renderer = CPURenderer(width: 2, height: 2)
  let rect = Rect(0, 0, 2, 2)
  for value: Float in [.nan, .infinity, -.infinity] {
    for draw in [
      DrawRect(rect, Color(value, 0, 0)),
      DrawRect(rect, Color(0, value, 0)),
      DrawRect(rect, Color(0, 0, value)),
      DrawRect(rect, Color(1, 0, 0, value)),
      DrawRect(rect, .text, radius: value)
    ] {
      renderer.render([draw].span)
      #expect(renderer.pixels == [10, 13, 18, 10, 13, 18, 10, 13, 18, 10, 13, 18])
    }
  }
}

@Test func emojiPixelsCompositePremultipliedColorExactlyOnce() {
  let atlas = EmojiAtlas.shared
  let uv = atlas.glyphUV("🙂")
  let mip = atlas.mipLevels[0]
  let x0 = Int((uv.x * Float(mip.width)).rounded())
  let y0 = Int((uv.y * Float(mip.height)).rounded())
  for opacity: Float in [1, 0.5] {
    let renderer = CPURenderer(width: 36, height: 42)
    renderer.render(
      [DrawRect(Rect(0, 0, 36, 42), Color(1, 0, 0, opacity), glyphUV: uv, colorGlyph: true)].span)
    var checked = 0
    for y in 0..<42 {
      for x in 0..<36 {
        let base = ((y0 + y) * mip.width + x0 + x) * 4
        let alpha = Float(mip.pixels[base + 3]) / 255
        guard alpha > 0.2 && alpha < 0.8 else { continue }
        let actual = pixel(renderer, x: x, y: y)
        for (channel, background): (Int, Float) in [(0, 10), (1, 13), (2, 18)] {
          let expected =
            Float(mip.pixels[base + 2 - channel]) * opacity + background * (1 - alpha * opacity)
          #expect(abs(Float(actual[channel]) - expected) < 2)
        }
        checked += 1
      }
    }
    #expect(checked > 0)
  }
}

@Test(arguments: [Float(1), 2]) func cpuFractionalAndNestedClipsIncludeOnlyPixelCenters(
  scale: Float
) {
  let renderer = CPURenderer(width: 16, height: 16)
  let parent = Rect(1.75, 0.5, 1.5, 6)
  for clip in [parent, parent.intersection(Rect(2.25, 1.75, 4, 2.5)), Rect(0.5, 0.5, 1, 1)] {
    let physical = Rect(clip.x * scale, clip.y * scale, clip.width * scale, clip.height * scale)
    renderer.render([DrawRect(Rect(-10, -10, 40, 40), Color(1, 0, 0), clip: physical)].span)
    for y in 0..<16 {
      for x in 0..<16 {
        let included = clip.contains(x: (Float(x) + 0.5) / scale, y: (Float(y) + 0.5) / scale)
        #expect(pixel(renderer, x: x, y: y) == (included ? [255, 0, 0] : [10, 13, 18]))
      }
    }
  }
}

@Test func cpuDerivativeQuadOriginAccountsForOddHeight() {
  let draw = DrawRect(Rect(1, 1, 6, 5), Color(1, 0, 0), radius: 2)
  let bottom = CPURenderer(width: 8, height: 7, fragmentOrigin: .bottomLeft)
  bottom.render([draw].span)
  var shifted = draw
  shifted.rect.y += 1
  let top = CPURenderer(width: 8, height: 8)
  top.render([shifted].span)
  #expect(bottom.pixels == Array(top.pixels.dropFirst(8 * 3)))
  let even = CPURenderer(width: 8, height: 8, fragmentOrigin: .bottomLeft)
  even.render([shifted].span)
  #expect(even.pixels == top.pixels)
}
