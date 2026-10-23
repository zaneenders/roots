# Windows backend

`RootsDesktop` selects `WindowsBridge` on Windows. Existing `RootsApp`,
`DesktopWindow`, public `Block` content, observation, frame delegates, keyboard
handlers, and `DesktopSystem` calls work without a platform-specific application
rewrite. This initial backend is software rendered, not a Direct3D port.

## Requirements and build

- Windows 10/11 with a supported Swift 6.4.1 installation (x64 or ARM64).
- Swift 6.4.1 with the matching Microsoft C++ Build Tools and Windows SDK, using
  the [official Swift installation instructions](https://www.swift.org/install/windows/).
- Git with the FreeType and libpng submodules initialized.
- zlib headers and `zlib.lib` for the target architecture. Windows does not provide
  system zlib. For example, an existing [vcpkg](https://learn.microsoft.com/en-us/vcpkg/)
  installation can supply `zlib:x64-windows` (or `zlib:arm64-windows`).

Use a Swift-enabled developer PowerShell with the C++ toolchain initialized.
Point `INCLUDE`, `LIB`, and `PATH` to that zlib installation before invoking Swift;
the font generators need zlib as well as the final application. For example,
after installing `zlib:x64-windows` into your existing vcpkg checkout:

```powershell
$zlib = "C:\vcpkg\installed\x64-windows"
$env:INCLUDE = "$zlib\include;$env:INCLUDE"
$env:LIB = "$zlib\lib;$env:LIB"
$env:PATH = "$zlib\bin;$env:PATH"
git submodule update --init --recursive
swift test
swift run --package-path Examples/WindowsDemo WindowsDemo
```

If your Swift driver does not propagate the header search environment, also pass
`-Xcc -I<zlib-path>\include` and `-Xlinker -LIBPATH:<zlib-path>\lib` to the build
command. Dynamic zlib installations need `zlib1.dll` available at runtime, including
when build-time font generators run. See Microsoft's
[vcpkg manual integration guide](https://learn.microsoft.com/en-us/vcpkg/users/buildsystems/manual-integration).

The example exercises the normal public Roots API: resizable content, observed
state, buttons/focus, keyboard events, Unicode text, clipboard reads/writes, and a
custom canvas. Escape closes it. `--offscreen` writes `windows-demo.ppm` without
opening a window. No Wayland, X11, EGL, OpenGL, or Metal dependency is used on Windows.

## Architecture and supported behavior

- A small C shim owns an HWND and pumps Win32 messages on its own UI thread. Swift
  consumes a bounded, synchronized event queue. No Win32 thread-affinity assumption
  is made about Swift's main actor, and async tasks remain runnable while a window
  is open.
- `RootsCPU` renders the real `UIDrawBatch`, including the normal font and emoji
  atlases. The shim copies RGB pixels to a top-down BGRx DIB for GDI presentation.
  Expose/paint events reuse the retained image. Observation and animation request
  new frames, rather than rendering continuously when idle.
- Resize, minimize/restore, close, task cancellation, and reopening after close
  share a single owned session. Input and drawing buffers are bounded; maximum
  render size is 8192 pixels per dimension, matching `RootsCPU`.
- Left-button capture preserves drag/release outside the window. Pointer leave,
  focus loss, high-resolution wheel detents, key repeat, modifiers, navigation,
  F1–F24, layout-aware shortcut characters, and committed Unicode text are mapped
  into Roots input. Focus loss and event overflow reset held input so keys do not
  remain stuck.
- Clipboard uses `CF_UNICODETEXT`, validates UTF-8/UTF-16, and caps data at 16 MiB.
  Clipboard contention or unavailable text returns `false`/`nil`; the backend
  does not silently overwrite non-text formats during a read.
- `maxFrames`, CPU offscreen rendering, and PPM screenshots are supported.

## Initial limitations

- Layout and rendering use physical client pixels, with `Viewport.scale == 1`.
  The UI thread requests per-monitor DPI awareness without changing process-wide
  settings, but automatic DIP scaling across monitors is not implemented.
- CPU rendering and RGB-to-DIB copying prioritize correctness and portability over
  GPU throughput. Large windows or animated scenes can be expensive. The async
  loop checks events at up to roughly 60 Hz and does not use a vblank scheduler.
- One top-level Roots window is active at a time, matching the other desktop
  backends' current session model. There are no Windows equivalents of Wayland
  layer-shell bars or popups.
- Standard Windows text commits/dead keys and supplementary Unicode scalars are
  accepted. IME composition/preedit/candidate positioning, accessibility, touch,
  pen input, drag-and-drop, and native menus are not implemented. Roots currently
  models text as individual scalar key events, not a separate composition API.
- Clipboard access is tied to an active native window. Offscreen sessions do not
  create an HWND or modify the system clipboard.

## Validation

`WindowsBridgeTests` includes portable keyboard/input/lifecycle-edge tests and
CPU rendering tests, runnable on Linux/macOS as well as Windows. The native host is
only compiled on Windows. To opt in to real-window integration tests on an
interactive Windows desktop:

```powershell
$env:ROOTS_WINDOWS_TEST_WINDOW = "1"
swift test --filter WindowsNativeTests
```

Before treating the backend as Windows-validated, run the native build and tests,
then check the demo at 100%, 150%, and 200% display scale; resize and minimize it;
drag outside the client area; Alt-Tab with held inputs; enter accented characters
and emoji; exercise Ctrl+C/clipboard paste; and close/reopen it. Clipboard tests
are intentionally manual to avoid replacing a developer's existing clipboard.

The initial implementation was developed on Linux with Swift 6.4.1. Portable tests
do not establish that the Microsoft Windows SDK build or native interaction has
passed. An actual Windows environment is required for that final validation.
