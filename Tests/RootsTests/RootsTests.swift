import Testing

@testable import Roots

private func row(_ frame: inout UIFrame, _ keys: [UInt64], action: (() -> Void)? = nil) {
  frame.beginRow(in: Rect(0, 0, 1000, 40), gap: 0)
  for key in keys { frame.button(key: key, "", extent: 80, onClick: action) }
  frame.end()
}

private func requiredHandle(
  _ ui: borrowing UIStore, for key: UInt64, sourceLocation: SourceLocation = #_sourceLocation
) throws -> NodeHandle {
  let handle = ui.handle(for: key)
  return try #require(handle, sourceLocation: sourceLocation)
}

@Test func stateFollowsKeyAcrossReorder() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1, 2]) }, present: { _ in })
  ui.frame(
    input: Input(x: 10, y: 10, released: true), build: { row(&$0, [1, 2]) }, present: { _ in })
  let first = try requiredHandle(ui, for: 1)
  let second = try requiredHandle(ui, for: 2)
  #expect(ui.state(for: first)?.clicks == 1)

  ui.frame(build: { row(&$0, [2, 1]) }, present: { _ in })
  #expect(ui.handle(for: 1) == first)
  #expect(ui.handle(for: 2) == second)
  #expect(ui.state(for: first)?.clicks == 1)
  #expect(ui.state(for: first)?.rect == Rect(80, 0, 80, 40))
  #expect(ui.state(for: first)?.focused == true)
  #expect(ui.state(for: second)?.clicks == 0)
  #expect(ui.state(for: second)?.rect == Rect(0, 0, 80, 40))
  #expect(ui.state(for: second)?.focused == false)
}

@Test(arguments: [UInt64(1), 2]) func removalInvalidatesHandlesAndResetsReusedSlots(
  replacementKey: UInt64
) throws {
  var ui = UIStore(nodeCapacity: 0)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab), KeyEvent(.enter)]), build: { row(&$0, [1]) },
    present: { _ in })
  let old = try requiredHandle(ui, for: 1)
  #expect(ui.state(for: old)?.clicks == 1)

  ui.frame(build: { _ in }, present: { _ in })
  #expect(ui.liveCount == 0)
  #expect(ui.handle(for: 1) == nil)
  #expect(ui.state(for: old) == nil)

  ui.frame(
    input: Input(keyEvents: [KeyEvent(.enter)]), build: { row(&$0, [replacementKey]) },
    present: { _ in })
  let replacement = try requiredHandle(ui, for: replacementKey)
  #expect(ui.slotCount == 1)
  #expect(ui.liveCount == 1)
  #expect(replacement != old)
  #expect(ui.state(for: old) == nil)
  #expect(ui.state(for: replacement)?.key == replacementKey)
  #expect(ui.state(for: replacement)?.clicks == 0)
  #expect(ui.state(for: replacement)?.focused == false)
}

@Test func ownerChecksRejectOtherStores() throws {
  var a = UIStore()
  var b = UIStore()
  a.frame(build: { row(&$0, [1]) }, present: { _ in })
  b.frame(build: { row(&$0, [1]) }, present: { _ in })
  let handle = try requiredHandle(a, for: 1)
  #expect(a.state(for: handle)?.key == 1)
  #expect(b.state(for: handle) == nil)
}

@Test(arguments: [false, true]) func releaseUsesCurrentCallback(clearAction: Bool) throws {
  var ui = UIStore()
  var first = 0
  var second = 0
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1], action: { first += 1 }) },
    present: { _ in })
  ui.frame(
    input: Input(x: 10, y: 10, released: true),
    build: { row(&$0, [1], action: clearAction ? nil : { second += 1 }) }, present: { _ in })
  #expect(first == 0)
  #expect(second == (clearAction ? 0 : 1))
  let handle = try requiredHandle(ui, for: 1)
  #expect(ui.state(for: handle)?.clicks == 1)
}

@Test func freshGeometryPreventsPreviousFrameHit() throws {
  var ui = UIStore()
  var clicks = 0
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true),
    build: { row(&$0, [1, 2], action: { clicks += 1 }) }, present: { _ in }
  )
  ui.frame(
    input: Input(x: 10, y: 10, released: true),
    build: { row(&$0, [2, 1], action: { clicks += 1 }) }, present: { _ in }
  )
  #expect(clicks == 0)
  let first = try requiredHandle(ui, for: 1)
  let second = try requiredHandle(ui, for: 2)
  #expect(ui.state(for: first)?.clicks == 0)
  #expect(ui.state(for: first)?.hovered == false)
  #expect(ui.state(for: second)?.clicks == 0)
  #expect(ui.state(for: second)?.hovered == true)
}

