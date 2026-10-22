// External consumer fixture: no SPI or @testable import is permitted here.
import Roots
import RootsDesktop

struct LinuxDesktopFixture: RootsApp {
  var window: some Window {
    DesktopWindow("X11 fixture", size: .init(320, 240)) { viewport in
      ColumnBlock(in: viewport.bounds) {
        LabelBlock(key: 1, "Public RootsDesktop API")
        ButtonBlock(key: 2, "Close") { DesktopSystem.requestClose() }
      }
    }
    .linuxBackend(.x11)
    .onKey { $0.key == .escape }
    .onStart {}
    .onClose {}
  }
}

@MainActor func publicLinuxBackends() -> [LinuxWindowBackend] {
  [.auto, .wayland, .x11]
}
