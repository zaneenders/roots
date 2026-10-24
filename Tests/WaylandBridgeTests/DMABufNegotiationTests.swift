import CEGLGLES
import DesktopTestSupport
import Glibc
import Testing

@testable import SwiftWayland
@testable import WaylandBridge

@Test func dmabufCandidatesPreserveTranchePriorityAndRequireAlpha() {
  let argb = WaylandDMABufFormat(format: 0x3432_5241, modifier: 7)
  let abgr = WaylandDMABufFormat(format: 0x3432_4241, modifier: 0)
  let xrgb = WaylandDMABufFormat(format: 0x3432_5258, modifier: 0)
  let feedback = WaylandDMABufFeedback(
    mainDevice: 123,
    tranches: [
      .init(device: 456, flags: 1, formats: [xrgb, argb]),
      .init(device: 123, flags: 0, formats: [argb, abgr]),
    ])
  #expect(dmabufCandidates(feedback) == [argb, abgr])
  #expect(dmabufCandidates(feedback, excluding: [argb]) == [abgr])
  #expect(dmabufCandidates(feedback, excluding: [argb, abgr]).isEmpty)
}

@Test @MainActor func invalidDRMDeviceFailsWithoutFallingBackToAnUnrelatedGPU() {
  #expect(throws: NativeWindowError.self) { try DMABufDevice(device: UInt64.max) }
}

extension NativeSessionTests {
  @Test(
    .enabled("Wayland presentation is unavailable") { try await WaylandAvailability.presentation })
  func negotiatedRendererUsesFeedbackDeviceAndImportsAdvertisedBuffers() async throws {
    let host = NativeHost(configuration: .init(width: 64, height: 48))
    defer { host.cleanup() }
    try await host.connect()
    try host.setupRenderer(surfaceless: false)
    if let preferred = host.connection.dmabufPreferences?.mainDevice {
      let device = try #require(host.renderer.device)
      #expect(device.node == (try DMABufDevice.renderNode(for: preferred)))
      let retained = device
      try host.renderer.updateDMABufDevice(input: host.input, connection: host.connection)
      #expect(host.renderer.device === retained)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    var ready = false
    while !ready && ContinuousClock.now < deadline {
      try host.renderer.makeCurrent()
      ready = try host.preparePresentation()
      try host.renderer.releaseCurrent()
      if !ready { try await Task.sleep(for: .milliseconds(1)) }
    }
    #expect(ready)
  }
}