@Test func removedPressCannotActivateReplacement() throws {
  var ui = UIStore()
  var clicks = 0
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1], action: { clicks += 1 }) },
    present: { _ in })
  ui.frame(build: { _ in }, present: { _ in })
  ui.frame(
    input: Input(x: 10, y: 10, released: true), build: { row(&$0, [2], action: { clicks += 1 }) },
    present: { _ in })
  let replacement = try requiredHandle(ui, for: 2)
  #expect(clicks == 0)
  #expect(ui.state(for: replacement)?.clicks == 0)
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true, released: true),
    build: { row(&$0, [2], action: { clicks += 1 }) }, present: { _ in })
  #expect(clicks == 1)
  #expect(ui.state(for: replacement)?.clicks == 1)
}

@Test(arguments: [false, true]) func removedOrClearedActionsReleaseCaptures(removeNode: Bool) {
  final class Token {}
  weak var released: Token?
  var ui = UIStore()
  do {
    let token = Token()
    released = token
    ui.frame(build: { row(&$0, [1], action: { _ = token }) }, present: { _ in })
  }
  #expect(released != nil)
  ui.frame(build: { row(&$0, removeNode ? [] : [1]) }, present: { _ in })
  #expect(released == nil)
}

@Test func keyboardFocusUsesCurrentOrderAndWraps() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab)]), build: { row(&$0, [1, 2, 3]) }, present: { _ in })
  let first = try requiredHandle(ui, for: 1)
  let second = try requiredHandle(ui, for: 2)
  let third = try requiredHandle(ui, for: 3)
  #expect(ui.state(for: first)?.focused == true)

  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab), KeyEvent(.enter)]), build: { row(&$0, [1, 3, 2]) },
    present: { _ in })
  #expect(ui.state(for: first)?.focused == false)
  #expect(ui.state(for: second)?.clicks == 0)
  #expect(ui.state(for: third)?.focused == true)
  #expect(ui.state(for: third)?.clicks == 1)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab)]), build: { row(&$0, [1, 3, 2]) }, present: { _ in })
  #expect(ui.state(for: second)?.focused == true)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab)]), build: { row(&$0, [1, 3, 2]) }, present: { _ in })
  #expect(ui.state(for: first)?.focused == true)
  #expect(ui.state(for: second)?.focused == false)
}

@Test func buttonBecomingLabelCancelsInteraction() throws {
  var ui = UIStore()
  var clicks = 0
  ui.frame(
    input: Input(x: 10, y: 10, pressed: true), build: { row(&$0, [1], action: { clicks += 1 }) },
    present: { _ in })
  let handle = try requiredHandle(ui, for: 1)
  #expect(ui.state(for: handle)?.focused == true)
  ui.frame(
    input: Input(x: 10, y: 10, released: true, keyEvents: [KeyEvent(.tab), KeyEvent(.enter)]),
    build: { frame in
      frame.beginRow(in: Rect(0, 0, 1000, 40))
      frame.label(key: 1, "", extent: 80)
      frame.end()
    }, present: { _ in })
  #expect(ui.handle(for: 1) == handle)
  #expect(ui.state(for: handle)?.focused == false)
  #expect(ui.state(for: handle)?.hovered == false)
  #expect(ui.state(for: handle)?.clicks == 0)
  #expect(clicks == 0)
}

