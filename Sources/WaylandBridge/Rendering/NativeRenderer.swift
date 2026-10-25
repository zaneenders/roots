import CEGLGLES
import Foundation
import Roots
import SwiftWayland

@safe @MainActor final class NativeRenderer {
  private var display: EGLDisplay?
  private var ownsDisplay = true
  private(set) var device: DMABufDevice?
  private var dmabuf: DMABufPresenter?
  private var context: EGLContext?
  private var surface: EGLSurface?
  private var program: GLuint = 0
  private var polylineProgram: GLuint = 0
  private var polylineLocations: [GLint] = []
  private var vertexBuffer: GLuint = 0
  private var readbackBuffer: GLuint = 0
  private var images: [ObjectIdentifier: ImageTextures] = [:]
  private var usedImages: Set<ObjectIdentifier> = []
  private var imageLocations: [GLint] = []
  private var fontTexture: GLuint = 0
  private var emojiTexture: GLuint = 0
  private var resolutionLocation: GLint = -1
  private var batch = RectangleBatch()
  private var clip: ScissorRect?
  private var width: Int32 = 0
  private var height: Int32 = 0
  private var logicalSize = SIMD2<Int32>(1, 1)
  private var active = false
  private var frameBorrowed = false
  private var frameError: (any Error)?

  init() {}

  func withFrame(_ body: (borrowing RenderFrame) -> Void) {
    precondition(active && !frameBorrowed)
    frameBorrowed = true
    defer { frameBorrowed = false }
    let frame = RenderFrame(renderer: self)
    body(frame)
  }

  func render(_ commands: borrowing UIDrawBatch) {
    guard active, frameError == nil else { return }
    for command in commands {
      switch command {
      case .rectangle(let draw):
        renderRectangle(draw)
      case .image(let image):
        flush()
        guard frameError == nil, let draw = image.resolve() else { continue }
        setClip(draw.clip)
        let id = ObjectIdentifier(draw.source)
        usedImages.insert(id)
        let textures = images[id] ?? ImageTextures()
        images[id] = textures
        do { try textures.bind(draw.frame) } catch { frameError = error; return }
        for (index, row) in [draw.frame.red, draw.frame.green, draw.frame.blue, draw.frame.chromaTransform].enumerated() {
          glUniform4f(imageLocations[index], row.x, row.y, row.z, row.w)
        }
        let mode: Float = draw.frame.format == .rgba8 ? 3 : (draw.frame.format == .nv12 ? 5 : 4)
        batch.append(draw.rectangle, textured: mode)
        flush()
      }
    }
    flush()
  }

  func render(_ draws: borrowing Span<DrawRect>) {
    guard active, frameError == nil else { return }
    for draw in draws { renderRectangle(draw) }
    flush()
  }

  private func renderRectangle(_ draw: DrawRect) {
    guard active, frameError == nil else { return }
    if let stroke = draw.polyline {
      flush()
      setClip(draw.clip)
      guard frameError == nil, draw.isValid else { return }
      renderPolyline(stroke, color: draw.color)
      return
    }
    setClip(draw.clip)
    guard frameError == nil, RectangleBatch.accepts(draw) else { return }
    if batch.count == RectangleBatch.capacity { flush() }
    guard frameError == nil else { return }
    batch.append(draw)
  }

  private func renderPolyline(_ stroke: PolylineStroke, color: Color) {
    glUseProgram(polylineProgram)
    let b = stroke.bounds
    glUniform2f(polylineLocations[0], Float(logicalSize.x), Float(logicalSize.y))
    glUniform4f(polylineLocations[1], b.x, b.y, b.width, b.height)
    var packed: [Float] = []
    packed.reserveCapacity(stroke.points.count * 2)
    for point in stroke.points {
      packed.append(point.x)
      packed.append(point.y)
    }
    unsafe glUniform2fv(polylineLocations[2], GLsizei(stroke.points.count), packed)
    glUniform1i(polylineLocations[3], GLint(stroke.points.count))
    glUniform1f(polylineLocations[4], stroke.width)
    glUniform4f(polylineLocations[5], color.r, color.g, color.b, color.a)
    glDrawArrays(GLenum(GL_TRIANGLES), 0, 6)
    glUseProgram(program)
  }

