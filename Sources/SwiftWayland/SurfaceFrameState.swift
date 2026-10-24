@MainActor final class SurfaceFrameState {
  var configured = false
  var redrawRequested = true
  var waitingForBuffer = false
  private var callback: UInt32 = 0

  var frameReady: Bool { callback == 0 }
  var canRender: Bool { configured && frameReady && redrawRequested && !waitingForBuffer }

  func complete(_ id: UInt32) {
    if callback == id { callback = 0 }
  }

  func endFrame(on surface: UInt32, objects: WaylandObjects, continuously: Bool) throws {
    guard frameReady else { throw WaylandError.connection }
    callback = objects.create(surface, WlSurfaceRequest.frame, "wl_callback")
    redrawRequested = redrawRequested || continuously
  }

  func close(objects: WaylandObjects) {
    objects.retire(callback)
    callback = 0
    configured = false
    redrawRequested = false
    waitingForBuffer = false
  }
}
