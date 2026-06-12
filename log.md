# Repository Evolution Log

This is a chronological, append-only record of significant changes, updates, and maintenance tasks performed by AI agents on this repository.

## [2026-06-12] ingest | Transitioned repository to Pulse
- Archived the old Python TUI app (`mac-monitor`) into the `legacy_tui/` directory.
- Established the LLM Wiki structure (`index.md`, `log.md`, `AGENTS.md`).
- Integrated Graphify to generate a knowledge graph of the `pulse` application.
- Updated root `README.md` to reflect the transition to Pulse.

## [2026-06-12] update | Product Specification updated to v2.0 in place
- Deep-analysed the full codebase (16 PulseKit files, 10 Views, 2 Models, 2 test files).
- Updated `docs/product_spec.html` in place to v2.0: authoritative spec covering shipped v0.2 state and M3–M6 milestone specifications.
- Spec includes: data model tables, UI layout contracts, new type signatures, alert rules, design constants, test requirements, and 4 open architecture decisions.

## [2026-06-12] fix | Dashboard disk card value aligned with Storage tab
- Modified `pulse/Sources/Pulse/Views/DashboardView.swift` to calculate and display the used and total space matching the Storage tab header's `used / total` format.
- Verified mathematically consistent numbers shown in both pages.

## [2026-06-12] update | Process RAM displayed in Top Processes panel
- Modified `pulse/Sources/Pulse/Views/TopProcessesPanel.swift` to add a new column displaying process resident memory usage in MB/GB.
- Adjusted CPU bar widths to keep the layout compact and clean.
- Updated header text to "CPU · RAM".

## [2026-06-12] update | Scrollable full processes list in Dashboard
- Changed default topProcessLimit in PulseEngine to 1024 to capture all processes.
- Wrapped process row list in ScrollView + LazyVStack in TopProcessesPanel.swift for scrolling performance.
- Renamed header title to "PROCESSES".

## [2026-06-12] update | Granular RAM breakdown in Dashboard
- Extracted active (App), wired, and compressed memory statistics from `host_statistics64` in `MemorySampler.swift`.
- Passed the granular byte counts through `SystemSnapshot` into the UI.
- Replaced the generic memory pressure string in the `MEMORY` card with exact byte breakdowns for App, Wired, Compressed, and Swap to clarify system memory consumption.

## [2026-06-12] update | Dashboard space optimization and larger fonts
- Replaced the oversized bottom CPU chart with a compact layout.
- Added a new `CoreHeatmap` component showing per-core CPU utilization below the main CPU chart.
- Increased the width of the Top Processes panel to reduce process name truncation.
- Added an inline color legend (`● App ● Wired ● Comp`) directly below the MEMORY sparkline.
- Replaced the failing ring segment tooltips with whole-card tooltips (`cardTooltip`) on all 4 KPI cards.
- Increased the base font sizes across `VitalCard` elements (titles, main values, and details) for better desktop readability.

## [2026-06-12] update | CPU and Memory Usage 30-minute charts
- Refactored `HistoryChart` to support custom line colors and scaling bounds.
- Decreased the CPU history chart window from 24H to 30M, providing a live continuous sparkline layout.
- Added a Memory Usage (RAM) chart beneath the CPU chart showing system memory pressure percentage.
- Added a unified, shared X-axis indicating the 30m trailing window and live tick.
- Unified the height of all four KPI VitalCards using `maxHeight: .infinity` and flexible spacers so they consistently stretch to match the tallest sibling card.
- Added context-aware summary tooltips with an `info.circle` icon next to all dashboard section titles (`PROCESSES`, `PER-CORE`, `NEEDS ATTENTION`, etc.).

## [2026-06-12] Added Network & Power Charts | Redesigned the chart area into a dense 2x2 grid featuring new sudoless Network (getifaddrs) and Power (SMC PSTR) tracking, aligning with btop/macmon aesthetics.

