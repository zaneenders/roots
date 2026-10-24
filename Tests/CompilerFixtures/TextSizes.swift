import Roots

@MainActor
func textSizes() -> some Block {
  Column(in: Region(0, 0, 200, 100)) {
    Button(key: 1, "Button", size: 14)
    RichText(key: 2, lines: [TextLine([TextRun("Line")], y: 0, size: 12)], extent: 20)
    Canvas(key: 3, extent: 40) { context in
      context.drawText("Canvas", x: 0, y: 0, size: 16)
    }
  }
}
