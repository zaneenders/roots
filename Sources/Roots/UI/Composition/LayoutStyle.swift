public enum LayoutSize: Equatable, Sendable {
  case fit
  case fill
  case fixed(Float)

  func measured(_ content: Float) -> Float {
    switch self {
    case .fit, .fill: return content
    case .fixed(let value):
      precondition(value.isFinite && value >= 0)
      return value
    }
  }

  func resolved(_ content: Float, available: Float) -> Float {
    switch self {
    case .fit: min(content, available)
    case .fill: available
    case .fixed: measured(content)
    }
  }
}

public struct Alignment: Equatable, Sendable {
  let x: Float
  let y: Float

  public static let topLeading = Alignment(x: 0, y: 0)
  public static let top = Alignment(x: 0.5, y: 0)
  public static let topTrailing = Alignment(x: 1, y: 0)
  public static let leading = Alignment(x: 0, y: 0.5)
  public static let center = Alignment(x: 0.5, y: 0.5)
  public static let trailing = Alignment(x: 1, y: 0.5)
  public static let bottomLeading = Alignment(x: 0, y: 1)
  public static let bottom = Alignment(x: 0.5, y: 1)
  public static let bottomTrailing = Alignment(x: 1, y: 1)
}

struct LayoutStyle {
  enum Kind {
    case leaf, row, column, stack, frame
    case grid(Int)
  }
  var kind: Kind = .stack
  var width: LayoutSize = .fit
  var height: LayoutSize = .fit
  var alignment: Alignment = .topLeading
  var gap: Float = 0
  var padding = SIMD2<Float>.zero
  var scrollsVertically = false
}

public struct FrameBlock<Content: Block>: Block {
  public typealias Body = Never
  let content: Content
  let style: LayoutStyle

  public borrowing func _build(into frame: inout UIFrame) {
    frame.beginLayout(style)
    content._build(into: &frame)
    frame.end()
  }
}

extension Block {
  public func frame(
    width: LayoutSize = .fit, height: LayoutSize = .fit, alignment: Alignment = .center
  ) -> FrameBlock<Self> {
    FrameBlock(content: self, style: LayoutStyle(kind: .frame, width: width, height: height, alignment: alignment))
  }

  public func padding(_ amount: Float) -> FrameBlock<Self> {
    precondition(amount.isFinite && amount >= 0)
    return padding(horizontal: amount, vertical: amount)
  }

  public func padding(horizontal: Float = 0, vertical: Float = 0) -> FrameBlock<Self> {
    precondition(horizontal.isFinite && horizontal >= 0 && vertical.isFinite && vertical >= 0)
    return FrameBlock(content: self, style: LayoutStyle(kind: .frame, padding: SIMD2(horizontal, vertical)))
  }
}
