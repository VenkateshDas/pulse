# Pulse Knowledge Base Index

Welcome to the Pulse repository LLM Wiki. This file serves as the main catalog for navigating the project.

## Components

- **Ask Pulse harness upgrade (2026-10-11, implemented; review pending):** [Design, source research and architecture options](docs/superpowers/specs/2026-10-11-pulse-agent-harness-design.md) and [implementation sequence](docs/superpowers/plans/2026-10-11-pulse-agent-harness.md). Implements Agno result offloading, isolated runs, user-scoped inspectable memory, native tools and assistant-ui embedded in WKWebView. History replays bounded conversational turns without historical tool payloads, so large skill reads cannot erase dialogue. Renderer snapshots are read in the visible SwiftUI body to register Observation dependencies; provider tool IDs are scoped per run. Provider setup discloses cached performance context shared with the selected model. Live response, skill calls and dialogue recall after restart are verified. Controlled hidden sample: 0.70% CPU, 59.1 MiB RSS; RSS target remains open. Whole-window teardown and allocator trimming were removed after unreliable close/reopen and unproven benefit. Native tool connection deadlines use weak captures so closed sockets release immediately. Provider credentials are endpoint-bound; startup uses a bounded, coalesced off-main Keychain read and passes the result directly to the daemon. Runtime details: `pulse-agent/README.md`; UI: `pulse-assistant/README.md`; shared command execution: `pulse/Sources/PulseCommands/`; authenticated bridge: `AgentNativeBridge.swift`. Branch `feat/pulse-agent-harness` starts from `main` at `a5fdf0d`; Design approved by the user. Interactive performance and visual review are tracked in the implementation sequence.

