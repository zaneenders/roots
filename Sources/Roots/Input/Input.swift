public struct Input: Sendable {
  public var mousePosition: Coordinate?
  public var scrollX: Float, scrollY: Float
  public var scrollVelocityY: Float?
  public var pressed = false, released = false
  public var focusLost: Bool
  public var keyEvents: [KeyEvent]
  public init(
    mousePosition: Coordinate? = nil, pressed: Bool = false, released: Bool = false, scrollX: Float = 0,
    scrollY: Float = 0,
    scrollVelocityY: Float? = nil,
    keyEvents: [KeyEvent] = [], focusLost: Bool = false
  ) {
    self.mousePosition = mousePosition
    self.pressed = pressed
    self.released = released
    self.scrollX = scrollX
    self.scrollY = scrollY
    self.scrollVelocityY = scrollVelocityY
    self.keyEvents = keyEvents
    self.focusLost = focusLost
  }
}
