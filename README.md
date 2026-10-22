# roots

⚠️ Work in progress 🤖

A Swift-native UI toolkit.

```swift
import Roots
import RootsDesktop

@MainActor
final class WorkspaceModel {
  var count = 0
}

@main
struct ShapeTree: RootsApp {
  let model = WorkspaceModel()

  var window: some Window {
    DesktopWindow("ShapeTree", size: .init(1180, 820)) { viewport in
      WorkspaceBlock(model: model, bounds: viewport.bounds)
    }
  }
}

struct WorkspaceBlock: Block {
  let model: WorkspaceModel
  let bounds: Rect

  var body: some Block {
    ColumnBlock(in: bounds) {
      LabelBlock(key: 1, "Count: \(model.count)")
      ButtonBlock(key: 2, "Increment") { model.count += 1 }
    }
  }
}
```

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

## Examples

- [Tetris](Examples/Tetris): a standalone Swift package demonstrating desktop windows,
  blocks, custom painting, keyboard input, observation, and frame-driven animation.
  Run it with `swift run --package-path Examples/Tetris Tetris`.

## License

Roots is licensed under [Apache-2.0](LICENSE). Copyright 2026 Zane Enders.
Third-party code and assets retain their respective licenses.
