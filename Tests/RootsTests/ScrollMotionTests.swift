import Testing

@testable import Roots

private func motionColumn(_ frame: inout UIFrame) {
  for key: UInt64 in 1...2 {
    frame.beginScrollColumn(key: key, in: Region(Float(key - 1) * 120, 0, 100, 100), gap: 0)
    frame.label(key: key + 10, "", extent: 2000)
    frame.end()
  }
}

private func motionOffset(_ ui: borrowing UIStore, key: UInt64 = 1) throws -> Float {
  let value = ui.handle(for: key).flatMap { ui.state(for: $0) }
  return try #require(value).scrollOffset
}

@Test func accelerationKeepsFirstStepsPreciseAndBoostsRapidInputInEitherDirection() throws {
  var ui = UIStore(scrollAcceleration: 1)
  func scroll(_ delta: Float, dt: Float = 0.05, x: Float = 20) {
    ui.frame(
      input: Input(x: x, y: 20, scrollY: delta), dt: dt, build: motionColumn, present: { _ in })
  }
  scroll(30)
  #expect(try motionOffset(ui) == 30)
  scroll(30)
  #expect(try motionOffset(ui) == 90)
  scroll(-10)
  #expect(try motionOffset(ui) == 80)
  scroll(-30)
  #expect(try motionOffset(ui) == 20)
  scroll(30, dt: 0.2)
  #expect(try motionOffset(ui) == 50)
  scroll(30, x: 140)
  #expect(try motionOffset(ui, key: 2) == 30)
  #expect(try motionOffset(ui) == 50)
}

@Test func accelerationCapsFastInputAndStillClampsAtContentBounds() throws {
  var ui = UIStore(scrollAcceleration: 1)
  for _ in 0..<2 {
    ui.frame(input: Input(x: 20, y: 20, scrollY: 100), build: motionColumn, present: { _ in })
  }
  #expect(try motionOffset(ui) == 400)
  ui.frame(input: Input(x: 20, y: 20, scrollY: 1000), build: motionColumn, present: { _ in })
  #expect(try motionOffset(ui) == 1900)
  ui.frame(input: Input(x: 20, y: 20, scrollY: -1000), build: motionColumn, present: { _ in })
  #expect(try motionOffset(ui) == 900)
  ui.frame(input: Input(x: 20, y: 20, scrollY: -1000), build: motionColumn, present: { _ in })
  #expect(try motionOffset(ui) == 0)
}

@Test(arguments: [
  Input(keyEvents: [KeyEvent(.escape)]), Input(pressed: true), Input(x: 300, y: 20, scrollY: 30)
])
func interactionsResetAcceleration(input: Input) throws {
  var ui = UIStore(scrollAcceleration: 1)
  let scroll = Input(x: 20, y: 20, scrollY: 30)
  ui.frame(input: scroll, dt: 0.05, build: motionColumn, present: { _ in })
  ui.frame(input: input, dt: 0.05, build: motionColumn, present: { _ in })
  ui.frame(input: scroll, dt: 0.05, build: motionColumn, present: { _ in })
  #expect(try motionOffset(ui) == 60)
}

@Test func appWideAccelerationAlsoReachesCustomScrollHandlersWithoutMovingTheirParent() throws {
  var ui = UIStore(scrollAcceleration: 1)
  var distances: [Float] = []
  func build(_ frame: inout UIFrame) {
    frame.beginScrollColumn(key: 1, in: Region(0, 0, 100, 100), gap: 0)
    frame.element(key: 2, extent: 2000, onScroll: { distances.append($0.deltaY) }, paint: { _ in })
    frame.end()
  }
  for _ in 0..<2 {
    ui.frame(input: Input(x: 20, y: 20, scrollY: 30), dt: 0.05, build: build, present: { _ in })
  }
  #expect(distances == [30, 60])
  #expect(try motionOffset(ui) == 0)
}

@Test func lowerDecelerationCoastsFurtherAndRemainsIndependentOfFrameRate() throws {
  var standard = UIStore()
  var slow = UIStore(scrollDeceleration: 4)
  var fast = UIStore(scrollDeceleration: 4)
  let input = Input(x: 20, y: 20, scrollY: 10, scrollVelocityY: 160)
  standard.frame(input: input, build: motionColumn, present: { _ in })
  slow.frame(input: input, build: motionColumn, present: { _ in })
  fast.frame(input: input, build: motionColumn, present: { _ in })
  for _ in 0..<6 { slow.frame(dt: 1 / 30, build: motionColumn, present: { _ in }) }
  for _ in 0..<24 { fast.frame(dt: 1 / 120, build: motionColumn, present: { _ in }) }
  #expect(abs(try motionOffset(slow) - motionOffset(fast)) < 0.0001)
  standard.frame(dt: 2, build: motionColumn, present: { _ in })
  slow.frame(dt: 2, build: motionColumn, present: { _ in })
  #expect(abs(try motionOffset(slow) - 48.75) < 0.0001)
  #expect(try motionOffset(slow) > motionOffset(standard))
  let settled = try motionOffset(slow)
  slow.frame(build: motionColumn, present: { _ in })
  #expect(try motionOffset(slow) == settled)
}

@Test func acceleratedGestureScalesALaterReleaseOnItsOriginalViewport() throws {
  var ui = UIStore(scrollAcceleration: 1, scrollDeceleration: 4)
  for _ in 0..<2 {
    ui.frame(
      input: Input(x: 20, y: 20, scrollY: 30), dt: 0.05, build: motionColumn, present: { _ in })
  }
  ui.frame(
    input: Input(x: 140, y: 20, scrollVelocityY: 160), build: motionColumn, present: { _ in })
  #expect(try motionOffset(ui) == 90)
  ui.frame(dt: 2, build: motionColumn, present: { _ in })
  #expect(abs(try motionOffset(ui) - 168.75) < 0.0001)
  #expect(try motionOffset(ui, key: 2) == 0)
}

@Test func accelerationResetsAfterGestureReleaseAndDoesNotScaleProgrammaticScrolling() throws {
  var ui = UIStore(scrollAcceleration: 1)
  let scroll = Input(x: 20, y: 20, scrollY: 30)
  ui.frame(input: scroll, dt: 0.05, build: motionColumn, present: { _ in })
  ui.frame(input: Input(scrollVelocityY: 0), dt: 0.05, build: motionColumn, present: { _ in })
  ui.frame(input: scroll, dt: 0.05, build: motionColumn, present: { _ in })
  #expect(try motionOffset(ui) == 60)
  let handleValue = ui.handle(for: 1)
  let handle = try #require(handleValue)
  ui.frame(
    build: { frame in
      motionColumn(&frame)
      frame.scrollTo(200, in: handle)
    }, present: { _ in })
  #expect(try motionOffset(ui) == 200)
}

@Test func accelerationUsesElapsedTimeAcrossIdleFrames() throws {
  var slow = UIStore(scrollAcceleration: 1)
  var fast = UIStore(scrollAcceleration: 1)
  let scroll = Input(x: 20, y: 20, scrollY: 30)
  slow.frame(input: scroll, dt: 0.05, build: motionColumn, present: { _ in })
  fast.frame(input: scroll, dt: 0.01, build: motionColumn, present: { _ in })
  slow.frame(input: scroll, dt: 0.05, build: motionColumn, present: { _ in })
  for _ in 0..<4 { fast.frame(dt: 0.01, build: motionColumn, present: { _ in }) }
  fast.frame(input: scroll, dt: 0.01, build: motionColumn, present: { _ in })
  #expect(abs(try motionOffset(slow) - motionOffset(fast)) < 0.0001)
}
