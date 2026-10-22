public struct Input: Sendable {
  public var x: Float = -1, y: Float = -1
  public var scrollX: Float, scrollY: Float
  public var scrollVelocityY: Float?
  public var pressed = false, released = false
  public var focusLost: Bool
  public var keyEvents: [KeyEvent]
  public init(
    x: Float = -1, y: Float = -1, pressed: Bool = false, released: Bool = false, scrollX: Float = 0,
    scrollY: Float = 0,
    scrollVelocityY: Float? = nil,
    keyEvents: [KeyEvent] = [], focusLost: Bool = false
  ) {
    self.x = x
    self.y = y
    self.pressed = pressed
    self.released = released
    self.scrollX = scrollX
    self.scrollY = scrollY
    self.scrollVelocityY = scrollVelocityY
    self.keyEvents = keyEvents
    self.focusLost = focusLost
  }
}
