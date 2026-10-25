@MainActor final class WaylandObjects {
  private static let serverIDStart: UInt32 = 0xff00_0000
  private var nextID: UInt32 = 2
  private var released: [UInt32] = []
  private var retired: Set<UInt32> = []
  private(set) var interfaces: [UInt32: String] = [1: "wl_display"]
  private(set) var versions: [UInt32: UInt32] = [1: 1]
  private var generation: UInt64 = 0
  private var serverGenerations: [UInt32: UInt64] = [:]
  private var pendingReclamation: [UInt32: UInt64] = [:]
  private var reclamation: (callback: UInt32, generations: [UInt32: UInt64])?
  private var requests: [WirePacket] = []
  private var queuedBytes = 0
  private var queuedDescriptors = 0
  private var failure: (any Error)?
  var requestQueued: (@MainActor () -> Void)?

  func allocate(_ interface: String, version: UInt32 = 1) -> UInt32 {
    let id: UInt32
    if let reusable = released.popLast() {
      id = reusable
    } else {
      guard nextID < Self.serverIDStart else {
        failure = WaylandError.dispatch
        return 0
      }
      id = nextID
      nextID += 1
    }
    register(id, interface, version: version)
    return id
  }
  func register(_ id: UInt32, _ interface: String, version: UInt32 = 1) {
    retired.remove(id)
    interfaces[id] = interface
    versions[id] = version
    if id >= Self.serverIDStart {
      generation += 1
      serverGenerations[id] = generation
      pendingReclamation.removeValue(forKey: id)
    }
  }
  func isLive(_ id: UInt32) -> Bool { interfaces[id] != nil && !retired.contains(id) }
  func retire(_ id: UInt32) {
    guard interfaces[id] != nil else { return }
    retired.insert(id)
    if let generation = serverGenerations[id] { pendingReclamation[id] = generation }
  }
  func deleted(_ id: UInt32) {
    guard id > 1, id < Self.serverIDStart, interfaces.removeValue(forKey: id) != nil else { return }
    versions.removeValue(forKey: id)
    retired.remove(id)
    released.append(id)
  }
  func completeReclamation(_ callback: UInt32) {
    guard let reclamation, reclamation.callback == callback else { return }
    for (id, generation) in reclamation.generations
    where serverGenerations[id] == generation && retired.contains(id) {
      interfaces.removeValue(forKey: id)
      versions.removeValue(forKey: id)
      serverGenerations.removeValue(forKey: id)
      retired.remove(id)
    }
    self.reclamation = nil
    if !pendingReclamation.isEmpty { requestQueued?() }
  }
  func request<R: WireRequest>(_ object: UInt32, _ opcode: R, _ arguments: [WireValue] = []) {
    guard failure == nil, object != 0, !retired.contains(object) else { return }
    guard interfaces[object] == R.interface else {
      failure = WaylandError.invalidConfiguration
      requestQueued?()
      return
    }
    request(object, opcode.rawValue, arguments)
  }
  func request(_ object: UInt32, _ opcode: UInt16, _ arguments: [WireValue] = []) {
    guard failure == nil, object != 0, !retired.contains(object) else { return }
    do {
      guard let interface = interfaces[object], let messages = WireSchema.requests[interface],
        Int(opcode) < messages.count, let version = versions[object],
        messages[Int(opcode)].since <= version
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
      guard actual == messages[Int(opcode)].signature else {
        throw WaylandError.invalidConfiguration
      }
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
  func create<R: WireRequest>(
    _ parent: UInt32, _ opcode: R, _ interface: String, _ tail: [WireValue] = []
  ) -> UInt32 {
    let version = min(versions[parent] ?? 1, WireSchema.versions[interface] ?? 1)
    let id = allocate(interface, version: version)
    request(parent, opcode, [.uint(id)] + tail)
    return id
  }
  func bind(_ registry: UInt32, _ name: UInt32, _ interface: String, _ version: UInt32) -> UInt32 {
    guard version > 0, let maximum = WireSchema.versions[interface], version <= maximum else {
      failure = WaylandError.invalidConfiguration
      requestQueued?()
      return 0
    }
    let id = allocate(interface, version: version)
    request(
      registry, WlRegistryRequest.bind,
      [.uint(name), .string(interface), .uint(version), .uint(id)])
    return id
  }
  func takeRequests() throws -> [WirePacket] {
    if let failure { throw failure }
    if reclamation == nil, !pendingReclamation.isEmpty {
      // A sync after the destructors drains events already in flight for server IDs.
      let generations = pendingReclamation
      pendingReclamation.removeAll(keepingCapacity: true)
      let callback = create(1, WlDisplayRequest.sync, "wl_callback")
      reclamation = (callback, generations)
    }
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
    interfaces.removeAll()
    versions.removeAll()
    retired.removeAll()
    released.removeAll()
    serverGenerations.removeAll()
    pendingReclamation.removeAll()
    reclamation = nil
  }
}
