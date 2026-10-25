/// Native cursor intent. A surface can decline shapes it does not support.
public enum CursorShape: Sendable, CaseIterable {
  case `default`, contextMenu, help, pointer, progress, wait, cell, crosshair, text
  case verticalText, alias, copy, move, noDrop, notAllowed, grab, grabbing
  case eastResize, northResize, northEastResize, northWestResize, southResize
  case southEastResize, southWestResize, westResize, eastWestResize, northSouthResize
  case northEastSouthWestResize, northWestSouthEastResize, columnResize, rowResize
  case allScroll, zoomIn, zoomOut

  public init(_ style: CursorStyle) {
    self =
      switch style {
      case .default: .default
      case .pointer: .pointer
      case .text: .text
      }
  }
}
