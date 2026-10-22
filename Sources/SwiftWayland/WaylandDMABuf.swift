public struct WaylandDMABufPlane: Sendable {
  public let descriptor: Int32
  public let offset: UInt32
  public let stride: UInt32
  public init(descriptor: Int32, offset: UInt32, stride: UInt32) {
    self.descriptor = descriptor
    self.offset = offset
    self.stride = stride
  }
}

@MainActor public final class WaylandDMABufBuffer {
  public enum State: Equatable { case importing, available, submitted, failed, closed }
  public private(set) var state = State.importing
  private(set) var params: UInt32
  private(set) var id: UInt32 = 0
  private let objects: WaylandObjects
  private let changed: @MainActor () -> Void

  init(params: UInt32, objects: WaylandObjects, changed: @escaping @MainActor () -> Void) {
    self.params = params
    self.objects = objects
    self.changed = changed
  }
  func created(_ id: UInt32) {
    guard state == .importing else {
      objects.request(id, 0)
      return
    }
    self.id = id
    objects.register(id, "wl_buffer")
    state = .available
    finishImport()
  }
  func failed() {
    guard state == .importing else { return }
    state = .failed
    finishImport()
  }
  private func finishImport() {
    objects.request(params, 0)
    params = 0
    changed()
  }
  func released() {
    guard state == .submitted else { return }
    state = .available
    changed()
  }
  func present(on surface: UInt32) throws {
    guard state == .available else { throw WaylandError.busy }
    state = .submitted
    objects.request(surface, 7, [.int(6)])
    objects.request(surface, 1, [.uint(id), .int(0), .int(0)])
    objects.request(surface, 2, [.int(0), .int(0), .int(.max), .int(.max)])
    objects.request(surface, 6)
  }
  public func close() {
    guard state != .closed else { return }
    objects.request(params, 0)
    objects.request(id, 0)
    params = 0
    id = 0
    state = .closed
  }
}

@MainActor final class WaylandDMABuf {
  var factory: UInt32 = 0
  private var formats: [UInt32: Set<UInt64>] = [:]
  private var buffers: [WaylandDMABufBuffer] = []
  private let objects: WaylandObjects
  init(objects: WaylandObjects) { self.objects = objects }

  func modifier(format: UInt32, high: UInt32, low: UInt32) {
    _ = formats[format, default: []].insert(UInt64(high) << 32 | UInt64(low))
  }
  func importBuffer(
    width: Int32, height: Int32, format: UInt32, modifier: UInt64,
    planes: borrowing Span<WaylandDMABufPlane>, changed: @escaping @MainActor () -> Void
  ) throws -> WaylandDMABufBuffer {
    guard width > 0, height > 0, !planes.isEmpty, planes.count <= 4 else {
      throw WaylandError.invalidConfiguration
    }
    for plane in planes where plane.descriptor < 0 || plane.stride == 0 {
      throw WaylandError.invalidConfiguration
    }
    guard factory != 0, formats[format]?.contains(modifier) == true else {
      throw WaylandError.missingGlobals
    }
    var fds: [WireDescriptor] = []
    for plane in planes { fds.append(try WireDescriptor.duplicate(plane.descriptor)) }
    buffers.removeAll { $0.state == .closed }
    let params = objects.create(factory, 1, "zwp_linux_buffer_params_v1")
    for index in planes.indices {
      objects.request(
        params, 1,
        [
          .fd(fds[index]), .uint(UInt32(index)), .uint(planes[index].offset),
          .uint(planes[index].stride), .uint(UInt32(truncatingIfNeeded: modifier >> 32)),
          .uint(UInt32(truncatingIfNeeded: modifier)),
        ])
    }
    objects.request(params, 2, [.int(width), .int(height), .uint(format), .uint(0)])
    let buffer = WaylandDMABufBuffer(params: params, objects: objects, changed: changed)
    buffers.append(buffer)
    return buffer
  }
  func event(_ message: WireMessage) {
    if message.object == factory, message.opcode == 1 {
      modifier(
        format: message.arguments[0].word, high: message.arguments[1].word,
        low: message.arguments[2].word)
    } else if let buffer = buffers.first(where: { $0.params == message.object && $0.params != 0 }) {
      if message.opcode == 0 { buffer.created(message.arguments[0].word) } else { buffer.failed() }
    } else if let buffer = buffers.first(where: { $0.id == message.object && $0.id != 0 }) {
      buffer.released()
    } else if message.opcode == 0,
      objects.interfaces[message.object] == "zwp_linux_buffer_params_v1"
    {
      let id = message.arguments[0].word
      objects.register(id, "wl_buffer")
      objects.request(id, 0)
    }
  }
  func owns(_ buffer: WaylandDMABufBuffer) -> Bool { buffers.contains { $0 === buffer } }
  func close() {
    for buffer in buffers { buffer.close() }
    buffers.removeAll()
    formats.removeAll()
    factory = 0
  }
}
