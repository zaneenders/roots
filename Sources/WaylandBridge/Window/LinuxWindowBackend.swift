import Foundation

/// Linux window-system selection. Automatic fallback is restricted to startup.
public enum LinuxWindowBackend: String, Sendable, CaseIterable {
  case auto, wayland, x11

  public init(arguments: [String]) throws {
    let positions = arguments.indices.filter { arguments[$0] == "--backend" }
    guard positions.count <= 1 else { throw NativeWindowError.invalidConfiguration }
    guard let index = positions.first else {
      self = .auto
      return
    }
    guard index + 1 < arguments.count, let backend = Self(rawValue: arguments[index + 1]) else {
      throw NativeWindowError.invalidConfiguration
    }
    self = backend
  }

  func candidates(
    topBar: Bool = false, environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> [Self] {
    guard self == .auto else { return [self] }
    // Layer-shell bars, popup grabs and idle inhibition are compositor protocols, not X11 toplevels.
    if topBar { return [.wayland] }
    let wayland =
      !(environment["WAYLAND_DISPLAY"] ?? "").isEmpty
      || !(environment["WAYLAND_SOCKET"] ?? "").isEmpty
    let x11 = !(environment["DISPLAY"] ?? "").isEmpty
    if wayland { return x11 ? [.wayland, .x11] : [.wayland] }
    if x11 { return [.x11] }
    return [.wayland, .x11]
  }
}