  private func setClip(_ region: Region?) {
    let scale = SIMD2(Double(width) / Double(logicalSize.x), Double(height) / Double(logicalSize.y))
    let next = region.map { ScissorRect($0, width: width, height: height, scale: scale) }
    guard next != clip else { return }
    flush()
    clip = next
    if let next {
      glEnable(GLenum(GL_SCISSOR_TEST))
      glScissor(next.x, height - next.y - next.height, next.width, next.height)
    } else {
      glDisable(GLenum(GL_SCISSOR_TEST))
    }
  }

  private func flush() {
    guard batch.count > 0 else { return }
    let instanceCount = batch.count
    do {
      let mapping = try VertexMapping(owner: self, buffer: vertexBuffer, source: batch.vertices)
      try mapping.unmap()
    } catch {
      frameError = error
      batch.reset()
      return
    }
    glDrawArraysInstanced(GLenum(GL_TRIANGLES), 0, 6, GLsizei(instanceCount))
    batch.reset()
  }

  func makeCurrent() throws {
    guard unsafe eglGetCurrentContext() != context else { return }
    guard eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) != 0,
      unsafe eglMakeCurrent(display, surface, surface, context) != 0
    else { throw NativeWindowError.egl(eglGetError()) }
  }

  func releaseCurrent() throws {
    precondition(!frameBorrowed)
    guard unsafe eglMakeCurrent(display, nil, nil, nil) != 0 else {
      throw NativeWindowError.egl(eglGetError())
    }
  }

  func beginFrame(
    width: Int32, height: Int32, bufferScale: Int32 = 1, fractionalScale120: UInt32? = nil,
    transparent: Bool = false
  ) throws {
    precondition(!frameBorrowed)
    frameError = nil
    usedImages.removeAll(keepingCapacity: true)
    let pixels = try BufferSize(
      width: width, height: height, scale: bufferScale, fractionalScale120: fractionalScale120)
    self.width = pixels.width
    self.height = pixels.height
    logicalSize = SIMD2(width, height)
    glViewport(0, 0, pixels.width, pixels.height)
    glDisable(GLenum(GL_SCISSOR_TEST))
    clip = nil
    if transparent { glClearColor(0, 0, 0, 0) } else { glClearColor(0.04, 0.05, 0.07, 1) }
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    glUseProgram(program)
    glUniform2f(resolutionLocation, Float(width), Float(height))
    active = true
  }

  func endFrame(surfaceless: Bool) throws {
    precondition(!frameBorrowed)
    flush()
    active = false
    for id in images.keys.filter({ !usedImages.contains($0) }) {
      images.removeValue(forKey: id)?.close()
    }
    if let frameError { throw frameError }
    if surfaceless { glFinish() }
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
  }

  func updateDMABufDevice(
    input: NativeWindowInput, connection: WaylandConnection, popup: Bool = false,
    sharedDevice: DMABufDevice? = nil
  ) throws {
    // Keep usable targets on the old device until replacements can be imported.
    guard connection.canImportDMABuf(popup: popup) else { return }
    let preferred = (popup ? connection.popupDMABufPreferences : connection.dmabufPreferences)?
      .mainDevice
    guard let preferred, preferred != device?.advertisedDevice else { return }
    let node = try DMABufDevice.renderNode(for: preferred)
    guard node != device?.node else { return }  // primary and render IDs may name the same GPU.
    let replacement: DMABufDevice
    if let sharedDevice, sharedDevice.node == node {
      replacement = sharedDevice
    } else {
      replacement = try DMABufDevice(device: preferred)
    }
    cleanup()
    do {
      try setup(input: input, device: replacement)
      enableDMABuf(connection: connection, popup: popup)
    } catch {
      cleanup()
      throw error
    }
  }

  func enableDMABuf(connection: WaylandConnection, popup: Bool = false) {
    dmabuf = DMABufPresenter(connection: connection, popup: popup)
  }

  func preparePresentation(
    width: Int32, height: Int32, bufferScale: Int32, fractionalScale120: UInt32? = nil
  ) throws -> Bool {
    guard dmabuf != nil else { return true }
    let pixels = try BufferSize(
      width: width, height: height, scale: bufferScale, fractionalScale120: fractionalScale120)
    guard let display = unsafe display, let context = unsafe context else {
      throw NativeWindowError.rendering
    }
    return try unsafe dmabuf!.prepare(
      display: display, context: context, width: pixels.width, height: pixels.height, device: device
    )
  }

  func swapBuffers() throws {
    if dmabuf != nil {
      try dmabuf!.present()
      return
    }
    guard unsafe eglSwapBuffers(display, surface) != 0 else {
      throw NativeWindowError.egl(eglGetError())
    }
  }

  func setup(
    input: NativeWindowInput, ownsDisplay: Bool = true, device: DMABufDevice? = nil
  ) throws {
    self.ownsDisplay = ownsDisplay
    self.device = device
    let pixels = try BufferSize(
      width: input.width, height: input.height, scale: input.bufferScale,
      fractionalScale120: input.fractionalScale120)
    guard let entry = unsafe eglGetProcAddress("eglGetPlatformDisplayEXT") else {
      throw NativeWindowError.egl(eglGetError())
    }
    let getPlatform = unsafe unsafeBitCast(entry, to: PFNEGLGETPLATFORMDISPLAYEXTPROC.self)
    unsafe display = device?.display ?? getPlatform(UInt32(EGL_PLATFORM_SURFACELESS_MESA), nil, nil)
    guard unsafe display != nil,
      unsafe device != nil || !ownsDisplay || eglInitialize(display, nil, nil) != 0,
      eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) != 0
    else { throw NativeWindowError.egl(eglGetError()) }
    let attributes: [EGLint] = [
      EGL_SURFACE_TYPE, device == nil ? EGL_PBUFFER_BIT : 0,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
      EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE,
    ]
    var config: EGLConfig?
    var count: EGLint = 0
    guard unsafe eglChooseConfig(display, attributes, &config, 1, &count) != 0, count == 1 else {
      throw NativeWindowError.egl(eglGetError())
    }
    unsafe context = eglCreateContext(
      display, config, nil, [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE])
    guard unsafe context != nil else { throw NativeWindowError.egl(eglGetError()) }
    if device == nil {
      unsafe surface = eglCreatePbufferSurface(
        display, config, [EGL_WIDTH, pixels.width, EGL_HEIGHT, pixels.height, EGL_NONE])
      guard unsafe surface != nil else { throw NativeWindowError.egl(eglGetError()) }
    } else {
      guard let extensions = unsafe eglQueryString(display, EGLint(EGL_EXTENSIONS)),
        unsafe String(cString: extensions).split(separator: " ").contains(
          "EGL_KHR_surfaceless_context")
      else { throw NativeWindowError.dmabuf("GBM EGL display lacks surfaceless contexts.") }
    }
    guard unsafe eglMakeCurrent(display, surface, surface, context) != 0
    else {
      throw NativeWindowError.egl(eglGetError())
    }
    unsafe eglSwapInterval(display, 0)
    try setupProgram()
    try setupFontTexture()
    let renderer =
      unsafe glGetString(GLenum(GL_RENDERER)).map { unsafe String(cString: $0) } ?? "unknown"
    let version =
      unsafe glGetString(GLenum(GL_VERSION)).map { unsafe String(cString: $0) } ?? "unknown"
    nativeLog("Offscreen EGL renderer: \(renderer) | \(version)")
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
  }

  private func setupProgram() throws {
    let vertex = try compileShader(GLenum(GL_VERTEX_SHADER), source: NativeShaders.vertexSource)
    defer { glDeleteShader(vertex) }
    let fragment = try compileShader(
      GLenum(GL_FRAGMENT_SHADER), source: NativeShaders.fragmentSource)
    defer { glDeleteShader(fragment) }
    program = glCreateProgram()
    glAttachShader(program, vertex)
    glAttachShader(program, fragment)
    glLinkProgram(program)
    var linked: GLint = 0
    unsafe glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linked)
    guard linked != 0 else {
      var log = [CChar](repeating: 0, count: 2048)
      unsafe glGetProgramInfoLog(program, GLsizei(log.count), nil, &log)
      throw NativeWindowError.shader(
        String(decoding: log.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
    let polylineVertex = try compileShader(
      GLenum(GL_VERTEX_SHADER), source: PolylineShaders.vertexSource)
    defer { glDeleteShader(polylineVertex) }
    let polylineFragment = try compileShader(
      GLenum(GL_FRAGMENT_SHADER), source: PolylineShaders.fragmentSource)
    defer { glDeleteShader(polylineFragment) }
    polylineProgram = glCreateProgram()
    glAttachShader(polylineProgram, polylineVertex)
    glAttachShader(polylineProgram, polylineFragment)
    glLinkProgram(polylineProgram)
    unsafe glGetProgramiv(polylineProgram, GLenum(GL_LINK_STATUS), &linked)
    guard linked != 0 else { throw NativeWindowError.rendering }
    let names: [String] = [
      "resolution", "bounds", "points[0]", "pointCount", "strokeWidth", "color"
    ]
    polylineLocations = names.map { name in
      name.withCString { unsafe glGetUniformLocation(polylineProgram, $0) }
    }
    resolutionLocation = unsafe glGetUniformLocation(program, "resolution")
    unsafe glGenBuffers(1, &vertexBuffer)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
    glUseProgram(program)
    for (index, name) in ["imageY", "imageU", "imageV"].enumerated() {
      name.withCString { glUniform1i(unsafe glGetUniformLocation(program, $0), GLint(index + 2)) }
    }
    imageLocations = ["imageRed", "imageGreen", "imageBlue", "chromaTransform"].map { name in
      name.withCString { unsafe glGetUniformLocation(program, $0) }
    }
    let lengths: [GLint] = [2, 2, 4, 1, 4, 1, 1, 2]
    let offsets = [0, 2, 4, 8, 9, 13, 14, 15]
    for index in 0..<lengths.count {
      glEnableVertexAttribArray(GLuint(index))
      glVertexAttribDivisor(GLuint(index), 1)
      unsafe glVertexAttribPointer(
        GLuint(index), lengths[index], GLenum(GL_FLOAT), GLboolean(GL_FALSE),
        GLsizei(RectangleBatch.vertexFloats * MemoryLayout<Float>.stride),
        UnsafeRawPointer(bitPattern: offsets[index] * MemoryLayout<Float>.stride))
    }
    glEnable(GLenum(GL_BLEND))
    glBlendFuncSeparate(
      GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA), GLenum(GL_ONE),
      GLenum(GL_ONE_MINUS_SRC_ALPHA))
  }

  private func setupFontTexture() throws {
    let atlas = FontAtlas.shared
    var maximum: GLint = 0
    unsafe glGetIntegerv(GLenum(GL_MAX_TEXTURE_SIZE), &maximum)
    guard atlas.width <= maximum, atlas.height <= maximum else { throw NativeWindowError.rendering }
    unsafe glGenTextures(1, &fontTexture)
    glActiveTexture(GLenum(GL_TEXTURE0))
    glBindTexture(GLenum(GL_TEXTURE_2D), fontTexture)
    glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
    for (level, mip) in atlas.mipLevels.enumerated() {
      mip.pixels.withUnsafeBytes { pixels in
        unsafe glTexImage2D(
          GLenum(GL_TEXTURE_2D), GLint(level), GL_R8, GLsizei(mip.width), GLsizei(mip.height), 0,
          GLenum(GL_RED), GLenum(GL_UNSIGNED_BYTE), pixels.baseAddress)
      }
    }
    glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 4)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    glUniform1i(unsafe glGetUniformLocation(program, "fontAtlas"), 0)
    try setupEmojiTexture()
  }

  private func setupEmojiTexture() throws {
    let atlas = EmojiAtlas.shared
    var maximum: GLint = 0
    unsafe glGetIntegerv(GLenum(GL_MAX_TEXTURE_SIZE), &maximum)
    guard atlas.width <= maximum, atlas.height <= maximum else { throw NativeWindowError.rendering }
    unsafe glGenTextures(1, &emojiTexture)
    glActiveTexture(GLenum(GL_TEXTURE1))
    glBindTexture(GLenum(GL_TEXTURE_2D), emojiTexture)
    glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 4)
    for (level, mip) in atlas.mipLevels.enumerated() {
      mip.pixels.withUnsafeBytes { pixels in
        unsafe glTexImage2D(
          GLenum(GL_TEXTURE_2D), GLint(level), GL_RGBA8, GLsizei(mip.width), GLsizei(mip.height), 0,
          GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pixels.baseAddress)
      }
    }
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    glActiveTexture(GLenum(GL_TEXTURE0))
    glUniform1i(unsafe glGetUniformLocation(program, "emojiAtlas"), 1)
  }

  private func compileShader(_ kind: GLenum, source: String) throws -> GLuint {
    let shader = glCreateShader(kind)
    source.withCString { string in
      var pointer: UnsafePointer<CChar>? = unsafe string
      unsafe glShaderSource(shader, 1, &pointer, nil)
    }
    glCompileShader(shader)
    var success: GLint = 0
    unsafe glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &success)
    guard success != 0 else {
      var log = [CChar](repeating: 0, count: 2048)
      unsafe glGetShaderInfoLog(shader, GLsizei(log.count), nil, &log)
      glDeleteShader(shader)
      throw NativeWindowError.shader(
        String(decoding: log.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
    return shader
  }

  func screenshot(to path: String) throws {
    let (pixelCount, overflow) = Int(width).multipliedReportingOverflow(by: Int(height))
    guard width > 0, height > 0, !overflow, pixelCount <= Int.max / 4 else {
      throw NativeWindowError.rendering
    }
    precondition(!frameBorrowed)
    if readbackBuffer == 0 { unsafe glGenBuffers(1, &readbackBuffer) }
    guard readbackBuffer != 0 else { throw NativeWindowError.rendering }
    let byteCount = pixelCount * 4
    glBindBuffer(GLenum(GL_PIXEL_PACK_BUFFER), readbackBuffer)
    defer { glBindBuffer(GLenum(GL_PIXEL_PACK_BUFFER), 0) }
    glBufferData(GLenum(GL_PIXEL_PACK_BUFFER), byteCount, nil, GLenum(GL_STREAM_READ))
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
    glReadPixels(0, 0, width, height, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
    let mapping = try PixelMapping(owner: self, buffer: readbackBuffer, count: byteCount)
    var ppm = Data("P6\n\(width) \(height)\n255\n".utf8)
    ppm.reserveCapacity(ppm.count + pixelCount * 3)
    mapping.appendRGB(to: &ppm, width: Int(width), height: Int(height))
    try mapping.unmap()
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
    try ppm.write(to: URL(fileURLWithPath: path))
  }

  @safe @MainActor private struct VertexMapping: ~Copyable, ~Escapable {
    private let buffer: GLuint
    private var isMapped = true

    @_lifetime(borrow owner)
    init(owner: borrowing NativeRenderer, buffer: GLuint, source: borrowing Span<Float>) throws {
      let count = source.count
      guard count > 0, count <= RectangleBatch.capacity * RectangleBatch.vertexFloats else {
        throw NativeWindowError.rendering
      }
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), buffer)
      glBufferData(
        GLenum(GL_ARRAY_BUFFER), count * MemoryLayout<Float>.stride, nil, GLenum(GL_STREAM_DRAW))
      guard glGetError() == GL_NO_ERROR,
        let pointer = unsafe glMapBufferRange(
          GLenum(GL_ARRAY_BUFFER), 0, count * MemoryLayout<Float>.stride,
          GLbitfield(GL_MAP_WRITE_BIT | GL_MAP_INVALIDATE_BUFFER_BIT))
      else { throw NativeWindowError.rendering }
      self.buffer = buffer
      let typed = unsafe pointer.bindMemory(to: Float.self, capacity: count)
      source.withUnsafeBufferPointer { values in
        unsafe typed.initialize(from: values.baseAddress!, count: count)
      }
    }

    consuming func unmap() throws {
      isMapped = false
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), buffer)
      guard glUnmapBuffer(GLenum(GL_ARRAY_BUFFER)) == GLboolean(GL_TRUE) else {
        throw NativeWindowError.rendering
      }
    }

    deinit {
      if isMapped {
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), buffer)
        glUnmapBuffer(GLenum(GL_ARRAY_BUFFER))
      }
    }
  }

  @safe @MainActor private struct PixelMapping: ~Copyable, ~Escapable {
    private let pointer: UnsafeMutableRawPointer
    private let buffer: GLuint
    private let count: Int
    private var isMapped = true

    @_lifetime(borrow owner)
    init(owner: borrowing NativeRenderer, buffer: GLuint, count: Int) throws {
      guard count > 0 else { throw NativeWindowError.rendering }
      glBindBuffer(GLenum(GL_PIXEL_PACK_BUFFER), buffer)
      guard
        let pointer = unsafe glMapBufferRange(
          GLenum(GL_PIXEL_PACK_BUFFER), 0, count, GLbitfield(GL_MAP_READ_BIT))
      else { throw NativeWindowError.rendering }
      unsafe self.pointer = pointer
      self.buffer = buffer
      self.count = count
    }

    private var bytes: Span<UInt8> {
      @_lifetime(borrow self)
      get {
        let span = unsafe Span<UInt8>(_unsafeStart: UnsafeRawPointer(pointer), byteCount: count)
        return unsafe _overrideLifetime(span, borrowing: self)
      }
    }

    func appendRGB(to data: inout Data, width: Int, height: Int) {
      let pixels = bytes
      for row in (0..<height).reversed() {
        for column in 0..<width {
          let offset = (row * width + column) * 4
          data.append(pixels[offset])
          data.append(pixels[offset + 1])
          data.append(pixels[offset + 2])
        }
      }
    }

    consuming func unmap() throws {
      isMapped = false
      glBindBuffer(GLenum(GL_PIXEL_PACK_BUFFER), buffer)
      guard glUnmapBuffer(GLenum(GL_PIXEL_PACK_BUFFER)) == GLboolean(GL_TRUE) else {
        throw NativeWindowError.rendering
      }
    }

    deinit {
      if isMapped {
        glBindBuffer(GLenum(GL_PIXEL_PACK_BUFFER), buffer)
        glUnmapBuffer(GLenum(GL_PIXEL_PACK_BUFFER))
      }
    }
  }

  func cleanup() {
    precondition(!frameBorrowed)
    active = false
    frameError = nil
    if unsafe display != nil {
      if unsafe context != nil, (try? makeCurrent()) != nil {
        if program != 0 { glDeleteProgram(program) }
        if polylineProgram != 0 { glDeleteProgram(polylineProgram) }
        for image in images.values { image.close() }
        images.removeAll()
        if fontTexture != 0 { unsafe glDeleteTextures(1, &fontTexture) }
        if emojiTexture != 0 { unsafe glDeleteTextures(1, &emojiTexture) }
        if vertexBuffer != 0 { unsafe glDeleteBuffers(1, &vertexBuffer) }
        if readbackBuffer != 0 { unsafe glDeleteBuffers(1, &readbackBuffer) }
      }
      dmabuf?.close()
      dmabuf = nil
      unsafe eglMakeCurrent(display, nil, nil, nil)
      if unsafe surface != nil { unsafe eglDestroySurface(display, surface) }
      if unsafe context != nil { unsafe eglDestroyContext(display, context) }
      if ownsDisplay && device == nil { unsafe eglTerminate(display) }
    }
    unsafe display = nil
    unsafe context = nil
    unsafe surface = nil
    device = nil
    polylineProgram = 0
    program = 0
    vertexBuffer = 0
    readbackBuffer = 0
    fontTexture = 0
    emojiTexture = 0
  }
}
