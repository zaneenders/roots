# Video playback

```text
FFmpeg (example package only)
  → serial decoder actor
  → immutable ImageFrame + PTS
  → ImageSource.publish
  → Video : Block
  → GLES / Metal textures
```

## Run

Requires the Roots toolchain/system libraries plus **FFmpeg 7+ development headers
and shared libraries** (`libavformat`, `libavcodec`, `libavutil`, `libswscale`) and
`pkg-config`. On macOS, make the installation's `lib/pkgconfig` directory visible
through `PKG_CONFIG_PATH` if necessary. FFmpeg is linked from the system; it is not
downloaded or installed by the package.

From the repository root:

```sh
swift run --package-path Examples/Video VideoPlayer /absolute/path/to/movie.mp4
swift test --package-path Examples/Video
```

| Key | Action |
| --- | --- |
| Space | Pause/resume |
| R | Restart from the beginning |
| Escape | Close |

## Scope

| Supported | Not yet supported |
| --- | --- |
| Local files, codecs supplied by the installed FFmpeg | Audio, network streams, subtitles |
| Progressive SDR, square pixels; visible crop | HDR/wide gamut, interlacing, rotated video |
| Timestamp-based playback, bounded latest-frame handoff | Arbitrary seek controls, display-time prediction |
| Direct planar YUV copy for YUV420P; conversion for other software formats | Hardware decoder / DMA-BUF / Core Video import |
| GPU YUV → RGB; texture reuse; UI draw-command reuse | Zero-copy decoding; prepared GPU geometry reuse |

Unsupported metadata produces a visible error rather than silently displaying
HDR/rotated/interlaced material incorrectly. Missing timestamps fall back to the
stream frame rate; unspecified color matrix uses BT.709 for HD and BT.601 for SD.
The decoder treats unspecified chroma siting as centered. Color conversion follows
Roots' existing SDR encoded-RGB blending, not a full color-managed player.

```text
MainActor                         dedicated serial executor
  Player                         Decoder + FFmpeg ownership
    │ await next() ────────────────► decode + copy owned planes
    ◄────────────────────────────── ImageFrame (Sendable)
    │ sleep until PTS
    └─ source.publish(frame)
         └─ coalesced window wake
             └─ media-only composition (no UI build/layout/paint)
```

The handoff retains one current image and one pending frame; renderers and FFmpeg
have their own bounded caches/reference pools. Paused playback stops requesting
frames. Shutdown cancels pacing and closes the decoder after any current blocking
local-file call completes. There is no guarantee of interrupting slow filesystem I/O.

Tests generate tiny Y4M files at runtime, exercise decoding/draining/reopening and
clock pause/resume, and render a decoded frame through RootsCPU. No downloaded
media, ffmpeg CLI, or compositor is required for these tests.

FFmpeg licensing depends on its build configuration and enabled codecs. Check the
licenses of the libraries you distribute with an application. Roots itself has no
FFmpeg package dependency or linkage.
