import Testing

@_spi(Hosting) @testable import Roots

@Test func growableDrawsKeepLaterElementsAcrossLargeAndSmallFrames() {
  var ui = UIStore(drawCapacity: nil)
  for count in [32_769, 262_145, 1, 262_145] {
    ui.frame(
      build: { frame in
        frame.beginColumn(in: Region(0, 0, 100, 100), gap: 0)
        frame.canvas(key: 1, extent: 50) { painter in
          for index in 0..<count {
            painter.draw(DrawRect(Region(0, 0, 1, 1), Color(Float(index), 0, 0)))
          }
        }
        frame.label(key: 2, "", extent: 50, color: .accent)
        frame.end()
      },
      present: { draws in
        #expect(draws.count == count + 2)
        guard draws.count == count + 2 else { return }
        #expect(draws[1].rectangle.color == Color(0, 0, 0))
        #expect(draws[count].rectangle.color == Color(Float(count - 1), 0, 0))
        #expect(draws[count + 1].rectangle.region == Region(0, 50, 100, 50))
        #expect(draws[count + 1].rectangle.color == .accent)
      })
    #expect(ui.droppedDraws == 0)
  }
  ui.frame(build: { _ in }, present: { #expect($0.count == 0) })
  #expect(ui.droppedDraws == 0)
}

@Test func growableDrawStorageRetainsExpandedCapacity() {
  var storage = UIStorage(nodeCapacity: 0, drawCapacity: nil)
  let initialCapacity = storage.draws.capacity
  for _ in 0...initialCapacity {
    storage.emit(DrawRect(Region(0, 0, 1, 1), .panel))
  }
  let expandedCapacity = storage.draws.capacity
  #expect(expandedCapacity > initialCapacity)
  #expect(storage.draws.count == initialCapacity + 1)
  #expect(storage.droppedDraws == 0)
  storage.draws.removeAll()
  #expect(storage.draws.capacity == expandedCapacity)
  for _ in 0...initialCapacity {
    storage.emit(DrawRect(Region(0, 0, 1, 1), .panel))
  }
  #expect(storage.draws.capacity == expandedCapacity)
  #expect(storage.draws.count == initialCapacity + 1)
  #expect(storage.droppedDraws == 0)
}

@Test func defaultDrawCapacityRemainsBounded() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginColumn(in: Region(0, 0, 10, 10))
      frame.canvas(key: 1, extent: 10) { painter in
        for _ in 0..<32_768 {
          painter.draw(DrawRect(Region(0, 0, 1, 1), .panel))
        }
      }
      frame.end()
    },
    present: { #expect($0.count == 32_768) })
  #expect(ui.droppedDraws == 1)
}

@MainActor
@Test func invalidDrawsDoNotConsumeCapacityOrDisplaceValidDraws() {
  var host = UIHost(drawCapacity: 2)
  host.frame(
    build: {
      Column(in: Region(0, 0, 100, 100)) {
        Canvas(key: 1, extent: 100) { painter in
          painter.fillRect(Region(0, 0, 10, 10), color: Color(.nan, 0, 0))
          painter.fillRect(Region(0, 0, 10, 10), color: .text, radius: .infinity)
          painter.fillRect(Region(0, 0, 0, 10), color: .text)
          painter.draw(DrawRect(Region(0, 0, 10, 10), .text, clip: Region(.nan, 0, 10, 10)))
          painter.fillRect(Region(0, 0, 10, 10), color: .accent)
        }
      }
    },
    present: { draws in
      #expect(draws.count == 2)
      #expect(draws[1].rectangle.isValid)
      #expect(draws[1].rectangle.color == .accent)
    })
  #expect(host.droppedDraws == 0)
}
