public enum Key: Equatable, Sendable {
  case character(UnicodeScalar)
  case escape
  case tab
  case enter
  case backspace
  case delete
  case left
  case right
  case up
  case down
  case home
  case end
  case pageUp
  case pageDown
  case shift
  case control
  case alt
  case altGraph
  case `super`
  case capsLock
  case numLock
  case function(Int)
  case symbol(UInt32)

  public var isModifier: Bool {
    switch self {
    case .shift, .control, .alt, .altGraph, .super, .capsLock, .numLock: true
    default: false
    }
  }
}

public enum KeyPhase: Equatable, Sendable {
  case pressed
  case repeated
  case released
}
