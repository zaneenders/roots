# roots

⚠️ Work in progress 🤖

A Swift-native UI toolkit.

## Examples

Explore the runnable apps in [Examples](Examples):

- [Markdown](Examples/Markdown): styled paragraphs, selectable text, scrolling,
  and clipboard support.
- [Mandelbrot](Examples/Mandelbrot): a cached fractal image, custom canvas painting,
  and aspect-ratio-preserving resizing.
- [Tetris](Examples/Tetris): declarative blocks, keyboard input, observation,
  and frame-driven animation.
- [Video](Examples/Video): muted local-file playback, GPU YUV conversion, and
  pause/restart. FFmpeg is a dependency of this example only.

After following the [setup instructions](#development), run an example from
the repository root:

```sh
swift run --package-path Examples/Markdown MarkdownDemo
swift run --package-path Examples/Tetris Tetris
swift run --package-path Examples/Mandelbrot Mandelbrot
```

Text measurement, drawing, and paragraphs recognize LF, CRLF, and CR line breaks.
Selectable plain text copies its displayed lines with LF separators.

## Platforms

macOS 27+ and Linux (Hyprland). PRs for other backends welcome.

## Desktop backends

`DesktopWindow` uses the bundled `MacOSBackend` or `WaylandBackend` by default.
Pass `backend:` to select another implementation; application content and frame
callbacks stay the same:

```swift
DesktopWindow("My app", backend: MyBackend()) { viewport in
  Column(in: viewport.bounds) { Text("Hello") }
}
```

Implement the public `DesktopBackend` protocol in `Roots`. Its `run` method owns
native window creation, event dispatch, frame pacing, presentation, cancellation,
and cleanup. Each frame supplies `BackendFrame` (normalized `Input`, logical size,
fractional scale, and time in seconds) plus a synchronous render closure accepting
`borrowing UIDrawBatch`. Consume or encode the draws before the closure returns;
the batch and render closure cannot escape. Public draw iteration and font/emoji
atlases are available to renderers in other packages.

`DesktopSurface` provides redraw and close commands. Add `DesktopCursorSurface`
or `DesktopTextInputSurface` when supported; both report temporary unavailability
with `false`. Cursor requests use `Roots.CursorShape`, and text-input context uses
`Roots.TextInputState` with UTF-8 byte offsets. Explicit cursor overrides survive
automatic hit testing until cleared with `DesktopSystem.setCursor(nil)` or the
surface closes. `DesktopSystem` routes services to the active backend, and the
runtime captures that backend for observation-driven redraws and copying.

Both bundled backends support cursor selection, auxiliary mouse buttons, and
wheel metadata. macOS currently has no input-method session implementation;
`DesktopSystem.setTextInput` returns `false` there. Wayland popups and layer-shell
bars remain native extensions, with independent popup redraw and cursor state.
The desktop host currently runs one window session at a time. Offscreen rendering
requires a positive frame limit; a backend without offscreen or screenshot support
should throw `DesktopBackendError.unsupportedFeature` for those requests.

## Images and video

```swift
let source = ImageSource() // MainActor; the decoder remains application-owned.

DesktopWindow("Video") { viewport in
  Column(in: viewport.bounds) { Video(source, key: 1) }
}

// Publish immutable RGBA8, YUV420P, or NV12 frames from your producer.
// source.publish(frame)
```

`Video` supports fit/fill/stretch; `UIPaintContext.drawImage` adds custom placement,
clipping, and opacity. Desktop media updates reuse draw commands without rebuilding
unchanged UI. The current path uploads CPU planes to reusable GPU textures; native
decoder-buffer imports and audio playback are not implemented.

**Backend migration:** `UIDrawBatch` now yields `DrawCommand`. Switch over
`.rectangle(DrawRect)` and `.image(ImageDraw)`; `ImageDraw.resolve()` on MainActor
returns an owned frame snapshot. See the [FFmpeg playback example](Examples/Video)
for a separate package that supplies frames without adding codecs to Roots.

## Design notes

- [Video display proposal](Docs/Video.md): GPU-backed image sources, frame ownership,
  playback timing, implemented CPU-frame support, and future native imports.

## Development

Requires Swift 6.4.1 (`pkg-config` on Linux), plus:

| Platform | System libraries |
| --- | --- |
| macOS | zlib (provided by the SDK) |
| Linux / Wayland | Development headers and libraries for zlib, xkbcommon, EGL, GLES 3, GBM, and libdrm |

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
```

`swift test` also compiles the external-client fixtures in
`Tests/CompilerFixtureTests/Inputs`. Valid clients must compile, and `Reject*`
fixtures must fail with their `// expected-error:` diagnostics. These checks run
full compilation so ownership and lifetime errors are checked beyond type checking.
Use the same Swift toolchain for building and running tests: the fixture runner
uses `SWIFT_EXEC` when set, otherwise `swiftc` from `PATH`. Each compiler invocation
has a 30-second timeout; compiler crashes and missing modules fail the test.

To run only the compiler fixtures:

```sh
swift test --filter compilerFixturesEnforceThePublicAPIAndLifetimes
```

### Wayland compositor tests

```sh
swift Scripts/test-compositors.swift  # current Wayland session
ROOTS_REQUIRE_PRESENTATION=1 swift Scripts/test-compositors.swift  # require GPU presentation
```

See [compositor testing](Tests/COMPOSITOR_TESTS.md) for coverage, prerequisites,
and retained logs. The runner requires a running compositor; ordinary
`swift test` still skips unavailable compositor tests.

## License

Roots is licensed under [Apache-2.0](LICENSE). Copyright 2026 Zane Enders.
Third-party code and assets retain their respective licenses.
