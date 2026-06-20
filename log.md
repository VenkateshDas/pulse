# Repository Evolution Log

This is a chronological, append-only record of significant changes, updates, and maintenance tasks performed by AI agents on this repository.

## [2026-06-20] fix | Removed shell subprocesses in Bluetooth and Proxy samplers
- **Context**: The `ponytail-audit` identified bloat and subprocess usages in samplers.
- **Changes**: Replaced `system_profiler` in `BluetoothSampler` with `IOBluetoothDevice` + `IOKit` `IORegistry` parsing. Replaced `scutil --proxy` in `ProxySampler` with `SystemConfiguration` `CFNetworkCopySystemProxySettings`.
- **Lessons Learnt**: The `ByteFormat` and `CString` "bloat" identified by the audit were actually necessary platform workarounds. `ByteCountFormatter` breaks deterministic formatting needed for tests and UI, and `String(cString: [CChar])` is explicitly deprecated. These changes were reverted after tests failed.

## [2026-06-15] fix | ProcessSampler CPU% was ~42× under-reported (latent bug)
- **Found while verifying F5.** Per-process CPU% divided raw `pti_total_*` by a wall delta that had been converted to nanoseconds via the mach timebase — but `pti_total_user/system` and `mach_absolute_time()` are **both in mach-absolute units**, so converting only the wall side inflated it by `numer/denom` (125/3 ≈ 41.7×) on Apple Silicon. A core-pegging `yes` reported ~2% instead of ~98%.
- **Lesson**: the earlier "[2026-06-14] CPU% timebase fix" in this log was itself the regression — it *added* the timebase conversion believing pti was in ns. It is not. Comparing the two raw deltas is unit-free and correct; no conversion belongs here.
- **Impact**: this had silently disabled the old 80%-threshold cpu-hog alert and F1's culprit attribution (50% floor) — nothing ever crossed the bar. All now work; verified live (`yes` → 98%, windowed watcher fires at 60 s).
- **`ProcessSampler.swift`**: removed the `mach_timebase_info` conversion; `wallDelta = now &- previousSampleAt`.

## [2026-06-15] feat | Pulse × Mole super-spec — Phases 1–5 shipped
Implemented `docs/pulse-mole-super-spec.html` one phase per PR (branch → CI green → user approval → merge). Each below is its own merged PR.

