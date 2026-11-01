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
- [Video](Examples/Video): muted local-file playback (requires FFmpeg).
- [Path3D](Examples/Path3D): interactive 3D torus knot.

After following the [setup instructions](#development), run an example from
the repository root:

```sh
swift run --package-path Examples/Markdown MarkdownDemo
swift run --package-path Examples/Tetris Tetris
swift run --package-path Examples/Mandelbrot Mandelbrot
swift run --package-path Examples/Video VideoPlayer /path/to/movie.mp4
swift run --package-path Examples/Path3D Path3D
```

Text measurement, drawing, and paragraphs recognize LF, CRLF, and CR line breaks.
Selectable plain text copies its displayed lines with LF separators.

Desktop windows, Wayland bars, and popups reserve space for 32,768 draw commands
at session startup. Set `drawCapacity` on their initializer for a larger or smaller
workload, including zero. Each frame retains the first valid commands up to that
limit; later commands are dropped and counted in `UIState.droppedDraws`, available
through `onFinishFrame`. Invalid capacities are rejected before the session starts.

The command arena reuses its uniquely owned allocation at capacity and after
overflow. Budget at least `drawCapacity * MemoryLayout<DrawCommand>.stride` bytes
per session, plus allocator rounding (3.75 MiB at the default on arm64, where the
stride is 120 bytes). A popup owns another arena. This guarantee covers command
storage; layout/text storage, referenced image/path resources, application paint
work, and backend/GPU staging have separate allocation and work costs. The low-level
hosting SPI still permits explicitly growable storage with `drawCapacity: nil`.

## Platforms

macOS 27+ and Linux (Hyprland). PRs for other backends welcome.

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

## Build-time font sources

FreeType and libpng are pinned submodules; libpng links system zlib.

```sh
git submodule update --init --recursive
```

## Build and test

Run from the `roots` directory:

```sh
swift test
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
