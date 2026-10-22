public enum WindowsWindowError: Error, Equatable {
  case invalidConfiguration
  case alreadyRunning
  case nativeFailure(code: UInt32)
}

/// The first Windows backend uses client pixels for both layout and rendering.
public struct WindowsWindowConfiguration: Sendable {
  public var size: SIMD2<Float>
  public var title: String
  public var maxFrames: Int32
  public var screenshotPath: String?

  public init(
    size: SIMD2<Float> = .init(900, 660), title: String = "Roots",
    maxFrames: Int32 = 0, screenshotPath: String? = nil
  ) {
    self.size = size
    self.title = title
    self.maxFrames = maxFrames
    self.screenshotPath = screenshotPath
  }

  func validate(offscreen: Bool) throws {
    guard size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
      size.x <= 8192, size.y <= 8192, maxFrames >= (offscreen ? 1 : 0),
      screenshotPath == nil || maxFrames > 0, !title.utf8.contains(0)
    else { throw WindowsWindowError.invalidConfiguration }
  }
}
