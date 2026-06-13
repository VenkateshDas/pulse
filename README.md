<div align="center">

<img src="pulse/Sources/Pulse/Resources/Logo.png" width="120" alt="Pulse logo" />

# Pulse

**Native macOS system monitor — CPU, memory, disk, network & battery in one menu bar app.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white)](https://github.com/VenkateshDas/pulse/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/VenkateshDas/pulse?include_prereleases&label=release)](https://github.com/VenkateshDas/pulse/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[**Download for Mac →**](https://github.com/VenkateshDas/pulse/releases/latest)

</div>

---

> **Beta note:** Pulse is ad-hoc signed. On first launch right-click → **Open** to bypass the Gatekeeper warning.

---

## Features

- **Menu bar vitals** — CPU %, memory pressure, network throughput, battery state at a glance
- **Dashboard** — real-time charts, per-core CPU heatmap, top processes by CPU/memory
- **Storage vault** — treemap of disk usage, smart-scan for reclaimable space (caches, venvs, node_modules)
- **Smart Clean** — safety-checked bulk delete with a preview vault before anything is removed
- **Health score** — single composite score from thermals, memory pressure, disk health, and battery wear
- **Timeline** — per-minute history charts for CPU, memory, disk I/O, and network
- **Dev Mode** — process-level sampler with µs-resolution CPU accounting
- **Weekly report** — summarized resource usage across the past 7 days
- **Zero overhead** — <1% CPU, <50 MB RSS while sampling every 2 s

## Install

### Download (recommended)

1. [Download the latest `.dmg`](https://github.com/VenkateshDas/pulse/releases/latest)
2. Open DMG → drag **Pulse** to Applications
3. First launch: **right-click Pulse.app → Open**

> If macOS still blocks it: `xattr -dr com.apple.quarantine /Applications/Pulse.app`

### Build from source

**Requirements:** macOS 14+, Xcode Command Line Tools

```sh
xcode-select --install          # if not already installed

git clone https://github.com/VenkateshDas/pulse
cd pulse/pulse
make bundle                     # → dist/Pulse.app
open dist/Pulse.app
```

## Architecture

| Module | Role |
|--------|------|
| `Sources/PulseKit` | UI-free data collection core. CPU, memory, disk, network, battery, processes. Reads kernel APIs directly — zero subprocess calls. |
| `Sources/CPulse` | C shim bridging `libproc.h` to Swift. |
| `Sources/Pulse` | SwiftUI app — menu bar extra + multi-pane dashboard (HALO design system). |
| `Tests/PulseKitTests` | Swift Testing suite for the collection core. |

## Performance

One shared sampling loop feeds all views. Opening more panes never adds samplers.

| Scenario | CPU | RSS |
|----------|-----|-----|
| Menu bar only | ~0.5% | ~30 MB |
| Dashboard open | ~1.3% | ~30 MB |

Measured on Apple M2, 60 s `cputime` deltas.

## Build commands

```sh
make build      # debug build
make test       # run test suite
make run        # run from terminal
make bundle     # → dist/Pulse.app (ad-hoc signed)
make dmg        # → dist/Pulse-x.y.z.dmg
```

## Contributing

Bug reports and feature requests welcome — open an [issue](https://github.com/VenkateshDas/pulse/issues).

Pull requests: open an issue first to discuss the change, then submit a PR against `main`.

## License

MIT — see [LICENSE](LICENSE).
