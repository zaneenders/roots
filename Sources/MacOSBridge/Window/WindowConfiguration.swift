public struct WindowConfiguration: Sendable {
  public var logicalSize: SIMD2<Float>
  public var title: String
  public var maxFrames: Int32
  public var screenshotPath: String?

  public init(
    logicalSize: SIMD2<Float> = .init(900, 660), title: String = "Keyed UI Demo",
    maxFrames: Int32 = 0, screenshotPath: String? = nil
  ) {
    self.logicalSize = logicalSize
    self.title = title
    self.maxFrames = maxFrames
    self.screenshotPath = screenshotPath
  }
}
