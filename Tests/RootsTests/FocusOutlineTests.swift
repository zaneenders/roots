@_spi(Hosting) import Roots
import Testing

@Test @MainActor func focusedOutlineStaysInsideControlsAtScrollViewportEdges() {
  var host = UIHost()
  let viewport = Region(10, 20, 100, 80)
  let target = Region(10, 20, 100, 40)
  host.frame {
    Scroll(key: 1, in: viewport) {
      Column(gap: 0) {
        Element(key: 2, extent: 40, color: .panel) { painter in
          painter.fillRect(painter.region, color: .panel, radius: 7)
        }
      }
    }
    Focus(key: 2)
  } present: { draws in
    var outlines = 0
    var backgroundIndex = -1
    var outlineIndex = -1
    var index = 0
    for draw in draws.rectangles {
      if draw.color == .panel { backgroundIndex = index }
      if draw.color == .accent {
        outlines += 1
        outlineIndex = index
        #expect(draw.strokeWidth == 2)
        #expect(draw.region == Region(11, 21, 98, 38))
        #expect(draw.clip == viewport)
        let bounds = draw.bounds
        #expect(bounds.x >= target.x && bounds.y >= target.y)
        #expect(bounds.x + bounds.width <= target.x + target.width)
        #expect(bounds.y + bounds.height <= target.y + target.height)
      }
      index += 1
    }
    #expect(outlines == 1 && outlineIndex > backgroundIndex)
  }
  #expect(host.droppedDraws == 0)
}
