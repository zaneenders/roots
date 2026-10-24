public struct WaylandInput: Sendable {
  public internal(set) var width: Int32
  public internal(set) var height: Int32
  /// `wl_surface.set_buffer_scale`; remains 1 when fractional scaling is active.
  public internal(set) var bufferScale: Int32 = 1
  /// Fractional scale numerator in units of 1/120; nil uses integer buffer scaling.
  public internal(set) var fractionalScale120: UInt32?
  /// Pixels per logical unit, before rounding the buffer dimensions.
  public var renderScale: Double {
    fractionalScale120.map { Double($0) / 120 } ?? Double(bufferScale)
  }
  public internal(set) var pointerX: Float = 0
  public internal(set) var pointerY: Float = 0
  public internal(set) var scrollX: Float = 0
  public internal(set) var scrollY: Float = 0
  public internal(set) var scrollVelocityY: Float?
  /// Wheel steps; 1 is one detent (120 protocol units). Do not add to scrollX/Y.
  public internal(set) var scrollStepsX: Float = 0
  public internal(set) var scrollStepsY: Float = 0
  public internal(set) var scrollInvertedX: Bool?
  public internal(set) var scrollInvertedY: Bool?
  private var wheel120X: Float = 0
  private var wheel120Y: Float = 0
  private var discreteX: Float = 0
  private var discreteY: Float = 0
  private var hasWheel120X = false
  private var hasWheel120Y = false
  private var verticalScroll = ScrollGesture()
  public internal(set) var pointerInside = false
  public internal(set) var primaryDown = false
  public internal(set) var primaryPressed = false
  public internal(set) var primaryReleased = false
  public internal(set) var secondaryDown = false
  public internal(set) var secondaryPressed = false
  public internal(set) var secondaryReleased = false
  public internal(set) var middleDown = false
  public internal(set) var middlePressed = false
  public internal(set) var middleReleased = false
  public internal(set) var textEvents: [WaylandTextInputEvent] = []
  public internal(set) var keyEvents: [WaylandKeyEvent] = []
  public internal(set) var focusLost = false

  public init(width: Int32, height: Int32) {
    self.width = width
    self.height = height
  }

  public mutating func resetEdges() {
    focusLost = false
    primaryPressed = false
    primaryReleased = false
    secondaryPressed = false
    secondaryReleased = false
    middlePressed = false
    middleReleased = false
    textEvents.removeAll(keepingCapacity: true)
    scrollStepsX = 0
    scrollStepsY = 0
    scrollInvertedX = nil
    scrollInvertedY = nil
    keyEvents.removeAll(keepingCapacity: true)
    scrollX = 0
    scrollY = 0
    scrollVelocityY = nil
  }

  mutating func leavePointer() {
    pointerInside = false
    primaryReleased = primaryReleased || primaryDown
    primaryDown = false
    secondaryReleased = secondaryReleased || secondaryDown
    middleReleased = middleReleased || middleDown
    secondaryDown = false
    middleDown = false
    clearWheelFrame()
    verticalScroll = ScrollGesture()
    scrollVelocityY = nil
  }

  mutating func axis(_ axis: UInt32, value: Int32, time: UInt32) {
    let distance = Float(value) / 256
    if axis == WaylandPointerAxis.verticalScroll.rawValue {
      scrollY += distance
      scrollVelocityY = nil
      verticalScroll.distance += distance
      verticalScroll.time = time
    }
    if axis == WaylandPointerAxis.horizontalScroll.rawValue { scrollX += distance }
  }

  mutating func axisSource(_ source: UInt32) {
    verticalScroll.source = source
  }

  mutating func axisStop(_ axis: UInt32, time: UInt32) {
    if axis == WaylandPointerAxis.verticalScroll.rawValue { verticalScroll.stopTime = time }
  }

  mutating func axisSteps(_ axis: UInt32, value: Int32, highResolution: Bool) {
    if axis == 0 {
      if highResolution {
        wheel120Y += Float(value)
        hasWheel120Y = true
      } else {
        discreteY += Float(value)
      }
    } else if axis == 1 {
      if highResolution {
        wheel120X += Float(value)
        hasWheel120X = true
      } else {
        discreteX += Float(value)
      }
    }
  }

  mutating func axisDirection(_ axis: UInt32, inverted: Bool) {
    if axis == 0 { scrollInvertedY = inverted }
    if axis == 1 { scrollInvertedX = inverted }
  }

  private mutating func clearWheelFrame() {
    wheel120X = 0
    wheel120Y = 0
    discreteX = 0
    discreteY = 0
    hasWheel120X = false
    hasWheel120Y = false
  }

  mutating func pointerFrame() {
    scrollStepsX += hasWheel120X ? wheel120X / 120 : discreteX
    scrollStepsY += hasWheel120Y ? wheel120Y / 120 : discreteY
    clearWheelFrame()
    if let velocity = verticalScroll.finish() { scrollVelocityY = velocity }
  }

  mutating func button(_ button: UInt32, state: UInt32) {
    guard state <= 1 else { return }
    let down = state == WaylandPointerButtonState.pressed.rawValue
    switch button {
    case 0x110:
      primaryPressed = primaryPressed || (down && !primaryDown)
      primaryReleased = primaryReleased || (!down && primaryDown)
      primaryDown = down
    case 0x111:
      secondaryPressed = secondaryPressed || (down && !secondaryDown)
      secondaryReleased = secondaryReleased || (!down && secondaryDown)
      secondaryDown = down
    case 0x112:
      middlePressed = middlePressed || (down && !middleDown)
      middleReleased = middleReleased || (!down && middleDown)
      middleDown = down
    default: break
    }
  }

  mutating func leaveKeyboard() {
    resetEdges()
    focusLost = true
    secondaryDown = false
    middleDown = false
    clearWheelFrame()
    primaryDown = false
    verticalScroll = ScrollGesture()
  }
}
