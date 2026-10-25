import Foundation
import Observation
import Roots

@MainActor @Observable final class Path3DModel {
  let geometry = Path3DGeometry()
  let rendering: PolylineStroke.Rendering
  init(rendering: PolylineStroke.Rendering = .ribbon) { self.rendering = rendering }
  var playing = true
  var orbiting = false
  private(set) var yaw: Float = 0.45
  private(set) var pitch: Float = 0.5
  private(set) var zoomLevel: Float = 1
  private(set) var progress: Float = 0.58
  @ObservationIgnored private var drag: Coordinate?
  @ObservationIgnored private var projection = Path3DProjection()
  var projectionRevision: Int { projection.revision }
  var camera: Path3DCamera { Path3DCamera(yaw: yaw, pitch: pitch) }
  var needsAnimation: Bool { playing || orbiting }

  func reset() {
    yaw = 0.45
    pitch = 0.5
    zoomLevel = 1
    progress = 0.58
    orbiting = false
    drag = nil
  }

  func advance(_ dt: Float) {
    guard dt.isFinite, dt > 0 else { return }
    let delta = min(dt, 0.1)
    if playing { progress = (progress + delta / 24).truncatingRemainder(dividingBy: 1) }
    if orbiting, drag == nil { yaw = (yaw + delta * 0.18).truncatingRemainder(dividingBy: 2 * .pi) }
  }

  func zoom(_ delta: Float) {
    guard delta.isFinite else { return }
    zoomLevel = min(1.8, max(0.5, zoomLevel * (1 + max(-0.2, min(0.2, delta * 0.01)))))
  }

  func pointer(_ event: PointerEvent) {
    guard event.position.x.isFinite, event.position.y.isFinite else { return }
    switch event.phase {
    case .pressed:
      drag = event.position
      orbiting = false
    case .dragged:
      if let drag {
        yaw = (yaw + (event.position.x - drag.x) * 0.008).truncatingRemainder(dividingBy: 2 * .pi)
        pitch = min(1.25, max(-0.15, pitch + (event.position.y - drag.y) * 0.008))
      }
      drag = event.position
    case .released, .cancelled: drag = nil
    }
  }

  func paint(_ painter: inout UIPaintContext) {
    let region = painter.region
    guard region.width > 1, region.height > 1 else { return }
    projection.update(geometry: geometry, camera: camera, rendering: rendering)
    let transform = camera.transform(in: region, zoom: zoomLevel)
    for line in projection.grid { painter.strokePolyline(line, transform: transform, tint: Color(0.12, 0.25, 0.34)) }
    if let shadow = projection.shadow {
      painter.strokePolyline(shadow, transform: transform, tint: Color(0.02, 0.09, 0.13))
    }
    let marker = camera.project(geometry.position(at: progress))
    let markerSegment = min(Int(progress * Float(Path3DGeometry.segmentCount)), Path3DGeometry.segmentCount - 1)
    for run in projection.runs {
      painter.strokePolyline(run.body, transform: transform)
      // Place the tracer just above its own ribbon; nearer runs can still cover it.
      if (run.firstSegment..<(run.firstSegment + 8)).contains(markerSegment) {
        paintMarker(
          &painter, at: transform.apply(marker.point),
          radius: transform.scale * Path3DGeometry.projectionScale * 0.035 / marker.depth)
      }
    }
    let hover = painter.mousePosition.flatMap {
      drag == nil ? projection.pick($0, transform: transform, clip: painter.clip) : nil
    }
    if let hover { painter.strokeCircle(center: hover.position, radius: 10, color: .text, width: 1.5) }
    let phase = hover?.progress ?? progress
    let world = geometry.position(at: phase)
    let font: Float = region.width < 600 ? 12 : 15
    let line = String(
      format: "%3.0f%%    x %+.2f   y %+.2f   z %+.2f", phase * 100, world.x,
      world.y, world.z)
    let footer = Region(region.x, region.y + max(0, region.height - 42), region.width, min(42, region.height))
    painter.fillRect(footer, color: Color(0.025, 0.04, 0.06, 0.95))
    painter.drawText(line, x: footer.x + 14, y: footer.y + 10, size: font, color: Color(0.65, 0.88, 0.97))
  }

  private func paintMarker(_ painter: inout UIPaintContext, at point: Coordinate, radius: Float) {
    painter.fillCircle(center: point, radius: radius, color: Color(0.85, 0.65, 1))
    painter.fillCircle(center: point, radius: radius * 0.45, color: Color(1, 1, 1))
  }
}
