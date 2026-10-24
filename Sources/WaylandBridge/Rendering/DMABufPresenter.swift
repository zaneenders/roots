import CEGLGLES
import Glibc
import SwiftWayland

@safe @MainActor struct DMABufPresenter: ~Copyable {
  private let connection: WaylandConnection
  private let popup: Bool
  private var targets = InlineArray<3, DMABufTarget?> { _ in nil }
  private var selected: Int?

  init(connection: WaylandConnection, popup: Bool) {
    self.connection = connection
    self.popup = popup
  }

  mutating func prepare(display: EGLDisplay, context: EGLContext, width: Int32, height: Int32)
    throws -> Bool
  {
    selected = nil
    for index in targets.indices {
      if let state = targets[index]?.buffer.state {
        switch state {
        case .failed: throw NativeWindowError.dmabuf("Compositor rejected the exported texture.")
        case .closed: throw NativeWindowError.dmabuf("Buffer was closed before rendering.")
        case .importing, .submitted: continue
        case .available:
          if targets[index]?.width == width && targets[index]?.height == height {
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), targets[index]?.framebuffer ?? 0)
            selected = index
            return true
          }
        }
      }
      targets[index]?.close()
      targets[index] = nil
      targets[index] = try unsafe DMABufTarget.create(
        display: display, context: context, connection: connection, width: width, height: height,
        popup: popup)
    }
    connection.waitForDMABufBuffer(popup: popup)
    return false
  }

  mutating func close() {
    for index in targets.indices {
      targets[index]?.close()
      targets[index] = nil
    }
  }

  mutating func present() throws {
    guard let selected, let buffer = targets[selected]?.buffer else {
      throw NativeWindowError.dmabuf("No target selected for presentation.")
    }
    glFinish()
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
    try connection.presentDMABuf(buffer, popup: popup)
    self.selected = nil
  }
}

@safe @MainActor struct DMABufTarget: ~Copyable {
  let width: Int32
  let height: Int32
  private let display: EGLDisplay
  private let context: EGLContext
  private var texture: GLuint = 0
  private(set) var framebuffer: GLuint = 0
  private var image: EGLImageKHR?
  private var imported: WaylandDMABufBuffer?
  private let destroyImage: PFNEGLDESTROYIMAGEKHRPROC

  var buffer: WaylandDMABufBuffer { imported! }

  private init(display: EGLDisplay, context: EGLContext, width: Int32, height: Int32) throws {
    unsafe self.display = display
    unsafe self.context = context
    self.width = width
    self.height = height
    unsafe destroyImage = try Self.entry("eglDestroyImageKHR", as: PFNEGLDESTROYIMAGEKHRPROC.self)
  }

  static func create(
    display: EGLDisplay, context: EGLContext, connection: WaylandConnection, width: Int32,
    height: Int32, popup: Bool
  ) throws -> DMABufTarget {
    var target = try unsafe DMABufTarget(
      display: display, context: context, width: width, height: height)
    try unsafe target.allocate(context: context, connection: connection, popup: popup)
    return target
  }

  private static func entry<T>(_ name: String, as: T.Type) throws -> T {
    guard let address = unsafe eglGetProcAddress(name) else { throw NativeWindowError.rendering }
    return unsafe unsafeBitCast(address, to: T.self)
  }

  private mutating func allocate(
    context: EGLContext, connection: WaylandConnection, popup: Bool
  ) throws {
    guard let extensions = unsafe eglQueryString(display, EGLint(EGL_EXTENSIONS)),
      unsafe String(cString: extensions).split(separator: " ").contains(
        "EGL_MESA_image_dma_buf_export")
    else { throw NativeWindowError.dmabuf("Driver lacks EGL_MESA_image_dma_buf_export.") }
    let createImage = try unsafe Self.entry("eglCreateImageKHR", as: PFNEGLCREATEIMAGEKHRPROC.self)
    let query = try unsafe Self.entry(
      "eglExportDMABUFImageQueryMESA", as: PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC.self)
    let export = try unsafe Self.entry(
      "eglExportDMABUFImageMESA", as: PFNEGLEXPORTDMABUFIMAGEMESAPROC.self)

    glActiveTexture(GLenum(GL_TEXTURE2))
    defer { glActiveTexture(GLenum(GL_TEXTURE0)) }
    unsafe glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    glTexStorage2D(GLenum(GL_TEXTURE_2D), 1, GLenum(GL_RGBA8), width, height)
    unsafe glGenFramebuffers(1, &framebuffer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
    guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GL_FRAMEBUFFER_COMPLETE,
      glGetError() == GL_NO_ERROR
    else { throw NativeWindowError.rendering }
    unsafe image = createImage(
      display, context, EGLenum(EGL_GL_TEXTURE_2D_KHR),
      UnsafeMutableRawPointer(bitPattern: UInt(texture)),
      [EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE])
    guard let image = unsafe image else { throw NativeWindowError.egl(eglGetError()) }
    var format: EGLint = 0
    var count: EGLint = 0
    var modifiers = [EGLuint64KHR](repeating: 0, count: 4)
    guard unsafe query(display, image, &format, &count, &modifiers) != 0, count > 0, count <= 4
    else {
      throw NativeWindowError.rendering
    }
    let modifier = modifiers[0]
    guard modifiers.prefix(Int(count)).allSatisfy({ $0 == modifier }) else {
      throw NativeWindowError.rendering
    }
    var fds = [Int32](repeating: -1, count: 4)
    defer { for fd in fds where fd >= 0 { _ = Glibc.close(fd) } }
    var strides = [EGLint](repeating: 0, count: 4)
    var offsets = [EGLint](repeating: 0, count: 4)
    guard unsafe export(display, image, &fds, &strides, &offsets) != 0 else {
      throw NativeWindowError.rendering
    }
    var planes: [WaylandDMABufPlane] = []
    for index in 0..<Int(count) {
      let fd = fds[index] >= 0 ? fds[index] : fds[0]
      guard fd >= 0, strides[index] > 0, offsets[index] >= 0 else {
        throw NativeWindowError.rendering
      }
      planes.append(
        .init(descriptor: fd, offset: UInt32(offsets[index]), stride: UInt32(strides[index])))
    }
    do {
      imported = try connection.importDMABuf(
        width: width, height: height, format: UInt32(bitPattern: format), modifier: modifier,
        planes: planes.span, popup: popup)
    } catch {
      throw NativeWindowError.dmabuf(
        "Cannot import format 0x\(String(UInt32(bitPattern: format), radix: 16)), "
          + "modifier 0x\(String(modifier, radix: 16)): \(error)")
    }
  }

  mutating func close() {
    imported?.close()
    imported = nil
  }

  deinit {
    if let image = unsafe image { _ = unsafe destroyImage(display, image) }
    guard unsafe eglGetCurrentContext() == context else { return }
    if framebuffer != 0 {
      var name = framebuffer
      unsafe glDeleteFramebuffers(1, &name)
    }
    if texture != 0 {
      var name = texture
      unsafe glDeleteTextures(1, &name)
    }
  }
}
