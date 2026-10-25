# Video display: proposed architecture

Status: the first CPU-frame/upload slice is implemented; the sections below retain
its broader design proposal. Proposed signatures are not necessarily the shipped API.

## Implemented slice

```text
Examples/Video (separate package)
  CVideoDecoder → Decoder actor (serial executor) → Player (PTS clock)
                                                      │
Roots                                                 ▼
  ImageFrame (immutable, Sendable) → ImageSource.publish → Video : Block
                                      │                     │
                                      └─ media wake ────────┤
                                                            ▼
                         UIDrawBatch<DrawCommand> → CPU / GLES / Metal
```

- `ImageFrame`: RGBA8, YUV420P, NV12; row strides, BT.601/709, full/limited range,
  centered/left/top-left chroma. SDR output follows the existing renderer's encoded
  RGB blending convention; this is not a linear-light/HDR color pipeline.
- `Video(source, key:contentMode:)` and `UIPaintContext.drawImage`: fit/fill/stretch,
  opacity, nested paint origins and clipping.
- `UIDrawBatch` now iterates `DrawCommand`; external backends must switch over
  `.rectangle` and `.image`. `ImageDraw.resolve()` returns an owned frame snapshot.
- `RootsDesktop` retains owned commands and subscribes to visible image sources.
  Media-only updates skip build/layout/paint and application frame callbacks;
  input, animation, observation, viewport changes, and explicit
  `DesktopSystem.requestRedraw()` still rebuild. Direct backend redraw commands
  cannot distinguish an application-state change from a media wake; use the desktop
  API for explicit UI invalidation.
- GLES reuses textures and uploads only changed frames. GL commands order reuse;
  Metal uses per-submission-slot textures so uploads do not overwrite in-flight data.
  These are CPU-upload paths, not native decoder-buffer imports.
- The [Video example](../Examples/Video) alone links FFmpeg. It decodes local files,
  preserves timestamps, supports pause/restart, and bounds the handoff to a current
  image plus one pending decoded frame (apart from decoder/GPU pools).

Still deferred: DMA-BUF/Core Video imports, prepared GPU geometry caching,
presentation-time prediction, audio, arbitrary seeking, HDR, native overlays.
Linux rendering and example tests are exercised; Metal changes require macOS CI.

---

## Recommendation

```text
Video : Block                    Optional playback adapter
    │                            AVFoundation / FFmpeg
    ▼                                     │
ImageDraw(source: ImageSourceID)            ▼
    │                            bounded, timestamped frames
    └──────────────────┬──────────────────┘
                       ▼
             Metal / GLES composition
                       │
           existing window presentation
```

- Add image sources, not a rectangle-per-pixel video widget.
- Preserve native decoder buffers; sample YUV planes on the GPU where supported.
- Keep frame owners alive until GPU completion, independently of draw-batch borrows.
- Give media-only redraws a path that reuses UI geometry.
- Keep decoding optional. A camera, screen capture, or external player should be
  able to supply frames without depending on a Roots media player.
- Keep Metal and GLES initially. Video does not, by itself, justify a Vulkan rewrite.

## Current call stack and gaps

```text
DesktopBackend.run
  └─ BackendFrameHandler(BackendFrame, render)
      └─ DesktopRuntime.frame
          └─ UIHost.trackedFrame
              └─ UIStore.frame
                  ├─ build
                  ├─ resolveLayouts
                  ├─ finish(input, animations)
                  ├─ paint
                  └─ present(UIDrawBatch : Span<DrawRect>)
                      ├─ MetalRenderFrame.render → MetalFrameState.render
                      ├─ RenderFrame.render → NativeRenderer.render
                      └─ CPURenderer.render
```

The native host surrounds this callback with submission/presentation:
`MetalRenderer.submit` encodes the collected runs and commits a command buffer;
Wayland ends the render frame and presents through `DMABufPresenter`.

