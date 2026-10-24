# Compositor testing

```sh
# Test the current Wayland session (Hyprland in development).
swift Scripts/test-compositors.swift

# Also require GPU presentation instead of allowing unavailable GPU tests to skip.
ROOTS_REQUIRE_PRESENTATION=1 swift Scripts/test-compositors.swift
```

```text
current Wayland session
├─ SwiftWaylandTests           deterministic wire peers + injected faults
├─ CompositorIntegrationTests  configure / drain / reconnect
│                             independent parent + popup presentation / reopen
└─ NativeSessionTests          buffers / fences / screenshots / layer popups
```

The runner requires `swift` on `PATH` and an already-running compositor accessible
through `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`. It does not launch, configure,
restart, or stop the compositor. `current` is accepted as an optional argument.
It prints progress and streams test output while preserving the full log.

| Setting | Default | Effect |
| --- | --- | --- |
| `ROOTS_REQUIRE_PRESENTATION` | `0` | `1`: fail if dma-buf presentation is unavailable |
| `ROOTS_TEST_TIMEOUT` | `180` | Whole build/test command timeout in seconds |
| `ROOTS_REQUIRE_COMPOSITOR` | runner sets `1` | Fail instead of skipping an unavailable compositor |

```text
.build/compositor-tests/current.<unique>/
└─ tests.log    advertised globals / failures / explicit skips
```

The tests may open windows. Missing required globals, test failures, and timeouts
fail the run. Cancellation stops the test process, not the compositor. Popup tests
map the parent first, as required by `xdg_popup`.

A dma-buf global alone is not proof that the driver can allocate/import buffers:
GPU tests must complete when enabled, rather than converting allocation failures
into skips.

## Compositor coverage

| Compositor | Status |
| --- | --- |
| Hyprland | Current development/test session, including GPU presentation |
| Sway / Weston / other compositors | Not specifically tested; no compositor-specific coverage is maintained |

Live output hotplug and scale transitions are not specifically tested. Their
protocol event handling is covered by deterministic peers below.

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

These peers control event order without relying on a compositor's timing. Tests
against the current session complement them; they do not attempt to make a
compositor reject valid buffers or delay releases nondeterministically.
