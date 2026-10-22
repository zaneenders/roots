public struct WaylandKeyModifiers: OptionSet, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let shift = WaylandKeyModifiers(rawValue: 1 << 0)
  public static let control = WaylandKeyModifiers(rawValue: 1 << 1)
  public static let alt = WaylandKeyModifiers(rawValue: 1 << 2)
  public static let `super` = WaylandKeyModifiers(rawValue: 1 << 3)
  public static let altGraph = WaylandKeyModifiers(rawValue: 1 << 4)
  public static let capsLock = WaylandKeyModifiers(rawValue: 1 << 5)
  public static let numLock = WaylandKeyModifiers(rawValue: 1 << 6)

}
