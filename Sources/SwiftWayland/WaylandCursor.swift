public enum WaylandCursorShape: UInt32, Sendable, CaseIterable {
  case `default` = 1
  case contextMenu, help, pointer, progress, wait, cell, crosshair, text
  case verticalText, alias, copy, move, noDrop, notAllowed, grab, grabbing
  case eastResize, northResize, northEastResize, northWestResize, southResize
  case southEastResize, southWestResize, westResize, eastWestResize, northSouthResize
  case northEastSouthWestResize, northWestSouthEastResize, columnResize, rowResize
  case allScroll, zoomIn, zoomOut
}

@MainActor final class WaylandCursor {
  private let objects: WaylandObjects
  var manager: UInt32 = 0
  private var device: UInt32 = 0
  private var serial: UInt32?
  private var surface: UInt32 = 0
  private var shapes: [UInt32: WaylandCursorShape] = [:]
  init(objects: WaylandObjects) { self.objects = objects }

  func attach(pointer: UInt32) {
    guard device == 0, manager != 0, pointer != 0 else { return }
    device = objects.create(manager, 1, "wp_cursor_shape_device_v1", [.uint(pointer)])
    apply()
  }
  func enter(surface: UInt32, serial: UInt32) {
    self.surface = surface
    self.serial = serial
    apply()
  }
  func leave() {
    serial = nil
    surface = 0
  }
  func set(_ shape: WaylandCursorShape, on surface: UInt32) {
    guard shapes[surface] != shape else { return }
    shapes[surface] = shape
    if self.surface == surface { apply() }
  }
  func forget(_ surface: UInt32) {
    shapes[surface] = nil
    if self.surface == surface { leave() }
  }
  private func apply() {
    guard device != 0, let serial else { return }
    objects.request(device, 1, [.uint(serial), .uint((shapes[surface] ?? .default).rawValue)])
  }
  func detach() {
    objects.request(device, 0)
    device = 0
    leave()
  }
  func close() {
    // Manager removal does not end pointer focus; reuse the enter serial if it returns.
    objects.request(device, 0)
    device = 0
    objects.request(manager, 0)
    manager = 0
  }
}
