import Observation
import Roots
import Testing

@testable import RootsDesktop

@Test @MainActor func videoFramesReuseUIAndStopObservingOnClose() throws {
  let source = ImageSource()
  var builds = 0
  var prepares = 0
  var redraws = 0
  var presentations = 0
  let viewport = Viewport(size: .init(width: 20, height: 20))
  let runtime = DesktopRuntime(
    content: { viewport in
      builds += 1
      return Column(in: viewport.bounds) { Video(source, key: 1) }
    }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: { redraws += 1 },
    frameCallbacks: .init(prepare: { _, _ in prepares += 1 }))
  runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { _ in presentations += 1 })
  let image = try ImageFrame(
    width: 1, height: 1, format: .rgba8,
    planes: [.init(bytes: [255, 0, 0, 255], bytesPerRow: 4)])
  source.publish(image)
  source.publish(image)
  #expect(redraws == 1)
  runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { _ in presentations += 1 })
  #expect(builds == 1 && prepares == 1 && presentations == 2)
  source.publish(nil)
  runtime.frame(
    input: Input(), viewport: Viewport(size: .init(width: 40, height: 20)), dt: 0,
    present: { _ in presentations += 1 })
  #expect(builds == 2)
  runtime.stop()
  let previous = redraws
  source.publish(image)
  #expect(redraws == previous)
}

@Test @MainActor func videoWakeDoesNotHideObservationOrExplicitInvalidation() throws {
  let model = VideoLabel()
  let source = ImageSource()
  var builds = 0
  let viewport = Viewport(size: .init(width: 20, height: 20))
  let runtime = DesktopRuntime(
    content: { viewport in
      builds += 1
      return Column(in: viewport.bounds) {
        Text(model.value)
        Video(source, key: 1)
      }
    }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {})
  defer { runtime.stop() }
  runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { _ in })
  let image = try ImageFrame(
    width: 1, height: 1, format: .rgba8,
    planes: [.init(bytes: [255, 0, 0, 255], bytesPerRow: 4)])
  source.publish(image)
  model.value = "Changed"
  // Deliberately do not yield to the observation Task before the media frame.
  runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { _ in })
  #expect(builds == 2)
  source.publish(nil)
  DesktopSystem.requestRedraw()
  runtime.frame(input: Input(), viewport: viewport, dt: 0, present: { _ in })
  #expect(builds == 3)
}

@MainActor @Observable private final class VideoLabel {
  var value = "Initial"
}
