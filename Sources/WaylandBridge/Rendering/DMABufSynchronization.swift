import CDRM
import CEGLGLES
import Glibc

@safe @MainActor struct DMABufSynchronization: ~Copyable {
  private let display: EGLDisplay
  private var fence: NativeFence?

  init(display: EGLDisplay) {
    unsafe self.display = display
    fence = unsafe NativeFence(display: display)
  }

  // Publish the GPU write fence before wl_surface.commit. The compositor can
  // then wait on the dma-buf without blocking the application's MainActor.
  @discardableResult
  mutating func finishRendering(descriptors: borrowing Span<Int32>) -> Bool {
    if let fence, !descriptors.isEmpty, publish(fence, to: descriptors) { return true }
    fence = nil
    glFinish()
    return false
  }

  private func publish(_ fence: NativeFence, to descriptors: borrowing Span<Int32>) -> Bool {
    guard
      let sync = unsafe fence.create(display, EGLenum(EGL_SYNC_NATIVE_FENCE_ANDROID), [EGL_NONE])
    else {
      _ = eglGetError()
      return false
    }
    defer { _ = unsafe fence.destroy(display, sync) }
    glFlush()
    let fd = unsafe fence.duplicate(display, sync)
    guard fd >= 0 else {
      _ = eglGetError()
      return false
    }
    defer { _ = Glibc.close(fd) }
    var imported = dma_buf_import_sync_file(flags: UInt32(DMA_BUF_SYNC_WRITE), fd: fd)
    for descriptor in descriptors {
      var result: Int32
      repeat {
        result = unsafe ioctl(descriptor, ROOTS_DMA_BUF_IOCTL_IMPORT_SYNC_FILE, &imported)
      } while result < 0 && errno == EINTR
      guard result == 0 else { return false }
    }
    return true
  }

  @safe private struct NativeFence {
    let create: PFNEGLCREATESYNCKHRPROC
    let destroy: PFNEGLDESTROYSYNCKHRPROC
    let duplicate: PFNEGLDUPNATIVEFENCEFDANDROIDPROC

    init?(display: EGLDisplay) {
      guard let extensions = unsafe eglQueryString(display, EGLint(EGL_EXTENSIONS)),
        unsafe String(cString: extensions).split(separator: " ").contains(
          "EGL_ANDROID_native_fence_sync"),
        let create = unsafe eglGetProcAddress("eglCreateSyncKHR"),
        let destroy = unsafe eglGetProcAddress("eglDestroySyncKHR"),
        let duplicate = unsafe eglGetProcAddress("eglDupNativeFenceFDANDROID")
      else { return nil }
      unsafe self.create = unsafeBitCast(create, to: PFNEGLCREATESYNCKHRPROC.self)
      unsafe self.destroy = unsafeBitCast(destroy, to: PFNEGLDESTROYSYNCKHRPROC.self)
      unsafe self.duplicate = unsafeBitCast(duplicate, to: PFNEGLDUPNATIVEFENCEFDANDROIDPROC.self)
    }
  }
}
