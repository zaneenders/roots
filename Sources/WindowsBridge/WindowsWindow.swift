import RootsCPU

@MainActor public enum WindowsWindow {
  /// Deterministic CPU rendering does not need an HWND or a graphics driver.
  public static func renderOffscreen(
    configuration: WindowsWindowConfiguration = .init(maxFrames: 12),
    frame: @MainActor (WindowsFrameInput, borrowing WindowsRenderFrame) -> Void
  ) async throws {
    try Task.checkCancellation()
    try configuration.validate(offscreen: true)
    let width = Int(configuration.size.x.rounded(.up))
    let height = Int(configuration.size.y.rounded(.up))
    let renderer = CPURenderer(width: width, height: height)
    for index in 0..<configuration.maxFrames {
      try Task.checkCancellation()
      frame(
        WindowsFrameInput(
          size: .init(Float(width), Float(height)), timeSeconds: Double(index) / 60),
        WindowsRenderFrame(renderer: renderer))
      if index == configuration.maxFrames - 1, let path = configuration.screenshotPath {
        try renderer.writePPM(to: path)
      }
      await Task.yield()
    }
  }
}
