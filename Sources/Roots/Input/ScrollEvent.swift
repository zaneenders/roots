public struct ScrollEvent: Sendable {
  public var deltaY: Float
  public var position: Coordinate
  public var region: Region

  public init(deltaY: Float, position: Coordinate, region: Region) {
    self.deltaY = deltaY
    self.position = position
    self.region = region
  }
}
