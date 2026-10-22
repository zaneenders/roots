public struct NativeWindowConfiguration: Sendable {
  public var width: Int32
  public var height: Int32
  public var maxFrames: Int32
  public var title: String
  public var screenshotPath: String?
  public var topBar: Bool
  public var topBarOverlayHeight: Int32
  public var appID: String
  public var minimumWidth: Int32
  public var minimumHeight: Int32
  public var layerNamespace: String

  public init(
    width: Int32 = 900, height: Int32 = 660, maxFrames: Int32 = 0,
    title: String = "Keyed UI Demo", screenshotPath: String? = nil, topBar: Bool = false,
    topBarOverlayHeight: Int32 = 0, appID: String = "org.example.keyed-ui-demo",
    minimumWidth: Int32 = 760, minimumHeight: Int32 = 640,
    layerNamespace: String = "hypr-desktop-bar"
  ) {
    self.width = width
    self.height = height
    self.maxFrames = maxFrames
    self.title = title
    self.screenshotPath = screenshotPath
    self.topBar = topBar
    self.topBarOverlayHeight = topBarOverlayHeight
    self.appID = appID
    self.minimumWidth = minimumWidth
    self.minimumHeight = minimumHeight
    self.layerNamespace = layerNamespace
  }
}
