import CDRM
import CEGLGLES
import CGBM
import Glibc
import SwiftWayland

@safe @MainActor final class DMABufDevice {
  let advertisedDevice: UInt64
  let node: String
  private let fd: Int32
  let gbm: OpaquePointer
  let display: EGLDisplay

  static func renderNode(for device: UInt64) throws -> String {
    var info: drmDevicePtr?
    guard unsafe drmGetDeviceFromDevId(dev_t(device), 0, &info) == 0, let pointer = unsafe info
    else {
      throw NativeWindowError.dmabuf("Cannot resolve compositor DRM device \(device).")
    }
    defer { unsafe drmFreeDevice(&info) }
    guard unsafe pointer.pointee.available_nodes & (1 << DRM_NODE_RENDER) != 0,
      let nodes = unsafe pointer.pointee.nodes, let path = unsafe nodes[Int(DRM_NODE_RENDER)]
    else { throw NativeWindowError.dmabuf("Compositor DRM device has no render node.") }
    return unsafe String(cString: path)
  }

  init(device: UInt64) throws {
    advertisedDevice = device
    node = try Self.renderNode(for: device)
    let fd = unsafe open(node, O_RDWR | O_CLOEXEC)
    guard fd >= 0 else { throw NativeWindowError.dmabuf("Cannot open \(node): errno \(errno).") }
    guard let gbm = unsafe gbm_create_device(fd) else {
      _ = Glibc.close(fd)
      throw NativeWindowError.dmabuf("Cannot create GBM device for \(node).")
    }
    guard let entry = unsafe eglGetProcAddress("eglGetPlatformDisplayEXT") else {
      unsafe gbm_device_destroy(gbm)
      _ = Glibc.close(fd)
      throw NativeWindowError.rendering
    }
    let getPlatform = unsafe unsafeBitCast(entry, to: PFNEGLGETPLATFORMDISPLAYEXTPROC.self)
    guard
      let display = unsafe getPlatform(
        EGLenum(EGL_PLATFORM_GBM_KHR), UnsafeMutableRawPointer(gbm), nil),
      unsafe eglInitialize(display, nil, nil) != 0
    else {
      let error = eglGetError()
      unsafe gbm_device_destroy(gbm)
      _ = Glibc.close(fd)
      throw NativeWindowError.egl(error)
    }
    self.fd = fd
    unsafe self.gbm = gbm
    unsafe self.display = display
    nativeLog("Wayland render device: \(node)")
  }

  isolated deinit {
    _ = unsafe eglTerminate(display)
    unsafe gbm_device_destroy(gbm)
    _ = Glibc.close(fd)
  }
}

// Keep alpha for transparent surfaces. Modifiers may add auxiliary planes.
func dmabufCandidates(
  _ feedback: WaylandDMABufFeedback, excluding rejected: Set<WaylandDMABufFormat> = []
) -> [WaylandDMABufFormat] {
  var seen: Set<WaylandDMABufFormat> = []
  return feedback.tranches.flatMap(\.formats).filter {
    ($0.format == UInt32(ROOTS_DRM_ARGB8888) || $0.format == UInt32(ROOTS_DRM_ABGR8888))
      && !rejected.contains($0) && seen.insert($0).inserted
  }
}
