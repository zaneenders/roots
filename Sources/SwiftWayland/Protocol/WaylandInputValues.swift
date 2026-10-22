enum WaylandPointerAxis: UInt32 {
  case verticalScroll = 0
  case horizontalScroll = 1
}

enum WaylandPointerAxisSource: UInt32 {
  case wheel = 0
  case finger = 1
  case continuous = 2
  case wheelTilt = 3
}

enum WaylandPointerButtonState: UInt32 {
  case released = 0
  case pressed = 1
}

enum WaylandKeyboardKeymapFormat: UInt32 {
  case noKeymap = 0
  case xkbV1 = 1
}