| Code | Existing behavior | Video gap |
| --- | --- | --- |
| [`DrawRect`](../Sources/Roots/Drawing/DrawRect.swift), [`UIDrawBatch`](../Sources/Roots/UI/UIDrawBatch.swift) | Rectangles, atlas glyphs, polylines; borrowed batch | No general texture/image command or resource ownership |
| [`MandelbrotImage`](../Examples/Mandelbrot/Sources/Mandelbrot/MandelbrotImage.swift) | Cached horizontal runs of colored rectangles | Not an image-upload path; unsuitable for decoded video |
| [`UIStore.frame`](../Sources/Roots/UI/UIStore.swift) | Build, layout, paint on every frame; clear draws afterward | Video updates rebuild unrelated UI |
| [`DesktopBackend`](../Sources/Roots/Hosting/DesktopBackend.swift) | Immediate redraw request; monotonic frame time | No media deadline, predicted display time, or presentation feedback |
| [`MetalRenderer`](../Sources/MacOSBridge/Rendering/MetalRenderer.swift) | Three submission slots; asynchronous completion | Slots need to retain imported frame resources |
| [`MacOSWindowHost`](../Sources/MacOSBridge/Window/MacOSWindowHost.swift) | `MTKView`, preferred 60 fps, pause when idle | Negotiate display cadence rather than assume 60 Hz |
| [`NativeRenderer`](../Sources/WaylandBridge/Rendering/NativeRenderer.swift) | GLES 3, font/emoji textures, ordered batching | Image/YUV programs, decoder-buffer import, source-read fences |
| [`DMABufPresenter`](../Sources/WaylandBridge/Rendering/DMABufPresenter.swift) | Three output targets, compositor feedback/release | Output allocation is not a decoded-frame input API |
| [`DMABufSynchronization`](../Sources/WaylandBridge/Rendering/DMABufSynchronization.swift) | Publishes output write fences; `glFinish()` fallback | Decoder acquire synchronization and source release are separate |
| [`CPURenderer`](../Sources/RootsCPU/CPURenderer.swift) | CPU reference rasterizer | CPU image/YUV sampling for deterministic tests |

## 1. Rendering API: image sources separate from commands

Retain `DrawRect` for existing shapes and glyphs. Change batch elements rather than
adding more unrelated optional fields to every rectangle.

```swift
// Proposed types, not declarations currently available in Roots.
struct ImageSourceID: Hashable, Sendable {
  let session: UInt64
  let slot: UInt32
  let generation: UInt32
}

enum DrawCommand: Sendable {
  case rectangle(DrawRect) // Includes the existing polyline representation.
  case image(ImageDraw)
}

struct ImageDraw: Sendable {
  let source: ImageSourceID
  let destination: Region
  let sourceUV: Region
  let clip: Region?
  let opacity: Float
}

// UIDrawBatch stays ~Copyable, ~Escapable; its span becomes Span<DrawCommand>.
// UIPaintContext.drawImage(_:in:sourceUV:opacity:) emits .image.
// Video(player, contentMode: .fit) emits the same command as any other image source.
```

```text
Retained scene                          Source registry (session-owned)
  image(source: A, geometry: …) ────────► A → current frame + bounded ready queue
  rectangles / text                     B → immutable still image

Backend submit
  1. Select each source once for the target presentation time.
  2. Acquire owned leases for the selected frames.
  3. Encode commands in painter order.
  4. Keep leases in the in-flight submission until GPU completion.
```

| Contract | Rule |
| --- | --- |
| Source identity | Stable while frames change; reject wrong-session/stale-generation IDs |
| Registration | Session registry owns a source; explicit registration lifetime, no global GPU registry |
| Resource access | Public capability/source contract in `Roots`; native import adapters in platform modules, not package-only access |
| Native types | Keep `MTLTexture`, EGL objects, and decoder pointers out of `DrawCommand` |
| Custom backends | Negotiate accepted frame storage/formats; CPU fallback or explicit unsupported error |
| Frame metadata | Coded extent, visible crop, sample aspect ratio, orientation, plane strides, color information, PTS/duration, seek generation |
| Source changes | Resolution/aspect changes invalidate geometry; ordinary frame changes invalidate composition only |
| Batching | Flush on material/source/clip changes; do not sort translucent draws across painter order |
| Sampling | Clamp-to-edge, explicit orientation/UV mapping; no per-frame mipmap generation |
| Failure | Retain last valid frame or show a placeholder with a reported error; never silently reinterpret unsupported storage |

The public source/import contract needs a small external-client prototype before
freezing signatures. It must allow an owned frame lease to outlive the synchronous
render closure without exposing borrowed native pointers as persistent resources.

## 2. Ownership: CPU borrowing is not GPU completion

```text
Decoder-owned frame allocation
  ├─ decode/reorder pool reference
  ├─ bounded ready queue reference
  ├─ current displayed frame reference (also retained while paused)
  └─ submission lease(s)
        ├─ native backing owner: CVPixelBuffer / AVFrame / CPU plane storage
        ├─ imported texture views: CVMetalTexture / EGLImage + texture
        └─ GPU completion → release lease

Last consumer releases → decoder may recycle allocation
```

