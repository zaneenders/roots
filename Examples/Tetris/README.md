# Tetris with Roots

A small, playable desktop game built entirely with Roots' public API. This is a
standalone Swift package inside the repository: it depends on the local checkout
of Roots, not on a separately published version or a private hosting interface.

## Run

Use **Swift 6.4.1** and either **macOS 27+** or **Linux with a Wayland compositor**
(Roots currently targets Hyprland). Linux needs development headers/libraries for
zlib, xkbcommon, EGL, and GLES 3, plus `pkg-config`. For example, on Debian/Ubuntu:

```sh
sudo apt install pkg-config zlib1g-dev libxkbcommon-dev libegl1-mesa-dev libgles2-mesa-dev
```

From the repository root:

```sh
git submodule update --init --recursive
cd Examples/Tetris
swift run Tetris
```

The nested package has its own build/test commands. Running `swift test` in the
repository root does **not** run this example's tests. You can also use
`swift run --package-path Examples/Tetris Tetris` from the root.

## Play

| Key | Action |
| --- | --- |
| Left / Right | Move; hold to repeat |
| Up / X | Rotate clockwise |
| Z | Rotate counterclockwise |
| Down | Soft drop; hold to repeat |
| Space | Hard drop |
| P / Escape | Pause or resume |
| R | Restart the current seeded sequence |
| Tab / Shift-Tab, Enter | Focus and activate the sidebar buttons |

Space is always hard drop, including while a button is focused. Use Enter to
activate a focused button. Switching away from the window pauses the game;
returning does not resume it automatically. Close the window to quit. A new
launch chooses a new random seed; restarting replays the same sequence.

Clear rows to score 100 / 300 / 500 / 800 points for 1 / 2 / 3 / 4 rows,
multiplied by the level before the clear. Soft and hard drops add 1 and 2 points
per cell. Every 10 lines raises the level and gravity speed. An outlined ghost
shows the landing position, and the sidebar previews the next three pieces.

This is an API example, not a guideline-complete Tetris implementation: rotation
uses a small set of wall/floor nudges rather than SRS; a blocked downward move
locks immediately; there is no hold, lock delay, T-spin bonus, sound, or persistence.
The board has 20 visible rows and no hidden spawn rows.

## Read the example

Start with [`TetrisApp.swift`](Sources/Tetris/TetrisApp.swift):

```swift
struct TetrisApp: RootsApp {
  // ... initialize the game controller ...
  var window: some Window {
    DesktopWindow("Tetris · Roots", size: .init(900, 800)) { viewport in
      GameBlock(controller: controller, bounds: viewport.bounds)
    }
    .onKey { controller.handleKey($0) }
    .frameDelegate(controller)
  }
}
```

- [`GameBlock.swift`](Sources/Tetris/GameBlock.swift) composes `ColumnBlock`,
  `ScrollColumnBlock`, `LabelBlock`, and `ButtonBlock` with stable keys. The sidebar
  scrolls if the window becomes short. `CanvasBlock` and `UIPaintContext` draw the
  board and previews with clipped fills, strokes, text, and local origins.
- [`GameController.swift`](Sources/Tetris/GameController.swift) is an
  `@MainActor @Observable` model. Reads during block construction and painting
  participate in Roots' observation tracking. `DesktopFrameDelegate.prepareFrame`
  advances gravity using the desktop frame clock, and `needsAnimationFrame`
  requests continuous frames only while playing. `frameUpdate` requests one
  same-frame rebuild after input so the score and pause button cannot lag behind
  the board. There is no polling timer or background task.
- The window's `onKey` handler consumes only recognized game keys, ignores key
  releases and system-modified shortcuts, and lets Roots handle Tab/Enter. A
  focus-loss frame pauses before advancing and discards simultaneous key events.
- [`TetrisCore`](Sources/TetrisCore) contains value-type rules with a seeded
  seven-bag randomizer. It has **no Roots dependency**, renderer, or wall clock,
  so the game is deterministic and easy to test independently of a desktop.

No `@_spi(Hosting)`, `UIHost`, platform bridge import, or changes to Roots itself
are needed to build the example.

## Verify

From this directory:

```sh
swift test
swift test -c release
swift run Tetris --screenshot /tmp/tetris.ppm
```

The screenshot command uses the public `DesktopWindow(offscreen:maxFrames:)`
configuration to render one deterministic 900 x 800 frame with seed 42 and exit.
The output is a binary PPM image. It does not need a live Wayland session on Linux,
but still needs an EGL/GLES driver supporting surfaceless rendering. It is a render
smoke test, not a replacement for testing interactive input in a real window.

Tests cover bag reproducibility, movement and stack collision, both rotation
directions, wall/floor nudges, blocked rotations, gravity, drop scoring, ghost
placement, 1–4 row clears, board compaction, levels, blocked spawn/game over,
pause/restart, invalid elapsed time, seeded command invariants, keyboard routing,
repeat/release/modifier handling, focus loss, and same-frame invalidation.

For an interactive smoke test, move and rotate at both walls, hard drop several
pieces, pause/resume by key and button, tab to buttons and activate with Enter,
switch away and back, resize the window, and restart after game over.

## License

Part of Roots, under the repository's [Apache-2.0 license](../../LICENSE).