## [2026-06-12] feature | M4 Clean module shipped (v0.6)
- Added `PulseKit/CleanScheduler.swift`: `CleanSchedule` (daily/weekly/monthly, 03:00 anchor), `CleanRecord`, and the `CleanScheduler` actor — schedule persisted at `~/Library/Application Support/Pulse/clean_schedule.json`, append-only history at `clean_history.jsonl`. `runNow` scans the safe tier via SmartScanner and stages everything into the SafetyVault (record links to the VaultSession for restore).
- Added `Pulse/CleanModel.swift`: NSBackgroundActivityScheduler trigger (interval = half the schedule period), due-run check at launch, UserNotifications guarded behind `Bundle.main.bundleIdentifier != nil` (bare `make run` executables trap otherwise).
- Added `Pulse/Views/CleanView.swift`: AUTO CLEAN card (frequency pills, next/last run, Run Now, auto-clean + notify toggles), CLEAN HISTORY with one-click Restore / confirmed Purge per run, and a dry-run PREVIEW of the next scheduled run. Clean enabled in sidebar + routed in RootView.
- 6 new tests in `CleanTests.swift` (45 total, all passing). Verified live: run → 263 MB staged → restore → all 4 dirs back at original paths, vault empty.
- Gotcha refound: stale `dist/Pulse.app` relaunched by macOS resume shadowed the new build during UI verification — pkill + re-bundle before judging UI.

## [2026-06-12] feature | M5 Monitor module shipped (v0.7)
- **PulseKit/MonitorEngine.swift**: `MonitorEngine` actor per spec — `sample(sortKey:ascending:)` (cpu/memory/threads/pageFaults/name/pid), `tree()` (parent-child via `proc_bsdinfo.pbi_ppid`, children CPU-desc), `networkDeltas()` (per-interface en* bytes/sec; idle zero-lifetime-byte interfaces dropped), plus `parents()`/`names()` helpers. New types `ProcessExtendedSample` (virtual bytes, threads from `pti_threadnum`, page-fault rate from `pti_pageins` delta), `ProcessNode`, `NetworkSample`. One pid-walk shared across all methods via 500ms collection cache.
- **Gotcha**: `proc_name()` is permission-gated (returns 0 for launchd/other users) but `proc_pidpath()` isn't — basename fallback keeps parent names real. Recorded in spec Lessons Learnt.
- **Pulse/MonitorModel.swift**: lazy pane — 2s sampling loop runs only while page visible AND window unoccluded (RootView occlusion hook). Selected-process 60-tick CPU history, network in/out history, SIGTERM quit with feedback, selection cleared honestly when process exits.
- **Pulse/Views/MonitorView.swift**: process list card (LIST/TREE toggle, sort menu + direction, name filter — filter forces flat list), detail card (facts grid, parent name, CPU sparkline, Send Quit behind confirmation), network card (per-interface rows + dual autoscaling chart, download ion / upload volt).
- **Verified live via pilot**: list/tree/sort/filter/select all exercised; Send Quit on a sacrificial `sleep` process → confirmed dead via `pgrep`; parent shows "launchd"; only en0 listed after idle-interface fix.
- **Tests**: 7 new in MonitorTests.swift — 52/52 pass.
- **Perf**: engine 6.7ms CPU per tick (0.33%). Page-visible app CPU 5.8–6.4% vs dashboard 6.6% in the same session → page adds ≈0; absolute numbers inflated by heavy ambient load (agent session at 40%+ CPU). RSS 121–155 MB (pre-existing retention pattern). Flagged in spec 13.3 for quiet-system re-measure.

## [2026-06-12] feature | M6 Health module shipped (v0.8)
- **PulseKit/HealthSampler.swift**: `BatteryHealth` struct per spec; pure `BatteryDecode.battery(from:)` (testable without IOKit, same pattern as SMCDecode) reading AppleSmartBattery registry props (~2ms, never system_profiler). Apple Silicon reports `CurrentCapacity` as a percentage (MaxCapacity pinned 100), Intel raw mAh — both handled. Gauge "unknown" sentinel 65535 minutes → nil. `condition` derived: PermanentFailureStatus ≠ 0 or capacity < 80% → "Service Recommended" (registry has no readable BatteryHealth key).
- **Startup items**: `StartupItem` with Kind `.userAgent`/`.globalAgent` — login items intentionally absent (no public API enumerates third-party login items; SMAppService = own app only, BTM store private; UI header says so). Toggle = rename `foo.plist` ⇄ `foo.plist.disabled` (launchd only loads *.plist; reversible, sudo-free, next-login effect). Global agents read-only with lock icon.
- **PulseKit/Benchmark.swift**: `Benchmark` actor — CPU SHA256 loop (5s, CryptoKit), 50 MB sequential write + `F_FULLFSYNC` (without it the write "finishes" in RAM and the number is fiction), 256 MB memcpy (pages pre-touched so it measures bandwidth, not zero-fill faults). Transparent score: mean of phase ratios vs fixed M1-class references × 1000. `BenchmarkStore` persists runs (capped 50) at `~/Library/Application Support/Pulse/benchmark-history.json`.
- **PulseKit/BatteryHistoryStore.swift**: one capacity+cycles entry per day, 60-day window, `battery-history.json`.
- **Pulse/HealthModel.swift**: lazy pane — 5s battery loop only while page visible AND window unoccluded; startup items refreshed on appear/toggle; benchmark on demand with running state.
- **Pulse/Views/HealthView.swift**: battery card (charge bar with bolt, %, state, time-to-event, capacity/cycles/condition facts), gap-honest 60-day capacity chart (dots per daily reading, line only across consecutive days, 70–100% y-scale), startup items table with next-login toggles + feedback, benchmark card (score + delta vs previous run, three phase throughputs). Health enabled in sidebar + routed in RootView; HealthModel wired into PulseApp + occlusion hook.
- **Tests**: 15 new in HealthTests.swift (battery decode fixtures incl. Intel scaling + sentinel + desktop nil, plist parse, toggle rename round-trip, global-agent refusal, history daily throttle + 60d prune, tiny benchmark run, score formula). 67/67 pass.
- **Verification**: build + tests green; live UI verification handed to user (both Pulse instances pkilled — launch fresh via `make run`). Perf not yet measured on quiet system — tracked in spec 13.5.

