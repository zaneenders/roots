public struct ScrollEvent: Sendable {
  public var deltaY: Float
  public var x: Float
  public var y: Float
  public var region: Region

  public init(deltaY: Float, x: Float, y: Float, region: Region) {
    self.deltaY = deltaY
    self.x = x
    self.y = y
    self.region = region
  }
}
