public struct Input: Sendable {
  public var mousePosition: Coordinate?
  public var scrollX: Float, scrollY: Float
  public var scrollVelocityY: Float?
  public var pressed = false, released = false
  public var focusLost: Bool
  public var secondaryDown: Bool, secondaryPressed: Bool, secondaryReleased: Bool
  public var middleDown: Bool, middlePressed: Bool, middleReleased: Bool
  /// Wheel detents; do not add to the logical scroll distance in scrollX/Y.
  public var scrollStepsX: Float, scrollStepsY: Float
  public var scrollInvertedX: Bool?, scrollInvertedY: Bool?
  public var textEvents: [TextInputEvent]
  public var keyEvents: [KeyEvent]
  public init(
    mousePosition: Coordinate? = nil, pressed: Bool = false, released: Bool = false,
    scrollX: Float = 0,
    scrollY: Float = 0,
    scrollVelocityY: Float? = nil,
    keyEvents: [KeyEvent] = [], focusLost: Bool = false,
    secondaryDown: Bool = false, secondaryPressed: Bool = false, secondaryReleased: Bool = false,
    middleDown: Bool = false, middlePressed: Bool = false, middleReleased: Bool = false,
    scrollStepsX: Float = 0, scrollStepsY: Float = 0,
    scrollInvertedX: Bool? = nil, scrollInvertedY: Bool? = nil,
    textEvents: [TextInputEvent] = []
  ) {
    self.mousePosition = mousePosition
    self.pressed = pressed
    self.released = released
    self.scrollX = scrollX
    self.scrollY = scrollY
    self.scrollVelocityY = scrollVelocityY
    self.keyEvents = keyEvents
    self.focusLost = focusLost
    self.secondaryDown = secondaryDown
    self.secondaryPressed = secondaryPressed
    self.secondaryReleased = secondaryReleased
    self.middleDown = middleDown
    self.middlePressed = middlePressed
    self.middleReleased = middleReleased
    self.scrollStepsX = scrollStepsX
    self.scrollStepsY = scrollStepsY
    self.scrollInvertedX = scrollInvertedX
    self.scrollInvertedY = scrollInvertedY
    self.textEvents = textEvents
  }
}
