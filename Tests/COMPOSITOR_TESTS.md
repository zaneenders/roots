# Compositor matrix

```text
swift Scripts/test-compositors.swift all
├─ Sway   / headless / Pixman / private XDG_RUNTIME_DIR
│  ├─ SwiftWaylandTests                 deterministic wire peers + injected faults
│  ├─ CompositorIntegrationTests        configure / drain / reconnect
│  └─ outputHotplugAndScaleChanges      HEADLESS-2: create → 2× → 1.5× → unplug
└─ Weston / headless / Pixman / kiosk-shell / private XDG_RUNTIME_DIR
   ├─ SwiftWaylandTests
   └─ CompositorIntegrationTests        no layer-shell requirement

ROOTS_REQUIRE_PRESENTATION=1 swift Scripts/test-compositors.swift current
└─ current Wayland session / real GPU
   ├─ NativeSessionTests                buffers / fences / screenshots / layer popups
   └─ CompositorIntegrationTests        parent + popup presentation / reopen / reconnect
```

Requires `swift`, `sway` + `swaymsg`, and `weston` on `PATH`. Missing
executables, compositor startup/exit failures, missing required globals, test
failures, and timeouts fail the run. The runner never installs packages or changes
the user's compositor configuration. It removes only its private runtime directory
and terminates only the compositor it started.

```sh
# Both CPU-only protocol lanes (no DRM/render node required).
swift Scripts/test-compositors.swift all

# Individual lanes.
swift Scripts/test-compositors.swift sway
swift Scripts/test-compositors.swift weston

# Hardware-backed headless Sway, when the driver supports dma-buf.
ROOTS_TEST_RENDERER=gles2 ROOTS_REQUIRE_PRESENTATION=1 \
  swift Scripts/test-compositors.swift sway

# Hardware-backed Weston.
ROOTS_TEST_RENDERER=gl ROOTS_REQUIRE_PRESENTATION=1 \
  swift Scripts/test-compositors.swift weston

# Existing Hyprland/Sway/Weston session; does not launch/stop the compositor.
ROOTS_REQUIRE_PRESENTATION=1 swift Scripts/test-compositors.swift current
```

| Setting | Default | Effect |
| --- | --- | --- |
| `ROOTS_TEST_RENDERER` | `pixman` | Renderer for an isolated compositor |
| `ROOTS_REQUIRE_PRESENTATION` | `0` | `1`: fail if dma-buf presentation is unavailable |
| `ROOTS_TEST_TIMEOUT` | `180` | Whole build/test command timeout in seconds |
| `ROOTS_REQUIRE_COMPOSITOR` | runner sets `1` | Fail instead of skipping an unavailable compositor |

```text
.build/compositor-tests/<compositor>.<unique>/
├─ compositor.log       startup / protocol errors (isolated lanes)
├─ sway.conf            generated config (Sway)
├─ version.log          version probe (Weston)
└─ tests.log            advertised globals / failures / explicit skips
```

Popup tests map the parent first, as required by `xdg_popup`.

Pixman lanes intentionally skip GPU presentation; they are not GPU coverage.
A dma-buf global alone is not proof that the driver can allocate/import buffers:
GPU tests must complete when enabled, rather than converting allocation failures
into skips. `current` may open test windows; use an isolated session for CI.

## Deterministic fault coverage

| Scenario | Swift test |
| --- | --- |
| Optional globals absent | `compositorWithoutOptionalGlobalsStillConfigures` |
| Delayed parent frame callback | `popupFramesProgressWhileParentCallbackIsDelayed` |
| Delayed buffer release / per-surface wakeup | `bufferAvailabilityIsScopedToItsSurface` |
| Closed submitted buffer awaiting release | `closedSubmittedBuffersWaitForReleaseAndSurviveImportPruning` |
| Import rejection / retry / parent and popup isolation | `rejectedImportWakesOnlyItsSurfaceAndAllowsRetry` |
| Resize + stale popup configure/dismissal | `coalescedResizeAndDismissalCannotConfigureReplacementPopup` |
| Output removal / integer scale fallback | `integerFallbackTracksEachSurfaceOutputAndFallsBackAfterRemoval` |
| Independent fractional scales | `fractionalScaleIsIndependentForEachSurfaceAndIgnoresIntegerPreferences` |

These peers control event order without relying on a compositor's timing. Real
compositor lanes complement them; they do not attempt to make a compositor reject
valid buffers or delay releases nondeterministically.
