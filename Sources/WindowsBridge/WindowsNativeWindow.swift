#if os(Windows)
  import CWindowsHost
  import Roots
  import RootsCPU

  extension WindowsWindow {
    private static var session: WindowsNativeSession?

    public static func requestRedraw() { session?.needsRedraw = true }
    public static func requestClose() { session?.requestClose() }

    public static func readClipboard() async -> String? {
      guard !Task.isCancelled else { return nil }
      return session?.readClipboard()
    }

    @discardableResult public static func writeClipboard(_ text: String) -> Bool {
      session?.writeClipboard(text) ?? false
    }

    /// Win32 runs its message pump on a dedicated UI thread. The async loop
    /// yields between frames instead of blocking Swift's main actor in GetMessage.
    public static func runAsync(
      configuration: WindowsWindowConfiguration = .init(),
      frame: @MainActor (WindowsFrameInput, borrowing WindowsRenderFrame) -> Void
    ) async throws {
      try Task.checkCancellation()
      try configuration.validate(offscreen: false)
      guard session == nil else { throw WindowsWindowError.alreadyRunning }
      let host = try WindowsNativeSession(configuration: configuration)
      session = host
      defer {
        host.close()
        session = nil
      }
      let clock = ContinuousClock()
      let started = clock.now
      var frames: Int32 = 0
      while !host.isClosed {
        try Task.checkCancellation()
        host.drainEvents()
        try host.checkError()
        if host.isClosed { break }
        if host.width > 0 && host.height > 0 && (host.needsRedraw || configuration.maxFrames > 0) {
          host.needsRedraw = false
          let renderer = host.renderer()
          let elapsed = started.duration(to: clock.now).components
          frame(
            WindowsFrameInput(
              input: host.consumeInput(), size: .init(Float(host.width), Float(host.height)),
              timeSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18),
            WindowsRenderFrame(renderer: renderer))
          try host.present(renderer)
          if configuration.maxFrames > 0 {
            frames += 1
            if frames >= configuration.maxFrames {
              if let path = configuration.screenshotPath { try renderer.writePPM(to: path) }
              break
            }
          }
        }
        // This also bounds cancellation latency and lets observation tasks run.
        try await Task.sleep(for: .milliseconds(16))
      }
      try host.checkError()
      try Task.checkCancellation()
    }
  }

  @safe @MainActor private final class WindowsNativeSession {
    private let handle: OpaquePointer
    private var image: CPURenderer?
    private var input = WindowsInputState()
    private(set) var width: Int
    private(set) var height: Int
    var needsRedraw = true

    init(configuration: WindowsWindowConfiguration) throws {
      let initialWidth = Int(configuration.size.x.rounded(.up))
      let initialHeight = Int(configuration.size.y.rounded(.up))
      width = initialWidth
      height = initialHeight
      var error: UInt32 = 0
      let native = configuration.title.withCString { title in
        unsafe roots_windows_host_create(title, Int32(initialWidth), Int32(initialHeight), &error)
      }
      guard let native = unsafe native else { throw WindowsWindowError.nativeFailure(code: error) }
      unsafe handle = native
    }

    // Explicitly called by the owning runAsync defer; no actor/thread-affinity
    // assumptions are made in deinit.
    func close() { unsafe roots_windows_host_destroy(handle) }
    func requestClose() { unsafe roots_windows_host_request_close(handle) }
    var isClosed: Bool { unsafe roots_windows_host_is_closed(handle) != 0 }

    func checkError() throws {
      let code = unsafe roots_windows_host_error_code(handle)
      if code != 0 { throw WindowsWindowError.nativeFailure(code: code) }
    }

    func renderer() -> CPURenderer {
      if let image, image.width == width && image.height == height { return image }
      let renderer = CPURenderer(width: width, height: height)
      image = renderer
      return renderer
    }

    func present(_ renderer: CPURenderer) throws {
      let error = renderer.pixels.withUnsafeBufferPointer { bytes in
        unsafe roots_windows_host_present_rgb(
          handle, bytes.baseAddress, bytes.count, Int32(renderer.width), Int32(renderer.height))
      }
      // Closing while a frame is computed is normal, not a presentation failure.
      if error != 0 && !isClosed { throw WindowsWindowError.nativeFailure(code: error) }
    }

    func consumeInput() -> Input { input.consume() }

    func drainEvents() {
      var event = RootsWindowsEvent()
      // Bound work even if another application continually sends native events.
      for _ in 0..<4096 {
        guard unsafe roots_windows_host_poll_event(handle, &event) != 0 else { break }
        needsRedraw = true
        switch event.type {
        case UInt32(ROOTS_WINDOWS_EVENT_RESIZE.rawValue):
          width = max(0, min(8192, Int(event.width)))
          height = max(0, min(8192, Int(event.height)))
        case UInt32(ROOTS_WINDOWS_EVENT_POINTER_MOVE.rawValue):
          pointer(event)
        case UInt32(ROOTS_WINDOWS_EVENT_POINTER_DOWN.rawValue):
          pointer(event)
          input.button(down: true)
        case UInt32(ROOTS_WINDOWS_EVENT_POINTER_UP.rawValue):
          pointer(event)
          input.button(down: false)
        case UInt32(ROOTS_WINDOWS_EVENT_POINTER_LEAVE.rawValue):
          input.pointer(x: input.input.x, y: input.input.y, inside: false)
        case UInt32(ROOTS_WINDOWS_EVENT_SCROLL.rawValue):
          pointer(event)
          input.scroll(x: Float(event.delta_x) * 48, y: -Float(event.delta_y) * 48)
        case UInt32(ROOTS_WINDOWS_EVENT_KEY.rawValue):
          input.key(
            virtualKey: event.virtual_key, scanCode: event.scan_code, scalar: event.text,
            producesText: event.text_key != 0,
            phase: phase(event.phase),
            modifiers: KeyModifiers(rawValue: UInt8(truncatingIfNeeded: event.modifiers)))
        case UInt32(ROOTS_WINDOWS_EVENT_TEXT.rawValue):
          input.text(
            scalar: event.text, scanCode: event.scan_code, phase: phase(event.phase),
            modifiers: KeyModifiers(rawValue: UInt8(truncatingIfNeeded: event.modifiers)))
        case UInt32(ROOTS_WINDOWS_EVENT_FOCUS_LOST.rawValue): input.loseFocus()
        default: break
        }
      }
    }

    private func pointer(_ event: RootsWindowsEvent) {
      let inside =
        event.x >= 0 && event.y >= 0 && event.x < Double(width) && event.y < Double(height)
      input.pointer(x: Float(event.x), y: Float(event.y), inside: inside)
    }

    private func phase(_ value: UInt32) -> KeyPhase {
      switch value {
      case UInt32(ROOTS_WINDOWS_KEY_REPEATED.rawValue): .repeated
      case UInt32(ROOTS_WINDOWS_KEY_RELEASED.rawValue): .released
      default: .pressed
      }
    }

    func readClipboard() -> String? {
      var text: UnsafeMutablePointer<CChar>?
      var count = 0
      let error = unsafe roots_windows_host_clipboard_read_utf8(handle, &text, &count)
      guard error == 0, let text = unsafe text else { return nil }
      defer { unsafe roots_windows_host_free(text) }
      guard count >= 0 && count <= 16 * 1024 * 1024 else { return nil }
      let buffer = unsafe UnsafeBufferPointer(start: text, count: count)
      return String(decoding: unsafe buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func writeClipboard(_ text: String) -> Bool {
      guard text.utf8.count <= 16 * 1024 * 1024, !text.utf8.contains(0) else { return false }
      return text.withCString { bytes in
        unsafe roots_windows_host_clipboard_write_utf8(handle, bytes, text.utf8.count) == 0
      }
    }
  }
#endif
