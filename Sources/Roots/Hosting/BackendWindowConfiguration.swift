public struct BackendWindowConfiguration: Sendable {
  public var title: String
  public var logicalSize: Size
  /// Nil uses the platform's default minimum size.
  public var minimumSize: Size?
  public var maxFrames: Int32
  public var screenshotPath: String?
  public var offscreen: Bool

  public init(
    title: String, logicalSize: Size = .init(width: 900, height: 660),
    minimumSize: Size? = nil, maxFrames: Int32 = 0,
    screenshotPath: String? = nil, offscreen: Bool = false
  ) {
    self.title = title
    self.logicalSize = logicalSize
    self.minimumSize = minimumSize
    self.maxFrames = maxFrames
    self.screenshotPath = screenshotPath
    self.offscreen = offscreen
  }

  public func validate() throws {
    guard logicalSize.width.isFinite, logicalSize.height.isFinite,
      logicalSize.width > 0, logicalSize.height > 0,
      logicalSize.width <= 8192, logicalSize.height <= 8192,
      maxFrames >= (offscreen ? 1 : 0), screenshotPath == nil || maxFrames > 0
    else { throw DesktopBackendError.invalidConfiguration }
    if let minimumSize {
      guard minimumSize.width.isFinite, minimumSize.height.isFinite,
        minimumSize.width >= 0, minimumSize.height >= 0,
        minimumSize.width <= logicalSize.width, minimumSize.height <= logicalSize.height
      else { throw DesktopBackendError.invalidConfiguration }
    }
  }
}