### [Pulse App](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse/README.md)
The main application: a native macOS command center for performance and storage built with Swift 6.
- **Location:** `pulse/`
- **Design System:** HALO design token system (`Theme.swift`) — `Shadow`, `Radius`, `Space`, `Motion` enums, `premiumCard()` / `sectionLabel()` view modifiers. The accessible redesign uses opaque surfaces, paired light/dark semantic colours, minimum 12pt typography and optional Larger text. Built from Apple HIG research (`.claude/skills/macos-design/SKILL.md`).
- **Sidebar Sections (redesign branch):** Home, Free up space, Apps, Battery & energy, Internet, Displays, Activity; Ask Pulse and Settings; expandable Advanced tools for App activity, Maintenance, Startup helpers, Performance test and Diagnostics.
- **Menu Bar Popover:** Explicit 620pt scroll viewport prevents MenuBarExtra from collapsing to a thin strip; overflow remains scrollable. Review summary, always-visible readings, last download/upload speed with manual retest/stop, Displays and Keep awake. Menu-bar organisation controls remain expanded. Cleanup and maintenance open review; Empty Trash retains explicit confirmation and in-place results.
- **Command Palette (⌘K):** Fuzzy-searchable navigation and quick actions.
- **Sampling:** native unlocked snapshots every 2 seconds; expensive process enumeration remains sparse, publishing only while an explicit window or popover state is visible. Idempotent surface states prevent repeated AppKit occlusion events from leaking visibility.
- **Diagnosis + Health Score (F1):** `DiagnosisEngine` (CPU→mem→disk→battery→thermal cascade, culprit attribution) + `HealthScore` (weighted 0–100, piecewise penalty curve). Plain-language Home and menu-bar condition summaries; numerical health score remains in advanced details.
- **Maintenance (redesign branch):** reviewed task selection in `OptimizeModel`; native saved-window-state Trash moves skip active apps. Legacy shell-backed operations remain visibly unavailable with macOS guidance; no privilege prompt is launched.
- **Orphan Scanner (F3):** Leftover helper files of deleted apps, reviewed Trash moves and auto-rescan after uninstall. Removing a helper file affects its next launch; running jobs are not unloaded.
- **Disk Insights / Hidden Space (F4):** `InsightScanner` — iOS backups, old Downloads (>90d), Xcode/Docker/OrbStack/dev caches, AI tool caches.
- **Process Watch (F5):** `ProcessWatcher` — sustained-threshold detection (50%/60s), `AnomalyStore` for Timeline history.
- **Clean Catalog (F6):** 30+ curated cleanup targets including AI tools (Claude, Codex, Cursor, Copilot, Gemini).
- **Sensors (F7):** GPU utilization (`IOAccelerator` IORegistry, no root), Bluetooth battery (`IOBluetoothDevice` + IOKit), proxy detection (`SystemConfiguration`).
- **Undo Journal (F8):** Every destructive action logged, all deletes via `FileManager.trashItem`, 30-day journal with restore.
- **App Uninstaller (§3.14, M9):** search and review (Finder drop is optional) with confidence-graded leftover matching (`PulseKit/UninstallScanner.swift`, `Pulse/UninstallModel.swift`, `Pulse/Views/UninstallView.swift`). App and selected related files → system Trash, plus a leftover scanner. The redesigned receipt distinguishes moved/failed items and restore limits. GUI native moves use atomic UndoJournal persistence with rollback; Finder permission events run on the main thread only for a denied app move, never to bypass journal failure. Protected by `BundleGuard` allowlist.
- **Displays (Brightness Control):** `BrightnessEngine.swift` (DDC/DisplayServices, adaptive sync), `MediaKeyManager.swift` (IOHIDManager interception via MediaKeyTap), `SoftwareDimmer.swift` (sub-zero overlay), `DisplaySliderView.swift` & `BrightnessOSD.swift` (unified -1 to 1 slider mapped to 0 to 1 with sub-zero visual range). Physical brightness keys routed through Pulse for both built-in and external monitors. Display controls use named native sliders; matching is unavailable without an external screen.
- **Internet:** `NetworkModel.swift`, `NetworkView.swift`, `SpeedTestRunner.swift`, `WiFiSampler.swift`. Native connection readings, manual bounded HTTPS estimates, opt-in automatic tests, explicit network-name permission and cancellable work. Previous test methods are labeled.
- **Menu Bar Action Flash:** `PulseKit/MenuBarFlash.swift` — main menu-bar icon briefly swaps to the triggered action's SF Symbol (keep awake cup, brightness sun, optimize bolt, trash) for 3s on hotkey or UI trigger, then reverts.
- **Menu Bar Stats (multi-select):** `Pulse/MenuBarStat.swift` (CPU / memory / CPU temp / battery, persisted `PulseMenuBarStats`), `Pulse/MenuBarLabelRenderer.swift` — the whole label is drawn into ONE template NSImage (MenuBarExtra flattens SwiftUI labels; see memory `menubarextra-label-flattening`). Values change-gated in `DashboardModel.menuBarValues`. Chips UI in Settings → Menu Bar.
- **Battery Drain Attribution:** `BatteryAttributionEngine` (`PulseKit/BatterySessionStore.swift`) — 7-day cross-session rollup, per-app CPU shares weighted by each session's charge drop; rendered by `BatteryDrainCard` in `HealthView.swift` above the sessions list.
- **Performance test:** explicit temporary workload explanation, native Start action and adaptive results. Fixed reference score is a synthetic comparison, not a health/hardware rating.
- **Startup helpers:** named native switches with pending-change guards, next-sign-in effects, and expandable evidence. Global helpers remain read only; launch helpers are not a complete list of login apps.
- **Launch at Login:** cached in `AppActivation.swift` — `SMAppService.status` validates the code signature via the Security framework and must never run on the main thread (runtime faults); reads return the cache, writes reconcile off-main.
- **Native CLI + Agent Skill:** `pulse/Sources/PulseCLI/` implements all 14 planned commands plus cached speed-test history. `make cli` produces `pulse/dist/cli/pulse`; `make install-cli` installs `pulse`. SwiftPM product is `pulse-cli` to avoid a case-insensitive collision with GUI `Pulse`. App-owned sleep/display commands use acknowledged `AppControl` messages; CLI Trash moves use a cross-process-locked `UndoJournal`. Exact target IDs, dry-run precedence, protected data roots and active-file checks gate actions. Portable skill: `.agents/skills/pulse/SKILL.md`, linked from `.claude/skills/pulse`. See [CLI behavior and verification](docs/pulse-cli.md).
- **Pulse Agent:** `pulse/Sources/Pulse/Views/AgentView.swift` provides the native Agent page; `AgentModel.swift` reduces versioned agent events into a safe timeline. `PulseKit/AgentConfiguration.swift` keeps provider URL/model in defaults and API key in Keychain. `AgentClient.swift` and `AgentDaemonManager.swift` authenticate the permitted local Agno sidecar. Release bundles include the whitelisted sidecar, Pulse skill, and CLI; the sidecar virtual environment lives in Application Support. Recent sessions load safe user/assistant history from SQLite, never system prompts or provider reasoning. `pulse-agent/` is the sidecar: typed SSE envelopes, bounded context, explicit provider transports, requirement-specific tool approvals, SQLite sessions and custom Agno LearningStore memory. Collection uses in-process `PulseCommands` via authenticated native RPC; the bundled CLI remains available for external integrations. Approval pauses retain Agno's resumable `RunOutput` (not its notification event); an unavailable or failed continuation returns a terminal Pulse event instead of corrupting the SSE stream. Design: [Pulse Agent Design](docs/superpowers/specs/2026-09-16-pulse-agent-design.md).
- **Architecture & Graph:** Check out the knowledge graph reports generated by Graphify to understand the structure:
  - [GRAPH_REPORT.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse/graphify-out/GRAPH_REPORT.md)
  - [graph.html](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse/graphify-out/graph.html)
  - [pulse_architecture.tldraw](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse_architecture.tldraw) (Interactive architecture & animated flow)

