import Foundation
import Metal
import Roots

struct MetalFrameCompletion: Sendable {
  let frameID: UInt64
  let slotID: Int
  let error: String?
}

private struct MetalFrameSlot: ~Copyable {
  var vertices: (any MTLBuffer)?
  var readback: (any MTLBuffer)?
  var frameID: UInt64?
  var drawableSize = SIMD2<Int32>.zero
  var rowBytes = 0
  var capturesImage = false
}

@safe @MainActor final class MetalRenderer {
  let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private let polylinePipeline: any MTLRenderPipelineState
  private let pipeline: any MTLRenderPipelineState
  private let atlas: any MTLTexture
  private let emojiAtlas: any MTLTexture
  private let sampler: any MTLSamplerState
  private var slots = UniqueArray<MetalFrameSlot>()
  private var frameState = MetalFrameState()
  private var nextFrameID: UInt64 = 0
  private var frameBorrowed = false
  private let offscreenTarget: (any MTLTexture)?
  private let offscreenLogicalSize: SIMD2<Float>?

  var hasFreeSlot: Bool { slots.indices.contains { slots[$0].frameID == nil } }
  var hasPendingFrames: Bool { slots.indices.contains { slots[$0].frameID != nil } }

  init(logicalSize: SIMD2<Float>? = nil, drawableSize: SIMD2<Int32>? = nil) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw MacOSWindowError.deviceUnavailable
    }
    self.device = device
    self.queue = queue
    pipeline = try Self.makePipeline(device: device)
    polylinePipeline = try Self.makePipeline(device: device, polyline: true)
    atlas = try Self.makeAtlas(device: device)
    emojiAtlas = try Self.makeEmojiAtlas(device: device)
    let descriptor = MTLSamplerDescriptor()
    descriptor.minFilter = .linear
    descriptor.magFilter = .linear
    descriptor.mipFilter = .linear
    descriptor.sAddressMode = .clampToEdge
    descriptor.tAddressMode = .clampToEdge
    guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
      throw MacOSWindowError.resourceAllocation
    }
    self.sampler = sampler
    if let logicalSize, let drawableSize {
      try Self.validate(logicalSize: logicalSize, drawableSize: drawableSize)
      offscreenTarget = try Self.makeTarget(device: device, size: drawableSize)
      offscreenLogicalSize = logicalSize
    } else {
      offscreenTarget = nil
      offscreenLogicalSize = nil
    }
    for _ in 0..<3 { slots.append(MetalFrameSlot()) }
  }

  static func validate(logicalSize: SIMD2<Float>, drawableSize: SIMD2<Int32>) throws {
    guard logicalSize.x.isFinite, logicalSize.y.isFinite, logicalSize.x > 0, logicalSize.y > 0,
      drawableSize.x > 0, drawableSize.y > 0, drawableSize.x <= 16_384, drawableSize.y <= 16_384
    else { throw MacOSWindowError.invalidConfiguration }
  }

  @discardableResult
  func submit(
    logicalSize: SIMD2<Float>, target: any MTLTexture, drawable: (any MTLDrawable)? = nil,
    readback: Bool, completions: AsyncStream<MetalFrameCompletion>.Continuation,
    frame: @MainActor (inout MetalRenderFrame) -> Void
  ) throws -> Bool {
    precondition(!frameBorrowed, "Renderer reentry during a frame")
    guard let slotID = slots.indices.first(where: { slots[$0].frameID == nil }) else {
      return false
    }
    let size = SIMD2<Int32>(Int32(target.width), Int32(target.height))
    try Self.validate(logicalSize: logicalSize, drawableSize: size)
    frameBorrowed = true
    frameState.begin(logicalSize: logicalSize, drawableSize: size)
    frameState.withFrame(frame)
    frameBorrowed = false
    guard let command = queue.makeCommandBuffer() else { throw MacOSWindowError.resourceAllocation }
    let renderTarget =
      readback && drawable != nil ? try Self.makeTarget(device: device, size: size) : target
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = renderTarget
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(
      red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      throw MacOSWindowError.resourceAllocation
    }
    do {
      try encodeDraws(encoder, slotID: slotID, logicalSize: logicalSize, drawableSize: size)
      encoder.endEncoding()
    } catch {
      encoder.endEncoding()
      throw error
    }
    let rowBytes = (target.width * 4 + 255) & ~255
    if readback {
      if slots[slotID].readback == nil || slots[slotID].readback!.length < rowBytes * target.height {
        slots[slotID].readback = device.makeBuffer(
          length: rowBytes * target.height, options: .storageModeShared)
      }
      guard let buffer = slots[slotID].readback, let blit = command.makeBlitCommandEncoder() else {
        throw MacOSWindowError.resourceAllocation
      }
      let extent = MTLSize(width: target.width, height: target.height, depth: 1)
      blit.copy(
        from: renderTarget, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
        sourceSize: extent,
        to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes,
        destinationBytesPerImage: rowBytes * target.height)
      if drawable != nil {
        blit.copy(
          from: renderTarget, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
          sourceSize: extent,
          to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
      }
      blit.endEncoding()
    }
    let frameID = nextFrameID
    nextFrameID += 1
    slots[slotID].frameID = frameID
    slots[slotID].drawableSize = size
    slots[slotID].rowBytes = rowBytes
    slots[slotID].capturesImage = readback
    command.addCompletedHandler { completed in
      completions.yield(
        MetalFrameCompletion(
          frameID: frameID, slotID: slotID,
          error: completed.status == .completed
            ? nil : completed.error?.localizedDescription ?? "Metal command buffer failed"))
    }
    if let drawable { command.present(drawable) }
    command.commit()
    return true
  }

  func complete(_ completion: MetalFrameCompletion) throws -> Data? {
    precondition(!frameBorrowed)
    guard slots.indices.contains(completion.slotID),
      slots[completion.slotID].frameID == completion.frameID
    else {
      throw MacOSWindowError.rendering("Unexpected frame completion")
    }
    defer { slots[completion.slotID].frameID = nil }
    if let error = completion.error { throw MacOSWindowError.rendering(error) }
    return slots[completion.slotID].capturesImage
      ? Self.makePPM(slot: slots[completion.slotID]) : nil
  }

  func render(readback: Bool, frame: @MainActor (inout MetalRenderFrame) -> Void) async throws
    -> Data?
  {
    guard !hasPendingFrames else { throw MacOSWindowError.alreadyRunning }
    guard let target = offscreenTarget, let logicalSize = offscreenLogicalSize else {
      throw MacOSWindowError.invalidConfiguration
    }
    try Task.checkCancellation()
    let (stream, continuation) = AsyncStream<MetalFrameCompletion>.makeStream()
    defer { continuation.finish() }
    try submit(
      logicalSize: logicalSize, target: target, readback: readback, completions: continuation,
      frame: frame)
    let completion = await Task.detached {
      var iterator = stream.makeAsyncIterator()
      return await iterator.next()!
    }.value
    let image = try complete(completion)
    try Task.checkCancellation()
    return image
  }

  private func encodeDraws(
    _ encoder: any MTLRenderCommandEncoder, slotID: Int, logicalSize: SIMD2<Float>,
    drawableSize: SIMD2<Int32>
  ) throws {
    guard !frameState.runs.isEmpty else { return }
    let (byteCount, overflow) = max(1, frameState.vertices.count).multipliedReportingOverflow(
      by: MemoryLayout<MetalVertex>.stride)
    guard !overflow, byteCount <= device.maxBufferLength else {
      throw MacOSWindowError.resourceAllocation
    }
    if slots[slotID].vertices == nil || slots[slotID].vertices!.length < byteCount {
      slots[slotID].vertices = device.makeBuffer(length: byteCount, options: .storageModeShared)
    }
    guard let buffer = slots[slotID].vertices else { throw MacOSWindowError.resourceAllocation }
    if !frameState.vertices.isEmpty {
      frameState.vertices.withUnsafeBytes { bytes in
        unsafe buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
      }
    }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
    var resolution = logicalSize
    unsafe encoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
    encoder.setFragmentTexture(atlas, index: 0)
    encoder.setFragmentSamplerState(sampler, index: 0)
    encoder.setFragmentTexture(emojiAtlas, index: 1)
    encoder.setFragmentSamplerState(sampler, index: 1)
    for run in frameState.runs {
      let clip =
        run.scissor
        ?? MetalScissorRect(
          Region(0, 0, logicalSize.x, logicalSize.y), logicalSize: logicalSize,
          drawableSize: drawableSize)
      encoder.setScissorRect(
        MTLScissorRect(x: clip.x, y: clip.y, width: clip.width, height: clip.height))
      if let draw = run.polyline, let stroke = draw.polyline {
        encoder.setRenderPipelineState(polylinePipeline)
        let b = stroke.bounds
        var bounds = SIMD4(b.x, b.y, b.width, b.height)
        var count = UInt32(stroke.points.count)
        var width = stroke.width
        var color = SIMD4(draw.color.r, draw.color.g, draw.color.b, draw.color.a)
        unsafe encoder.setVertexBytes(&bounds, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        stroke.points.withUnsafeBytes { bytes in
          unsafe encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        unsafe encoder.setFragmentBytes(&count, length: MemoryLayout<UInt32>.stride, index: 1)
        unsafe encoder.setFragmentBytes(&width, length: MemoryLayout<Float>.stride, index: 2)
        unsafe encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      } else {
        encoder.drawPrimitives(
          type: .triangle, vertexStart: 0, vertexCount: 6,
          instanceCount: run.vertexCount, baseInstance: run.firstVertex)
      }
    }
  }

  private static func makePPM(slot: borrowing MetalFrameSlot) -> Data {
    let width = Int(slot.drawableSize.x)
    let height = Int(slot.drawableSize.y)
    var result = Data("P6\n\(width) \(height)\n255\n".utf8)
    result.reserveCapacity(result.count + width * height * 3)
    let bytes = unsafe UnsafeRawBufferPointer(
      start: slot.readback!.contents(), count: slot.rowBytes * height)
    for y in 0..<height {
      for x in 0..<width {
        let offset = y * slot.rowBytes + x * 4
        unsafe result.append(bytes[offset + 2])
        unsafe result.append(bytes[offset + 1])
        unsafe result.append(bytes[offset])
      }
    }
    return result
  }

  private static func makeTarget(device: any MTLDevice, size: SIMD2<Int32>) throws -> any MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: Int(size.x), height: Int(size.y), mipmapped: false)
    descriptor.storageMode = .private
    descriptor.usage = .renderTarget
    guard let target = device.makeTexture(descriptor: descriptor) else {
      throw MacOSWindowError.resourceAllocation
    }
    return target
  }

  private static func makeEmojiAtlas(device: any MTLDevice) throws -> any MTLTexture {
    let atlas = EmojiAtlas.shared
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: atlas.width, height: atlas.height, mipmapped: true)
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw MacOSWindowError.resourceAllocation
    }
    for (level, mip) in atlas.mipLevels.enumerated() {
      mip.pixels.withUnsafeBytes { bytes in
        unsafe texture.replace(
          region: MTLRegionMake2D(0, 0, mip.width, mip.height), mipmapLevel: level,
          withBytes: bytes.baseAddress!, bytesPerRow: mip.width * 4)
      }
    }
    return texture
  }

  private static func makePipeline(device: any MTLDevice, polyline: Bool = false) throws
    -> any MTLRenderPipelineState
  {
    guard
      let url = Bundle.module.url(
        forResource: "Rectangle", withExtension: "metal", subdirectory: "Shaders")
    else {
      throw MacOSWindowError.missingShader
    }
    let library = try device.makeLibrary(
      source: String(contentsOf: url, encoding: .utf8), options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(
      name: polyline ? "polylineVertex" : "rectangleVertex")
    descriptor.fragmentFunction = library.makeFunction(
      name: polyline ? "polylineFragment" : "rectangleFragment")
    let vertices = MTLVertexDescriptor()
    let offsets = [
      MemoryLayout<MetalVertex>.offset(of: \.position)!,
      MemoryLayout<MetalVertex>.offset(of: \.size)!, MemoryLayout<MetalVertex>.offset(of: \.color)!,
      MemoryLayout<MetalVertex>.offset(of: \.radius)!,
      MemoryLayout<MetalVertex>.offset(of: \.glyphUV)!,
      MemoryLayout<MetalVertex>.offset(of: \.textured)!,
      MemoryLayout<MetalVertex>.offset(of: \.strokeWidth)!,
      MemoryLayout<MetalVertex>.offset(of: \.axis)!
    ]
    let formats: [MTLVertexFormat] = [
      .float2, .float2, .float4, .float, .float4, .float, .float, .float2
    ]
    for index in offsets.indices {
      vertices.attributes[index].format = formats[index]
      vertices.attributes[index].offset = offsets[index]
      vertices.attributes[index].bufferIndex = 0
    }
    vertices.layouts[0].stride = MemoryLayout<MetalVertex>.stride
    vertices.layouts[0].stepFunction = .perInstance
    vertices.layouts[0].stepRate = 1
    if !polyline { descriptor.vertexDescriptor = vertices }
    let color = descriptor.colorAttachments[0]!
    color.pixelFormat = .bgra8Unorm
    color.isBlendingEnabled = true
    color.sourceRGBBlendFactor = .sourceAlpha
    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.sourceAlphaBlendFactor = .one
    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return try device.makeRenderPipelineState(descriptor: descriptor)
  }

  private static func makeAtlas(device: any MTLDevice) throws -> any MTLTexture {
    let atlas = FontAtlas.shared
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r8Unorm, width: atlas.width, height: atlas.height, mipmapped: true)
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw MacOSWindowError.resourceAllocation
    }
    for (level, mip) in atlas.mipLevels.enumerated() {
      mip.pixels.withUnsafeBytes { bytes in
        unsafe texture.replace(
          region: MTLRegionMake2D(0, 0, mip.width, mip.height), mipmapLevel: level,
          withBytes: bytes.baseAddress!, bytesPerRow: mip.width)
      }
    }
    return texture
  }
}