@Test func redeclarationRefreshesDrawConfiguration() {
  var ui = UIStore()
  ui.frame(
    build: { frame in
      frame.beginColumn(in: Rect(10, 20, 30, 40))
      frame.label(key: 1, ".", extent: 16, color: Color(1, 0, 0), font: MonospaceFont(size: 10))
      frame.end()
    },
    present: { draws in
      #expect(draws.count == 2)
      let expected = [Rect(10, 20, 30, 16), Rect(22, 21, 10, 14)]
      guard draws.count == expected.count else { return }
      for i in expected.indices { #expect(draws[i].rect == expected[i]) }
      #expect(draws[0].color == Color(1, 0, 0))
      #expect(draws[0].radius == 7)
      for i in 1..<draws.count {
        #expect(draws[i].color == .text)
        #expect(draws[i].radius == 0)
      }
    })
  ui.frame(
    build: { frame in
      frame.beginRow(in: Rect(50, 60, 100, 20))
      frame.label(key: 1, ".", extent: 40, color: Color(0, 1, 0))
      frame.end()
    },
    present: { draws in
      #expect(draws.count == 2)
      guard draws.count == 2 else { return }
      #expect(draws[0].rect == Rect(50, 60, 40, 20))
      #expect(draws[0].color == Color(0, 1, 0))
      #expect(draws[1].rect == Rect(62, 56, 20, 28))
      #expect(draws[1].glyphUV == FontAtlas.shared.glyphUV("."))
    })
  ui.frame(build: { row(&$0, [1]) }, present: { #expect($0.count == 1) })
}

@Test(arguments: [0, 1, 2, 3]) func boundedDrawOverflowIsReported(capacity: Int) {
  var ui = UIStore(drawCapacity: capacity)
  for _ in 0..<2 {
    ui.frame(
      build: { row(&$0, [1, 2]) },
      present: { draws in
        #expect(draws.count == min(capacity, 2))
        for i in 0..<draws.count {
          #expect(draws[i].rect == Rect(Float(i) * 80, 0, 80, 40))
        }
      })
    #expect(ui.droppedDraws == max(0, 2 - capacity))
  }
  ui.frame(build: { _ in }, present: { #expect($0.count == 0) })
  #expect(ui.droppedDraws == 0)
}

@Test func drawStorageIsReusedAfterOverflow() {
  var storage = UIStorage(nodeCapacity: 0, drawCapacity: 3)
  storage.draws.reserveCapacity(8)
  let capacity = storage.draws.capacity
  #expect(capacity >= 8)
  var address: UInt = 0
  for frame in 0..<2 {
    for i in 0..<4 { storage.emit(DrawRect(Rect(Float(i), 0, 1, 1), .panel)) }
    #expect(storage.draws.count == 3)
    #expect(storage.droppedDraws == 1)
    #expect(storage.draws.capacity == capacity)
    let current = storage.draws.span.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    if frame == 0 {
      address = current
    } else {
      #expect(current == address)
    }
    storage.draws.removeAll()
    storage.droppedDraws = 0
    #expect(storage.draws.count == 0)
    #expect(storage.draws.capacity == capacity)
  }
}

@Test func removedSlotsAreReusedAcrossChurn() {
  var ui = UIStore(nodeCapacity: 0)
  for base in [UInt64(0), 3, 6] {
    ui.frame(
      build: { row(&$0, [base + 1, base + 2, base + 3]) }, present: { #expect($0.count == 3) })
    #expect(ui.slotCount == 3)
    #expect(ui.liveCount == 3)
    ui.frame(build: { _ in }, present: { #expect($0.count == 0) })
    #expect(ui.slotCount == 3)
    #expect(ui.liveCount == 0)
  }
}

@Test func shiftTabWrapsBackwardAndRepeatsAndReleasesDoNotMoveFocus() throws {
  var ui = UIStore()
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab)]), build: { row(&$0, [1, 2, 3]) }, present: { _ in })
  let first = try requiredHandle(ui, for: 1)
  let second = try requiredHandle(ui, for: 2)
  let third = try requiredHandle(ui, for: 3)
  ui.frame(
    input: Input(keyEvents: [
      KeyEvent(.tab, modifiers: .shift), KeyEvent(.tab, phase: .repeated),
      KeyEvent(.tab, phase: .released)
    ]), build: { row(&$0, [1, 2, 3]) }, present: { _ in })
  #expect(ui.state(for: third)?.focused == true)
  ui.frame(
    input: Input(keyEvents: [KeyEvent(.tab, modifiers: .shift)]),
    build: { row(&$0, [1, 2, 3]) }, present: { _ in })
  #expect(ui.state(for: second)?.focused == true)
  #expect(ui.state(for: first)?.focused == false)
}

@Test func buttonsActivateOnFreshEnterOrSpaceButNotShortcutsOrRepeats() throws {
  var ui = UIStore()
  var calls = 0
  ui.frame(
    input: Input(keyEvents: [
      KeyEvent(.tab), KeyEvent(.enter), KeyEvent(.enter, phase: .repeated),
      KeyEvent(.enter, phase: .released),
      KeyEvent(.character(" ")), KeyEvent(.character(" "), phase: .repeated),
      KeyEvent(.enter, modifiers: .control), KeyEvent(.character(" "), modifiers: .alt)
    ]), build: { row(&$0, [1], action: { calls += 1 }) }, present: { _ in })
  let handle = try requiredHandle(ui, for: 1)
  #expect(calls == 2)
  #expect(ui.state(for: handle)?.clicks == 2)
}
