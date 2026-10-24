public struct WaylandPopupConfiguration: Sendable {
  public var x: Int32
  public var y: Int32
  public var anchorWidth: Int32
  public var anchorHeight: Int32
  public var width: Int32
  public var height: Int32
  public init(
    x: Int32, y: Int32, anchorWidth: Int32, anchorHeight: Int32, width: Int32, height: Int32
  ) {
    self.x = x
    self.y = y
    self.anchorWidth = anchorWidth
    self.anchorHeight = anchorHeight
    self.width = width
    self.height = height
  }
  var isValid: Bool { width > 0 && height > 0 && anchorWidth > 0 && anchorHeight > 0 }
}

@MainActor final class WaylandPopup {
  var input: WaylandInput
  let frame = SurfaceFrameState()
  let scale = SurfaceScale()
  var pendingSize: SIMD2<Int32>?
  var dismissed = false
  let surface: UInt32
  let xdgSurface: UInt32
  let popup: UInt32
  private let objects: WaylandObjects
  private let onDismiss: @MainActor () -> Void
  private var closed = false

  init(
    configuration: WaylandPopupConfiguration, scale: Int32, compositor: UInt32, shell: UInt32,
    parent: UInt32, layerParent: UInt32, seat: UInt32, serial: UInt32?, objects: WaylandObjects,
    fractionalManager: UInt32 = 0, viewporter: UInt32 = 0,
    onDismiss: @escaping @MainActor () -> Void
  ) {
    self.objects = objects
    self.onDismiss = onDismiss
    input = WaylandInput(width: configuration.width, height: configuration.height)
    input.bufferScale = scale
    surface = objects.create(compositor, WlCompositorRequest.createSurface, "wl_surface")
    objects.request(surface, WlSurfaceRequest.setBufferScale, [.int(scale)])
    self.scale.setup(
      surface: surface, manager: fractionalManager, viewporter: viewporter, objects: objects)
    xdgSurface = objects.create(
      shell, XdgWmBaseRequest.getXdgSurface, "xdg_surface", [.uint(surface)])
    let positioner = objects.create(shell, XdgWmBaseRequest.createPositioner, "xdg_positioner")
    objects.request(
      positioner, XdgPositionerRequest.setSize,
      [.int(configuration.width), .int(configuration.height)])
    objects.request(
      positioner, XdgPositionerRequest.setAnchorRect,
      [
        .int(configuration.x), .int(configuration.y), .int(configuration.anchorWidth),
        .int(configuration.anchorHeight),
      ])
    objects.request(
      positioner, XdgPositionerRequest.setAnchor,
      [.uint(WaylandPositionerAnchor.bottomRight.rawValue)])
    objects.request(
      positioner, XdgPositionerRequest.setGravity,
      [.uint(WaylandPositionerGravity.bottomLeft.rawValue)])
    objects.request(
      positioner, XdgPositionerRequest.setConstraintAdjustment,
      [.uint(WaylandConstraintAdjustment([.slideX, .slideY, .flipY]).rawValue)])
    popup = objects.create(
      xdgSurface, XdgSurfaceRequest.getPopup, "xdg_popup", [.uint(parent), .uint(positioner)])
    objects.request(positioner, XdgPositionerRequest.destroy)
    if layerParent != 0 {
      objects.request(layerParent, ZwlrLayerSurfaceV1Request.getPopup, [.uint(popup)])
    }
    if seat != 0, let serial {
      objects.request(popup, XdgPopupRequest.grab, [.uint(seat), .uint(serial)])
    }
    objects.request(surface, WlSurfaceRequest.commit)
  }

  func close() {
    guard !closed else { return }
    closed = true
    frame.close(objects: objects)
    objects.request(popup, XdgPopupRequest.destroy)
    objects.request(xdgSurface, XdgSurfaceRequest.destroy)
    scale.close(objects: objects)
    objects.request(surface, WlSurfaceRequest.destroy)
    onDismiss()
  }
}
