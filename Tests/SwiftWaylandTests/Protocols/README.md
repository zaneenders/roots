# Protocol inputs

- `wayland.xml`: [Wayland 1.26.0](https://github.com/wayland-mirror/wayland/blob/1.26.0/protocol/wayland.xml).
- `idle-inhibit-unstable-v1.xml`: [wayland-protocols 1.49](https://github.com/wayland-mirror/wayland-protocols/blob/1.49/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml).
- `linux-dmabuf-v1.xml`: [wayland-protocols 1.49](https://github.com/wayland-mirror/wayland-protocols/blob/1.49/stable/linux-dmabuf/linux-dmabuf-v1.xml).
- `fractional-scale-v1.xml`: [wayland-protocols 1.49](https://github.com/wayland-mirror/wayland-protocols/blob/1.49/staging/fractional-scale/fractional-scale-v1.xml).
- `viewporter.xml`: [wayland-protocols 1.49](https://github.com/wayland-mirror/wayland-protocols/blob/1.49/stable/viewporter/viewporter.xml).
- `xdg-shell.xml`: [wayland-protocols 1.45](https://github.com/wayland-mirror/wayland-protocols/blob/1.45/stable/xdg-shell/xdg-shell.xml).
- `wlr-layer-shell-unstable-v1.xml`: [swaywm/wlr-protocols b010a03648b88d143236de193bddbfea0c08bc84](https://github.com/swaywm/wlr-protocols/blob/b010a03648b88d143236de193bddbfea0c08bc84/unstable/wlr-layer-shell-unstable-v1.xml).

Copyright/permission notices are retained in the XML. These are test-only resources;
runtime builds use compact Swift request/event signatures in
[`WireSchema.swift`](../../../Sources/SwiftWayland/Protocol/WireSchema.swift).
`SchemaTests` verifies signatures, opcode declaration order, and input enum values
against these pinned inputs. No scanner or generated C bindings are used.

```text
wl_compositor v3…6 → surfaces / transforms / integer buffer scale
xdg_wm_base v1     → toplevel / child popup
layer-shell v1    → passive top bar / child popup
fractional-scale v1 + viewporter v1 → per-surface scale / logical destination
wl_seat v4…5      → pointer / keyboard
linux-dmabuf v3…4 → v3 announcements / v4 atomic device + format/modifier feedback
idle-inhibit v1   → visible-parent surface inhibition; disconnect releases it
```

Objects keep tombstone metadata for queued events; client IDs are not reused until
`wl_display.delete_id`. Server-created IDs are registered before decoding the next
event. The dmabuf presenter uses `created`/`failed`, not `create_immed`.

## Surface scheduling

```text
WaylandConnection
├─ frame: SurfaceFrameState              (parent)
└─ popup: WaylandPopup?
   └─ frame: SurfaceFrameState            (popup)

SurfaceFrameState.canRender
  = configured && frameReady && redrawRequested && !waitingForBuffer

parent: requestRedraw()      → beginFrame()     → endFrame()      → commit
popup:  requestPopupRedraw() → takePopupInput() → endPopupFrame() → commit

wl_callback.done      → originating SurfaceFrameState.complete(id)
wl_buffer.release     → originating SurfaceFrameState.waitingForBuffer = false
```

`WaylandConnection.canRender` remains parent-only; `canRenderPopup` is independent.
`dispatchAsync()` wakes for either surface or popup dismissal. Each `end*Frame()`
queues `wl_surface.frame` before that surface's buffer commit. Popup dismissal
retires its pending callback; buffer wakeups weakly reference the originating
`SurfaceFrameState`, not a replacement popup.

`NativeWindow.requestRedraw()` targets the parent;
`NativeWindow.requestPopupRedraw()` targets the popup. `WaylandPopup` runtime
invalidation uses the latter, including observation and animation frames.

```text
v4 default feedback ──┐
v4 surface feedback ──┴→ WaylandDMABufFeedback (published at done)
                           ├── mainDevice → libdrm → render node → GBM / EGL
                           └── tranches   → ARGB / ABGR + modifier candidates
                                                ↓
                                       GBM allocation → EGLImage → FBO
                                                ↓
                                       async wl_buffer create
                                       ├── created → present → release
                                       └── failed  → next candidate

v3 announcements → surfaceless EGL texture → MESA export → async wl_buffer create
```

Feedback changes replace idle buffers; submitted buffers wait for release. Device
changes recreate the renderer on the advertised GPU. Parent and popup share a
`DMABufDevice` when their render nodes match. No `wl_shm` fallback is provided.

## Surface scale

```text
WaylandInput.width / height                     (logical)
    × fractionalScale120 / 120 → round(.toNearestOrAwayFromZero)
BufferSize.width / height                       (pixels)
    → wp_viewport.set_destination(width, height) (logical)

fractionalScale120 != nil → bufferScale = 1; renderScale = fractionalScale120 / 120
fractionalScale120 == nil → renderScale = Double(bufferScale)
```

`SurfaceScale` negotiates parent and popup independently. Both optional globals
are required; otherwise `wl_surface.preferred_buffer_scale` / entered outputs
supply the integer fallback. Clips use the actual rounded pixel-to-logical ratio
on each axis; input coordinates remain logical.
