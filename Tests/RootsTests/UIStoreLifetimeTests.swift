import Testing

@testable import Roots

private final class StoreOwner {
  var ui = UIStore(nodeCapacity: 0, drawCapacity: 0)
}

private final class CallbackCapture {
  var clicks = 0
}

@Test @MainActor func destroyingStoreOwnerReleasesNodeCallbacks() {
  var owner: StoreOwner? = StoreOwner()
  weak var retainedCapture: CallbackCapture?
  do {
    let capture = CallbackCapture()
    retainedCapture = capture
    owner?.ui.frame(
      build: { frame in
        frame.beginRow(in: Region(0, 0, 100, 40))
        frame.button(key: 1, "", extent: 100, onClick: { capture.clicks += 1 })
        frame.end()
      }, present: { _ in })
  }
  #expect(retainedCapture != nil)
  owner = nil
  #expect(retainedCapture == nil)
}
