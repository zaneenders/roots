import Testing

@testable import Roots

@Test func canvasDoesNotTakeFocusOrScrollWhenTyping() {
  var ui = UIStore()
  var canvas: NodeHandle?
  var editor: NodeHandle?
  var viewport: NodeHandle?
  var painted = false
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab)]),
    build: { frame in
      let scroll = frame.beginScrollColumn(key: 1, in: Region(0, 0, 300, 100))
      viewport = scroll
      canvas = frame.canvas(key: 2, extent: 1000) { painter in
        painted = true
        let focused = painter.focused
        #expect(!focused)
        painter.drawText("# raw markdown", x: painter.region.x, y: painter.region.y)
      }
      frame.end()
      frame.scrollTo(400, in: scroll)
      frame.beginColumn(in: Region(0, 120, 300, 44))
      editor = frame.element(key: 3, paint: { _ in })
      frame.end()
    }, present: { _ in })
  #expect(painted)
  #expect(ui.state(for: canvas!)?.focused == false)
  #expect(ui.state(for: editor!)?.focused == true)
  #expect(ui.state(for: viewport!)?.scrollOffset == 400)
}

@Test func everyPrintableASCIIGlyphIsDefined() {
  let atlas = FontAtlas.shared
  for code in UInt8(32)...126 {
    let character = Character(UnicodeScalar(code))
    #expect(atlas.contains(character))
    #expect(atlas.glyphUV(character) != atlas.glyphUV("�"))
  }
  #expect(atlas.glyphUV("a") != atlas.glyphUV("A"))
}

@Test func labelTextIsClippedToItsOwnBounds() {
  var ui = UIStore()
  let region = Region(0, 0, 40, 32)
  ui.frame(
    build: { frame in
      frame.beginColumn(in: region)
      frame.label(key: 1, "a long label that must not overlap adjacent controls", extent: 32)
      frame.end()
    },
    present: { draws in
      for draw in draws.rectangles where draw.color == .text {
        #expect(draw.clip == region)
      }
    })
}
