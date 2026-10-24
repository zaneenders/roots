import SystemPackage

@MainActor final class WaylandClipboard {
  static let textTypes = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING"]
  let io = ClipboardIO()
  private let objects: WaylandObjects
  var manager: UInt32 = 0
  private var device: UInt32 = 0
  private var offers: [UInt32: Set<String>] = [:]
  private var selection: UInt32 = 0
  private var drag: UInt32 = 0
  private var source: UInt32 = 0
  private var payload: [UInt8] = []
  var serial: UInt32?
  var focused = false
  init(objects: WaylandObjects) { self.objects = objects }

  func attach(seat: UInt32) {
    guard device == 0, manager != 0 else { return }
    device = objects.create(
      manager, WlDataDeviceManagerRequest.getDataDevice, "wl_data_device", [.uint(seat)])
  }
  private func retire(_ id: UInt32) {
    guard id != 0, offers.removeValue(forKey: id) != nil else { return }
    objects.request(id, WlDataOfferRequest.destroy)
  }
  func event(_ message: WireMessage) {
    let a = message.arguments
    if message.opcode == 0, objects.interfaces[message.object] == "wl_data_device",
      message.object != device
    {
      objects.register(a[0].word, "wl_data_offer", version: objects.versions[message.object] ?? 1)
      objects.request(a[0].word, WlDataOfferRequest.destroy)
      return
    }
    if message.object == device {
      switch message.opcode {
      case 0:
        let id = a[0].word
        objects.register(id, "wl_data_offer", version: objects.versions[device] ?? 1)
        offers[id] = []
      case 1:
        retire(drag)
        drag = a[4].word
      case 2, 4:
        retire(drag)
        drag = 0
      case 5:
        retire(selection)
        selection = a[0].word
      default: break
      }
    } else if offers[message.object] != nil, message.opcode == 0, let mime = a[0].text {
      _ = offers[message.object, default: []].insert(mime)
    } else if message.object == source {
      if message.opcode == 1, case .fd(let fd) = a[1] {
        guard let mime = a[0].text, Self.textTypes.contains(mime) else {
          fd.close()
          return
        }
        let bytes = payload
        Task { [io] in
          try? await io.write(bytes, to: OwnedFD(taking: FileDescriptor(rawValue: fd.take())))
        }
      } else if message.opcode == 2 {
        objects.request(source, WlDataSourceRequest.destroy)
        source = 0
        payload.removeAll()
      }
    }
  }
  func write(_ text: String) -> Bool {
    guard focused, let serial, manager != 0, device != 0,
      text.utf8.count <= ClipboardIO.maximumBytes
    else {
      return false
    }
    objects.request(source, WlDataSourceRequest.destroy)
    source = objects.create(manager, WlDataDeviceManagerRequest.createDataSource, "wl_data_source")
    payload = Array(text.utf8)
    for mime in Self.textTypes {
      objects.request(source, WlDataSourceRequest.offer, [.string(mime)])
    }
    objects.request(device, WlDataDeviceRequest.setSelection, [.uint(source), .uint(serial)])
    return true
  }
  func beginRead() -> OwnedFD? {
    guard focused, let types = offers[selection],
      let mime = Self.textTypes.first(where: types.contains)
    else {
      return nil
    }
    // The source application may use blocking writes. NIO makes only our read
    // end nonblocking when ClipboardIO takes ownership of it.
    guard let pipe = try? FileDescriptor.pipe(options: .closeOnExec) else { return nil }
    let read = OwnedFD(taking: pipe.readEnd)
    let write = WireDescriptor(taking: pipe.writeEnd.rawValue)
    objects.request(selection, WlDataOfferRequest.receive, [.string(mime), .fd(write)])
    return read
  }
  func detachSeat() {
    for id in Array(offers.keys) { retire(id) }
    objects.retire(device)
    device = 0
    selection = 0
    drag = 0
    serial = nil
    focused = false
  }
  func close() {
    detachSeat()
    objects.request(source, WlDataSourceRequest.destroy)
    source = 0
    payload.removeAll()
    objects.retire(manager)
    manager = 0
  }
}
