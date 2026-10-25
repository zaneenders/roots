# Mandelbrot with Roots

[Setup requirements](../../README.md#development). From the repository root:

```sh
swift run --package-path Examples/Mandelbrot Mandelbrot
swift test --package-path Examples/Mandelbrot
```

```text
MandelbrotApp → DesktopWindow → MandelbrotPage
                                 └─ Canvas → MandelbrotImage.runs → DrawRect
```

`MandelbrotImage` samples a 640 × 400 grid with 160 iterations and the smooth
escape-time palette from [Chroma's ImageDemo](https://github.com/zaneenders/chroma-examples/tree/main/Sources/ImageDemo).
`runs: [DrawRect]` caches horizontal runs of equal RGBA8 colors once; `Canvas`
paints them with overlapping edges to avoid antialiasing seams. No bitmap texture
API or per-pixel `Block` is required. `fitted(in: Region)` centers the image without
changing its aspect ratio when the window resizes.