## [2026-06-12] update | Rebuilt Graphify knowledge graph and verified M6
- Re-ran `graphify update pulse` to regenerate the codebase structure including `HealthSampler`, `BatteryHistoryStore`, `Benchmark`, and related views.
- Verified all code implementations, tests (67/67 passing), and product specification documents for M6 feature parity.

## [2026-06-12] fix | Capacity trend chart overlap and line segmentation
- Fixed a UX overlap bug in `CapacityTrendChart` where a single historical dot on the right edge was drawn immediately next to the right-side grid labels (e.g. `80 •`), making it look like a list bullet and appearing "broken" or empty.
- Shifted grid labels (`100`, `90`, `80`) to the left of the chart area, started grid lines at `x: 20`, and scaled data points to the range `[20, size.width - 8]` to prevent overlap and clipping.
- Relaxed the gap threshold from 1.5 days to 5.0 days to prevent weekends/holidays from fragmenting the line chart into disconnected dots.
- Conditionally hid the capacity trend card on desktop Macs where the battery is unavailable, letting the battery card scale to full width.

## [2026-06-12] fix | Silenced CleanScheduler unused result warning
- Silenced a Swift compiler warning in `CleanScheduler.swift` about the unused result of `try? handle.seekToEnd()` by explicitly ignoring the returned value with `_ =`.
- Verified the fix builds cleanly without warnings under both debug and release configurations.

## [2026-06-13] feature | Battery history backfilled using pmset on startup
- **BatteryHistoryStore.swift**: Added `backfillFromSystemLog()` method that executes `/usr/bin/pmset -g log` asynchronously on a background thread. Reconstructs previous 60 days of battery usage from awake/sleep power events, handling multi-day session splits and merging with existing history.
- **DashboardModel.swift**: Triggers the history backfill on startup in a detached Task, updating the observable `batteryTrend` property when finished to refresh the UI.
- **Strict Concurrency**: Fixed strict-concurrency check failures in Swift 6 by isolating pmset log execution and state machine parsing to non-capturing global functions.

## [2026-06-13] feature | M7 Dev Mode module shipped (v0.9)
- **PulseKit/SMCSensors.swift**: Added `dumpAll()` method to iterate through all readable keys instead of using a hardcoded list. Decodes values generically as float, integer, or hex fallback.
- **PulseKit/DevModeSampler.swift**: Created an actor to safely sample `sysctlbyname` (string, int32, int64), process file descriptor counts via `proc_pidinfo(..., PROC_PIDLISTFDS, ...)`, and SMC dump efficiently without subprocesses.
- **Pulse/DevModeModel.swift & Pulse/Views/DevModeView.swift**: Designed a dense 3-panel layout conforming to HALO system aesthetics for a diagnostic console. The panels auto-refresh every 5 seconds while visible.
- **Sidebar Integration**: Unlocked the Dev Mode tab in `SidebarView` and `RootView`. Silenced an unneeded `default` case warning in the Sidebar exhaustive switch.
- **Verification**: Built using `make build` and ran 67 tests successfully in under 1.5s using `make test`.

