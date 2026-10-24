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
| Linux / Wayland | Development headers and libraries for zlib, xkbcommon, EGL, GLES 3, GBM, and libdrm |

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

`swift test` also compiles the external-client fixtures in
`Tests/CompilerFixtureTests/Inputs`. Valid clients must compile, and `Reject*`
fixtures must fail with their `// expected-error:` diagnostics. These checks run
full compilation so ownership and lifetime errors are checked beyond type checking.
Use the same Swift toolchain for building and running tests: the fixture runner
uses `SWIFT_EXEC` when set, otherwise `swiftc` from `PATH`. Each compiler invocation
has a 30-second timeout; compiler crashes and missing modules fail the test.

To run only the compiler fixtures:

```sh
swift test --filter compilerFixturesEnforceThePublicAPIAndLifetimes
```

### Wayland compositor tests

```sh
swift Scripts/test-compositors.swift  # current Wayland session
ROOTS_REQUIRE_PRESENTATION=1 swift Scripts/test-compositors.swift  # require GPU presentation
```

See [compositor testing](Tests/COMPOSITOR_TESTS.md) for coverage, prerequisites,
and retained logs. The runner requires a running compositor; ordinary
`swift test` still skips unavailable compositor tests.

## License

Roots is licensed under [Apache-2.0](LICENSE). Copyright 2026 Zane Enders.
Third-party code and assets retain their respective licenses.
