public struct WaylandWindowConfiguration: Sendable {
  public var width: Int32
  public var height: Int32
  public var minimumWidth: Int32
  public var minimumHeight: Int32
  public var title: String
  public var appID: String
  public var layerNamespace: String
  public var topBar: Bool
  public var topBarOverlayHeight: Int32

  public init(
    width: Int32 = 900, height: Int32 = 660, title: String = "Wayland Window",
    appID: String = "org.swift.wayland", minimumWidth: Int32 = 0, minimumHeight: Int32 = 0,
    topBar: Bool = false,
    topBarOverlayHeight: Int32 = 0, layerNamespace: String = "swift-wayland"
  ) {
    self.width = width
    self.height = height
    self.minimumWidth = minimumWidth
    self.minimumHeight = minimumHeight
    self.title = title
    self.appID = appID
    self.layerNamespace = layerNamespace
    self.topBar = topBar
    self.topBarOverlayHeight = topBarOverlayHeight
  }
}
