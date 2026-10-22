import Testing

@testable import WaylandBridge

struct X11FrameScheduleTests {
  @Test func idleWindowHasNoRenderTimer() {
    let now = ContinuousClock.now
    var schedule = X11FrameSchedule(now: now)
    #expect(schedule.isReady(now: now))
    schedule.beginFrame()
    schedule.endFrame(continuously: false, now: now)
    #expect(schedule.deadline == nil)
    #expect(!schedule.isReady(now: now.advanced(by: .seconds(20))))
  }

  @Test func redrawsCoalesceAndCallbackRequestsSurviveEndFrame() {
    let now = ContinuousClock.now
    var schedule = X11FrameSchedule(now: now)
    schedule.beginFrame()
    for _ in 0..<20 { schedule.requestRedraw() }
    schedule.endFrame(continuously: false, now: now)
    #expect(schedule.redrawRequested)
    #expect(!schedule.isReady(now: now.advanced(by: .milliseconds(16))))
    #expect(schedule.isReady(now: now.advanced(by: .milliseconds(17))))
    schedule.beginFrame()
    schedule.endFrame(continuously: false, now: now.advanced(by: .milliseconds(17)))
    #expect(schedule.deadline == nil)
  }

  @Test func onlyContinuousFramesScheduleAnotherDeadlineWithoutARequest() {
    let now = ContinuousClock.now
    var schedule = X11FrameSchedule(now: now)
    schedule.beginFrame()
    schedule.endFrame(continuously: true, now: now)
    #expect(schedule.deadline == now.advanced(by: X11FrameSchedule.interval))
    #expect(schedule.isReady(now: now.advanced(by: .seconds(1))))
    schedule.beginFrame()
    schedule.endFrame(continuously: true, now: now.advanced(by: .seconds(1)))
    #expect(!schedule.isReady(now: now.advanced(by: .seconds(1))))
  }

  @Test func clipboardDeadlinesSurviveIdleAndUnmappedWindows() {
    let now = ContinuousClock.now
    let clipboard = now.advanced(by: .milliseconds(10))
    var schedule = X11FrameSchedule(now: now)
    #expect(schedule.waitDeadline(drawable: false, clipboardDeadline: clipboard) == clipboard)
    #expect(schedule.waitDeadline(drawable: false, clipboardDeadline: nil) == nil)
    schedule.beginFrame()
    schedule.endFrame(continuously: false, now: now)
    #expect(schedule.waitDeadline(drawable: true, clipboardDeadline: clipboard) == clipboard)
    #expect(schedule.waitDeadline(drawable: true, clipboardDeadline: nil) == nil)
    schedule.requestRedraw()
    #expect(schedule.waitDeadline(drawable: true, clipboardDeadline: clipboard) == clipboard)
    #expect(schedule.waitDeadline(drawable: false, clipboardDeadline: clipboard) == clipboard)
  }

  @Test func remappingInvalidatesImmediately() {
    let now = ContinuousClock.now
    var schedule = X11FrameSchedule(now: now)
    schedule.beginFrame()
    schedule.endFrame(continuously: false, now: now)
    schedule.mapped(now: now.advanced(by: .seconds(1)))
    #expect(schedule.isReady(now: now.advanced(by: .seconds(1))))
  }
}
