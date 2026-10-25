import Roots
import Testing

@Test func backendConfigurationValidatesBeforeNativeAllocation() throws {
  try BackendWindowConfiguration(title: "Default").validate()
  try BackendWindowConfiguration(
    title: "Offscreen", minimumSize: .init(width: 0, height: 0),
    maxFrames: 1, screenshotPath: "frame.ppm", offscreen: true
  ).validate()
  for configuration: BackendWindowConfiguration in [
    .init(title: "Zero", logicalSize: .init(width: 0, height: 10)),
    .init(title: "Nonfinite", logicalSize: .init(width: .nan, height: 10)),
    .init(title: "Too large", logicalSize: .init(width: 9000, height: 10)),
    .init(title: "Negative frames", maxFrames: -1),
    .init(title: "Unbounded offscreen", offscreen: true),
    .init(title: "Unbounded screenshot", screenshotPath: "frame.ppm"),
    .init(title: "Bad minimum", minimumSize: .init(width: -1, height: 10)),
    .init(title: "Nonfinite minimum", minimumSize: .init(width: 10, height: .infinity)),
    .init(title: "Minimum exceeds initial size", minimumSize: .init(width: 1000, height: 10))
  ] {
    #expect(throws: DesktopBackendError.invalidConfiguration) { try configuration.validate() }
  }
}

@Test func textInputContextUsesUTF8BoundariesAndLeavesNativeLimitsToTheBackend() {
  var state = TextInputState(
    surroundingText: "aé日", cursor: 3, anchor: 1, cursorRectangle: .init(5, 10, 1, 20))
  #expect(state.isValid)
  state.cursor = 2
  #expect(!state.isValid)
  state.cursor = 6
  #expect(state.isValid)
  state.anchor = -1
  #expect(!state.isValid)
  state.anchor = 0
  state.cursorRectangle.z = -1
  #expect(!state.isValid)
  state.cursorRectangle.z = 1
  state.surroundingText = String(repeating: "a", count: 5000)
  #expect(state.isValid)
}
