# Protocol inputs

- `wayland.xml`: [Wayland 1.26.0](https://github.com/wayland-mirror/wayland/blob/1.26.0/protocol/wayland.xml).
- `idle-inhibit-unstable-v1.xml`: [wayland-protocols 1.49](https://github.com/wayland-mirror/wayland-protocols/blob/1.49/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml).
- `linux-dmabuf-v1.xml`: [wayland-protocols 1.49](https://github.com/wayland-mirror/wayland-protocols/blob/1.49/stable/linux-dmabuf/linux-dmabuf-v1.xml).
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
wl_seat v4…5      → pointer / keyboard
linux-dmabuf v3   → format/modifier announcements + async create
idle-inhibit v1   → visible-parent surface inhibition; disconnect releases it
```

Objects keep tombstone metadata for queued events; client IDs are not reused until
`wl_display.delete_id`. Server-created IDs are registered before decoding the next
event. The dmabuf presenter uses `created`/`failed`, not `create_immed`.
