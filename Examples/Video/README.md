# Video playback

Requires FFmpeg 7+ development libraries (`libavformat`, `libavcodec`, `libavutil`,
`libswscale`) and `pkg-config`. FFmpeg is only linked by this example, not Roots.

From the repository root:

```sh
swift run --package-path Examples/Video VideoPlayer /path/to/movie.mp4
```

Muted playback.
