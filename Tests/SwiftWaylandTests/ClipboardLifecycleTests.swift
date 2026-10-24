import Glibc
import SystemPackage
import Testing

@testable import SwiftWayland

@MainActor private func clipboardFixture() throws -> (WaylandClipboard, WaylandObjects, UInt32) {
  let objects = WaylandObjects()
  let manager = objects.allocate("wl_data_device_manager")
  let seat = objects.allocate("wl_seat")
  let clipboard = WaylandClipboard(objects: objects)
  clipboard.manager = manager
  clipboard.focused = true
  clipboard.serial = 7
  clipboard.attach(seat: seat)
  let (requests, _) = try objects.takeRequests()
  let packet = try #require(requests.first)
  let device: UInt32 = try #require(packet.bytes.getInteger(at: 8, endianness: .host))
  return (clipboard, objects, device)
}

@Test @MainActor func clipboardSelectionDoesNotRetireDragAndQueuedOffersCloseExactlyOnce() throws {
  let (clipboard, objects, device) = try clipboardFixture()
  let drag: UInt32 = 0xff00_0000
  let first = drag + 1
  let second = drag + 2
  for id in [drag, first, second] {
    clipboard.event(.init(object: device, opcode: 0, arguments: [.uint(id)]))
    clipboard.event(.init(object: id, opcode: 0, arguments: [.string("text/plain")]))
  }
  clipboard.event(
    .init(
      object: device, opcode: 1, arguments: [.uint(1), .uint(9), .int(0), .int(0), .uint(drag)]))
  clipboard.event(.init(object: device, opcode: 5, arguments: [.uint(first)]))
  clipboard.event(.init(object: device, opcode: 5, arguments: [.uint(second)]))
  let (selectionRequests, _) = try objects.takeRequests()
  #expect(selectionRequests.count == 1)
  #expect(selectionRequests[0].bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == first)
  clipboard.close()
  clipboard.close()
  let (closed, _) = try objects.takeRequests()
  #expect(closed.count == 2)
}

@Test @MainActor func clipboardReceiveQueuesOwnedFDAndLeavesCallerReadEndAlive() throws {
  let (clipboard, objects, device) = try clipboardFixture()
  let offer: UInt32 = 0xff00_0000
  clipboard.event(.init(object: device, opcode: 0, arguments: [.uint(offer)]))
  clipboard.event(.init(object: offer, opcode: 0, arguments: [.string("text/plain;charset=utf-8")]))
  clipboard.event(.init(object: device, opcode: 5, arguments: [.uint(offer)]))
  guard let reader = clipboard.beginRead() else {
    Issue.record("Missing clipboard reader")
    return
  }
  let descriptorValue = reader.descriptor
  let readDescriptor = try #require(descriptorValue)
  let (requests, _) = try objects.takeRequests()
  let descriptor = try #require(requests.first?.descriptors.first)
  #expect(descriptor.borrow { fcntl($0, F_GETFD) & FD_CLOEXEC != 0 })
  #expect(fcntl(readDescriptor.rawValue, F_GETFD) & FD_CLOEXEC != 0)
  #expect(fcntl(readDescriptor.rawValue, F_GETFL) & O_NONBLOCK != 0)
  descriptor.close()
  #expect(fcntl(readDescriptor.rawValue, F_GETFD) >= 0)
  clipboard.close()
}

@Test @MainActor func clipboardSourceCancellationPreservesInFlightSnapshot() async throws {
  let (clipboard, objects, _) = try clipboardFixture()
  let text = "hello café 🙂"
  #expect(clipboard.write(text))
  let (requests, _) = try objects.takeRequests()
  let source: UInt32 = try #require(requests.first?.bytes.getInteger(at: 8, endianness: .host))
  let pipe = try FileDescriptor.pipe(options: [.closeOnExec, .nonBlocking])
  clipboard.event(
    .init(
      object: source, opcode: 1,
      arguments: [.string("text/plain"), .fd(WireDescriptor(taking: pipe.writeEnd.rawValue))]
    ))
  clipboard.event(.init(object: source, opcode: 2, arguments: []))
  clipboard.close()
  let bytes = try await ClipboardIO().read(from: OwnedFD(taking: pipe.readEnd))
  #expect(String(bytes: bytes, encoding: .utf8) == text)
}

@Test @MainActor func retiredDataDeviceStillDestroysLateOffers() throws {
  let (clipboard, objects, device) = try clipboardFixture()
  clipboard.detachSeat()
  #expect(!objects.isLive(device))
  let offer: UInt32 = 0xff00_0000
  clipboard.event(.init(object: device, opcode: 0, arguments: [.uint(offer)]))
  #expect(objects.interfaces[offer] == "wl_data_offer" && !objects.isLive(offer))
  let requests = try objects.takeRequests().0
  #expect(requests.count == 1)
  #expect(requests.first?.bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == offer)
}
