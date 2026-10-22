import Roots

/// X11 accumulates into the same value-only snapshot exposed by the Wayland host.
/// These helpers do not depend on Wayland protocol constants or transport state.
extension NativeWindowInput {
  mutating func resetEdges() {
    primaryPressed = false
    primaryReleased = false
    keyEvents.removeAll(keepingCapacity: true)
    scrollX = 0
    scrollY = 0
    scrollVelocityY = nil
    focusLost = false
  }

  mutating func leavePointer() {
    pointerInside = false
    scrollVelocityY = nil
    // X11's implicit pointer grab keeps dragging outside the window. Retain the
    // held button and the outside coordinates until the actual button release.
  }

  mutating func leaveKeyboard() {
    keyEvents.removeAll(keepingCapacity: true)
    focusLost = true
    releaseButtons()
  }

  mutating func releaseButtons() {
    primaryReleased = primaryReleased || primaryDown
    primaryDown = false
    scrollVelocityY = nil
  }

  mutating func appendKeyEvent(_ event: KeyEvent) {
    // Bound input retained while the window is unmapped or rendering is stalled.
    if keyEvents.count >= 256 { keyEvents.removeFirst() }
    keyEvents.append(event)
  }
}
