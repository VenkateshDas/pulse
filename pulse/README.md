# Pulse for Mac

Native macOS command center for performance and storage. v0.9 — Dev Mode shipped.

Spec: [../docs/product_spec.html](../docs/product_spec.html) · Design: [../docs/design_mockups.html](../docs/design_mockups.html)

## Requirements

- macOS 14+
- Swift 6 toolchain (Command Line Tools are enough; Xcode not required)

## Layout

- `Sources/PulseKit` — UI-independent collection core (CPU, memory, disk, processes). No subprocesses, ever; everything reads kernel APIs directly (`host_processor_info`, `host_statistics64`, libproc).
- `Sources/CPulse` — C shim exposing `libproc.h` to Swift.
- `Sources/Pulse` — SwiftUI app: menu bar extra + dashboard window (HALO design system).
- `Tests/PulseKitTests` — Swift Testing suite for the core.

## Develop

Always go through `make` — it applies two workarounds for the broken
Command Line Tools 26.5 install on this machine (stale PackageDescription
private interfaces; missing Testing.framework search paths). Details in the
[Makefile](Makefile).

```sh
make build           # debug build
make test            # run core tests
make run             # run the app from terminal
```

## Ship a local .app

```sh
make bundle          # → dist/Pulse.app (ad-hoc signed)
open dist/Pulse.app
```

## Performance budget

Menu bar + dashboard combined: **< 1% CPU, < 50 MB RSS** while sampling every 2 s.
One shared sampling loop feeds all views; opening more UI never adds samplers.

Measured (Apple M2, 60 s `cputime` deltas): ~0.5% window closed, ~1.3% dashboard
visible, ~30 MB footprint. Hard-won rules that keep it there:

- Never attach `.animation` to data-driven values — every animation frame re-runs
  the entire hosting view's layout (a 0.3 s spring per 2 s sample cost ~12% CPU).
  Springs are for user-initiated transitions only.
- Publish snapshots only while something is on screen: closed-but-alive windows
  and the lock screen (which does **not** change NSWindow occlusion state) both
  keep re-rendering otherwise.
- Keep changing text layout-stable: monospaced, fixed-width formats.
