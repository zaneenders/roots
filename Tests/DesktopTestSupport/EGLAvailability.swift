#if os(Linux)
import CEGLGLES

@MainActor public enum EGLAvailability {
  public static let isAvailable = detect()

  public static let canExportDMABuf = detect(requireDMABufExport: true)

  public static func detect(requireDMABufExport: Bool = false) -> Bool {
    guard let entry = unsafe eglGetProcAddress("eglGetPlatformDisplayEXT") else { return false }
    let getPlatform = unsafe unsafeBitCast(entry, to: PFNEGLGETPLATFORMDISPLAYEXTPROC.self)
    guard let display = unsafe getPlatform(UInt32(EGL_PLATFORM_SURFACELESS_MESA), nil, nil),
      unsafe eglInitialize(display, nil, nil) != 0
    else { return false }
    defer { unsafe eglTerminate(display) }

    let previousAPI = eglQueryAPI()
    guard eglBindAPI(EGLenum(EGL_OPENGL_ES_API)) != 0 else { return false }
    defer { eglBindAPI(previousAPI) }
    let attributes: [EGLint] = [
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE
    ]
    var config: EGLConfig?
    var count: EGLint = 0
    guard unsafe eglChooseConfig(display, attributes, &config, 1, &count) != 0, count == 1,
      let context = unsafe eglCreateContext(
        display, config, nil, [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE])
    else { return false }
    defer { unsafe eglDestroyContext(display, context) }
    guard
      let surface = unsafe eglCreatePbufferSurface(
        display, config, [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE])
    else { return false }
    defer { unsafe eglDestroySurface(display, surface) }
    guard unsafe eglMakeCurrent(display, surface, surface, context) != 0 else { return false }
    defer { unsafe eglMakeCurrent(display, nil, nil, nil) }
    if requireDMABufExport {
      guard let extensions = unsafe eglQueryString(display, EGLint(EGL_EXTENSIONS)) else {
        return false
      }
      return unsafe String(cString: extensions).split(separator: " ").contains(
        "EGL_MESA_image_dma_buf_export")
    }
    return true
  }
}

#endif
