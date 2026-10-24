@_spi(Hosting) import Roots
import Testing

@MainActor
struct ScrollLayoutTests {
  @Test func gridScrollsAtItsFullContentHeightAndClipsToViewport() {
    var host = UIHost()
    let bounds = Region(10, 20, 100, 30)
    host.frame(
      build: {
        Scroll(key: 1, in: bounds, showsScrollIndicator: true) {
          Grid(columns: 2, gap: 4, alignment: .topLeading) {
            ForEach([UInt64(2), 3, 4, 5]) { key in
              Canvas(key: key, extent: 20) { context in
                context.fillRect(context.region, color: .accent)
              }
            }
          }
        }
        ScrollTo(100, in: 1)
      },
      present: { batch in
        var clips: [Region?] = []
        for draw in batch where draw.color == .accent { clips.append(draw.clip) }
        #expect(clips == [
          Region(10, 20, 48, 6), Region(62, 20, 48, 6),
          Region(10, 30, 48, 20), Region(62, 30, 48, 20)
        ])
      })
    #expect(host.state(for: 1)?.scrollOffset == 14)
    #expect(host.state(for: 2)?.region == Region(10, 6, 48, 20))
    #expect(host.state(for: 3)?.region == Region(62, 6, 48, 20))
    #expect(host.state(for: 4)?.region == Region(10, 30, 48, 20))
    #expect(host.state(for: 5)?.region == Region(62, 30, 48, 20))
  }

  @Test func rowRemainsHorizontalInsideScroll() {
    var host = UIHost()
    host.frame(
      build: {
        Scroll(key: 1, in: Region(10, 20, 100, 30)) {
          Row(gap: 5) {
            Canvas(key: 2) { _ in }.frame(width: .fixed(20), height: .fixed(60))
            Canvas(key: 3) { _ in }.frame(width: .fixed(30), height: .fixed(60))
          }
        }
        ScrollTo(100, in: 1)
      }, present: { _ in })
    #expect(host.state(for: 1)?.scrollOffset == 30)
    #expect(host.state(for: 2)?.region == Region(10, -10, 20, 60))
    #expect(host.state(for: 3)?.region == Region(35, -10, 30, 60))
  }

  @Test func stackOverlapsChildrenInsteadOfAddingImplicitColumnSpacing() {
    var host = UIHost()
    host.frame(
      build: {
        Scroll(key: 1, in: Region(0, 0, 100, 30)) {
          Stack(alignment: .topLeading) {
            Canvas(key: 2) { _ in }.frame(width: .fill, height: .fixed(60))
            Canvas(key: 3) { _ in }.frame(width: .fill, height: .fixed(40))
          }
        }
        ScrollTo(100, in: 1)
      }, present: { _ in })
    #expect(host.state(for: 1)?.scrollOffset == 30)
    #expect(host.state(for: 2)?.region == Region(0, -30, 100, 60))
    #expect(host.state(for: 3)?.region == Region(0, -30, 100, 40))
  }

  @Test func paragraphsReflowBeforeScrollHeightIsResolved() throws {
    var host = UIHost()
    var previousHeight: Float = 0
    for width: Float in [100, 40] {
      host.frame(
        build: {
          Scroll(key: 1, in: Region(0, 0, width, 20)) {
            Column(gap: 4) {
              Paragraph { Text("One two three four five six seven eight nine ten") }
                .size(10).selectable(key: 2)
              Canvas(key: 3, extent: 10) { _ in }
            }
          }
          ScrollTo(10_000, in: 1)
        }, present: { _ in })
      let paragraph = try #require(host.state(for: 2)?.region)
      let footer = try #require(host.state(for: 3)?.region)
      #expect(paragraph.width == width)
      #expect(paragraph.height > previousHeight)
      #expect(footer.y == 10)
      #expect(host.state(for: 1)?.scrollOffset == paragraph.height + 4 + 10 - 20)
      previousHeight = paragraph.height
    }
  }
}
