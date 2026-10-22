enum NodeInteraction {
  case none
  case canvas(paint: (inout UIPaintContext) -> Void)
  case button(onClick: (() -> Void)?)
  case element(
    onKey: ((KeyEvent) -> Void)?, onPointer: ((PointerEvent) -> Void)?,
    onScroll: ((ScrollEvent) -> Void)?,
    paint: (inout UIPaintContext) -> Void)

  var isInteractive: Bool {
    switch self {
    case .none, .canvas: false
    case .button, .element: true
    }
  }

  func handleKey(_ event: KeyEvent) {
    if case .element(let onKey, _, _, _) = self { onKey?(event) }
  }

  func handlePointer(_ event: PointerEvent) {
    if case .element(_, let onPointer, _, _) = self { onPointer?(event) }
  }

  var onScroll: ((ScrollEvent) -> Void)? {
    if case .element(_, _, let onScroll, _) = self { return onScroll }
    return nil
  }

  func activate() {
    if case .button(let onClick) = self { onClick?() }
  }
}
