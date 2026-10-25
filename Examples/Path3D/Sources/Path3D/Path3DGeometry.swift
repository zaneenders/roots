import Foundation
import Roots

/// Synthetic (2, 3) torus knot. No assets, FIT files, or networking.
struct Path3DGeometry: Sendable {
  struct Sample: Sendable {
    let position: SIMD3<Float>
    let color: Color
  }

  static let segmentCount = 1_024
  static let projectionScale: Float = 500
  let samples: [Sample]

  init() {
    samples = (0...Self.segmentCount).map { index in
      let phase = Float(index) / Float(Self.segmentCount)
      let t = phase * 2 * Float.pi
      let radius = 0.72 + 0.28 * cos(3 * t)
      return Sample(
        position: SIMD3(radius * cos(2 * t), 0.5 * sin(3 * t) + 0.12, radius * sin(2 * t)),
        color: Self.color(phase))
    }
  }

  static func color(_ phase: Float) -> Color {
    let t = phase * 2 * Float.pi
    return Color(0.58 + 0.4 * cos(t), 0.58 + 0.4 * cos(t - 2.1), 0.58 + 0.4 * cos(t + 2.1))
  }

  func position(at progress: Float) -> SIMD3<Float> {
    let value = min(1, max(0, progress)) * Float(Self.segmentCount)
    let index = min(Int(value), Self.segmentCount - 1)
    let fraction = value - Float(index)
    return samples[index].position + (samples[index + 1].position - samples[index].position) * fraction
  }
}

struct Path3DCamera: Equatable {
  let yaw: Float
  let pitch: Float
  static let distance: Float = 3.2
  static let floor: Float = -0.75

  struct Projected {
    let point: Coordinate
    let depth: Float
  }

  func project(_ world: SIMD3<Float>) -> Projected {
    let x = world.x * cos(yaw) - world.z * sin(yaw)
    let z = world.x * sin(yaw) + world.z * cos(yaw)
    let y = world.y * cos(pitch) + z * sin(pitch)
    let depth = Self.distance - world.y * sin(pitch) + z * cos(pitch)
    // The orbit/zoom bounds keep all demo geometry in front of the near plane.
    return Projected(
      point: Coordinate(x: x / depth * Path3DGeometry.projectionScale, y: -y / depth * Path3DGeometry.projectionScale),
      depth: depth)
  }

  func transform(in region: Region, zoom: Float) -> PathTransform {
    PathTransform(
      translation: Coordinate(x: region.center.x, y: region.y + region.height * 0.43),
      scale: max(0.001, min(region.width * 0.8, region.height) * 1.45 * zoom / Path3DGeometry.projectionScale))
  }
}

/// Projection is rebuilt only for camera orbit, not marker playback, resizing, or zoom.
/// Short runs are depth-sorted for approximate 3D occlusion; Roots still renders 2D paths.
struct Path3DProjection: ~Copyable {
  struct Run {
    let firstSegment: Int
    let depth: Float
    let body: PolylineStroke
  }
  struct Pick {
    let segment: Int
    let fraction: Float
    let position: Coordinate
    var progress: Float { (Float(segment) + fraction) / Float(Path3DGeometry.segmentCount) }
  }

  private var rendering: PolylineStroke.Rendering?
  private(set) var camera: Path3DCamera?
  private(set) var revision = 0
  private(set) var runs: [Run] = []
  private(set) var grid: [PolylineStroke] = []
  private(set) var shadow: PolylineStroke?
  private var depths: [Float] = []

  mutating func update(
    geometry: borrowing Path3DGeometry, camera: Path3DCamera, rendering: PolylineStroke.Rendering = .ribbon
  ) {
    guard self.camera != camera || self.rendering != rendering else { return }
    self.camera = camera
    self.rendering = rendering
    revision += 1
    let projected = geometry.samples.map { camera.project($0.position) }
    depths = projected.map(\.depth)
    var runs: [Run] = []
    // Eight-segment slices make crossings read correctly without a depth-buffer API.
    for start in stride(from: 0, to: Path3DGeometry.segmentCount, by: 8) {
      let end = min(start + 8, Path3DGeometry.segmentCount)
      let positions = projected[start...end].map(\.point)
      let depth = (projected[start].depth + projected[end].depth) / 2
      let width: Float = 0.052 / depth * Path3DGeometry.projectionScale
      let light = min(1, max(0.45, 1.1 - (depth - 2.2) * 0.2))
      let colors = geometry.samples[start...end].map {
        Color($0.color.r * light, $0.color.g * light, $0.color.b * light)
      }
      if let body = PolylineStroke(points: positions, width: width, colors: colors, rendering: rendering) {
        runs.append(Run(firstSegment: start, depth: depth, body: body))
      }
    }
    self.runs = runs.sorted { $0.depth > $1.depth }
    grid.removeAll(keepingCapacity: true)
    for index in -7...7 {
      let offset = Float(index) / 5
      for alongX in [false, true] {
        let a = SIMD3<Float>(alongX ? -1.4 : offset, Path3DCamera.floor, alongX ? offset : -1.4)
        let b = SIMD3<Float>(alongX ? 1.4 : offset, Path3DCamera.floor, alongX ? offset : 1.4)
        if let line = PolylineStroke(
          points: [camera.project(a).point, camera.project(b).point], width: 0.0007 * Path3DGeometry.projectionScale)
        {
          grid.append(line)
        }
      }
    }
    shadow = PolylineStroke(
      points: geometry.samples.map {
        camera.project(SIMD3($0.position.x, Path3DCamera.floor, $0.position.z)).point
      }, width: 0.012 * Path3DGeometry.projectionScale, rendering: rendering)
  }

  borrowing func pick(_ point: Coordinate, transform: PathTransform, clip: Region) -> Pick? {
    var result: Pick?
    var nearest: Float = 12
    // Nearest depth first; ties at a crossing select the visible frontmost run.
    for run in runs.reversed() {
      guard let hit = run.body.hitTest(point, transform: transform, tolerance: nearest, clip: clip) else { continue }
      if result != nil && hit.distance >= nearest - 0.25 { continue }
      let segment = run.firstSegment + hit.segmentIndex
      let d0 = depths[segment]
      let d1 = depths[segment + 1]
      let t = hit.fraction
      let fraction = t * d0 / ((1 - t) * d1 + t * d0)
      nearest = hit.distance
      result = Pick(segment: segment, fraction: fraction, position: hit.position)
    }
    return result
  }
}
