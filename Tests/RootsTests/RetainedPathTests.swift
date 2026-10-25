import Foundation
import Testing

@testable import Roots

@Test func retainedPathTransformsKeepGeometryIdentity() throws {
  let stroke = try #require(PolylineStroke(points: [.init(x: 0, y: 0), .init(x: 10, y: 0)], width: 2))
  let inner = PathTransform(translation: .init(x: 5, y: 5), scale: 2, rotation: .pi / 2)
  let outer = PathTransform(translation: .init(x: 10, y: 20), scale: 3)
  let transform = outer.concatenating(inner)
  var store = UIStore()
  for _ in 0..<3 {
    store.frame(
      build: { frame in
        frame.beginColumn(in: Region(0, 0, 200, 200))
        frame.canvas(key: 1, extent: 200) { context in
          context.withOrigin(x: 10, y: 20, scale: 3) { local in
            local.strokePolyline(stroke, transform: inner)
          }
        }
        frame.end()
      },
      present: { batch in
        for draw in batch.rectangles where draw.polyline != nil {
          #expect(draw.polyline === stroke)
          #expect(draw.pathTransform == transform)
          #expect(draw.isValid)
        }
      })
  }
  let point = Coordinate(x: 4, y: 1)
  let roundTrip = transform.unapply(transform.apply(point))
  #expect(abs(roundTrip.x - point.x) < 0.0001 && abs(roundTrip.y - point.y) < 0.0001)
}

@Test func coloredPathPickingUsesSourceSegmentsAndScreenDistances() throws {
  let stroke = try #require(
    PolylineStroke(
      points: [.init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 10)], width: 2,
      colors: [Color(1, 0, 0), Color(0, 0, 1), Color(0, 1, 0)]))
  let transform = PathTransform(translation: .init(x: 20, y: 20), scale: 2, rotation: .pi / 2)
  let point = transform.apply(.init(x: 5, y: 1))
  let hit = try #require(stroke.hitTest(point, transform: transform, tolerance: 2.1))
  #expect(hit.segmentIndex == 0)
  #expect(abs(hit.fraction - 0.5) < 0.0001)
  #expect(abs(hit.distance - 2) < 0.0001)
  let color = stroke.color(at: hit)
  #expect(abs(color.r - 0.5) < 0.0001 && abs(color.b - 0.5) < 0.0001)
  #expect(stroke.hitTest(point, transform: transform, tolerance: 1) == nil)
  #expect(stroke.hitTest(point, transform: transform, clip: Region(0, 0, 1, 1)) == nil)
}

@Test func longPathsRejectInvalidDataAndKeepChunkBoundaryIndices() throws {
  let points = (0..<1_024).map { Coordinate(x: Float($0), y: 0) }
  let stroke = try #require(PolylineStroke(points: points, width: 1))
  #expect(stroke.chunks.count == 16)
  let hit = try #require(stroke.hitTest(.init(x: 64.5, y: 0)))
  #expect(hit.segmentIndex == 64 && hit.fraction == 0.5)
  #expect(PolylineStroke(points: points, width: 1, colors: [.accent]) == nil)
  #expect(PolylineStroke(points: [.init(x: .nan, y: 0)], width: 1) == nil)
  #expect(!DrawRect(polyline: stroke, transform: .init(scale: 0)).isValid)
  #expect(!DrawRect(polyline: stroke, transform: .init(rotation: .infinity)).isValid)
  #expect(stroke.hitTest(.zero, transform: .init(scale: .nan)) == nil)
  #expect(stroke.hitTest(.zero, tolerance: -.infinity) == nil)
}

@Test func duplicatesAndCrossingsHaveDeterministicHits() throws {
  let stroke = try #require(
    PolylineStroke(
      points: [
        .init(x: 0, y: 0), .init(x: 0, y: 0), .init(x: 10, y: 10), .init(x: 0, y: 10), .init(x: 10, y: 0)
      ], width: 2))
  #expect(stroke.hitTest(.zero)?.segmentIndex == 0)
  #expect(stroke.hitTest(.init(x: 5, y: 5))?.segmentIndex == 1)
  let dot = try #require(PolylineStroke(points: [.init(x: 2, y: 3)], width: 4))
  #expect(dot.hitTest(.init(x: 2, y: 3))?.fraction == 0)
}

@Test func retainedPathFrameGenerationBenchmark() throws {
  guard ProcessInfo.processInfo.environment["ROOTS_PATH_BENCHMARK"] == "1" else { return }
  let points = (0..<4_097).map { Coordinate(x: Float($0) / 10, y: Float($0 % 73)) }
  let stroke = try #require(PolylineStroke(points: points, width: 3))
  var store = UIStore()
  // Same paint scope and workload. Only geometry construction/transform ownership differs.
  for retained in [false, true, false, true] {
    var durations: [Double] = []
    for index in 0..<530 {
      let start = ContinuousClock.now
      store.frame(
        build: { frame in
          frame.beginColumn(in: Region(0, 0, 800, 600))
          frame.canvas(key: 1, extent: 600) { context in
            context.withOrigin(x: 10, y: 20, scale: 1.2) { local in
              if retained { local.strokePolyline(stroke) } else { local.strokePolyline(points, color: .text, width: 3) }
            }
          }
          frame.end()
        }, present: { _ in })
      if index >= 30 {
        let elapsed = start.duration(to: .now).components
        durations.append(Double(elapsed.seconds) * 1e6 + Double(elapsed.attoseconds) / 1e12)
      }
    }
    durations.sort()
    print(
      "PATH CPU generation retained=\(retained) points=4097 frames=500 p50_us=\(durations[250]) p95_us=\(durations[475])"
    )
    #expect(store.droppedDraws == 0)
  }
}
