import NIOCore
import Testing

@testable import SwiftWayland

@Test @MainActor func boundVersionsPropagateToChildrenAndRejectNewerRequests() throws {
  let objects = WaylandObjects()
  let registry = objects.create(1, WlDisplayRequest.getRegistry, "wl_registry")
  let compositor = objects.bind(registry, 1, "wl_compositor", 3)
  let surface = objects.create(compositor, WlCompositorRequest.createSurface, "wl_surface")
  let callback = objects.create(surface, WlSurfaceRequest.frame, "wl_callback")
  #expect(objects.versions[compositor] == 3)
  #expect(objects.versions[surface] == 3)
  #expect(objects.versions[callback] == 1)
  objects.request(surface, WlSurfaceRequest.setBufferScale, [.int(2)])
  _ = try objects.takeRequests()
  objects.request(surface, WlSurfaceRequest.damageBuffer, [.int(0), .int(0), .int(1), .int(1)])
  #expect(throws: WaylandError.invalidConfiguration) { try objects.takeRequests() }
}

@Test @MainActor func typedRequestsRejectTheWrongInterface() throws {
  let objects = WaylandObjects()
  let surface = objects.allocate("wl_surface")
  objects.request(surface, WlBufferRequest.destroy)
  #expect(throws: WaylandError.invalidConfiguration) { try objects.takeRequests() }
  #expect(objects.isLive(surface))
}

@Test(arguments: [UInt32(0), 8]) @MainActor func invalidBindVersionsAreNotQueued(version: UInt32) {
  let objects = WaylandObjects()
  let registry = objects.create(1, WlDisplayRequest.getRegistry, "wl_registry")
  #expect(objects.bind(registry, 1, "wl_compositor", version) == 0)
  #expect(throws: WaylandError.invalidConfiguration) { try objects.takeRequests() }
}

@Test(arguments: [UInt32(7), 8]) func eventsRespectNegotiatedVersion(version: UInt32) throws {
  var decoder = WireDecoder()
  var event = try WirePacket(object: 2, opcode: 9, arguments: [.uint(0), .int(120)])
  try decoder.append(&event.bytes, descriptors: [])
  if version == 7 {
    #expect(throws: WaylandError.dispatch) {
      try decoder.next(interfaces: [2: "wl_pointer"], versions: [2: version])
    }
  } else {
    #expect(try decoder.next(interfaces: [2: "wl_pointer"], versions: [2: version])?.opcode == 9)
  }
}

@MainActor private func reclamationCallback(_ objects: WaylandObjects) throws -> UInt32 {
  let requests = try objects.takeRequests()
  let sync = try #require(requests.last)
  #expect(sync.bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == 1)
  #expect(sync.bytes.getInteger(at: 4, endianness: .host, as: UInt32.self) == 12 << 16)
  return try #require(sync.bytes.getInteger(at: 8, endianness: .host))
}

@Test @MainActor func serverTombstonesDecodeLateEventsUntilTheSyncBarrier() throws {
  let objects = WaylandObjects()
  let id: UInt32 = 0xff00_0000
  objects.register(id, "wl_buffer")
  objects.request(id, WlBufferRequest.destroy)
  let callback = try reclamationCallback(objects)
  #expect(!objects.isLive(id))
  var decoder = WireDecoder()
  var release = try WirePacket(object: id, opcode: 0, arguments: [])
  try decoder.append(&release.bytes, descriptors: [])
  #expect(
    try decoder.next(interfaces: objects.interfaces, versions: objects.versions)?.object == id)
  objects.completeReclamation(callback + 1)
  #expect(objects.interfaces[id] != nil)
  objects.completeReclamation(callback)
  #expect(objects.interfaces[id] == nil && objects.versions[id] == nil)
  #expect(objects.interfaces[callback] == "wl_callback")
  objects.deleted(callback)
  #expect(objects.allocate("wl_surface") == callback)
}

@Test(arguments: [false, true]) @MainActor func reclamationPreservesReusedServerIDs(
  retireAgain: Bool
) throws {
  let objects = WaylandObjects()
  let id: UInt32 = 0xff00_0000
  objects.register(id, "wl_buffer")
  objects.request(id, WlBufferRequest.destroy)
  let first = try reclamationCallback(objects)
  objects.register(id, "wl_data_offer", version: 3)
  if retireAgain { objects.request(id, WlDataOfferRequest.destroy) }
  // Only one reclamation callback is allowed in flight.
  #expect(try objects.takeRequests().count == (retireAgain ? 1 : 0))
  objects.completeReclamation(first)
  #expect(objects.interfaces[id] == "wl_data_offer" && objects.versions[id] == 3)
  if retireAgain {
    let second = try reclamationCallback(objects)
    objects.completeReclamation(second)
    #expect(objects.interfaces[id] == nil)
  } else {
    #expect(objects.isLive(id))
    #expect(try objects.takeRequests().isEmpty)
  }
}

@Test @MainActor func clipboardAndBufferChurnReclaimsServerMetadata() throws {
  let objects = WaylandObjects()
  let manager = objects.allocate("wl_data_device_manager")
  let clipboard = WaylandClipboard(objects: objects)
  clipboard.manager = manager
  clipboard.attach(seat: objects.allocate("wl_seat"))
  let device = try #require(
    try objects.takeRequests().first?.bytes.getInteger(
      at: 8, endianness: .host, as: UInt32.self))
  let dmabuf = WaylandDMABuf(objects: objects)
  let params = objects.allocate("zwp_linux_buffer_params_v1")
  objects.request(params, ZwpLinuxBufferParamsV1Request.destroy)
  _ = try objects.takeRequests()
  let baseline = objects.interfaces.count
  for index: UInt32 in 0..<256 {
    let offer = 0xff00_0000 + index * 2
    clipboard.event(.init(object: device, opcode: 0, arguments: [.uint(offer)]))
    clipboard.event(.init(object: device, opcode: 5, arguments: [.uint(offer)]))
    clipboard.event(.init(object: device, opcode: 5, arguments: [.uint(0)]))
    dmabuf.event(.init(object: params, opcode: 0, arguments: [.uint(offer + 1)]))
    let callback = try reclamationCallback(objects)
    #expect(objects.interfaces.count == baseline + 3)
    objects.completeReclamation(callback)
    objects.deleted(callback)
    #expect(objects.interfaces.count == baseline)
    #expect(objects.versions.count == baseline)
  }
  objects.discard()
  #expect(objects.interfaces.isEmpty && objects.versions.isEmpty)
}