- **Phase 1 · F1 — Diagnosis + Health Score** (PR #8). New `DiagnosisEngine` (mole's CPU→mem→disk→battery→thermal cascade, names the leading process as culprit) and `HealthScore` (weighted CPU 30 / Mem 25 / Disk 20 / Thermal 15, piecewise penalty curve). Disk-IO factor declared but excluded until a sampler exists; weights renormalize over available factors. UI: Dashboard hero ring + verdict + culprit→Monitor deep-link, menu-bar HUD, Health "what's costing you" breakdown. **Decision**: compute every 2 s tick in `DashboardModel`, not on demand.
- **Phase 2 · F2 — Optimize engine** (PR #9). `OptimizeEngine` (typed dry-run-aware tasks, skip checks, VPN guard ported verbatim from mole, 5-entry refusal manifest), Disk → Optimize tab. 4 safe in-process tasks (saved-state→Trash, QuickLook, DNS, Launch Services). **Key decision — privilege**: first built an `SMAppService` privileged XPC daemon; it *cannot register under a self-signed local cert* (needs a Developer-ID Team identifier), so it never worked locally. Replaced with **Authorization Services** (`osascript … with administrator privileges`) — the GUI equivalent of `sudo`, works under any signing. **Lesson**: SMAppService daemons are a paid-account-only path; for local-testable elevation use Authorization Services. Security kept via the closed `PrivilegedOperation` whitelist (fixed absolute paths + literal args, single-quoted, no caller input → no injection). Also fixed an Xcode-26.3 strict-concurrency error (per-call XPC connection, no cross-actor mutable state) before the pivot.
- **Phase 3 · F3 — Orphan scanner** (PR #10). The residue-name orphan scan already existed; added launchd jobs that **load a now-missing binary** (the name scan can't catch those), `launchctl bootout` (gui domain) on disabling a user agent, and auto-rescan of orphans after an uninstall (self-healing). **Lesson**: check the existing codebase before building a spec item — F3 was ~80% already there; shipped only the genuine delta.
- **Phase 4 · F4 — Disk insights** (PR #11). `InsightScanner` (curated hidden-space targets, bounded 8-way concurrency, Downloads >90 d mtime filter, wildcard path resolution) + Disk sub-tab **renamed "Hidden Space"** (user feedback: "Insights" was wrong). Time-diff half already ships via the Timeline tab, so not rebuilt.
- **Phase 5 · F5 — Process watch** (PR #12). `ProcessWatcher` (sustained 50 %/60 s; identity `(pid, name)` since `ProcessSample` carries no ppid; clock resets on cooldown) replaces the instantaneous cpu-hog alert; `AnomalyStore` (30-day JSON) feeds a "Process anomalies" section in Timeline. Surfaced — and fixed — the ProcessSampler bug above.

**Cross-cutting lessons**: (1) bundle/sign realities gate macOS privilege design — verify locally before committing to SMAppService; (2) CI runs a newer/stricter Swift toolchain than the local one — strict-concurrency errors surfaced only in CI; (3) reuse existing stores/UI (Timeline, Trash) instead of duplicating; (4) `docs/` is gitignored (dev-only) so the spec/product docs aren't versioned.

## [2026-06-14] feat | Timeline repurposed as Daily Health Journal (v1.0)
- **Motivation**: Original Timeline showed disk-only data; showed "Collecting" with <2 days of data and provided no value on fresh install. Replaced with a multi-signal daily journal matching patterns from iStatistica Pro, coconutBattery, and Usage (iOS).
- **`TimelineView.swift`**: Complete rewrite — 3 permanent sections + 2 conditional:
  - **Week Summary card** (always visible, even day 1): total disk growth, total/avg battery hours, benchmark score.
  - **TODAY card** (highlighted, cyan border): live disk used (from `SystemSnapshot`) + today's delta, battery hours + active time window (e.g. `9:00am–11:30pm`), system uptime. Benchmark event row appears if a benchmark ran today.
  - **Past Days card**: compact newest-first rows — date, disk delta (▲/▼ with proportional bar), battery hours + time window, `SPIKE` badge on >2 GB jumps (tap → navigates to Clean).
  - **Disk trend chart**: appears only when `snapshots.count >= 7` (no more useless flat line on day 1).
  - **Category breakdown**: kept at bottom, only when scan data available.
- **Data join**: Per-day entries union `TimelineStore` (disk snapshots) with `DashboardModel.batteryTrend` (battery sessions) — both are keyed by calendar start-of-day.
- **`HealthModel`**: Added `benchmarkHistory: [BenchmarkResult]` (exposes `BenchmarkStore.results`) so Timeline can annotate benchmark events per day.
- Build clean, 67/67 tests pass.

## [2026-06-14] update | Health page: dock icon + battery intelligence + layout
- **Dock icon**: `LSUIElement` → `false` in `scripts/bundle.sh` (canonical source); `PulseApp.init` always sets `.regular` activation policy. App now shows in dock and responds to Cmd+Tab.
- **`BatteryHealth` (HealthSampler.swift)**: Added `powerWatts: Double?` (from IOKit `InstantAmperage` mA × `Voltage` mV ÷ 1 000 000; `>0.5W` threshold to suppress idle noise) and `cyclesRemaining: Int` (Swift.max(0, 1000 − cycleCount), per Apple's 1000-cycle service guideline).
- **`BatteryHistoryStore.Entry`**: Added `firstActiveAt: Date?` and `lastActiveAt: Date?`. `addTimeOnBattery(_:at:)` refactored off the generic helper to update these timestamps inline — gives per-day battery session window (e.g. "9:00am–11:30pm").
- **Health page layout**:
  - Battery card: 6-fact 2-row `LazyVGrid` — `CAPACITY`, `CYCLES`, `CONDITION`, `POWER DRAW`, `CYCLES LEFT` (green >500, amber >150, red ≤150), `THERMAL` (from `ProcessInfo.thermalState`). Frame 140→185px to fit content.
  - `BatteryStatsCard` (new): shown when capacity trend has <2 readings — 3-column card with Capacity Health %, Cycle Health (N left), and Capacity Trend status. Replaces useless "Collecting" empty state.
  - `BatteryConsumptionCard` row: shows time window + proportional usage bar per day.
  - `BatteryStatsCard` divider: 1px `Rectangle.fill(Halo.surface2)` replacing broken `Divider().overlay(...)`.
  - Header: spacing 4→6, `.padding(.bottom, 4)` added; outer VStack spacing 16→20 for clearer card separation.
- Build clean, 67/67 tests pass.

## [2026-06-14] update | Dashboard KPI cards: footer stat chips on CPU/Disk/Thermal
- Added an optional `stats: [Stat]` slot to `VitalCard` (small `LABEL value` pairs styled like the existing MEMORY legend), filling the dead space under cards that lack a legend so all four KPI cards are equal height and information-dense.
- **CPU**: `TOP <proc> <n>%` (biggest live consumer, name capped 12 chars) + `BUSY <busy>/<total>` cores ≥20% loaded (amber when all pegged).
- **DISK**: `FREE <bytes>` + `FULL IN ~Xwk/mo/y` — projects `diskWeeklyGrowthBytes` forward to estimate runway (amber under 8 weeks); `TREND stable` when growth ≤ 0. Falls back to FREE-only until a week of growth data accrues.
- **THERMAL**: `HEADROOM <n>°` to the ~90 °C Apple-Silicon throttle ceiling (amber <25°, red <10°) + `TREND rising/steady/falling` from `tempHistory`.
- All values reuse existing `SystemSnapshot` fields — no new sampling, no subprocess, hot path untouched. Build clean, 67/67 tests pass.

## [2026-06-14] fix | Codebase review: 7 correctness/security fixes across PulseKit + Views
- **CPU% timebase (ProcessSampler.swift, MonitorEngine.swift)**: per-process CPU% divided `pti_total_*` (nanoseconds) by a `mach_absolute_time()` delta (mach ticks, ≈24 MHz on Apple Silicon) — inflating every reading ~40× on M-series (correct only on Intel where the units coincide). Now converts the wall delta to ns via a cached `mach_timebase_info` before the busy/wall ratio.
- **Vault freed-byte accounting (SafetyVault.swift)**: `purgeOldestIfNeeded`/`purgeExpired` credited `session.totalBytes` to "freed" *before* a `try?`-swallowed `removeItem`, overstating reclaimed space (and breaking disk-pressure relief) when a file was locked/SIP/read-only. `purge` now returns whether the dir is actually gone; bytes are credited only on success.
- **Vault protected-path guard (SafetyVault.swift)**: added `isProtected()` defense-in-depth at the stage/restore boundary — refuses system locations (`/System`, `/usr`, `/etc`, LaunchDaemons/Agents, `/Applications`) and top-level user-data roots (Documents/Desktop/iCloud/CloudStorage), independent of scanner grading. Stops a tampered manifest turning restore into arbitrary file placement.
- **Trash cleaning (SmartScan.swift)**: `.Trash` was graded `.safe` and pre-selected, so Smart Clean moved the *entire* `~/.Trash` directory into the vault — burying items and breaking Finder "Put Back". New `expandTrash` stages each trashed item individually; the `.Trash` directory itself is never moved.
- **Storage double-count (StorageScanner.swift)**: `scanSizesStream` added directory children to `resolvedBytes` AND re-summed every directory in the `newTotal` loop, double-counting any pre-sized dir (e.g. from a deep scan) and inflating parent totals. Directories are now summed once.
- **Treemap color crash/instability (TreemapView.swift, StorageView.swift)**: `abs(String.hashValue) % palette` could trap on `Int.min` and produced different colors every launch (per-process hash seed). Replaced with a stable FNV-1a `String.paletteIndex`, used by both the treemap and its legend so they always agree.
- **pmset parse robustness (BatteryHistoryStore.swift)**: replaced blind `line.prefix(25)` date slicing with a regex matching a leading `yyyy-MM-dd HH:mm:ss ±ZZZZ` stamp — tolerant of leading whitespace / offset-width drift instead of silently returning an empty 60-day battery chart.
- **Investigated & refuted**: the CPU-hog "% of total load" math in `Alerts.swift` — `hog/(avgCorePct × cores)×100` is dimensionally correct since `cpuTotalPercent` is a per-core average; its earlier-looking garbage was a symptom of the CPU timebase bug, not Alerts. Left untouched.
- Verified via `make build` + `make test` (67/67). The protected-path guard initially used real `NSHomeDirectory()` and rejected the test harness's temp home; reworked to a system-prefix + user-root denylist that defends the real attack surface without assuming a fixed home.

## [2026-06-13] fix | Resolved Swift 6 String(cString:) deprecation warnings
- Modified `StorageScanner.swift` to use `.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }` instead of the deprecated array overload for `String(cString:)`, clearing all compiler warnings.

## [2026-06-13] fix | Fixed storage map sizing and legend visibility
- Modified `StorageScanner.scanLevel` to compute the sizes of subdirectories using `fastDirectorySize` so the Storage view displays proper squarified sizes instead of 0 bytes.
- Wrapped the Storage view legend in a semi-opaque background capsule to ensure color contrast over the dense treemap.

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

## [2026-06-13] feature | Async Progressive Storage Scanning
- Refactored `StorageScanner.swift` to use an `AsyncStream` and `TaskGroup` to lazily compute directory sizes in parallel.
- Updated `StorageModel.swift` to decouple the blocking `SmartScanner` run and consume the `scanSizesStream` to progressively update the UI.
- Treemap blocks now draw instantly and organically resize as true sizes are resolved, eliminating the long "Scanning disk..." spinner UX.

## [2026-06-13] feature | Safety Vault flat file-viewer redesign
- **Flat UI**: Removed rigid `VaultSession` grouping in favor of a modern flat file-viewer list.
- **Granular Restores**: Rewrote `SafetyVault.swift` to support item-level purge and restore without touching the rest of a session's files.
- **Multi-select**: Added custom checkboxes, "Select All", and a dynamic morphing header bar.
- **Bottom Bar**: Added explicit `Used / Purgeable / Free / Total` breakdown to clear up Apple's free space math mystery. Reverted dummy file hacks to maintain pure APFS semantics.

## [2026-06-14] feature | M9 App Uninstaller shipped (drag-to-remove + orphan scan)
- **PulseKit/UninstallScanner.swift**: New pure-FileManager/Bundle/Spotlight scanner (zero subprocess). Reads `Info.plist` for `CFBundleIdentifier`/`CFBundleName`/`CFBundleDisplayName`, derives the reverse-DNS vendor prefix and ≥4-char name tokens (`AppIdentity.make`). `classify(name:identity:)` grades each residue match by confidence: bundle-ID containment → SAFE, vendor-prefix / exact-display-name folder → CAREFUL, weak name-token substring → REVIEW (the Pearcleaner false-positive guard, `com.apple` vendor denylisted). `scanLeftovers` sweeps ~12 `~/Library` + `/Library` residue dirs (plus system LaunchDaemons/PrivilegedHelperTools) shallowly, surfaces `/var/db/receipts` read-only, caps the REVIEW tier at 25. `scanOrphans(resolver:)` flags residue whose reverse-DNS bundle ID no longer resolves via an injected LaunchServices lookup. `installedApps()` enumerates `/Applications`, `/Applications/Utilities`, `~/Applications` with `kMDItemLastUsedDate`.
- **Pulse/UninstallModel.swift**: `@MainActor @Observable` flow. App bundle → system Trash via `NSWorkspace.recycle` (Finder "Put Back"); ticked leftovers → one `SafetyVault` session — so the `/Applications` denylist stays fully intact. Running-app hard guard (`NSRunningApplication`). Orphan tab stages selections to the Vault.
- **Pulse/Views/UninstallView.swift**: Drop zone (`dropDestination(for: URL.self)` — MainActor-clean), searchable installed-app list, plan detail with grade sections mirroring Smart Clean, and an Orphans tab. New `.uninstall` sidebar item + RootView route + `UninstallModel` env injection + "Scan Orphaned Files" command-palette entry.
- **Tests**: `Tests/PulseKitTests/UninstallTests.swift` — classification grades, false-positive rejection, identity/token derivation, leftover grading across library locations, orphan detection, and bundle-ID extraction (only known extensions stripped so `com.foo.bar` survives). 81 tests green via `make test`.

## [2026-06-14] feature | Uninstaller post-action receipt (Verify beat)
- **Pulse/UninstallModel.swift**: Added `UninstallResult` struct + `result` property. `uninstall()` now captures the real `VaultSession` and builds a receipt from reality — staged rows are the session's actual contents (a row only exists if its move succeeded), app row reflects the true `recycle` result, plus `failedCount` and `reviewLeftCount`. `restoreLastUninstall()` (Vault session restore; app via Finder Put-Back) and `dismissResult()`. Replaced the transient one-line `uninstallReport` string.
- **Pulse/Views/UninstallView.swift**: New `UninstallResultCard` — green success header, app→Trash row, itemized "STAGED IN VAULT" list (label · original path · size), honest notes for skipped/failed, and Restore-everything / Done actions. `uninstallTab` routes to it when `result != nil`.
- **docs/product_spec.html §3.14**: Added the "Verify step" bullet documenting the receipt.
- Build + 84 tests green via `make`.

## [2026-06-14] feature | Uninstaller Full Disk Access recovery + retry
- **Pulse/UninstallModel.swift**: `UninstallResult` now keeps `failedItems: [PendingItem]` and `sessionIDs: [UUID]` (was a single id) with `needsAttention`. `retryUninstall()` re-attempts only the failed app move + unstaged leftovers and merges into the existing receipt. `openFullDiskAccessSettings()` deep-links to Settings → Privacy & Security → Full Disk Access. `restoreLastUninstall()` restores across all sessions.
- **Pulse/Views/UninstallView.swift**: Receipt gained a "PENDING — NEEDS FULL DISK ACCESS" section listing blocked items, an explanatory note, and Grant-Full-Disk-Access + Retry buttons (shown when `needsAttention`).
- **docs/product_spec.html §3.14**: Documented the FDA recovery flow.
- Build + 84 tests green via `make`.

## [2026-06-14] fix | Uninstaller app-bundle trashing (App Store macl bug)
- **Root cause**: `NSWorkspace.recycle` returns no error but silently fails to move Mac App Store bundles that carry a `com.apple.macl` sandbox xattr (e.g. Amphetamine.app, root:wheel-owned). Granting Full Disk Access doesn't help — `/Applications` isn't TCC-protected; the move only needs write on the parent dir, which admin users have.
- **Fix**: `UninstallModel.moveAppToTrash` now uses `FileManager.trashItem(at:resultingItemURL:)` (same rename into ~/.Trash, keeps Finder "Put Back"), with a direct ~/.Trash rename fallback if even trashItem refuses. Replaced recycle in both `uninstall()` and `retryUninstall()`; dropped the withCheckedContinuation dance.
- Verified the underlying rename works for a root-owned App Store bundle (`mv` round-trip in /Applications succeeded). Build + 84 tests green.

## [2026-06-14] fix | Stable dev code-signing so TCC grants survive rebuilds
- **Real reason Uninstall "needs Full Disk Access" never cleared**: `make bundle` ad-hoc signs (Signature=adhoc, CDHash changes every build). macOS keys TCC grants (Full Disk Access, App Management — the latter gates moving *other* apps' bundles to Trash on macOS 13+) to that hash, so every rebuild silently invalidated the grant even though Settings still listed "Pulse". Not a logic bug — confirmed adhoc signature on dist/Pulse.app.
- **scripts/dev-cert.sh** (new) + `make dev-cert`: creates a self-signed "Pulse Local Signing" identity (openssl, legacy-PBE p12 for macOS import, user-domain codeSign trust). Its designated requirement is stable (`identifier "com.pulse.app" and certificate leaf = H"…"`), so a grant made once persists across rebuilds.
- **scripts/bundle.sh**: signs with "Pulse Local Signing" when present (else Developer ID via SIGN_IDENTITY, else ad-hoc with a warning). CI has neither identity → ad-hoc path, smoke test unaffected.
- Verified end to end: created identity, rebuilt → `Authority=Pulse Local Signing`, stable DR; `tccutil reset …AllFiles/…AppBundles com.pulse.app` to clear stale adhoc records.

## [2026-06-14] fix | Uninstaller trashes App-Management-protected bundles via Finder
- **Symptom**: with FDA granted, the sandboxed *leftover* (~/Library/Containers) finally staged, but the .app bundle still "couldn't be moved to Trash". So it was never FDA for the bundle.
- **Real cause**: macOS 13+ **App Management** protection — a gate SEPARATE from Full Disk Access — blocks a GUI app from moving/deleting *other* apps' bundles (Amphetamine.app is App Store, root:wheel, com.apple.macl). `FileManager.trashItem`/`moveItem` from Pulse is denied; a plain `mv` from a CLI tool isn't subject to the same enforcement, which is why the earlier Terminal test passed.
- **Fix** (`UninstallModel.moveAppToTrash`, now `@MainActor`): try `trashItem` first (silent, ordinary apps); on failure, ask **Finder** to trash via `NSAppleScript` (`tell application "Finder" to delete …`). Finder is exempt from App Management and prompts for admin auth like a manual drag-to-Trash. Apple Events are in-process (no subprocess) but must run on the main thread, so `uninstall()`/`retryUninstall()` now run the trash step on the main actor and stage leftovers via an awaited detached task. Confirms success against the filesystem, not the event result.
- **scripts/bundle.sh**: added `NSAppleEventsUsageDescription` so the Finder automation prompt is shown (required) instead of crashing.
- Build + 84 tests green.

## [2026-06-14] docs | App Uninstaller + permission lessons across all docs
- README.md: added App Uninstaller to Features; documented `make dev-cert` + the local TCC/Finder-Apple-Events testing notes under Build commands.
- AGENTS.md: clarified the zero-subprocess rule (in-process Apple Events allowed for one-shot privileged actions), added `make dev-cert`, mapped the uninstaller files, and added a "Lessons Learnt (macOS permissions & dev signing)" section.
- CONTRIBUTING.md + CLAUDE.md: dev-cert command + permission-gated-feature testing guidance.
- Memory: macos-app-removal-tcc reference.

## [2026-06-14] fix | Code-review pass: 8 uninstaller findings fixed
- **#1 retry running-app guard**: retryUninstall now re-checks `isRunning(bundleID)` before re-trashing (added appBundleID to UninstallResult). Prevents trashing a relaunched app.
- **#2 main-thread freeze**: moveAppToTrash is `nonisolated` again and runs on a detached task (verified NSAppleScript works off-main); only the final state write hops to MainActor. No more UI freeze during the Finder/admin prompt.
- **#3 /Library infinite-retry loop**: any leftover under root-owned /Library (systemLibrary) is now graded REVIEW (not just LaunchDaemons/PrivilegedHelperTools) — never pre-selected, never staged, so it can't become a perpetually-"failed" item. residueRoots tags isSystem; dropped systemOnlyCategories string-set.
- **#4 wrong remedy**: receipt now distinguishes appNeedsAttention (App Management / Finder consent → Retry + approve Finder/admin) from leftoversNeedAttention (genuine FDA → Grant Full Disk Access button). FDA button only shows when leftovers failed.
- **#5 false success**: moveAppToTrash returns true only when the Apple Event reports no error AND the bundle is actually gone; scriptError no longer ignored.
- **#6 anchored matching**: bundleIDAnchored replaces componentRun — bundle ID/vendor must match at the START of the name's components (after optional group.), rejecting infix/suffix false positives.
- **#7 icon cache**: model.icon(for:) memoizes NSWorkspace icons; row builders no longer re-hit LaunchServices every render.
- **#8 lazy size**: installedApps() no longer walks every bundle tree; size computed on selection (describeApp). List load is fast; list omits size until selected.
- Also: extracted shared perform() helper (uninstall/retry dedup). 86 tests green.

## [2026-06-20] feat | Premium HIG redesign with HALO design token system (PR #29)
- **Context**: Full UI overhaul following Apple Human Interface Guidelines research. Created `.claude/skills/macos-design/SKILL.md` — a reusable macOS HIG skill covering typography, colors, spacing, shadows, radii, animations, navigation, accessibility, SF Symbols, and Liquid Glass (WWDC25).
- **Theme.swift**: Upgraded `Halo` enum with full design token system — `Shadow` (card shadow), `Radius` (small/medium/large/xl), `Space` (xs through xxl), `Motion` (snappy spring/smooth easeInOut/ring easeOut). Added `borderSubtle`, `textSecondary` surface tokens. Added `accentGradient()`, `meshBackground` gradient. Added `premiumCard(padding:cornerRadius:)` and `sectionLabel()` view modifiers.
- **SidebarView**: Complete rewrite — `SidebarSection` enum grouping items (Overview/Insights/System/Tools), filled SF Symbol variants, hover states, blue tint active indicator in capsule, "Command Center" subtitle, section headers with tracking.
- **VitalCard**: Hover micro-interaction (glow shadow, scale 1.01, border color shift), fill gradient on MiniLine, rounded rectangle legend items, `.continuous` corners throughout.
- **DashboardView**: 26pt greeting, mesh gradient background, `premiumCard()` for charts panel, all `Halo.Space` tokens.
- **AlertsSection**: Simplified header, LIVE dot shadow glow, 28×28 tinted icon containers, circular dismiss button, `premiumCard()` wrapper.
- **14 secondary views** migrated to `premiumCard()`, `borderSubtle`, mesh backgrounds, 24pt headers: TopProcessesPanel, CoreHeatmap, HealthHero, HistoryChart, Sparkline, CommandPaletteView, MenuBarContent, DiskView, MonitorView, DevModeView, OnboardingView, UninstallView, TimelineView, StorageDetailPanel/Components.
- **MenuBarContent**: Metric labels → `Halo.textSecondary`, dividers → `Halo.borderSubtle`. "Open Command Center" moved from large button to subtle 26×26 grid icon in HUD header adjacent to health score ring.
- **DiskView**: Capsule pill-style tabs with hover states, animated tab switching.
- **RootView**: View transitions (opacity + move), command palette scale transition.

## [2026-06-20] fix | Guard Bluetooth API against missing TCC description on macOS 26
- **Root cause**: `IOBluetoothDevice.pairedDevices()` triggers `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` on macOS 26 when binary lacks `NSBluetoothAlwaysUsageDescription` in Info.plist. SwiftPM debug builds (`make run`) have no Info.plist.
- **BluetoothSampler.swift**: Added guard — returns empty if `NSBluetoothAlwaysUsageDescription` key missing from main bundle.
- **bundle.sh**: Added `NSBluetoothAlwaysUsageDescription` key to generated Info.plist.

## [2026-06-20] fix | BundleGuard case-sensitivity bypass
- **Root cause**: `isProtected()` lowercased input via `bundleID.lowercased()`, but 14 of 22 entries in `protectedBundleIDs` set had mixed case (e.g. "com.apple.Safari"). Swift `Set.contains` is case-sensitive, so these never matched — Safari, Preview, Photos, Notes, etc. were unprotected.
- **BundleGuard.swift**: Lowercased all 22 entries to match the lowercased check.

## [2026-06-20] docs | Added Agent Optimization Modes to AGENTS.md
- **AGENTS.md**: Added Section 7 detailing concise guidelines for using Caveman (communication style) and Ponytail (code structure) agent modes before starting coding work.
- **Global Config**: Installed Ponytail skills suite globally in the user's config directory (~/.gemini/config/skills/).

