import AppKit
import MetalKit
import Roots

@MainActor final class MacOSInputView: MTKView {
  weak var host: MacOSWindowHost?
  private var pointerTracking: NSTrackingArea?
  private var nativeCursor = NSCursor.arrow
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerTracking { removeTrackingArea(pointerTracking) }
    let tracking = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(tracking)
    pointerTracking = tracking
  }

  func setCursor(_ shape: CursorShape) -> Bool {
    guard let cursor = MacOSCursor.cursor(for: shape) else { return false }
    nativeCursor = cursor
    if host?.input.pointerInside == true, unsafe window?.isKeyWindow == true { cursor.set() }
    return true
  }

  override func cursorUpdate(with event: NSEvent) { nativeCursor.set() }

  private func pointer(_ event: NSEvent, inside: Bool? = nil) {
    let point = convert(event.locationInWindow, from: nil)
    host?.input.pointer(
      x: Float(point.x), y: Float(point.y), inside: inside ?? bounds.contains(point))
    host?.requestRedraw()
  }

  override func mouseEntered(with event: NSEvent) { pointer(event, inside: true) }
  override func mouseExited(with event: NSEvent) { pointer(event, inside: false) }
  override func mouseMoved(with event: NSEvent) { pointer(event) }
  override func mouseDown(with event: NSEvent) {
    pointer(event)
    host?.input.button(down: true)
  }
  override func mouseDragged(with event: NSEvent) { pointer(event) }
  override func mouseUp(with event: NSEvent) {
    pointer(event)
    host?.input.button(down: false)
  }
  override func rightMouseDown(with event: NSEvent) {
    pointer(event)
    host?.input.button(.secondary, down: true)
  }
  override func rightMouseDragged(with event: NSEvent) { pointer(event) }
  override func rightMouseUp(with event: NSEvent) {
    pointer(event)
    host?.input.button(.secondary, down: false)
  }
  override func otherMouseDown(with event: NSEvent) {
    guard event.buttonNumber == 2 else { return }
    pointer(event)
    host?.input.button(.middle, down: true)
  }
  override func otherMouseDragged(with event: NSEvent) {
    if event.buttonNumber == 2 { pointer(event) }
  }
  override func otherMouseUp(with event: NSEvent) {
    guard event.buttonNumber == 2 else { return }
    pointer(event)
    host?.input.button(.middle, down: false)
  }
  override func keyDown(with event: NSEvent) {
    host?.input.key(MacOSKeyboard.event(event))
    host?.requestRedraw()
  }
  override func keyUp(with event: NSEvent) {
    host?.input.key(MacOSKeyboard.event(event))
    host?.requestRedraw()
  }
  override func flagsChanged(with event: NSEvent) {
    host?.input.flags(
      MacOSKeyboard.modifiers(event.modifierFlags), code: UInt32(event.keyCode),
      key: MacOSKeyboard.key(code: event.keyCode, characters: nil))
    host?.requestRedraw()
  }
  override func scrollWheel(with event: NSEvent) {
    pointer(event)
    let scale: Float = event.hasPreciseScrollingDeltas ? 1 : 10
    host?.input.scroll(
      x: -Float(event.scrollingDeltaX) * scale, y: -Float(event.scrollingDeltaY) * scale,
      stepsX: event.hasPreciseScrollingDeltas ? 0 : -Float(event.scrollingDeltaX),
      stepsY: event.hasPreciseScrollingDeltas ? 0 : -Float(event.scrollingDeltaY),
      inverted: event.isDirectionInvertedFromDevice)
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "q"
    {
      return false
    }
    guard event.modifierFlags.contains(.command), unsafe window?.isKeyWindow == true else {
      return false
    }
    keyDown(with: event)
    return true
  }
}
