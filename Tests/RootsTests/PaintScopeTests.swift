import Testing

@testable import Roots

@Test func regionHelpersInsetOffsetAndCollapseAtCenter() {
  let region = Region(10, 20, 30, 40)
  #expect(region.center == .init(25, 40))
  #expect(region.offsetBy(dx: -5, dy: 3) == Region(5, 23, 30, 40))
  #expect(region.insetBy(dx: 2, dy: 4) == Region(12, 24, 26, 32))
  #expect(region.insetBy(dx: 100, dy: 100) == Region(25, 40, 0, 0))
  #expect(region.insetBy(dx: -1, dy: -2) == Region(9, 18, 32, 44))
}

@Test func clipsComposeWithTransformsAndRestorePointerTextAndGeometry() {
  var store = UIStore()
  var output: [DrawRect] = []
  store.frame(
    input: Input(x: 30, y: 40),
    build: { frame in
      frame.beginRow(in: Region(10, 20, 100, 80))
      frame.canvas(key: 1, extent: 100) { context in
        context.withOrigin(x: 10, y: 20, scale: 2) { local in
          #expect(local.pointerPosition == .init(10, 10))
          local.withClip(Region(5, 5, 10, 10)) { clipped in
            #expect(clipped.clip == Region(5, 5, 10, 10))
            clipped.fillRect(Region(0, 0, 40, 30), color: .accent)
            clipped.drawText("A", x: 5, y: 5, size: 5)
            clipped.withClip(Region(30, 30, 2, 2)) { empty in
              #expect(empty.pointerPosition == nil)
              empty.fillCircle(center: .init(10, 10), radius: 3, color: .text)
            }
            #expect(clipped.pointerPosition == .init(10, 10))
          }
          #expect(local.clip == Region(0, 0, 50, 40))
        }
        #expect(context.pointerPosition == .init(30, 40))
        #expect(context.clip == Region(10, 20, 100, 80))
        context.strokeCircle(center: .init(80, 70), radius: 6, color: .text, width: 2)
      }
      frame.end()
    }, present: { span in for draw in span { output.append(draw) } })
  let clipped = output.filter { $0.color == .accent || $0.glyphUV != nil }
  #expect(clipped.count == 2)
  #expect(clipped.allSatisfy { $0.clip == Region(20, 30, 20, 20) })
  #expect(output.last?.region == Region(74, 64, 12, 12))
  #expect(output.last?.strokeWidth == 2)
  #expect(output.last?.clip == Region(10, 20, 100, 80))
}

@Test func invalidClipsAndOversizedPolylinesDoNotPaint() {
  var store = UIStore()
  store.frame(
    build: { frame in
      frame.beginRow(in: Region(0, 0, 100, 100))
      frame.canvas(key: 1, extent: 100) { context in
        context.withClip(Region(.nan, 0, 10, 10)) { clipped in
          clipped.fillRect(Region(0, 0, 100, 100), color: .accent)
        }
        context.strokePolyline([], color: .accent)
        context.strokePolyline([.init(.nan, 0)], color: .accent)
        context.strokePolyline(Array(repeating: .zero, count: 129), color: .accent)
        context.fillCircle(center: .zero, radius: -1, color: .accent)
      }
      frame.end()
    },
    present: { span in
      for draw in span { #expect(draw.color != .accent) }
    })
}

@Test func polylinesTransformExactlyOnceAndKeepTheScopedClip() throws {
  var store = UIStore()
  var strokes: [DrawRect] = []
  let stroke = try #require(PolylineStroke(points: [.init(1, 2), .init(3, 4)], width: 2))
  store.frame(
    build: { frame in
      frame.beginRow(in: Region(10, 20, 80, 60))
      frame.canvas(key: 1, extent: 80) { context in
        context.withOrigin(x: 10, y: 20, scale: 2) { local in
          local.withClip(Region(0, 0, 10, 10)) { clipped in
            clipped.strokePolyline(stroke.points, color: .accent, width: stroke.width)
            clipped.draw(DrawRect(polyline: stroke, color: .text))
          }
        }
      }
      frame.end()
    },
    present: { draws in
      for draw in draws where draw.polyline != nil { strokes.append(draw) }
    })
  #expect(strokes.count == 2)
  for draw in strokes {
    #expect(draw.polyline?.points == [.init(12, 24), .init(16, 28)])
    #expect(draw.polyline?.width == 4)
    #expect(draw.clip == Region(10, 20, 20, 20))
    #expect(draw.isValid)
  }
}

@Test func paintContextRejectsInvalidPolylineDrawMutations() throws {
  let stroke = try #require(PolylineStroke(points: [.init(5, 5), .init(15, 15)], width: 2))
  let mutations: [(inout DrawRect) -> Void] = [
    { $0.region.x = .nan },
    { $0.region.x += 1 },
    { $0.axis = .init(0, 1) },
    { $0.radius = 1 },
    { $0.strokeWidth = 1 },
    { $0.glyphUV = Region(0, 0, 1, 1) }
  ]
  var store = UIStore()
  store.frame(
    build: { frame in
      frame.beginRow(in: Region(0, 0, 100, 100))
      frame.canvas(key: 1, extent: 100) { context in
        for mutate in mutations {
          var draw = DrawRect(polyline: stroke, color: .accent)
          mutate(&draw)
          #expect(!draw.isValid)
          context.draw(draw)
          context.withOrigin(x: 10, y: 20, scale: 2) { local in
            local.draw(draw)
          }
        }
      }
      frame.end()
    },
    present: { draws in
      for draw in draws { #expect(draw.polyline == nil) }
    })
  #expect(store.droppedDraws == 0)
}

@Test func invalidPolylineDrawMutationsAreRejectedAndFocusLossClearsPointer() throws {
  let stroke = try #require(PolylineStroke(points: [.init(1, 1)], width: 2))
  var draw = DrawRect(polyline: stroke, color: .accent)
  draw.region.x = .nan
  #expect(!draw.isValid)
  #expect(PolylineStroke(points: [.init(.greatestFiniteMagnitude, 0), .zero], width: 2) == nil)
  var store = UIStore()
  store.frame(
    input: Input(x: 10, y: 10, focusLost: true),
    build: { frame in
      frame.beginRow(in: Region(0, 0, 20, 20))
      frame.canvas(key: 1, extent: 20) { context in
        #expect(context.pointerPosition == nil)
      }
      frame.end()
    }, present: { _ in })
}
