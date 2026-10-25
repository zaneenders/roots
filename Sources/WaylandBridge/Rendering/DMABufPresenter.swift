import CDRM
import CEGLGLES
import CGBM
import Glibc
import SwiftWayland

@safe @MainActor struct DMABufPresenter: ~Copyable {
  private let connection: WaylandConnection
  private let popup: Bool
  private var targets = InlineArray<3, DMABufTarget?> { _ in nil }
  private var selected: Int?
  private var synchronization: DMABufSynchronization?
  private var preferences: WaylandDMABufFeedback?
  private var rejected: Set<WaylandDMABufFormat> = []

  init(connection: WaylandConnection, popup: Bool) {
    self.connection = connection
    self.popup = popup
  }

  mutating func prepare(
    display: EGLDisplay, context: EGLContext, width: Int32, height: Int32, device: DMABufDevice?
  )
    throws -> Bool
  {
    selected = nil
    if synchronization == nil { synchronization = unsafe DMABufSynchronization(display: display) }
    let feedback = popup ? connection.popupDMABufPreferences : connection.dmabufPreferences
    let canImport = connection.canImportDMABuf(popup: popup)
    if feedback != preferences {
      preferences = feedback
      rejected.removeAll()
    }
    // Reuse any suitable buffer before trying to allocate another one. The
    // factory may have disappeared while its existing buffers remain usable.
    for index in targets.indices {
      if targets[index]?.buffer.state == .available,
        targets[index]?.width == width && targets[index]?.height == height,
        targets[index]?.preferences == feedback || !canImport
      {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), targets[index]?.framebuffer ?? 0)
        selected = index
        return true
      }
    }
    guard canImport else {
      guard feedback != nil else {
        throw NativeWindowError.dmabuf("Compositor has no dma-buf allocation feedback.")
      }
      // Releases and fresh factory feedback both wake this surface.
      connection.waitForDMABufBuffer(popup: popup)
      return false
    }
    for index in targets.indices {
      if let state = targets[index]?.buffer.state {
        switch state {
        case .failed:
          if targets[index]?.preferences == feedback, let format = targets[index]?.format {
            rejected.insert(format)
          }
          if device == nil {
            throw NativeWindowError.dmabuf("Compositor rejected the exported texture.")
          }
        case .closed: throw NativeWindowError.dmabuf("Buffer was closed before rendering.")
        case .importing, .submitted: continue
        case .available: break
        }
      }
      targets[index]?.close()
      targets[index] = nil
      targets[index] = try unsafe DMABufTarget.create(
        display: display, context: context, connection: connection, width: width, height: height,
        popup: popup, device: device, preferences: feedback, rejected: rejected)
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
    guard let selected, let buffer = targets[selected]?.buffer, synchronization != nil else {
      throw NativeWindowError.dmabuf("No target selected for presentation.")
    }
    targets[selected]?.finishRendering(using: &synchronization!)
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
  private var allocation: OpaquePointer?
  private(set) var format: WaylandDMABufFormat?
  private(set) var preferences: WaylandDMABufFeedback?
  private var imported: WaylandDMABufBuffer?
  private var synchronizationDescriptors: [Int32] = []
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
    height: Int32, popup: Bool, device: DMABufDevice?,
    preferences: WaylandDMABufFeedback?, rejected: Set<WaylandDMABufFormat>
  ) throws -> DMABufTarget {
    if let device, let preferences {
      var lastError: (any Error)?
      for format in dmabufCandidates(preferences, excluding: rejected) {
        do {
          var target = try unsafe DMABufTarget(
            display: display, context: context, width: width, height: height)
          target.preferences = preferences
          try target.allocate(
            device: device, format: format, connection: connection, popup: popup)
          return target
        } catch {
          lastError = error
          // A failed EGLImage/FBO candidate must not poison the next allocation.
          while glGetError() != GL_NO_ERROR {}
        }
      }
      throw NativeWindowError.dmabuf(
        "No usable advertised ARGB8888/ABGR8888 format/modifier on \(device.node). "
          + (lastError.map { String(describing: $0) } ?? "All candidates were rejected or absent."))
    }
    var target = try unsafe DMABufTarget(
      display: display, context: context, width: width, height: height)
    target.preferences = preferences
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
    try attachFramebuffer()
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
    self.format = .init(format: UInt32(bitPattern: format), modifier: modifier)
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
      synchronizationDescriptors = fds.filter { $0 >= 0 }
      fds = []
    } catch {
      throw NativeWindowError.dmabuf(
        "Cannot import format 0x\(String(UInt32(bitPattern: format), radix: 16)), "
          + "modifier 0x\(String(modifier, radix: 16)): \(error)")
    }
  }

  private mutating func allocate(
    device: DMABufDevice, format: WaylandDMABufFormat, connection: WaylandConnection, popup: Bool
  ) throws {
    let implicit = format.modifier == ROOTS_DRM_MOD_INVALID
    guard let extensions = unsafe eglQueryString(display, EGLint(EGL_EXTENSIONS)) else {
      throw NativeWindowError.rendering
    }
    let supported = unsafe String(cString: extensions).split(separator: " ")
    guard supported.contains("EGL_EXT_image_dma_buf_import"),
      implicit || supported.contains("EGL_EXT_image_dma_buf_import_modifiers")
    else { throw NativeWindowError.dmabuf("EGL cannot import the advertised modifier.") }
    if implicit {
      unsafe allocation = gbm_bo_create(
        device.gbm, UInt32(width), UInt32(height), format.format,
        UInt32(GBM_BO_USE_RENDERING.rawValue))
    } else {
      var modifier = format.modifier
      unsafe allocation = gbm_bo_create_with_modifiers2(
        device.gbm, UInt32(width), UInt32(height), format.format, &modifier, 1,
        UInt32(GBM_BO_USE_RENDERING.rawValue))
    }
    guard let allocation = unsafe allocation else {
      throw NativeWindowError.dmabuf(
        "GBM allocation failed for format 0x\(String(format.format, radix: 16)), "
          + "modifier 0x\(String(format.modifier, radix: 16)).")
    }
    guard unsafe implicit || gbm_bo_get_modifier(allocation) == format.modifier else {
      throw NativeWindowError.dmabuf("GBM returned a different modifier than requested.")
    }
    let count = unsafe gbm_bo_get_plane_count(allocation)
    guard count > 0 && count <= 4 else { throw NativeWindowError.rendering }
    var planes: [WaylandDMABufPlane] = []
    defer { for plane in planes { _ = Glibc.close(plane.descriptor) } }
    var attributes: [EGLint] = [
      EGL_WIDTH, width, EGL_HEIGHT, height, EGL_LINUX_DRM_FOURCC_EXT,
      Int32(bitPattern: format.format)
    ]
    let planeKeys: [(EGLint, EGLint, EGLint, EGLint, EGLint)] = [
      (
        EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGL_DMA_BUF_PLANE0_PITCH_EXT,
        EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT
      ),
      (
        EGL_DMA_BUF_PLANE1_FD_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT, EGL_DMA_BUF_PLANE1_PITCH_EXT,
        EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT
      ),
      (
        EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE2_OFFSET_EXT, EGL_DMA_BUF_PLANE2_PITCH_EXT,
        EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT
      ),
      (
        EGL_DMA_BUF_PLANE3_FD_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT, EGL_DMA_BUF_PLANE3_PITCH_EXT,
        EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT
      )
    ]
    for index in 0..<count {
      let fd = unsafe gbm_bo_get_fd_for_plane(allocation, index)
      guard fd >= 0 else { throw NativeWindowError.rendering }
      let offset = unsafe gbm_bo_get_offset(allocation, index)
      let stride = unsafe gbm_bo_get_stride_for_plane(allocation, index)
      planes.append(.init(descriptor: fd, offset: offset, stride: stride))
      guard offset <= Int32.max, stride > 0, stride <= Int32.max else {
        throw NativeWindowError.rendering
      }
      let keys = planeKeys[Int(index)]
      attributes += [keys.0, fd, keys.1, Int32(offset), keys.2, Int32(stride)]
      if !implicit {
        attributes += [
          keys.3, Int32(truncatingIfNeeded: format.modifier),
          keys.4, Int32(truncatingIfNeeded: format.modifier >> 32)
        ]
      }
    }
    attributes.append(EGL_NONE)
    let createImage = try unsafe Self.entry("eglCreateImageKHR", as: PFNEGLCREATEIMAGEKHRPROC.self)
    let bindImage = try unsafe Self.entry(
      "glEGLImageTargetTexture2DOES", as: PFNGLEGLIMAGETARGETTEXTURE2DOESPROC.self)
    unsafe image = createImage(display, nil, EGLenum(EGL_LINUX_DMA_BUF_EXT), nil, attributes)
    guard let image = unsafe image else { throw NativeWindowError.egl(eglGetError()) }
    glActiveTexture(GLenum(GL_TEXTURE2))
    defer { glActiveTexture(GLenum(GL_TEXTURE0)) }
    unsafe glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    unsafe bindImage(GLenum(GL_TEXTURE_2D), image)
    try attachFramebuffer()
    self.format = format
    imported = try connection.importDMABuf(
      width: width, height: height, format: format.format, modifier: format.modifier,
      planes: planes.span, popup: popup)
    synchronizationDescriptors = planes.map(\.descriptor)
    planes = []
  }

  private mutating func attachFramebuffer() throws {
    unsafe glGenFramebuffers(1, &framebuffer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
    guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GL_FRAMEBUFFER_COMPLETE,
      glGetError() == GL_NO_ERROR
    else { throw NativeWindowError.rendering }
  }

  @discardableResult
  func finishRendering(using synchronization: inout DMABufSynchronization) -> Bool {
    synchronization.finishRendering(descriptors: synchronizationDescriptors.span)
  }

  mutating func close() {
    imported?.close()
    imported = nil
  }

  deinit {
    for fd in synchronizationDescriptors { _ = Glibc.close(fd) }
    if let image = unsafe image { _ = unsafe destroyImage(display, image) }
    if let allocation = unsafe allocation { unsafe gbm_bo_destroy(allocation) }
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