| Type/boundary | Ownership strategy |
| --- | --- |
| Native allocation / FD owner | `~Copyable` wrapper with explicit cleanup |
| Submission lease | Owned, escapable `~Copyable` value; retains a reference to backing allocation |
| Encode-time view | `~Copyable, ~Escapable`, `Ref` / `MutableRef`, `@_lifetime` |
| Decode state | Dedicated serial worker/executor; never blocking decode on `MainActor` |
| UI and graphics resources | Actor-isolated; GLES calls on the owning current context |
| Worker handoff | Compiler-checked `Sendable` values or proven isolated ownership transfer; no assumed sendability of imported SDK pointers |
| C callbacks | Small `@c` entry points where needed; no capture of frame-scoped borrows |
| Synchronous mailbox, if required | `Synchronization.Mutex`; never hold it during decode, GPU calls, or `await` |

An actor serializes access but does not automatically move blocking codec work off
the UI thread or turn a foreign buffer into a safely transferable value.

### Platform release points

```text
Metal: command-buffer completion
         → release slot's CVPixelBuffer + CVMetalTexture owners

GLES: fence after the last source texture read
         → observe completion without blocking MainActor
         → release AVFrame/native owner and imported views

Wayland wl_buffer.release
         → output target is reusable
         ≠ proof of decoder input ownership or acquire synchronization
```

Acquire synchronization must also prove decoding has finished before GPU sampling.
An exported DMA-BUF FD alone is not that proof. If a decoder requires a blocking
wait (for example a VA surface synchronization), do it on its worker. Preserve a
correct fallback when fence interoperability is unavailable; report the slow path.

Import-cache keys need allocation identity **and generation**, device, format,
modifier, and dimensions—not a recyclable FD integer or pointer address alone.
Bound the cache to live pool allocations. Closing, seeking, format changes, and
GPU/device replacement must invalidate stale entries and drain in-flight leases.

## 3. Platform paths

### macOS: AVFoundation → Core Video → Metal

```text
AVPlayer                              owns playback/audio clock
  └─ AVPlayerItemVideoOutput
      └─ itemTime(forHostTime: predictedDisplayHostTime)
          ├─ hasNewPixelBuffer(forItemTime:)
          └─ copyPixelBuffer(forItemTime:itemTimeForDisplay:)
              └─ CVPixelBuffer (request Metal-compatible storage)
                  └─ CVMetalTextureCacheCreateTextureFromImage
                      ├─ NV12 Y  → r8Unorm
                      ├─ NV12 UV → rg8Unorm
                      └─ image fragment shader → existing render target
```

Use the renderer's `MTLDevice` for the texture cache. Prefer native bi-planar
output where supported; inspect the actual returned format. Retain both pixel
buffer and Core Video texture wrappers through command completion. `copyPixelBuffer`
returns an owned buffer reference; it does not require a CPU pixel-array copy.

Use AVFoundation's host-time mapping, not Roots' session-relative `timeSeconds`
as though it were the platform host clock. Request output-change notifications
when idle. Direct VideoToolbox integration is a later option for custom packet or
live-stream decoding, not a prerequisite for ordinary file playback.

### Linux: optional FFmpeg adapter → DMA-BUF → EGL/GLES

```text
FFmpeg demux/decode worker
  ├─ compatible hardware decoder + export/map support
  │   └─ AV_PIX_FMT_DRM_PRIME / AVDRMFrameDescriptor
  │       ├─ objects: FD, allocation size, modifier
  │       ├─ layers: DRM fourcc
  │       └─ planes: object index, offset, pitch
  │           └─ EGL_LINUX_DMA_BUF_EXT → EGLImage → sampled texture(s)
  │
  └─ software decoded frame / unsupported hardware import
      └─ bounded CPU planes → reusable GPU upload slots → same image draw
```

| Import decision | Requirement |
| --- | --- |
| Hardware choice | Negotiate codec/device/export support; VA-API is one adapter, not a universal Linux assumption |
| Multi-GPU | Prefer decode on the rendering device; cross-device import may fail or copy |
| Format/modifier | Query EGL support and validate actual descriptor layout; compositor output feedback is not a decoder-import capability list |
| Plane representation | Respect object/layer/plane mapping, offsets, strides, auxiliary planes, and modifiers |
| Texture target | Check `external_only`; some formats require `GL_TEXTURE_EXTERNAL_OES` and the appropriate GLES external-image extension |
| YUV conversion | Explicit plane shaders when supported; external sampling may perform driver conversion—do not apply the matrix twice |
| Unsupported combination | Software decode/upload or explicit failure; never assume arbitrary NV12 buffers can be reinterpreted as separate R/RG textures |
| Software upload | Preserve YUV where supported; row-stride-aware uploads and reusable slots, no per-frame texture allocation or GPU readback |

