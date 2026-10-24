import SwiftWayland
import Testing

@testable import WaylandBridge

@Test func bridgePreservesStructuredWaylandProtocolErrors() {
  let failure = WaylandProtocolError(
    objectID: 42, interface: "wl_surface", code: 3, message: "invalid buffer scale")
  let error = NativeWindowError(WaylandError.protocolViolation(failure))
  #expect(error == .waylandProtocol(failure))
  #expect(
    error.description == "Wayland protocol violation: wl_surface@42: error 3: invalid buffer scale")
}
