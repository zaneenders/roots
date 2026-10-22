import Testing

@testable import Roots

@Test func drawBatchProvidesReadOnlyOrderedFrameOutput() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginRow(in: Rect(0, 0, 80, 40), gap: 0)
      frame.canvas(key: 1, extent: 40, color: .panel) { context in
        context.fillRect(Rect(4, 4, 8, 8), color: .accent)
      }
      frame.canvas(key: 2, extent: 40, color: .text) { _ in }
      frame.end()
    },
    present: { batch in
      let isEmpty = batch.isEmpty
      #expect(!isEmpty)
      #expect(batch.count == 3)
      #expect(batch.underestimatedCount == batch.count)
      guard batch.count == 3 else { return }
      #expect(batch[0].color == .panel)
      #expect(batch[1].color == .accent)
      #expect(batch[2].color == .text)
      var index = 0
      for draw in batch {
        #expect(draw.rect == batch[index].rect)
        #expect(draw.color == batch[index].color)
        index += 1
      }
      #expect(index == batch.count)
    })
  ui.frame(
    build: { _ in },
    present: { batch in
      let isEmpty = batch.isEmpty
      #expect(isEmpty)
      #expect(batch.count == 0)
      for _ in batch { Issue.record("Empty frame retained a previous draw") }
    })
}