Start with FFmpeg if scope is frame display plus local, initially muted playback.
It provides demux/decode, not a finished audio device, playback clock, or streaming
policy. If full cross-platform playback (audio/networking/buffering) is the first
requirement, evaluate a GStreamer-based adapter before building those services.
Neither library belongs in the base `Roots` product. Review redistribution/license
requirements for the selected FFmpeg build and codecs.

## 4. Clocking, queue bounds, and UI reuse

```swift
// Proposed timing concepts; exact backend protocol signatures remain open.
struct MediaTime: Sendable { let ticks: Int64; let timescale: Int32 }
enum FrameInvalidationReason { case ui, media }

// BackendFrame: retain timeSeconds for UI animation;
// add optional predicted presentation time in an explicitly mapped clock domain.
// Surface scheduler: cancellable, coalesced redraw-at-deadline requests.
```

```text
media PTS ↔ playback clock ↔ host monotonic clock ↔ predicted display time
                   ▲
        audio clock when audio exists
        monotonic clock for muted playback

At a display opportunity:
  newest frame with PTS <= target media time → display
  older eligible frames                    → drop
  only future frames                       → keep current frame; schedule deadline
  no free submission slot                  → backpressure, not queue growth
```

- Preserve variable-frame-rate timestamps; do not accumulate `1 / fps`.
- Bound ready frames (initial target: 2–3), current frame, in-flight submissions,
  and import cache. Decoder reference/reorder surfaces are a separate bounded pool.
- A seek increments a generation, flushes queued old frames, and prevents stale
  worker results from becoming current; in-flight GPU leases still drain normally.
- A paused or unchanged video needs no periodic redraw. Visibility policy should
  throttle/suspend video work without unintentionally stopping audio.
- Wayland frame callbacks authorize another frame; they are not actual
  presentation timestamps. Add optional `wp_presentation` feedback for calibration.
  Keep a documented monotonic fallback when prediction/feedback is unavailable.
- On macOS, obtain display timing from an appropriate display-link mechanism;
  don't derive media time from `preferredFramesPerSecond = 60`.

### Media-only composition

```text
UI/input/animation/viewport invalidation
  → build + layout + paint → owned scene/geometry cache → compose

New eligible video frame, unchanged geometry
  → resolve source frame → reuse scene/geometry cache → compose
```

Do not retain `UIDrawBatch`: it remains a borrowed view. Keep owned command storage
in the host and prepared geometry in the renderer. Invalidate both when UI state,
clips, scale, viewport, or source geometry changes. Media-only ticks must not replay
input edges or application frame callbacks. Avoid making the decoded frame an
`@Observable` pixel-array property that invalidates the entire block tree.

This initially still composites the full window on the GPU. Damage tracking,
Wayland video subsurfaces/direct scanout, and separate native video layers are
later optimizations: they complicate clipping, overlay ordering, screenshots,
and backend parity. They are not required to avoid CPU pixel copies.

## 5. Color and scope

```text
stored Y′CbCr
  → range expansion (limited/full)
  → matrix (BT.601 / BT.709 / BT.2020)
  → transfer decoding
  → primaries conversion
  → compositor working space
  → output transfer
```

Do not conflate YUV matrix conversion with complete color management. Specify
chroma siting, crop, pixel aspect ratio, orientation, and the image alpha convention.
The current shaders/targets do not establish an HDR pipeline.

| First supported slice | Deferred, explicitly unsupported or converted |
| --- | --- |
| Progressive SDR, BGRA/RGBA, NV12 and planar 8-bit YUV fallback | HDR/EDR output, P010/10-bit paths, interlacing |
| Fit/fill, clipping, UI controls over video | Protected/DRM content |
| Synthetic source, then muted local file, pause/seek/loop | Audio playback, network streaming, subtitles |
| Explicit SDR working/output space and reference color tests | Wide-gamut output and tone mapping |

Keep metadata extensible now. Reject unsupported transfer functions/formats until
there is a correct conversion path; do not display HDR values as if they were SDR.

## 6. Breaking changes worth making

| Change | Migration / benefit |
| --- | --- |
| `UIDrawBatch` yields `DrawCommand`, not `DrawRect` | Update all three renderers and external fixtures; enables image commands without bloating every shape |
| Public image-source/resource capability contract | External backends participate; frame lifetime no longer implied by CPU draw lifetime |
| Backend timing + scoped deadline/invalidation API | Media cadence without permanent animation redraws; cancellation on surface close |
| Owned scene and prepared-geometry caches | Reuse static UI on media-only frames; preserve borrowed public batches |

