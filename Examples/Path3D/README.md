# 3D Path

```sh
swift run -c release --package-path Examples/Path3D Path3D
swift run --package-path Examples/Path3D Path3D --offscreen --screenshot /tmp/path3d.ppm
swift run -c release --package-path Examples/Path3D Path3D --analytic # coverage comparison
swift test --package-path Examples/Path3D
```

| Input | State |
| --- | --- |
| Drag | Camera yaw / pitch |
| Wheel | Uniform zoom |
| Auto orbit | Camera rotation |
| Hover | Source segment + perspective-correct fraction + XYZ |
| Play / Pause | Moving tracer, 24-second loop |
| Reset | Default camera + playback position |
| Focus loss | Stops playback and orbit |

```text
Path3DGeometry: (2, 3) torus knot / 1,025 SIMD3<Float> samples
  → Path3DCamera: perspective projection
    → Path3DProjection: ~Copyable
      ├─ opaque depth-sorted ribbon runs
      ├─ floor grid + projected shadow
      └─ camera revision cache
        → PolylineStroke(.ribbon) → cached triangles
        → sharp/degenerate runs → analytic fallback

Playback / zoom: reuse geometry
Orbit: rebuild projection
Paused + orbit off: no animation frame requests
No glow pass
```

This is CPU-projected, approximately depth-sorted 3D, not a depth-buffer/mesh engine.
Source-over ribbon crossings are intentional; use `.analytic` for exact single-coverage paths.
No network, FIT parser, user files, or extra runtime dependencies.

## Rendering comparison (Linux / GLES)

```sh
ROOTS_PATH3D_BENCHMARK=1 swift test --package-path Examples/Path3D --no-parallel --filter path3DRenderingBenchmark
```

```text
Historical capture before the compact UI rename:
1000 × 800 logical / 2000 × 1600 pixels
5 warmup + 30 frames; analytic → ribbon → analytic → ribbon
EGL submission + glFinish (not isolated GPU timestamps)
Debug Swift 6.4.1 / Apple M1 / Mesa 26.2.4

No-glow knot, captured medians:
  analytic 13.30–16.56 ms
  ribbon    7.37–7.39 ms

Includes fallback paths, UI, grid, shadow, moving tracer.
Excludes native presentation and auto-orbit projection rebuilds.
Not a GPU-utilization or power-consumption measurement.
```

See [retained path contracts and backend behavior](../../Docs/Paths.md).