### [Specifications & Research](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs)
- **Accessible whole-app redesign (2026-10-11, implementation approved):** [Design and research](docs/superpowers/specs/2026-10-11-accessible-pulse-redesign.md), [implementation checklist](docs/superpowers/plans/2026-10-11-accessible-pulse-redesign.md), [product context](PRODUCT.md), and [visual system](DESIGN.md). Branch `feat/accessible-pulse-redesign` starts from latest `main` (`ef7ac5c`). Track implementation and validation evidence in the checklist.
- **Product Spec (v3.0):** [product_spec.html](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/product_spec.html) — authoritative implementation specification containing the full v1.0 state, HALO design tokens, and detailed feature specs.
- **Mole Super-Spec:** [pulse-mole-super-spec.html](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/pulse-mole-super-spec.html) — port specification from Mole (F1–F8). All phases shipped except GPU sensor (F7, root-only `powermetrics`).
- **BLAKE3 Spec:** [blake3-duplicate-finder-spec.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/blake3-duplicate-finder-spec.md) — prod & tech spec for 4-stage BLAKE3 duplicate file finder.
- **MCP Server Architecture Spike:** [mcp-server-architecture-spike.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/mcp-server-architecture-spike.md) — architectural design & feasibility report for exposing Pulse to AI agents (Antigravity, Claude Code, Codex) via MCP without disturbing existing codebase.
- **CLI + Agent Skill Architecture Report:** [cli-skill-architecture-report.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/cli-skill-architecture-report.md) — zero-overhead CLI + Agent Skill architecture blueprint and implementation plan for Antigravity, Claude Code, and terminal agents.
- **Market Research:** [market_research_report.html](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/market_research_report.html)

### [macOS Design Skill](file:///Users/venkateshmurugadas/software_codes/mac-monitor/.claude/skills/macos-design/SKILL.md)
Reusable Claude Code skill for macOS frontend development. Covers Apple HIG typography, colors, spacing, shadows, corner radii, animations, navigation patterns, accessibility, SF Symbols, and Liquid Glass (WWDC25/macOS 26 Tahoe).

### [Legacy App (TUI)](file:///Users/venkateshmurugadas/software_codes/mac-monitor/legacy_tui)
The old Python-based Textual TUI app (mac-monitor). Kept for reference.
- **Location:** `legacy_tui/`

## Mole Super-Spec Audit (2026-06-20)

Features from `pulse-mole-super-spec.html` cross-referenced against implementation:

| Feature | Status | Notes |
|---------|--------|-------|
| F1 — Diagnosis + Health Score | ✅ Shipped | PR #8. Dashboard hero, menu-bar HUD, health breakdown. |
| F2 — Optimize Engine | ✅ Shipped | PR #9. 4 safe + 3 admin tasks, VPN guard, refusal manifest. |
| F3 — Orphan Scanner | ✅ Shipped | PR #10. Launchd missing-binary detection, bootout, auto-rescan. |
| F4 — Disk Insights | ✅ Shipped | PR #11. Hidden Space tab, InsightScanner, bounded concurrency. |
| F5 — Process Watch | ✅ Shipped | PR #12. Sustained 50%/60s, AnomalyStore, fixed CPU% bug. |
| F6 — Catalog Import | ✅ Shipped | CleanCatalog with AI tool paths (.claude/.codex/.cursor etc). |
| F7 — Bluetooth sensor | ✅ Shipped | Native IOBluetooth (not system_profiler). TCC guard for macOS 26. |
| F7 — Proxy sensor | ✅ Shipped | Native SystemConfiguration (not scutil). |
| F7 — GPU sensor | ✅ Shipped | IOKit IOAccelerator (no root). Shows Device/Renderer/Tiler Utilization %. |
| F8 — Undo Journal | ✅ Shipped | All deletes via trashItem, 30-day journal. |
| Displays (Brightness) | ✅ Shipped | `BrightnessEngine` (DDC/DisplayServices, adaptive sync), `MediaKeyManager` (IOHIDManager via MediaKeyTap), `SoftwareDimmer` (sub-zero overlay), `DisplaySliderView` (per-monitor slider). Physical brightness keys routed through Pulse. |
| BundleGuard | ✅ Shipped | Case-sensitivity fix applied 2026-06-20. |
| Branch decision (unified DiskView) | ✅ Shipped | Map/Hidden Space/Reclaim/Trash/Optimize sub-tabs. |

