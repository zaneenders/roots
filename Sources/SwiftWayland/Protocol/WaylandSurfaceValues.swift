enum WaylandBufferTransform: Int32 {
  case flipped180 = 6
}

enum WaylandPositionerAnchor: UInt32 {
  case bottomRight = 8
}

enum WaylandPositionerGravity: UInt32 {
  case bottomLeft = 6
}

struct WaylandConstraintAdjustment: OptionSet {
  let rawValue: UInt32
  static let slideX = Self(rawValue: 1)
  static let slideY = Self(rawValue: 2)
  static let flipY = Self(rawValue: 8)
}

struct WaylandLayerAnchor: OptionSet {
  let rawValue: UInt32
  static let top = Self(rawValue: 1)
  static let left = Self(rawValue: 4)
  static let right = Self(rawValue: 8)
}

enum WaylandLayer: UInt32 {
  case top = 2
}

enum WaylandKeyboardInteractivity: UInt32 {
  case none = 0
}
