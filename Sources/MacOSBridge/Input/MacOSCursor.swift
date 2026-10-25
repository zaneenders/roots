import AppKit
import Roots

@MainActor
enum MacOSCursor {
  static func cursor(for shape: CursorShape) -> NSCursor? {
    switch shape {
    case .default: .arrow
    case .contextMenu: .contextualMenu
    case .pointer: .pointingHand
    case .crosshair: .crosshair
    case .text: .iBeam
    case .verticalText: .iBeamCursorForVerticalLayout
    case .alias: .dragLink
    case .copy: .dragCopy
    case .noDrop, .notAllowed: .operationNotAllowed
    case .grab: .openHand
    case .grabbing: .closedHand
    case .eastWestResize, .columnResize: .columnResize
    case .northSouthResize, .rowResize: .rowResize
    case .eastResize: .frameResize(position: .right, directions: .all)
    case .westResize: .frameResize(position: .left, directions: .all)
    case .northResize: .frameResize(position: .top, directions: .all)
    case .southResize: .frameResize(position: .bottom, directions: .all)
    case .northEastResize, .northEastSouthWestResize:
      .frameResize(position: .topRight, directions: .all)
    case .northWestResize, .northWestSouthEastResize:
      .frameResize(position: .topLeft, directions: .all)
    case .southEastResize: .frameResize(position: .bottomRight, directions: .all)
    case .southWestResize: .frameResize(position: .bottomLeft, directions: .all)
    case .zoomIn: .zoomIn
    case .zoomOut: .zoomOut
    case .help, .progress, .wait, .cell, .move, .allScroll: nil
    }
  }
}
