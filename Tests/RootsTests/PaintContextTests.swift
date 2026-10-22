import Testing

@testable import Roots

@Test func paintContextScopesComposeAndRestoreGeometryClipsAndText() {
  var ui = UIStore()
  let viewport = Rect(10, 20, 80, 60)
  ui.frame(
    build: { frame in
      frame.beginRow(in: viewport)
      frame.canvas(key: 1, extent: 80) { context in
        context.withOrigin(x: 10, y: 20, scale: 2) { local in
          #expect(local.rect == Rect(0, 0, 40, 30))
          #expect(local.clip == Rect(0, 0, 40, 30))
          local.strokeRect(Rect(1, 2, 10, 8), color: Color(1, 0, 0), radius: 2, width: 0.5)
          local.withOrigin(x: 3, y: 4, scale: 0.5) { nested in
            nested.draw(DrawRect(Rect(0, 0, 4, 6), Color(0, 1, 0), clip: Rect(1, 1, 2, 3)))
            let end = nested.drawText("A", x: 0, y: 0, font: MonospaceFont(size: 10))
            #expect(end == 6)
          }
          #expect(local.rect == Rect(0, 0, 40, 30))
        }
        #expect(context.rect == viewport)
        #expect(context.clip == viewport)
        context.fillRect(Rect(70, 60, 3, 4), color: Color(0, 0, 1))
      }
      frame.end()
    },
    present: { span in
      var draws: [DrawRect] = []
      for draw in span { draws.append(draw) }
      let stroke = draws.first { $0.strokeWidth > 0 }
      #expect(stroke?.rect == Rect(12, 24, 20, 16))
      #expect(stroke?.radius == 4)
      #expect(stroke?.strokeWidth == 1)
      #expect(stroke?.clip == viewport)
      let nested = draws.first { $0.color == Color(0, 1, 0) }
      #expect(nested?.rect == Rect(16, 28, 4, 6))
      #expect(nested?.clip == Rect(17, 29, 2, 3))
      let text = draws.first { $0.glyphUV != nil }
      #expect(text?.rect == Rect(16, 28, 10, 14))
      #expect(text?.clip == viewport)
      #expect(draws.last?.rect == Rect(70, 60, 3, 4))
    })
}

@Test func paintContextEmitsOneOrientedShapePerLineAndDefinesDegenerateCaps() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginRow(in: Rect(0, 0, 100, 100))
      frame.canvas(key: 1, extent: 100) { context in
        context.strokeLine(from: .init(20, 20), to: .init(26, 28), color: .accent, width: 2)
        context.strokeLine(
          from: .init(20, 20), to: .init(26, 28), color: .accent, width: 2, cap: .butt)
        context.strokeLine(from: .init(40, 40), to: .init(40, 40), color: .accent, width: 4)
        context.strokeLine(from: .init(40, 40), to: .init(40, 40), color: .accent, cap: .butt)
        for width: Float in [0, -1, .nan, .infinity] {
          context.strokeLine(from: .zero, to: .init(2, 2), color: .accent, width: width)
          context.strokeRect(Rect(1, 1, 4, 4), color: .accent, width: width)
        }
        context.strokeLine(from: .init(.nan, 0), to: .zero, color: .accent)
      }
      frame.end()
    },
    present: { span in
      var draws: [DrawRect] = []
      for draw in span { draws.append(draw) }
      let lines = draws.filter { $0.color == .accent }
      #expect(lines.count == 3)
      #expect(lines[0].axis == SIMD2<Float>(0.6, 0.8))
      #expect(lines[0].rect.width == 12 && lines[0].rect.height == 2 && lines[0].radius == 1)
      #expect(lines[1].rect.width == 10 && lines[1].radius == 0)
      #expect(lines[2].rect == Rect(38, 38, 4, 4) && lines[2].radius == 2)
      #expect(lines.allSatisfy { $0.isValid })
    })
}

@Test func rotatedBoundsPreventPrematureClipping() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginRow(in: Rect(0, 0, 30, 30))
      frame.canvas(key: 1, extent: 30) { context in
        context.strokeLine(from: .init(40, 15), to: .init(-10, 15), color: .accent, width: 2)
      }
      frame.end()
    },
    present: { span in
      var draws: [DrawRect] = []
      for draw in span { draws.append(draw) }
      #expect(draws.filter { $0.color == .accent }.count == 1)
    })
}

@Test func shapeValidationRejectsInvalidAxesWidthsAndOverflow() {
  for axis: SIMD2<Float> in [.zero, .init(2, 0), .init(.nan, 1), .init(1, .infinity)] {
    #expect(!DrawRect(Rect(1, 1, 4, 4), .accent, axis: axis).isValid)
  }
  for width: Float in [-1, .nan, .infinity] {
    #expect(!DrawRect(Rect(1, 1, 4, 4), .accent, strokeWidth: width).isValid)
  }
  #expect(
    !DrawRect(Rect(.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude, 1), .accent).isValid)
}
