import Testing

@testable import Roots

@Test func multilineLabelUsesSeparateTextRows() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginColumn(in: Region(0, 0, 100, 44))
      frame.label(key: 1, "A\nA", extent: 44)
      frame.end()
    },
    present: { draws in
      var first: Region?
      var last: Region?
      for draw in draws where draw.color == .text {
        if first == nil { first = draw.region }
        last = draw.region
      }
      #expect((last?.y ?? 0) - (first?.y ?? 0) >= 20)
      #expect(draws[0].region == Region(0, 0, 100, 44))
    })
}

@Test func applicationReceivesKeysEvenWithoutFocusedControls() {
  var ui = UIStore()
  let events = [KeyEvent(.function(12)), KeyEvent(.symbol(0xFE51), phase: .released)]
  var received: [KeyEvent] = []
  ui.frame(
    input: Input(keyEvents: events),
    onKey: {
      received.append($0)
      return false
    },
    build: { _ in }, present: { _ in })
  #expect(received == events)
}

@Test func elementsRouteRawKeysInFocusOrderAndPaintUpdatedApplicationState() {
  var ui = UIStore()
  var first: [KeyEvent] = []
  var second: [KeyEvent] = []
  var intercepted: [KeyEvent] = []
  let events = [
    KeyEvent(.character("é"), modifiers: .control), KeyEvent(.backspace, phase: .repeated),
    KeyEvent(.escape), KeyEvent(.tab), KeyEvent(.enter),
    KeyEvent(.character("🙂"), phase: .released),
    KeyEvent(.tab), KeyEvent(.left)
  ]
  ui.frame(
    input: Input(keyEvents: events),
    onKey: {
      intercepted.append($0)
      return $0.key == .escape
    },
    build: { frame in
      frame.beginRow(in: Region(10, 20, 200, 40), gap: 0)
      let handle = frame.element(
        key: 1, extent: 100, onKey: { first.append($0) },
        paint: { painter in
          #expect(first == [events[0], events[1], events[7]])
          let focused = painter.focused
          #expect(focused)
          #expect(painter.region == Region(10, 20, 100, 40))
          painter.draw(DrawRect(Region(10, 20, Float(first.count), 1), .text))
        })
      frame.element(
        key: 2, extent: 100, onKey: { second.append($0) },
        paint: { painter in
          #expect(second == [events[4], events[5]])
          let focused = painter.focused
          #expect(!focused)
          #expect(painter.region == Region(110, 20, 100, 40))
        })
      frame.focus(handle)
      frame.end()
    },
    present: { draws in
      var foundUpdatedDraw = false
      for draw in draws where draw.color == .text {
        #expect(draw.region == Region(10, 20, 3, 1))
        foundUpdatedDraw = true
      }
      #expect(foundUpdatedDraw)
    })
  #expect(intercepted == events)
  #expect(first == [events[0], events[1], events[7]])
  #expect(second == [events[4], events[5]])
}

@Test func elementsRefreshKeyAndPaintCallbacksAndCanClearKeyHandling() {
  var ui = UIStore()
  var oldKeys = 0
  var newKeys = 0
  var oldPaints = 0
  var newPaints = 0
  ui.frame(
    build: { frame in
      frame.beginColumn(in: Region(0, 0, 100, 40))
      let handle = frame.element(
        key: 1, onKey: { _ in oldKeys += 1 }, paint: { _ in oldPaints += 1 })
      frame.focus(handle)
      frame.end()
    }, present: { _ in })
  let original = ui.handle(for: 1)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.enter)]),
    build: { frame in
      frame.beginColumn(in: Region(20, 30, 200, 50))
      frame.element(
        key: 1, extent: 50, onKey: { _ in newKeys += 1 },
        paint: { painter in
          newPaints += 1
          #expect(newKeys == 1)
          #expect(painter.region == Region(20, 30, 200, 50))
          let focused = painter.focused
          #expect(focused)
        })
      frame.end()
    }, present: { _ in })
  #expect(ui.handle(for: 1) == original)
  #expect(oldKeys == 0 && newKeys == 1)
  #expect(oldPaints == 1 && newPaints == 1)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.enter)]),
    build: { frame in
      frame.beginColumn(in: Region(0, 0, 100, 40))
      frame.element(key: 1, paint: { _ in })
      frame.end()
    }, present: { _ in })
  #expect(oldKeys == 0 && newKeys == 1)
  #expect(oldPaints == 1 && newPaints == 1)
}

