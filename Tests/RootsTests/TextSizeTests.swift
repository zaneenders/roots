@_spi(Hosting) import Roots
import Testing

@MainActor
struct TextSizeTests {
  @Test func buttonUsesNumericSizeForItsTitle() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 40)) {
          Button(key: 1, "A", extent: 40, size: 10)
        }
      },
      present: { batch in
        #expect(batch.count == 2)
        #expect(batch[1].region == Region(12, 13, 10, 14))
      })
  }

  @Test func textLineSizeChangesRefreshRendering() {
    var host = UIHost()
    var line = TextLine([TextRun("A")], x: 0, y: 0, size: 10)
    #expect(line.size == 10)
    for size: Float in [10, 17.5, 10] {
      line.size = size
      #expect(line.size == size)
      host.frame(
        build: {
          Column(in: Region(0, 0, 100, 50)) {
            RichText(key: 1, lines: [line], extent: 50)
          }
        },
        present: { batch in
          #expect(batch.count == 2)
          #expect(batch[1].region == Region(0, 0, size, size * 1.4))
        })
    }
  }

  @Test func canvasTextUsesDefaultAndExplicitSizes() {
    var host = UIHost()
    var defaultEnd: Float = 0
    var fractionalEnd: Float = 0
    host.frame(
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          Canvas(key: 1) { context in
            defaultEnd = context.drawText("A", x: 0, y: 0)
            fractionalEnd = context.drawText("B", x: 0, y: 30, size: 17.5)
          }
        }
      },
      present: { batch in
        #expect(batch.count == 3)
        #expect(batch[1].region == Region(0, 0, 20, 28))
        #expect(batch[2].region == Region(0, 30, 17.5, 24.5))
      })
    #expect(defaultEnd == 12)
    #expect(fractionalEnd == 10.5)
  }
}
