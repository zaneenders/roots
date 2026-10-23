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
  var configured = false
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
    onDismiss: @escaping @MainActor () -> Void
  ) {
    self.objects = objects
    self.onDismiss = onDismiss
    input = WaylandInput(width: configuration.width, height: configuration.height)
    input.bufferScale = scale
    surface = objects.create(compositor, 0, "wl_surface")
    objects.request(surface, 8, [.int(scale)])
    xdgSurface = objects.create(shell, 2, "xdg_surface", [.uint(surface)])
    let positioner = objects.create(shell, 1, "xdg_positioner")
    objects.request(positioner, 1, [.int(configuration.width), .int(configuration.height)])
    objects.request(
      positioner, 2,
      [
        .int(configuration.x), .int(configuration.y), .int(configuration.anchorWidth),
        .int(configuration.anchorHeight)
      ])
    objects.request(positioner, 3, [.uint(8)])
    objects.request(positioner, 4, [.uint(6)])
    objects.request(positioner, 5, [.uint(1 | 2 | 8)])
    popup = objects.create(xdgSurface, 2, "xdg_popup", [.uint(parent), .uint(positioner)])
    objects.request(positioner, 0)
    if layerParent != 0 { objects.request(layerParent, 5, [.uint(popup)]) }
    if seat != 0, let serial { objects.request(popup, 1, [.uint(seat), .uint(serial)]) }
    objects.request(surface, 6)
  }

  func close() {
    guard !closed else { return }
    closed = true
    objects.request(popup, 0)
    objects.request(xdgSurface, 0)
    objects.request(surface, 0)
    onDismiss()
  }
}