### Product Spec Features Not Yet Implemented

| Feature | Spec Section | Status |
|---------|-------------|--------|
| Weekly Pulse Report (full screen) | §3.11 | Not built — notification stub exists |
| Storage Map overlay lenses | §3.3 | Not built (Safety/Age/Owner lenses) |
| Sunburst visualization toggle | §3.3 | Not built (treemap only) |
| FSEvents live watcher | §3.3 | Not built (manual rescan) |
| Pricing / free tier gating | §8 | Not built — everything unlocked |
| App Store sandboxed SKU | §9 M10 | Not built |
| Duplicate file finder | §9 M9 | BLAKE3 exact duplicates implemented, native clone/hard-link checks; perceptual hashing not built |
| F2 SQLite VACUUM (Mail/Messages) | Mole F2 | Not built |
| F2 Quarantine cleanup | Mole F2 | Not built |
| F3 Weekly orphan background scan | Mole F3 | Not built — manual only |

- **CLI/skill deployment audit (2026-09-13):** [Results and release gates](docs/pulse-cli-audit-2026-09-13.md); [approved native probe design](docs/superpowers/specs/2026-09-13-native-verdict-design.md). UsageGraphScanner now reads Homebrew receipts and Mach-O headers without subprocesses.

- **Diagnostic investigation:** native VM/storage rates, readable PID coverage and shared CPU accounting. `observe`, `process`, `network`, `history`, `startup`, and identity-bound `quit` share core evidence with Monitor → Investigate. Monitor supports app grouping and process role/footprint details. New anomaly start tokens and CPU/pressure/swap/temperature/battery minute histories support gap-honest correlation. See `docs/pulse-cli.md`.
- **Diagnostic upgrade plan:** `docs/superpowers/specs/2026-10-10-pulse-diagnostics-design.md` — shared native observation, reliable telemetry, app/CLI/skill parity and targeted remedies.

- **Ask Pulse provider setup:** explicit field labels, remote HTTPS/loopback HTTP validation, verified Keychain save feedback and duplicate-save guard. Invalid endpoints are blocked before starting the optional agent.
- **Ask Pulse stop lifecycle:** generation-scoped stream and cancellation acknowledgements prevent stale events/status from changing a later conversation; controlled cancellation fixtures cover out-of-order replies.

- **Redesign review:** draft PR #84 (https://github.com/VenkateshDas/pulse/pull/84); 360 tests pass. User delegated budget interpretation: enforce <1% CPU/<50 MB RSS in background two-second monitoring, report interactive costs separately. Background proof and human visual/functional approval remain open.

- **Storage scrolling (2026-10-11):** Cleanup categories/protected rows use lazy stacks; hover is row-local. Cleanup, Files, Changes and storage inspectors resolve/rasterise file icons asynchronously, retain per-row thumbnails and share a bounded cache. Regression verifies off-main lookup and cache reuse. Previous full freeze was not reproduced after restart; runtime stress evidence is tracked in the redesign plan.

- **Cleanup freeze correction:** live recurrence at 100% CPU captured main-thread SwiftUI lazy layout sizing. Cleanup now uses native List sections instead of nested lazy ScrollView stacks; icon work remains asynchronous.

- **Ask Pulse timeline correction:** Native List replaces lazy message layout after live hang capture. Answer text wraps vertically and renders inline Markdown off-main after streaming, retaining paragraph breaks; provider/actions unchanged.

- **Ask Pulse tool calls:** Consecutive calls are grouped behind a native disclosure, collapsed by default. Each result has its own disclosure; answers and action approvals remain visible.

- **Grouped app quit (2026-10-17):** App activity groups inspect the regular application PID instead of the busiest helper, so Brave/Chromium renderer load cannot redirect Send Quit to a refused helper. Aggregate totals and exact PID/start-token quit guards remain unchanged. Regression: `MonitorGroupingTests`.

- **Beta download (2026-10-17):** Landing navigation and hero link directly to the universal v0.3.0-beta.5 DMG; waitlist remains available for updates. Release includes the grouped app quit fix.

- **Landing feature coverage (2026-10-17):** [Approved content plan](docs/superpowers/specs/2026-10-17-landing-current-features-design.md). Landing copy covers released app features, optional AI/provider costs, history and restore limits; removes unshipped plans and unsupported guarantees.

- **Ask Pulse branch sync (2026-10-17):** `feat/pulse-agent-harness` includes main through landing PR #88 and grouped-app quit fix #86. Local review bundle is stamped `0.3.0-beta.5-harness.dev`.