@Test(arguments: [false, true]) func removedOrNoninteractiveElementsReleaseBothCallbacks(
  remove: Bool
) {
  final class Token {}
  var ui = UIStore()
  weak var releasedKey: Token?
  weak var releasedPaint: Token?
  do {
    let keyToken = Token()
    let paintToken = Token()
    releasedKey = keyToken
    releasedPaint = paintToken
    ui.frame(
      build: { frame in
        frame.beginColumn(in: Region(0, 0, 100, 40))
        let handle = frame.element(
          key: 1, onKey: { _ in _ = keyToken }, paint: { _ in _ = paintToken })
        frame.focus(handle)
        frame.end()
      }, present: { _ in })
  }
  #expect(releasedKey != nil && releasedPaint != nil)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.enter)]),
    build: { frame in
      if !remove {
        frame.beginColumn(in: Region(0, 0, 100, 40))
        frame.label(key: 1, "")
        frame.end()
      }
    }, present: { _ in })
  #expect(releasedKey == nil && releasedPaint == nil)
  if let handle = ui.handle(for: 1) { #expect(ui.state(for: handle)?.focused == false) }
}

@Test func elementContentIntersectsBoundsViewportAndExplicitDrawClips() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginScrollColumn(key: 100, in: Region(10, 20, 100, 60), gap: 10)
      frame.label(key: 1, "", extent: 40)
      frame.element(
        key: 2, extent: 40,
        paint: { painter in
          #expect(painter.region == Region(10, 70, 100, 40))
          #expect(painter.clip == Region(10, 70, 100, 10))
          painter.draw(DrawRect(Region(0, 0, 200, 200), .accent))
          painter.draw(DrawRect(Region(0, 0, 200, 200), .accent, clip: Region(20, 70, 30, 20)))
          painter.draw(DrawRect(Region(0, 0, 1, 1), .accent))
          painter.draw(DrawRect(Region(0, 0, 200, 200), .accent, clip: Region(0, 0, 1, 1)))
          painter.drawText("A", x: 10, y: 70, size: 10)
        })
      frame.end()
    },
    present: { draws in
      var shapes = 0
      var glyphs = 0
      for draw in draws {
        if draw.color == .accent {
          #expect(draw.region == Region(0, 0, 200, 200))
          #expect(draw.clip == (shapes == 0 ? Region(10, 70, 100, 10) : Region(20, 70, 30, 10)))
          shapes += 1
        }
        if draw.color == .text {
          #expect(draw.clip == Region(10, 70, 100, 10))
          #expect(!draw.region.intersection(Region(10, 70, 100, 10)).isEmpty)
          glyphs += 1
        }
      }
      #expect(shapes == 2 && glyphs > 0)
    })
  #expect(ui.droppedDraws == 0)
}

@Test(arguments: [0, 1, 2, 3]) func customElementDrawingUsesTheStoreBudget(capacity: Int) {
  var ui = UIStore(drawCapacity: capacity)
  ui.frame(
    build: { frame in
      frame.beginColumn(in: Region(0, 0, 100, 40))
      frame.element(
        key: 1,
        paint: { painter in
          painter.draw(DrawRect(Region(-10, -10, 1, 1), .text))
          for i in 0..<4 { painter.draw(DrawRect(Region(Float(i), 0, 1, 1), .text)) }
        })
      frame.end()
    },
    present: { draws in
      #expect(draws.count == capacity)
      for i in 0..<draws.count where i > 0 { #expect(draws[i].clip == Region(0, 0, 100, 44)) }
    })
  #expect(ui.droppedDraws == 5 - capacity)
}

@Test func elementScrollUsesLocalCoordinatesWithoutChangingFocusAndRunsBeforeKeysAndPaint() throws {
  var ui = UIStore()
  var received: [ScrollEvent] = []
  var phases: [String] = []
  var handlesScroll = true
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: Region(10, 20, 100, 60), gap: 0)
    let focused = frame.element(
      key: 1, extent: 30, onKey: { _ in phases.append("key") }, paint: { _ in })
    frame.element(
      key: 2, extent: 90,
      onKey: { _ in phases.append("key") },
      onScroll: handlesScroll
        ? {
          received.append($0)
          phases.append("scroll")
        } : nil,
      paint: { _ in phases.append("paint") })
    frame.focus(focused)
    frame.end()
  }
  ui.frame(input: Input(mousePosition: .init(x: 30, y: 55), scrollY: 12.5), build: build, present: { _ in })
  #expect(received.count == 1)
  #expect(received.first?.deltaY == 12.5)
  #expect(received.first?.region == Region(10, 50, 100, 90))
  #expect(received.first?.position.x == 20 && received.first?.position.y == 5)
  #expect(phases == ["scroll", "paint"])
  let viewportHandle = ui.handle(for: 100)
  let viewport = try #require(viewportHandle)
  let firstHandle = ui.handle(for: 1)
  let first = try #require(firstHandle)
  let secondHandle = ui.handle(for: 2)
  let second = try #require(secondHandle)
  #expect(ui.state(for: viewport)?.scrollOffset == 0)
  #expect(ui.state(for: first)?.focused == true)
  #expect(ui.state(for: second)?.focused == false)
  for input in [
    Input(mousePosition: .init(x: 30, y: 90), scrollY: 10),
    Input(mousePosition: .init(x: 30, y: 55), scrollY: .nan),
    Input(mousePosition: .init(x: 30, y: 55), scrollY: .infinity),
    Input(mousePosition: .init(x: 30, y: 55), scrollX: 10)
  ] {
    ui.frame(input: input, build: build, present: { _ in })
  }
  #expect(received.count == 1)
  phases = []
  ui.frame(
    input: Input(mousePosition: .init(x: 30, y: 55), scrollY: 10, keyEvents: [KeyEvent(.down)]),
    build: build, present: { _ in })
  #expect(phases == ["scroll", "key", "paint"])
  handlesScroll = false
  ui.frame(input: Input(mousePosition: .init(x: 30, y: 55), scrollY: 10), build: build, present: { _ in })
  #expect(received.count == 2)
  #expect(ui.state(for: viewport)?.scrollOffset == 10)
}