Keep `DesktopWindow`, existing `Block` composition, and rectangle drawing intact
where possible. No need to replace every shape type, use an untyped native-handle
escape hatch, or force all users to install a codec stack.

## 7. Implementation slices and verification

| Slice | Deliverable | Gate |
| --- | --- | --- |
| 1 | `DrawCommand.image`, source registry, CPU-backed still images in CPU/Metal/GLES | Ordering, clipping, resize/scale, external-backend fixtures, unchanged shape output |
| 2 | Synthetic timestamped planar video, GPU YUV sampling, bounded queues/leases | Strides, odd extents, color bars, fit/fill, fake-clock pacing, delayed GPU release |
| 3 | Linux hardware import proof on target devices; AVFoundation/Core Video adapter on macOS | Hardware path measured, correct acquire/release, visible fallback reason |
| 4 | Optional muted file player, clock/deadline scheduling, media-only scene reuse | Pause/seek/end-of-stream, VFR, no static UI rebuilds on media ticks |
| 5 | Playback demo + performance/cleanup suite | 1080p60 and 4K60 trials, memory plateau, repeated seek/open/close, idle wakeups |

The hardware-import proof is a risk gate before committing to a Linux decoder
stack: particularly codec availability, modifiers, synchronization, and multi-GPU.

```text
Tests/RootsTests             source IDs, commands, fit/crop, invalidation
Tests/RootsCPUTests           reference RGB/YUV sampling + color fixtures
Tests/CompilerFixtureTests   valid external source/backend clients;
                             reject escaping frame views / consuming borrowed owners
Tests/MacOSBridgeTests       delayed completion keeps CV owners alive; import failures
Tests/WaylandBridgeTests     acquire/read fences, FD ownership, modifier fallback;
                             resize/device change/close with work in flight
Tests/RootsDesktopTests      fake-clock PTS selection, bounds, seek generations,
                             media-only reuse, input delivery exactly once
```

### Performance measurements, not promises

| Metric | Desired property |
| --- | --- |
| CPU frame copies / upload bytes | Zero pixel uploads on compatible native-import path |
| Resource allocation | Plateau after pool/format warmup; no unbounded per-PTS cache |
| UI CPU time | No rebuild/layout on unchanged media-only ticks |
| Queue depth and frame age | Bounded; drop late frames instead of accumulating latency |
| Main-thread stalls | No decode waits or routine `glFinish()` on fast path |
| Display cadence | Test 24/30/60 fps on 60/120/144 Hz and fractional scaling |
| Input latency | Responsive while decoding, resizing, and seeking |
| Idle power | No periodic video wakeups while paused; visibility-aware playback |

At 3840×2160×60, one uncompressed RGBA8 pass is about **1.99 GB/s**; NV12
is about **0.75 GB/s**, before padding. These are byte-rate calculations, not
benchmarks. Importing native frames avoids CPU upload traffic; it does not remove
GPU sampling, color conversion, output writes, or possible driver-internal copies.

## Investigation checks and API references

- Repository rendering, ownership, pacing, and compiler-fixture paths inspected.
- Local toolchain: Swift 6.4.1, Linux aarch64. A standalone probe compiled with
  `-swift-version 6 -enable-experimental-feature Lifetimes -strict-memory-safety
  -warnings-as-errors -c`, covering `~Copyable` owners, `~Escapable` views,
  `@_lifetime(borrow ...)`, `Ref`, `MutableRef`, and `@c`.
- At the investigation stage, the proposed public API and platform adapters had
  not been implemented or compiled; see the implemented subset above. No playback benchmark or macOS SDK validation was performed during that investigation.

References consulted:

- Swift compiler/stdlib: [`Ref`](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/Ref.swift), [`@c` compiler tests](https://github.com/swiftlang/swift/blob/main/test/attr/attr_c.swift).
- Apple: [`AVPlayerItemVideoOutput`](https://developer.apple.com/documentation/avfoundation/avplayeritemvideooutput), [`CVMetalTextureCacheCreateTextureFromImage`](https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage(_:_:_:_:_:_:_:_:_:)).
- FFmpeg: [`AVDRMFrameDescriptor`](https://github.com/FFmpeg/FFmpeg/blob/master/libavutil/hwcontext_drm.h).
- Khronos: [`EGL_EXT_image_dma_buf_import`](https://registry.khronos.org/EGL/extensions/EXT/EGL_EXT_image_dma_buf_import.txt), [`EGL_EXT_image_dma_buf_import_modifiers`](https://registry.khronos.org/EGL/extensions/EXT/EGL_EXT_image_dma_buf_import_modifiers.txt).
