@_spi(Hosting) import Roots
import Testing

@testable import MacOSBridge

@Test @MainActor func scissorsUseIndependentAxisRatiosAndPixelCenters() {
  let clip = MetalScissorRect(
    Rect(-2.5, 3.5, 12.75, 200), logicalSize: .init(100, 80), drawableSize: .init(200, 120))
  #expect(clip.x == 0 && clip.y == 5 && clip.width == 20 && clip.height == 115)
  let fractional = MetalScissorRect(
    Rect(0.1, 0.1, 0.9, 0.9), logicalSize: .init(10, 10), drawableSize: .init(15, 20))
  #expect(fractional.x == 0 && fractional.y == 0 && fractional.width == 1 && fractional.height == 2)
}

@Test @MainActor func invalidAndOutsideScissorsAreEmpty() {
  for rect in [
    Rect(.nan, 0, 1, 1), Rect(0, 0, .infinity, 1), Rect(0, 0, -1, 1), Rect(20, 20, 1, 1),
  ] {
    #expect(MetalScissorRect(rect, logicalSize: .init(10, 10), drawableSize: .init(20, 20)).isEmpty)
  }
  let large = MetalScissorRect(
    Rect(0, 0, .greatestFiniteMagnitude, 1), logicalSize: .init(1, 1), drawableSize: .init(.max, 1))
  #expect(large.width == Int(Int32.max))
}

@Test @MainActor func frameCopiesVerticesAndOnlyMergesAdjacentClips() {
  var state = MetalFrameState()
  state.begin(logicalSize: .init(100, 80), drawableSize: .init(200, 160))
  let clip = Rect(0, 0, 10, 10)
  var draws = [
    DrawRect(Rect(10, 20, 30, 40), Color(0.1, 0.2, 0.3, 0.4), radius: 5),
    DrawRect(Rect(0, 0, 10, 10), .text),
    DrawRect(Rect(0, 0, 10, 10), .text, clip: clip),
    DrawRect(Rect(0, 0, 10, 10), .text),
  ]
  state.withFrame { $0.render(draws.span) }
  draws.removeAll()
  #expect(state.vertices.count == 4)
  #expect(state.runs.map(\.firstVertex) == [0, 2, 3])
  #expect(state.runs.map(\.vertexCount) == [2, 1, 1])
  #expect(state.vertices[0].position == .init(10, 20))
  #expect(state.vertices[0].size == .init(30, 40))
  #expect(state.vertices[0].color == .init(0.1, 0.2, 0.3, 0.4))
  #expect(state.vertices[0].radius == 5)
  #expect(state.vertices[0].textured == 0)
  state.begin(logicalSize: .init(100, 80), drawableSize: .init(200, 160))
  #expect(state.vertices.isEmpty && state.runs.isEmpty)
}

@Test @MainActor func frameSkipsInvalidDrawsAndEmptyClips() {
  var state = MetalFrameState()
  state.begin(logicalSize: .init(10, 10), drawableSize: .init(20, 20))
  let draws = [
    DrawRect(Rect(0, 0, 0, 1), .text),
    DrawRect(Rect(.nan, 0, 1, 1), .text),
    DrawRect(Rect(.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude, 1), .text),
    DrawRect(Rect(0, 0, 1, 1), Color(0, 0, 0, .nan)),
    DrawRect(Rect(0, 0, 1, 1), .text, radius: .infinity),
    DrawRect(Rect(0, 0, 1, 1), .text, clip: Rect(.nan, 0, 1, 1)),
    DrawRect(Rect(0, 0, 1, 1), .text, clip: Rect(20, 20, 1, 1)),
    DrawRect(Rect(0, 0, 1, 1), .text, glyphUV: Rect(0, 0, 2, 1)),
  ]
  state.withFrame { $0.render(draws.span) }
  #expect(state.vertices.isEmpty && state.runs.isEmpty)
}

@Test @MainActor func glyphVerticesUseAtlasCoordinatesAndSupportMultipleSubmissions() {
  var state = MetalFrameState()
  state.begin(logicalSize: .init(100, 100), drawableSize: .init(100, 100))
  let uv = FontAtlas.shared.glyphUV("A")
  let draws = [DrawRect(Rect(0, 0, 20, 28), .text, glyphUV: uv)]
  state.withFrame { frame in
    frame.render(draws.span)
    frame.render(draws.span)
  }
  #expect(state.vertices.count == 2)
  #expect(state.runs.count == 1 && state.runs[0].vertexCount == 2)
  #expect(state.vertices[0].glyphUV == .init(uv.x, uv.y, uv.width, uv.height))
  #expect(state.vertices[1].glyphUV == state.vertices[0].glyphUV)
  #expect(state.vertices[0].textured == 1)
}

@Test @MainActor func polylinesKeepOwnedPointsAndSeparateAdjacentInstanceRuns() throws {
  var state = MetalFrameState()
  let stroke = try #require(PolylineStroke(points: [.init(2, 2), .init(8, 8)], width: 2))
  var draws = [
    DrawRect(Rect(0, 0, 10, 10), .text),
    DrawRect(polyline: stroke, color: .accent),
    DrawRect(Rect(0, 0, 10, 10), .text),
  ]
  state.begin(logicalSize: .init(10, 10), drawableSize: .init(20, 20))
  state.withFrame { $0.render(draws.span) }
  draws.removeAll()
  #expect(state.vertices.count == 2 && state.runs.count == 3)
  #expect(state.runs[1].polyline?.polyline?.points == [.init(2, 2), .init(8, 8)])
  #expect(state.runs[2].firstVertex == 1)
}

@Test @MainActor func metalFrameAcceptsUIOutputWithoutRawDrawSubmission() {
  var state = MetalFrameState()
  state.begin(logicalSize: .init(80, 40), drawableSize: .init(80, 40))
  var ui = UIHost()
  ui.frame(
    build: {
      RowBlock(in: Rect(0, 0, 80, 40)) {
        CanvasBlock(key: 1, extent: 80, color: .panel) { context in
          context.fillRect(Rect(4, 4, 8, 8), color: .accent)
        }
      }
    }, present: { batch in state.withFrame { $0.render(batch) } })
  #expect(state.vertices.count == 2)
  #expect(state.vertices[1].position == .init(4, 4))
  #expect(
    state.vertices[1].color == .init(Color.accent.r, Color.accent.g, Color.accent.b, Color.accent.a)
  )
}

@Test(arguments: [Int32(1), 2]) func fractionalMetalScissorsMatchHalfOpenPixelCenters(scale: Int32)
{
  let parent = Rect(1.75, 0.5, 1.5, 6)
  for rect in [parent, parent.intersection(Rect(2.25, 1.75, 4, 2.5)), Rect(0.5, 0.5, 1, 1)] {
    let scissor = MetalScissorRect(
      rect, logicalSize: .init(8, 8), drawableSize: .init(8 * scale, 8 * scale))
    for y in 0..<Int(8 * scale) {
      for x in 0..<Int(8 * scale) {
        let included =
          x >= scissor.x && x < scissor.x + scissor.width
          && y >= scissor.y && y < scissor.y + scissor.height
        #expect(
          included
            == rect.contains(x: (Float(x) + 0.5) / Float(scale), y: (Float(y) + 0.5) / Float(scale))
        )
      }
    }
  }
}
