import CEGLGLES
import DesktopTestSupport
import Testing

extension NativeSessionTests {
  @Test func eglAvailabilityProbeReleasesItsContext() {
    let previousAPI = eglQueryAPI()
    #expect(EGLAvailability.detect())
    #expect(eglQueryAPI() == previousAPI)
    #expect(unsafe eglGetCurrentContext() == nil)
    #expect(unsafe eglGetCurrentDisplay() == nil)
  }
}
