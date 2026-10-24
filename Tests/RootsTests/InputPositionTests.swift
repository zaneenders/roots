import Testing

@testable import Roots

@Test func missingMousePositionDoesNotHitNegativeCoordinates() throws {
  var store = UIStore()
  var events: [PointerEvent] = []
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(-20, -20, 40, 40))
    frame.element(key: 1, extent: 40, onPointer: { events.append($0) }, paint: { _ in })
    frame.end()
  }
  #expect(Input().mousePosition == nil)
  store.frame(input: Input(pressed: true, scrollY: 10), build: build, present: { _ in })
  let declared = store.handle(for: 1)
  let handle = try #require(declared)
  #expect(store.state(for: handle)?.hovered == false)
  #expect(events.isEmpty)

  store.frame(
    input: Input(mousePosition: .init(x: -1, y: -1), pressed: true),
    build: build, present: { _ in })
  #expect(store.state(for: handle)?.hovered == true)
  #expect(events.count == 1)
  #expect(events.first?.position == Coordinate(x: 19, y: 19))
}

@Test(arguments: [false, true])
func captureWithoutMousePositionUsesLastPositionOnlyForEndingEvents(focusLost: Bool) {
  var store = UIStore()
  var events: [PointerEvent] = []
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(10, 20, 100, 100))
    frame.element(key: 1, extent: 100, onPointer: { events.append($0) }, paint: { _ in })
    frame.end()
  }
  store.frame(
    input: Input(mousePosition: .init(x: 30, y: 50), pressed: true),
    build: build, present: { _ in })
  store.frame(build: build, present: { _ in })
  #expect(events.map(\.phase) == [.pressed])
  store.frame(input: Input(released: !focusLost, focusLost: focusLost), build: build, present: { _ in })
  #expect(events.map(\.phase) == [.pressed, focusLost ? .cancelled : .released])
  #expect(events.last?.position == Coordinate(x: 20, y: 30))
  store.frame(build: build, present: { _ in })
  #expect(events.count == 2)
}

@Test func absentMousePositionIgnoresScrolling() throws {
  var store = UIStore()
  var events: [ScrollEvent] = []
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(-20, -20, 40, 40))
    frame.element(key: 1, extent: 40, onScroll: { events.append($0) }, paint: { _ in })
    frame.end()
  }
  store.frame(input: Input(scrollY: 12), build: build, present: { _ in })
  #expect(events.isEmpty)
  store.frame(
    input: Input(mousePosition: .init(x: -1, y: -1), scrollY: 12),
    build: build, present: { _ in })
  let event = try #require(events.first)
  #expect(event.position == Coordinate(x: 19, y: 19))
  #expect(event.deltaY == 12)
}

@Test(arguments: [Coordinate(x: .nan, y: 0), Coordinate(x: 0, y: .infinity)])
func nonfiniteMousePositionsAreIgnored(position: Coordinate) {
  var store = UIStore()
  var events: [PointerEvent] = []
  store.frame(
    input: Input(mousePosition: position, pressed: true),
    build: { frame in
      frame.beginColumn(in: Region(-20, -20, 40, 40))
      frame.element(key: 1, extent: 40, onPointer: { events.append($0) }, paint: { context in
        #expect(context.mousePosition == nil)
      })
      frame.end()
    }, present: { _ in })
  #expect(events.isEmpty)
}
