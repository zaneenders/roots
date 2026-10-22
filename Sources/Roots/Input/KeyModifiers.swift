public struct KeyModifiers: OptionSet, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let shift = KeyModifiers(rawValue: 1 << 0)
  public static let control = KeyModifiers(rawValue: 1 << 1)
  public static let alt = KeyModifiers(rawValue: 1 << 2)
  public static let `super` = KeyModifiers(rawValue: 1 << 3)
  public static let altGraph = KeyModifiers(rawValue: 1 << 4)
  public static let capsLock = KeyModifiers(rawValue: 1 << 5)
  public static let numLock = KeyModifiers(rawValue: 1 << 6)

  var hasShortcutModifier: Bool { !intersection([.control, .alt, .super]).isEmpty }
}
