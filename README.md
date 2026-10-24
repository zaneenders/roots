# roots

⚠️ Work in progress 🤖

A Swift-native UI toolkit.

## Examples

Explore the runnable apps in [Examples](Examples):

- [Markdown](Examples/Markdown): styled paragraphs, selectable text, scrolling,
  and clipboard support.
- [Tetris](Examples/Tetris): declarative blocks, keyboard input, observation,
  and frame-driven animation.

After following the [setup instructions](#development), run either example from
the repository root:

```sh
swift run --package-path Examples/Markdown MarkdownDemo
swift run --package-path Examples/Tetris Tetris
```

Text measurement, drawing, and paragraphs recognize LF, CRLF, and CR line breaks.
Selectable plain text copies its displayed lines with LF separators.

## Platforms

macOS 27+ and Linux (Hyprland). PRs for other backends welcome.

## Development

Requires Swift 6.4.1 (`pkg-config` on Linux), plus:

| Platform | System libraries |
| --- | --- |
| macOS | zlib (provided by the SDK) |
| Linux / Wayland | Development headers and libraries for zlib, xkbcommon, EGL, and GLES 3 |

```sh
git clone --recurse-submodules https://github.com/zaneenders/roots.git
cd roots
```

### Build-time font sources

FreeType and libpng are pinned submodules; libpng links system zlib.

```sh
git submodule update --init --recursive
```

### Build and test

Run from the `roots` directory:

```sh
swift test
```

## License

Roots is licensed under [Apache-2.0](LICENSE). Copyright 2026 Zane Enders.
Third-party code and assets retain their respective licenses.
