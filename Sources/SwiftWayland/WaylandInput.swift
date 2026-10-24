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
  private var verticalScroll = ScrollGesture()
  public internal(set) var pointerInside = false
  public internal(set) var primaryDown = false
  public internal(set) var primaryPressed = false
  public internal(set) var primaryReleased = false
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
    keyEvents.removeAll(keepingCapacity: true)
    scrollX = 0
    scrollY = 0
    scrollVelocityY = nil
  }

  mutating func leavePointer() {
    pointerInside = false
    primaryReleased = primaryReleased || primaryDown
    primaryDown = false
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

  mutating func pointerFrame() {
    if let velocity = verticalScroll.finish() { scrollVelocityY = velocity }
  }

  mutating func button(_ button: UInt32, state: UInt32) {
    guard button == 0x110 else { return }
    let down = state == WaylandPointerButtonState.pressed.rawValue
    primaryPressed = primaryPressed || (down && !primaryDown)
    primaryReleased = primaryReleased || (!down && primaryDown)
    primaryDown = down
  }

  mutating func leaveKeyboard() {
    resetEdges()
    focusLost = true
    primaryDown = false
    verticalScroll = ScrollGesture()
  }
}
