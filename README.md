# roots

⚠️ Work in progress 🤖

A Swift-native UI toolkit.

```swift
import Roots
import RootsDesktop

@MainActor
final class WorkspaceModel {
  var count = 0
}

@main
struct ShapeTree: RootsApp {
  let model = WorkspaceModel()

  var window: some Window {
    DesktopWindow("ShapeTree", size: .init(1180, 820)) { viewport in
      WorkspaceBlock(model: model, bounds: viewport.bounds)
    }
  }
}

struct WorkspaceBlock: Block {
  let model: WorkspaceModel
  let bounds: Rect

  var body: some Block {
    ColumnBlock(in: bounds) {
      LabelBlock(key: 1, "Count: \(model.count)")
      ButtonBlock(key: 2, "Increment") { model.count += 1 }
    }
  }
}
```

## Platforms

macOS 27+ (Metal) and Linux on Wayland or X11 (OpenGL ES 3).

Linux windows automatically prefer an advertised Wayland display or inherited
`WAYLAND_SOCKET`, otherwise `DISPLAY` selects X11. When both are available,
automatic selection can fall back only during startup. An explicit selection
never falls back, and cancellation, application close, or a runtime failure never
starts another backend.

```swift
DesktopWindow("Roots", size: .init(900, 660)) { viewport in
  WorkspaceBlock(model: model, bounds: viewport.bounds)
}
#if os(Linux)
.linuxBackend(.x11) // .auto (default), .wayland, or .x11
#endif
```

`RootsApp`, `Block`, observation-driven redraw, clipboard operations, and borrowed
render batches are shared across the Linux backends. Existing low-level clients
can use `NativeWindow.runAsync(..., backend: .x11)` from `WaylandBridge`; the
module retains its name for source compatibility. Offscreen rendering uses the
same surfaceless EGL path and requires `.auto` rather than an explicit native backend.

### X11 support

- XCB windows with an EGL-matched visual/colormap, resize, expose, map/unmap,
  focus changes, window-manager close, and cancellable event waits.
- Coalesced on-demand redraw, with bounded pacing while animating and no
  unconditional frame timer while idle. EGL is released before suspension.
- XKB keyboard layout/modifiers, detectable and legacy key repeat, captured
  pointer drag/release, and core wheel scrolling.
- Asynchronous UTF-8 `CLIPBOARD`, including ordinary and `INCR` transfers,
  bounded memory, cancellation, and five-second transfer deadlines.

The EGL provider must support `EGL_EXT_platform_xcb` and OpenGL ES 3. Initial X11
buffer scale is 1; fractional scaling, XInput2 smooth scrolling, input-method
composition, and `PRIMARY` selection are not implemented. Clipboard contents are
owned while the application runs; persistent clipboard storage depends on the
desktop's clipboard manager.

`WaylandBar`, native popups, popup grabs, and idle inhibition remain Wayland-only.
The native SwiftWayland transport and dma-buf presenter remain unchanged; this
backend does not restore a libwayland dependency.

## Development

Requires Swift 6.4.1 (`pkg-config` on Linux), plus:

| Platform | System libraries |
| --- | --- |
| macOS | zlib (provided by the SDK) |
| Linux / Wayland and X11 | Development headers and libraries for zlib, EGL, GLES 3, XCB, XCB XKB, xkbcommon, and xkbcommon-x11 |

For Debian/Ubuntu, the Linux packages include `zlib1g-dev`, `libegl1-mesa-dev`,
`libgles2-mesa-dev`, `libxcb1-dev`, `libxcb-xkb-dev`, `libxkbcommon-dev`, and
`libxkbcommon-x11-dev`. Both Linux backends are built into `RootsDesktop`.

```sh
git clone --recurse-submodules https://github.com/zaneenders/roots.git
cd roots
```

### Build-time font sources

FreeType and libpng are pinned submodules; libpng links system zlib.

```sh
git submodule update --init --recursive
```

### Build and test

Run from the `roots` directory:

```sh
swift test
swift test -c release
```

Headless tests cover backend selection, lifecycle validation, keyboard repeat,
focus/pointer state, redraw scheduling, descriptor cancellation, and clipboard
buffer bounds. Existing renderer tests detect available offscreen EGL support.
The native X11 tests are opt-in and require an existing authenticated Xorg or
XWayland session; they never launch a server or change display access controls:

```sh
ROOTS_X11_TESTS=1 swift test --filter X11WindowTests
ROOTS_X11_CLIPBOARD_TESTS=1 swift test --filter X11ClipboardIntegrationTests
```

The clipboard integration tests replace the session's current clipboard contents.
Run them in a disposable test session or after saving anything you need. Native
window-manager and real clipboard interoperability must be validated in such a
session; a successful offscreen test is not evidence of native presentation.

## License

Roots is licensed under [Apache-2.0](LICENSE). Copyright 2026 Zane Enders.
Third-party code and assets retain their respective licenses.
