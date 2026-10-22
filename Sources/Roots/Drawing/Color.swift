public struct Color: Equatable, BitwiseCopyable, Sendable {
  public var r, g, b, a: Float
  public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }
  public static let text = Color(0.86, 0.9, 0.96)
  public static let panel = Color(0.10, 0.14, 0.20)
  public static let accent = Color(0.17, 0.78, 0.73)
}
