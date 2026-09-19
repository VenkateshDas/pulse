# Pulse Knowledge Base Index

Welcome to the Pulse repository LLM Wiki. This file serves as the main catalog for navigating the project.

## Components

### [Pulse App](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse/README.md)
The main application: a native macOS command center for performance and storage built with Swift 6.
- **Location:** `pulse/`
- **Design System:** HALO design token system (`Theme.swift`) — `Shadow`, `Radius`, `Space`, `Motion` enums, `premiumCard()` / `sectionLabel()` view modifiers, mesh gradient backgrounds. Built from Apple HIG research (`.claude/skills/macos-design/SKILL.md`).
- **Sidebar Sections:** Overview (Dashboard), Insights (Storage, Timeline), System (Monitor, Health), Tools (Uninstall, Dev Mode)
- **Menu Bar Popover:** Live vitals with 30s sparklines, top processes, disk delta, quick actions (Quick Clean, Empty Trash), subtle Command Center icon in HUD header.
- **Command Palette (⌘K):** Fuzzy-searchable navigation and quick actions.
- **Diagnosis + Health Score (F1):** `DiagnosisEngine` (CPU→mem→disk→battery→thermal cascade, culprit attribution) + `HealthScore` (weighted 0–100, piecewise penalty curve). Dashboard hero ring + menu-bar HUD.
- **Optimize (F2):** `OptimizeEngine` (typed dry-run-aware tasks, VPN guard, 5-entry refusal manifest). 4 safe + 3 admin tasks via Authorization Services.
- **Orphan Scanner (F3):** Leftover daemons/helpers of deleted apps, `launchctl bootout`, auto-rescan after uninstall.
- **Disk Insights / Hidden Space (F4):** `InsightScanner` — iOS backups, old Downloads (>90d), Xcode/Docker/OrbStack/dev caches, AI tool caches.
- **Process Watch (F5):** `ProcessWatcher` — sustained-threshold detection (50%/60s), `AnomalyStore` for Timeline history.
- **Clean Catalog (F6):** 30+ curated cleanup targets including AI tools (Claude, Codex, Cursor, Copilot, Gemini).
- **Sensors (F7):** GPU utilization (`IOAccelerator` IORegistry, no root), Bluetooth battery (`IOBluetoothDevice` + IOKit), proxy detection (`SystemConfiguration`).
- **Undo Journal (F8):** Every destructive action logged, all deletes via `FileManager.trashItem`, 30-day journal with restore.
- **App Uninstaller (§3.14, M9):** drag-to-remove with confidence-graded leftover matching (`PulseKit/UninstallScanner.swift`, `Pulse/UninstallModel.swift`, `Pulse/Views/UninstallView.swift`). App → system Trash, leftovers → Vault, plus an orphan scanner. Protected by `BundleGuard` allowlist.
- **Displays (Brightness Control):** `BrightnessEngine.swift` (DDC/DisplayServices, adaptive sync), `MediaKeyManager.swift` (IOHIDManager interception via MediaKeyTap), `SoftwareDimmer.swift` (sub-zero overlay), `DisplaySliderView.swift` & `BrightnessOSD.swift` (unified -1 to 1 slider mapped to 0 to 1 with sub-zero visual range). Physical brightness keys routed through Pulse for both built-in and external monitors.
- **Network Health Card:** `NetworkModel.swift`, `NetworkView.swift`, `SpeedTestRunner.swift`, `WiFiSampler.swift`. Provides real-time WiFi metrics and automated speed tests.
- **Menu Bar Action Flash:** `PulseKit/MenuBarFlash.swift` — main menu-bar icon briefly swaps to the triggered action's SF Symbol (keep awake cup, brightness sun, optimize bolt, trash) for 3s on hotkey or UI trigger, then reverts.
- **Menu Bar Stats (multi-select):** `Pulse/MenuBarStat.swift` (CPU / memory / CPU temp / battery, persisted `PulseMenuBarStats`), `Pulse/MenuBarLabelRenderer.swift` — the whole label is drawn into ONE template NSImage (MenuBarExtra flattens SwiftUI labels; see memory `menubarextra-label-flattening`). Values change-gated in `DashboardModel.menuBarValues`. Chips UI in Settings → Menu Bar.
- **Battery Drain Attribution:** `BatteryAttributionEngine` (`PulseKit/BatterySessionStore.swift`) — 7-day cross-session rollup, per-app CPU shares weighted by each session's charge drop; rendered by `BatteryDrainCard` in `HealthView.swift` above the sessions list.
- **Launch at Login:** cached in `AppActivation.swift` — `SMAppService.status` validates the code signature via the Security framework and must never run on the main thread (runtime faults); reads return the cache, writes reconcile off-main.
- **Native CLI + Agent Skill:** `pulse/Sources/PulseCLI/` implements all 14 planned commands plus cached speed-test history. `make cli` produces `pulse/dist/cli/pulse`; `make install-cli` installs `pulse`. SwiftPM product is `pulse-cli` to avoid a case-insensitive collision with GUI `Pulse`. App-owned sleep/display commands use acknowledged `AppControl` messages; CLI Trash moves use a cross-process-locked `UndoJournal`. Exact target IDs, dry-run precedence, protected data roots and active-file checks gate actions. Portable skill: `.agents/skills/pulse/SKILL.md`, linked from `.claude/skills/pulse`. See [CLI behavior and verification](docs/pulse-cli.md).
- **Pulse Agent:** `pulse/Sources/Pulse/Views/AgentView.swift` provides the native Agent page; `AgentModel.swift` reduces versioned agent events into a safe timeline. `PulseKit/AgentConfiguration.swift` keeps provider URL/model in defaults and API key in Keychain. `AgentClient.swift` and `AgentDaemonManager.swift` authenticate the permitted local Agno sidecar. Release bundles include the whitelisted sidecar, Pulse skill, and CLI; the sidecar virtual environment lives in Application Support. Recent sessions load safe user/assistant history from SQLite, never system prompts or provider reasoning. `pulse-agent/` is the sidecar: typed SSE envelopes, bounded context, tool approvals, and SQLite sessions. Approval pauses retain Agno's resumable `RunOutput` (not its notification event); an unavailable or failed continuation returns a terminal Pulse event instead of corrupting the SSE stream. Design: [Pulse Agent Design](docs/superpowers/specs/2026-09-16-pulse-agent-design.md).
- **Agent Workspace Upgrade:** OpenWorker-inspired, native SwiftUI conversation ergonomics: active and historical sessions remain in the rail; provider summaries persist in a collapsible Thinking trace; each run's tool calls stay grouped before its final answer; user-selected compact tool cards reveal typed evidence; native approval gates retain explicit impact/reversibility feedback. The composer owns run status and swaps Send for Stop while streaming; cancellation flushes buffered text and preserves tool evidence. Its input and status row have fixed geometry, while the transcript owns remaining height, preventing SwiftUI layout feedback across consecutive turns. Agent answers use a native Markdown block renderer for headings, inline emphasis/code, lists, quotes, code blocks, rules, and tables. Design: `docs/superpowers/specs/2026-09-19-pulse-agent-workspace-design.md`.
- **Architecture & Graph:** Check out the knowledge graph reports generated by Graphify to understand the structure:
  - [GRAPH_REPORT.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse/graphify-out/GRAPH_REPORT.md)
  - [graph.html](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse/graphify-out/graph.html)
  - [pulse_architecture.tldraw](file:///Users/venkateshmurugadas/software_codes/mac-monitor/pulse_architecture.tldraw) (Interactive architecture & animated flow)

### [Specifications & Research](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs)
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
