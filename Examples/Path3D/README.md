# Path3D

```sh
swift run -c release --package-path Examples/Path3D Path3D
swift run --package-path Examples/Path3D Path3D --offscreen --screenshot /tmp/path3d.ppm
swift run -c release --package-path Examples/Path3D Path3D --analytic
swift test --package-path Examples/Path3D
```

| Input | Action |
| --- | --- |
| Drag | Orbit camera |
| Wheel | Zoom |
| Auto orbit | Rotate camera |
| Hover | Source segment + perspective-correct fraction + XYZ |
| Play / Pause | Tracer playback |
| Reset | Camera + playback position |
| Focus loss | Pause playback and orbit |

```text
SIMD3<Float> → Path3DCamera → depth-sorted PolylineStroke runs
```

CPU-projected 3D; approximate occlusion, no depth buffer.
