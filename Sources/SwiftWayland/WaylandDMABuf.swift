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
      objects.request(id, WlBufferRequest.destroy)
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
    objects.request(params, ZwpLinuxBufferParamsV1Request.destroy)
    params = 0
    changed()
  }
  func released() {
    if state == .closed {
      objects.request(id, WlBufferRequest.destroy)
      id = 0
    } else if state == .submitted {
      state = .available
      changed()
    }
  }
  func present(on surface: UInt32) throws {
    guard state == .available else { throw WaylandError.busy }
    state = .submitted
    objects.request(
      surface, WlSurfaceRequest.setBufferTransform,
      [.int(WaylandBufferTransform.flipped180.rawValue)])
    objects.request(surface, WlSurfaceRequest.attach, [.uint(id), .int(0), .int(0)])
    objects.request(surface, WlSurfaceRequest.damage, [.int(0), .int(0), .int(.max), .int(.max)])
    objects.request(surface, WlSurfaceRequest.commit)
  }
  public func close() {
    guard state != .closed else { return }
    objects.request(params, ZwpLinuxBufferParamsV1Request.destroy)
    params = 0
    // Keep submitted buffers registered until the compositor releases its use.
    if state != .submitted {
      objects.request(id, WlBufferRequest.destroy)
      id = 0
    }
    state = .closed
  }
}

@MainActor final class WaylandDMABuf {
  var factory: UInt32 = 0
  var version: UInt32 = 3
  private var feedback: [UInt32: DMABufFeedback] = [:]
  private var formats: [UInt32: Set<UInt64>] = [:]
  private var retainedPreferences: [UInt32: WaylandDMABufFeedback] = [:]
  private var buffers: [WaylandDMABufBuffer] = []
  private let objects: WaylandObjects
  init(objects: WaylandObjects) { self.objects = objects }

  func watch(surface: UInt32 = 0) {
    guard factory != 0, version >= 4, feedback[surface] == nil else { return }
    let id = objects.create(
      factory, surface == 0 ? ZwpLinuxDmabufV1Request.getDefaultFeedback : .getSurfaceFeedback,
      "zwp_linux_dmabuf_feedback_v1",
      surface == 0 ? [] : [.uint(surface)])
    feedback[surface] = DMABufFeedback(id: id)
  }
  func unwatch(surface: UInt32) {
    retainedPreferences[surface] = nil
    if let removed = feedback.removeValue(forKey: surface) {
      objects.request(removed.id, ZwpLinuxDmabufFeedbackV1Request.destroy)
    }
  }
  func preferences(surface: UInt32 = 0) -> WaylandDMABufFeedback? {
    currentPreferences(surface: surface) ?? retainedPreferences[surface] ?? retainedPreferences[0]
  }
  func canImport(surface: UInt32) -> Bool { currentPreferences(surface: surface) != nil }
  private func currentPreferences(surface: UInt32) -> WaylandDMABufFeedback? {
    guard factory != 0 else { return nil }
    if version >= 4 { return feedback[surface]?.current ?? feedback[0]?.current }
    guard !formats.isEmpty else { return nil }
    return WaylandDMABufFeedback(
      mainDevice: nil,
      tranches: [
        .init(
          device: nil, flags: 0,
          formats: formats.flatMap { format, modifiers in
            modifiers.sorted().map { .init(format: format, modifier: $0) }
          }.sorted { $0.format < $1.format })
      ])
  }
  func ready(surface: UInt32) -> Bool {
    factory == 0 || version < 4 || feedback[surface]?.current != nil
  }
  func feedbackEvent(_ message: WireMessage) throws -> Bool {
    guard let target = feedback.values.first(where: { $0.id == message.object }) else {
      return false
    }
    return try target.event(message)
  }
  func modifier(format: UInt32, high: UInt32, low: UInt32) {
    _ = formats[format, default: []].insert(UInt64(high) << 32 | UInt64(low))
  }
  func importBuffer(
    width: Int32, height: Int32, format: UInt32, modifier: UInt64,
    planes: borrowing Span<WaylandDMABufPlane>, surface: UInt32 = 0,
    changed: @escaping @MainActor () -> Void
  ) throws -> WaylandDMABufBuffer {
    guard width > 0, height > 0, !planes.isEmpty, planes.count <= 4 else {
      throw WaylandError.invalidConfiguration
    }
    for plane in planes where plane.descriptor < 0 || plane.stride == 0 {
      throw WaylandError.invalidConfiguration
    }
    guard factory != 0,
      currentPreferences(surface: surface)?.supports(format: format, modifier: modifier) == true
    else {
      throw WaylandError.missingGlobals
    }
    var fds: [WireDescriptor] = []
    for plane in planes { fds.append(try WireDescriptor.duplicate(plane.descriptor)) }
    buffers.removeAll { $0.state == .closed && $0.id == 0 }
    let params = objects.create(
      factory, ZwpLinuxDmabufV1Request.createParams, "zwp_linux_buffer_params_v1")
    for index in planes.indices {
      objects.request(
        params, ZwpLinuxBufferParamsV1Request.add,
        [
          .fd(fds[index]), .uint(UInt32(index)), .uint(planes[index].offset),
          .uint(planes[index].stride), .uint(UInt32(truncatingIfNeeded: modifier >> 32)),
          .uint(UInt32(truncatingIfNeeded: modifier)),
        ])
    }
    objects.request(
      params, ZwpLinuxBufferParamsV1Request.create,
      [.int(width), .int(height), .uint(format), .uint(0)])
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
      if buffer.id == 0 { buffers.removeAll { $0 === buffer } }
    } else if message.opcode == 0,
      objects.interfaces[message.object] == "zwp_linux_buffer_params_v1"
    {
      let id = message.arguments[0].word
      objects.register(id, "wl_buffer")
      objects.request(id, WlBufferRequest.destroy)
    }
  }
  func owns(_ buffer: WaylandDMABufBuffer) -> Bool { buffers.contains { $0 === buffer } }
  func removeFactory() {
    guard factory != 0 else { return }
    // The factory's children remain valid. Keep completed feedback for reusing
    // their allocations, but require fresh announcements before importing again.
    var retained = retainedPreferences
    for surface in Set(feedback.keys).union(retained.keys).union([0]) {
      retained[surface] = preferences(surface: surface)
    }
    for surface in Array(feedback.keys) { unwatch(surface: surface) }
    formats.removeAll()
    factory = 0
    retainedPreferences = retained
  }
  func close(disconnecting: Bool = false) {
    for buffer in buffers { buffer.close() }
    // Explicitly closed submitted buffers still need their release events.
    buffers.removeAll { disconnecting || $0.id == 0 }
    removeFactory()
    retainedPreferences.removeAll()
  }
}
