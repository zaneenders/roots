# Retained paths

```swift
let route = PolylineStroke(
  points: samples.map(\.position),
  width: 3,
  colors: samples.map(\.color), // optional; empty = white × draw tint
  rendering: .automatic
)!

let camera = PathTransform(
  translation: Coordinate(x: 400, y: 300), scale: 1.5, rotation: 0.4)

Canvas(key: 1) { paint in
  paint.strokePolyline(route, transform: camera)
  if let mouse = paint.mousePosition,
    let hit = route.hitTest(mouse, transform: camera, tolerance: 12, clip: paint.clip) {
    // Original source segment, not a renderer chunk index.
    let sample = Float(hit.segmentIndex) + hit.fraction
    paint.strokeCircle(center: hit.position, radius: 8, color: .text)
  }
}
```

```text
PolylineStroke: Sendable (immutable shared identity)
  ├─ [Coordinate] + [Color] + width
  └─ chunk bounds / 64 segments
       │
UIPaintContext: ~Copyable, ~Escapable
  └─ DrawRect(polyline:, transform:, clip:)  // no vertex map/copy
       ├─ .automatic: opaque + valid ribbon → cached triangles
       ├─ .analytic: bounded nearest-segment → one-coverage union
       └─ .ribbon: source-over triangles; degenerate runs fall back
          ├─ RootsCPU → triangle raster / analytic coverage
          ├─ GLES → cached VBO + VAO / RGBA32F texture
          └─ Metal → cached MTLBuffer
                        │
                        └─ transform uniforms; reuse until geometry changes
```

| Contract | Behavior |
| --- | --- |
| `PathTransform` | Translation, rotation (radians), positive uniform scale; no shear/perspective |
| `width` | Local units; scaled with geometry |
| `Hit.distance`, `tolerance` | Centerline distance in caller coordinates, not stroke-edge distance |
| `Hit.position` | Caller coordinates; usable with the same paint scope |
| `clip` | Caller coordinates for picking; frame coordinates in retained draw commands |
| `colors` | Empty or one finite RGBA value per point; interpolated by nearest-segment fraction |
| Picking ties | Earliest source segment wins |
| `.analytic` crossings | One-coverage union; earliest segment colors ties |
| `.ribbon` crossings | Source-over; opaque colors follow source drawing order |
| `.automatic` | Ribbons for opaque paths/tints; analytic for translucent content |
| Joins | Shared-edge miter ribbons; round caps; sharp turns/duplicates/folded inner edges fall back to analytic |
| Long paths | Up to 65,536 points; no client chunking |
| Empty / invalid geometry | Failable initializer returns `nil` |
| Duplicate / single points | Valid; single point renders a round dot |
| Mutation | Create a new immutable `PolylineStroke`; geometry identity is the cache revision |
| GPU lifetime | Per-renderer cache retains used paths; evicts unused paths after a frame. Metal commands retain in-flight buffers |

```text
paint.withOrigin(outer) {
  paint.strokePolyline(route, transform: inner)
}

frame transform = outer.concatenating(inner)
frame point     = outer.apply(inner.apply(localPoint))
```

`DrawRect.polyline.points` and `.width` remain in **geometry-local coordinates** after painting.
Custom renderers must apply `DrawRect.pathTransform`; previously `UIPaintContext` baked its transform into copied points.

The analytic fallback limits its segment search to the stroke + a two-pixel antialias margin.
It preserves translucent union coverage but remains fragment-heavy for large paths. Ribbons rasterize only
stroke triangles; crossings use source-over. No path sampling, scene-layer cache, or mesh/depth renderer is implied.
Application sampling and 3D projection remain outside Roots.

## Example and checks

```sh
swift run --package-path Examples/Path3D Path3D
swift run --package-path Examples/Path3D Path3D --offscreen --screenshot /tmp/path3d.ppm
ROOTS_PATH3D_PREVIEW=/tmp/path3d-cpu.ppm swift test --package-path Examples/Path3D
  (2, 3) torus knot → camera projection → depth-sorted ribbon runs
    → zoom / playback reuse cached geometry
    → orbit rebuilds projection
    → no glow; floor shadow + color/depth shading

Tests
  retainedPathTransformsKeepGeometryIdentity
  coloredPathPickingUsesSourceSegmentsAndScreenDistances
  longColoredSelfCrossingPathBlendsOnceAtChunkBoundaries
  retainedColoredPathsMatchCPUAndReuseUploads (GLES; fractional scale)
  retainedColoredPathMatchesCPUAndCachesBuffers (Metal; macOS)
  ribbonsMatchCPUAndDoNotReupload (GLES; 1× / 1.5× / 2×)
  translucentRibbonJoinsDoNotDoubleBlend
  pausedSceneStopsRequestingAnimationFrames (Path3D example)
```

## CPU command-generation benchmark

```sh
swift test -c release --filter retainedPathFrameGenerationBenchmark
ROOTS_PATH_BENCHMARK=1 taskset -c 4 swift test -c release --skip-build \
  --no-parallel --filter retainedPathFrameGenerationBenchmark
```

```text
Same binary / scope / 4,097 points / 30 warmup + 500 frames
  rebuild → retain → rebuild → retain

Captured: Swift 6.4.1, Linux aarch64, CPU affinity 4
  rebuild p50 11.583 µs   p95 11.625 µs
  retain  p50  0.584 µs   p95  0.625 µs

Excluded: GPU execution, presentation, allocator/ARC instrumentation
Correctness gates: geometry identity, upload counter, cache eviction, CPU/GPU pixel parity
```
