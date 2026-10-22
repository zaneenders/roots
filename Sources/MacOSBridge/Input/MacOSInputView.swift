import AppKit
import MetalKit

@MainActor final class MacOSInputView: MTKView {
  weak var host: MacOSWindowHost?
  private var pointerTracking: NSTrackingArea?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerTracking { removeTrackingArea(pointerTracking) }
    let tracking = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(tracking)
    pointerTracking = tracking
  }

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
      x: -Float(event.scrollingDeltaX) * scale, y: -Float(event.scrollingDeltaY) * scale)
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
