import Roots
import SwiftWayland

public struct NativeWindowInput: Sendable {
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
  public internal(set) var timeSeconds: Double = 0
  public internal(set) var pointerX: Float = 0
  public internal(set) var pointerY: Float = 0
  public internal(set) var scrollX: Float = 0
  public internal(set) var scrollY: Float = 0
  public internal(set) var scrollVelocityY: Float?
  public internal(set) var pointerInside = false
  public internal(set) var primaryDown = false
  public internal(set) var primaryPressed = false
  public internal(set) var primaryReleased = false
  public internal(set) var keyEvents: [KeyEvent] = []
  public internal(set) var focusLost = false

  init(width: Int32, height: Int32) {
    self.width = width
    self.height = height
  }

  init(_ input: WaylandInput) {
    width = input.width
    height = input.height
    bufferScale = input.bufferScale
    fractionalScale120 = input.fractionalScale120
    pointerX = input.pointerX
    pointerY = input.pointerY
    scrollX = input.scrollX
    scrollY = input.scrollY
    scrollVelocityY = input.scrollVelocityY
    pointerInside = input.pointerInside
    primaryDown = input.primaryDown
    primaryPressed = input.primaryPressed
    primaryReleased = input.primaryReleased
    focusLost = input.focusLost
    keyEvents = input.keyEvents.map {
      KeyEvent(
        Key($0.key), phase: KeyPhase($0.phase),
        modifiers: KeyModifiers(rawValue: $0.modifiers.rawValue),
        physicalCode: $0.physicalCode)
    }
  }
}

extension KeyPhase {
  fileprivate init(_ phase: WaylandKeyPhase) {
    switch phase {
    case .pressed: self = .pressed
    case .repeated: self = .repeated
    case .released: self = .released
    }
  }
}

extension Key {
  fileprivate init(_ key: WaylandKey) {
    switch key {
    case .escape: self = .escape
    case .tab: self = .tab
    case .enter: self = .enter
    case .backspace: self = .backspace
    case .delete: self = .delete
    case .left: self = .left
    case .right: self = .right
    case .up: self = .up
    case .down: self = .down
    case .home: self = .home
    case .end: self = .end
    case .pageUp: self = .pageUp
    case .pageDown: self = .pageDown
    case .shift: self = .shift
    case .control: self = .control
    case .alt: self = .alt
    case .altGraph: self = .altGraph
    case .super: self = .super
    case .capsLock: self = .capsLock
    case .numLock: self = .numLock
    case .character(let value): self = .character(value)
    case .function(let value): self = .function(value)
    case .symbol(let value): self = .symbol(value)
    }
  }
}