@Test func elementScrollStopsParentMomentumInsteadOfFlingingTheParent() throws {
  var ui = UIStore()
  var distances: [Float] = []
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 100, in: Region(0, 0, 100, 100), gap: 0)
    frame.element(key: 1, extent: 40, onScroll: { distances.append($0.deltaY) }, paint: { _ in })
    frame.label(key: 2, "", extent: 200)
    frame.end()
  }
  ui.frame(
    input: Input(mousePosition: .init(x: 20, y: 60), scrollY: 10, scrollVelocityY: 160),
    build: build, present: { _ in })
  let viewportHandle = ui.handle(for: 100)
  let viewport = try #require(viewportHandle)
  #expect(ui.state(for: viewport)?.scrollOffset == 10)
  ui.frame(
    input: Input(mousePosition: .init(x: 20, y: 10), scrollY: 5, scrollVelocityY: 160),
    build: build, present: { _ in })
  ui.frame(build: build, present: { _ in })
  #expect(distances == [5])
  #expect(ui.state(for: viewport)?.scrollOffset == 10)
}

@Test func pointerOnlyElementsCaptureWithoutFocusOrHighlighting() throws {
  var ui = UIStore()
  var pointers: [PointerEvent] = []
  var scrolls = 0
  var keys = 0
  let overlay = Region(0, 0, 300, 200)
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 220, 100, 32))
    frame.button(key: 1, "First", extent: 32)
    frame.end()
    frame.beginColumn(in: overlay)
    let handle = frame.element(
      key: 2, extent: overlay.height, color: Color(0, 0, 0, 0.5), onKey: { _ in keys += 1 },
      onPointer: { pointers.append($0) }, onScroll: { _ in scrolls += 1 }, focusable: false,
      paint: { painter in
        let focused = painter.focused
        #expect(!focused)
      })
    frame.focus(handle)
    frame.end()
    frame.beginColumn(in: Region(110, 220, 100, 32))
    frame.button(key: 3, "Last", extent: 32)
    frame.end()
  }
  func present(_ draws: borrowing UIDrawBatch) {
    for draw in draws {
      if draw.color == .accent { #expect(draw.region.height < overlay.height) }
      if draw.region == overlay { #expect(draw.color == Color(0, 0, 0, 0.5)) }
    }
  }
  ui.frame(
    input: Input(mousePosition: .init(x: 20, y: 20), pressed: true, keyEvents: [KeyEvent(.enter)]),
    build: build, present: present)
  let overlayHandle = ui.handle(for: 2)
  let requiredOverlay = try #require(overlayHandle)
  #expect(ui.state(for: requiredOverlay)?.focused == false)
  ui.frame(input: Input(mousePosition: .init(x: 400, y: 210), released: true), build: build, present: present)
  #expect(pointers.map(\.phase) == [.pressed, .released])
  ui.frame(
    input: Input(mousePosition: .init(x: 20, y: 20), scrollY: 10, keyEvents: [KeyEvent(.tab)]), build: build,
    present: present)
  let firstHandle = ui.handle(for: 1)
  let requiredFirst = try #require(firstHandle)
  #expect(ui.state(for: requiredFirst)?.focused == true)
  ui.frame(input: Input(keyEvents: [KeyEvent(.tab)]), build: build, present: present)
  let lastHandle = ui.handle(for: 3)
  let requiredLast = try #require(lastHandle)
  #expect(ui.state(for: requiredLast)?.focused == true)
  #expect(scrolls == 1)
  #expect(keys == 0)
}

@Test func changingAnElementToPointerOnlyClearsExistingFocus() throws {
  var ui = UIStore()
  var focusable = true
  var keys = 0
  func build(_ frame: inout UIFrame) {
    frame.beginColumn(in: Region(0, 0, 100, 40))
    let handle = frame.element(
      key: 1, onKey: { _ in keys += 1 }, focusable: focusable, paint: { _ in })
    if focusable { frame.focus(handle) }
    frame.end()
  }
  ui.frame(build: build, present: { _ in })
  let firstHandle = ui.handle(for: 1)
  let requiredFirst = try #require(firstHandle)
  #expect(ui.state(for: requiredFirst)?.focused == true)
  focusable = false
  ui.frame(input: Input(keyEvents: [KeyEvent(.enter)]), build: build, present: { _ in })
  #expect(ui.state(for: requiredFirst)?.focused == false)
  #expect(keys == 0)
}
