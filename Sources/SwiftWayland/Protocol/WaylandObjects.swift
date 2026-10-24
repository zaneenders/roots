@MainActor final class WaylandObjects {
  private var nextID: UInt32 = 2
  private var released: [UInt32] = []
  private var retired: Set<UInt32> = []
  private(set) var interfaces: [UInt32: String] = [1: "wl_display"]
  private var requests: [WirePacket] = []
  private var queuedBytes = 0
  private var queuedDescriptors = 0
  private var failure: (any Error)?
  var requestQueued: (@MainActor () -> Void)?

  func allocate(_ interface: String) -> UInt32 {
    let id: UInt32
    if let reusable = released.popLast() {
      id = reusable
    } else {
      id = nextID
      nextID += 1
    }
    register(id, interface)
    return id
  }
  func register(_ id: UInt32, _ interface: String) {
    retired.remove(id)
    interfaces[id] = interface
  }
  func isLive(_ id: UInt32) -> Bool { interfaces[id] != nil && !retired.contains(id) }
  func retire(_ id: UInt32) {
    if id != 0 { retired.insert(id) }
  }
  func deleted(_ id: UInt32) {
    guard id > 1, id < 0xff00_0000, interfaces.removeValue(forKey: id) != nil else { return }
    retired.remove(id)
    released.append(id)
  }
  func request(_ object: UInt32, _ opcode: UInt16, _ arguments: [WireValue] = []) {
    guard failure == nil, object != 0, !retired.contains(object) else { return }
    do {
      guard let interface = interfaces[object], let signatures = WireSchema.requests[interface],
        Int(opcode) < signatures.count
      else { throw WaylandError.invalidConfiguration }
      let actual = arguments.map { value -> String in
        switch value {
        case .uint: "u"
        case .int: "i"
        case .string: "s"
        case .array: "a"
        case .fd: "h"
        }
      }.joined()
      guard actual == signatures[Int(opcode)] else { throw WaylandError.invalidConfiguration }
      let packet = try WirePacket(object: object, opcode: opcode, arguments: arguments)
      guard packet.bytes.readableBytes <= WireBatch.maximumBytes - queuedBytes,
        packet.descriptors.count <= WireBatch.maximumDescriptors - queuedDescriptors
      else { throw WaylandError.dispatch }
      queuedBytes += packet.bytes.readableBytes
      queuedDescriptors += packet.descriptors.count
      requests.append(packet)
      if WireSchema.destructors[interface] == opcode { retire(object) }
    } catch { failure = error }
    requestQueued?()
  }
  func create(_ parent: UInt32, _ opcode: UInt16, _ interface: String, _ tail: [WireValue] = [])
    -> UInt32
  {
    let id = allocate(interface)
    request(parent, opcode, [.uint(id)] + tail)
    return id
  }
  func bind(_ registry: UInt32, _ name: UInt32, _ interface: String, _ version: UInt32) -> UInt32 {
    let id = allocate(interface)
    request(registry, 0, [.uint(name), .string(interface), .uint(version), .uint(id)])
    return id
  }
  func takeRequests() throws -> [WirePacket] {
    if let failure { throw failure }
    let result = requests
    requests.removeAll(keepingCapacity: true)
    queuedBytes = 0
    queuedDescriptors = 0
    return result
  }
  func discard() {
    requests.removeAll()
    queuedBytes = 0
    queuedDescriptors = 0
    requestQueued = nil
  }
}
