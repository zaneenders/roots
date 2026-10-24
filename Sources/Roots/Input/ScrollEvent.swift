public struct ScrollEvent: Sendable {
  public var deltaY: Float
  /// Coordinates relative to the element's origin.
  public var position: Coordinate
  public var region: Region

  public init(deltaY: Float, position: Coordinate, region: Region) {
    self.deltaY = deltaY
    self.position = position
    self.region = region
  }
}
