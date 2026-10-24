@MainActor final class SurfaceScale {
  var outputs: Set<UInt32> = []
  var preferredBufferScale: Int32?
  private(set) var fractional: UInt32 = 0
  private var viewport: UInt32 = 0
  var preferredFractionalScale: UInt32?

  func setup(surface: UInt32, manager: UInt32, viewporter: UInt32, objects: WaylandObjects) {
    guard surface != 0, fractional == 0, manager != 0, viewporter != 0 else { return }
    viewport = objects.create(
      viewporter, WpViewporterRequest.getViewport, "wp_viewport", [.uint(surface)])
    fractional = objects.create(
      manager, WpFractionalScaleManagerV1Request.getFractionalScale, "wp_fractional_scale_v1",
      [.uint(surface)])
  }

  func update(
    input: inout WaylandInput, surface: UInt32, fallback: Int32, objects: WaylandObjects
  ) -> Bool {
    let fractionalScale120 = preferredFractionalScale
    let bufferScale = fractionalScale120 == nil ? preferredBufferScale ?? fallback : 1
    guard surface != 0,
      input.bufferScale != bufferScale || input.fractionalScale120 != fractionalScale120
    else { return false }
    input.bufferScale = bufferScale
    input.fractionalScale120 = fractionalScale120
    objects.request(surface, WlSurfaceRequest.setBufferScale, [.int(bufferScale)])
    return true
  }

  func prepare(width: Int32, height: Int32, objects: WaylandObjects) {
    if preferredFractionalScale != nil {
      objects.request(viewport, WpViewportRequest.setDestination, [.int(width), .int(height)])
    }
  }

  func close(objects: WaylandObjects) {
    objects.request(fractional, WpFractionalScaleV1Request.destroy)
    objects.request(viewport, WpViewportRequest.destroy)
    fractional = 0
    viewport = 0
  }
}
