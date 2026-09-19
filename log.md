# Pulse Changelog & Wiki Log

## [2026-09-16] Feature | Native Pulse Agent interface and authenticated Agno harness
- Added Overview → Agent: native session rail, streamed evidence timeline, tool cards, final-answer lane, native action approvals, and pinned natural-language composer.
- Added versioned sidecar event envelopes, local bearer authentication, bounded context/session summaries, and server-enforced human approval for all mutations.
- Added OpenRouter-compatible Agent Settings: Keychain API-key storage, configurable base URL and model, plus runtime configuration refresh.
- Recorded design and verification requirements in `docs/superpowers/specs/2026-09-16-pulse-agent-design.md`.

## [2026-09-04] Architecture Blueprint | CLI + Agent Skill Architecture & Implementation Plan
- Completed deep architectural blueprint replacing MCP with native Swift CLI (`pulse`) + Agent Skill (`SKILL.md`).
- Documented dual-persona output engine (TTY tables vs deterministic `--json`), Darwin notification bridge to `MenuBarFlash`, dry-run safety gates, and 12-subcommand catalog in [docs/cli-skill-architecture-report.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/cli-skill-architecture-report.md).
- Designed zero-dependency implementation roadmap preserving offline CLT build reliability with 0 lines changed in existing codebase.

## [2026-09-04] Architecture Spike | Pulse MCP Server Feasibility & Design
- Completed comprehensive architectural spike on turning Pulse into an agent-friendly Model Context Protocol (MCP) server for Antigravity, Claude Code, and Codex.
- Verified zero codebase disruption path: new lightweight CLI target `pulse-mcp` linking `PulseKit` + `modelcontextprotocol/swift-sdk` over `stdio` transport.
- Documented complete technical spike, 10 tool definitions, 4 resources, 2 prompt templates, performance budget (<1% CPU, <15MB RSS), and implementation roadmap in [docs/mcp-server-architecture-spike.md](file:///Users/venkateshmurugadas/software_codes/mac-monitor/docs/mcp-server-architecture-spike.md).

## [2026-08-14] Optimization | Landing Page Speed, Modern Web Guidance, and A11y
- Converted hero background image (`hero-bg-2.png`, 1.09MB) to modern WebP (`hero-bg-2.webp`, 29KB, 97.2% reduction) and JPEG fallback.
- Added critical resource preloading with `fetchpriority="high"` and CSS `image-set()` responsive format delivery.
- Added `content-visibility: auto` and `contain-intrinsic-size` across off-screen sections (`.section`, `.merge`, `.cta-section`) to reduce initial render cost.
- Implemented `font-size-adjust: from-font` to eliminate layout shift (CLS) across fallback system fonts.
- Implemented complete ARIA semantics: skip-to-content landmark, accessible form inputs with `autocomplete="email"`, tablist/tab controls for carousel, synchronized `aria-expanded` and `aria-controls` for FAQ accordion, and `role="progressbar"` for mini-bars.
- Optimized JavaScript runtime: throttled bento hover animations via `requestAnimationFrame`, paused CPU sparkline intervals when scrolled out of viewport via `IntersectionObserver`, and added `{ passive: true }` flags on scroll listeners.
- Added OpenGraph, Twitter Cards, canonical URL, and Schema.org `SoftwareApplication` JSON-LD metadata for SEO.
- Fixed an issue where `BrightnessEngine`'s hardware brightness echo (from clamping built-in displays to 0.01 in the sub-zero range) would overwrite the software brightness state, erasing sub-zero dimming.
- Updated `BrightnessOSD.swift` slider track to correctly visualize the -1.0 to 1.0 range, matching the main popover slider with an indigo-to-blue gradient for sub-zero values.

## [2026-07-10] Feature | Menu bar icon flash on actions
- Added `MenuBarFlash` (PulseKit, @Observable singleton): main menu-bar icon briefly swaps to the triggered action's SF Symbol for 3s, then reverts — covers hotkey and UI triggers.
- Hooks: `KeepAwakeController` (cup filled/outline), `BrightnessEngine.isAdaptiveModeEnabled` (sun), `OptimizeEngine.runSafeTasks` (bolt.heart), Empty Trash in `StorageModel` + `KeybindingActions` (trash).

## [2026-06-29] Fix | Performance and UX optimization
- Disabled adaptive sync when external display brightness is overridden via media keys to fix CPU storm.
- Removed data-driven `.animation` on `HealthHero`, `TreemapView`, and `VitalCard` to prevent layout invalidation loops.
- Removed 0.3s toggle debounce in `MenuBarManager` for instant chevron responsiveness.
## [2026-06-21] Architecture Extraction | Replicated Hidden Bar's 2-item menu bar hiding mechanism in Pulse
- Removed single status item hack. Implemented 2-item structure (separator + chevron).
- Documented hard-won Menu Bar UI lessons (Notch heights, NSStatusItem self-healing, geometry order validation) in AGENTS.md.

## [2026-06-21] Feature | Intelligent Adaptive Brightness & Media Key Interception
- Added `BrightnessEngine` (DDC + DisplayServices hardware control, adaptive sync mode, per-monitor brightness map with UserDefaults persistence).
- Added `SoftwareDimmer` (NSWindow overlay for sub-zero brightness below hardware minimum).
- Added `MediaKeyManager` using `alin23/MediaKeyTap` with `observeBuiltIn: true` for IOHIDManager-based brightness key interception on Apple Silicon.
- Added `DisplaySliderView` (custom capsule slider, -1…1 range) and `DisplaysPopoverSection` (menu bar popover displays control).
- Added `NSEvent.addGlobalMonitorForEvents` fallback for when Accessibility permission is not granted.
- Fixed `AppActivation.swift` launch logic: always prompt for Accessibility if not trusted, always call `MediaKeyManager.start()` (graceful degradation via fallback monitor).

## [2026-06-21] Fix | Health & Monitor page data population
- Removed overly restrictive `guard visible != windowVisible` in `RootView.swift` occlusion observer that permanently halted `HealthModel` and `MonitorModel` sampling loops after window close/reopen.

## [2026-06-21] Fix | Adaptive Sync CPU storm (DCPAVServiceProxy)
- Added automatic sync-breaker: manual slider drag or brightness key press on external monitor disables `isAdaptiveModeEnabled`, stopping the 2s background loop from fighting user input and spamming I2C DDC commands.

## [2026-06-21] Lesson | CGEvent taps cannot intercept brightness keys on Apple Silicon
- Documented that brightness keys are processed at IOKit HID layer, below CGEvents. Only IOHIDManager (MediaKeyTap with `observeBuiltIn: true`) reliably intercepts them. Raw CGEvent.tapCreate at any level creates a valid tap but callback never fires for brightness events.

## [2026-07-11] Feature | Network Health Card
- Added `NetworkModel` and `NetworkView` for monitoring network health.
- Added `SpeedTestRunner` and `WiFiSampler` to support network diagnostics and metrics.
- Integrated Network Health Card into `DashboardView` and `MenuBarContent`.
## [2026-07-11] Network Feature | Implemented Network Health Card with real-time Wi-Fi metrics, connection type monitoring, and automated speed tests cached in SpeedTestStore.

## [2026-07-18] Documentation | Created interactive tldraw architecture diagram & animated workflow
- Created `pulse_architecture.tldraw` mapping UI, Control, and Platform/Driver layers of the app.
- Redesigned the diagram to use highly modular visual mockups (e.g. status bar extra, dashboard window with sidebar, health score, and brightness sliders), Apple system emojis for icons, and structured arrow routing to avoid overlaps.
- Implemented `main.js` document script running live background animations across 9 flows and real-time metric updates on individual stat chips.

## [2026-08-13] Documentation | Created product & technical spec for BLAKE3 Duplicate File Finder
- Created `docs/blake3-duplicate-finder-spec.md` detailing the 4-stage progressive filtering pipeline (Size -> 8KB Head/Tail -> Full BLAKE3 -> APFS Inode/Clone check).
- Designed zero-subprocess C engine integration in `CPulse`, Swift 6 `DuplicateScanner` actor, smart auto-selection heuristics, and `DiskView` sub-tab layout.

## [2026-08-13] Feature | Reclaim Item Protection ("Move to Worth a Look")
- Added `excludedPaths` to `CleanSchedule` & `CleanScheduler` for persisting protected item paths across app restarts and auto-clean background jobs.
- Updated `CleanScheduler.runNow()` and `preview()` with path hierarchy matching (`CleanSchedule.isPathExcluded`) to exclude protected items from scheduled auto-cleans.
- Updated `StorageModel` (`selectAllSafe`, `trashProtectedItem`) to omit protected paths from bulk selections and support single-item manual deletion with `UndoJournal` recording and trash sound.
- Updated `CleanView` with "Move to Worth a Look" shield action on cleanable item rows and a "PROTECTED ITEMS" sub-section under "WORTH A LOOK" with "Restore to Reclaim", "Trash", and "Reveal in Finder" controls.
- Added comprehensive unit tests in `CleanTests.swift` validating `excludedPaths` persistence and subpath exclusion behavior.

## [2026-08-14] Perf | App and Loading Elements Speed Optimization
- Added `FileIconCache` (`Pulse/FileIconCache.swift`) with static cache and async pre-warming, eliminating blocking synchronous `NSWorkspace.shared.icon(forFile:)` calls across `StorageView`, `CleanView`, and `UninstallView`.
- Optimized `StorageModel.scanItemsByPath` to maintain a cached index updated on scan completion instead of re-allocating a dictionary on every column and row render.
- Replaced `/bin/df` shell subprocess in `StorageModel.refreshHiddenBreakdown()` with native POSIX `statfs` kernel calls, achieving sub-millisecond execution with zero subprocesses.
- Throttled `StorageScanner.scanSizesStream` yields (100ms interval + final yield) to eliminate SwiftUI `@MainActor` re-render thrashing during directory sizing.
- Unified battery log backfill in `BatteryHistoryStore` and `DashboardModel` to a single pass and avoided redundant `pmset -g log` subprocess execution on startup when cached history is present.


## [2026-09-08] Feature | Complete native Pulse CLI and portable agent skill
- Repaired the uncommitted CLI draft; added strict parser/JSON contracts, all 14 planned commands, cached-only speed-test history, Make targets and test coverage.
- Added acknowledged app-owned display/sleep controls and bounded DDC completion reporting; CLI sampling no longer writes GUI disk history.
- Hardened exact cleanup/uninstall selection, protected-data and active-file checks, per-move journal persistence/rollback, cross-process locking and conflict-preserving undo.
- Fixed APFS clone detection to use native clone IDs instead of equating clones with inodes; made duplicate minimum size configurable.
- Added standards-validated `.agents/skills/pulse/SKILL.md`, Claude discovery link and `docs/pulse-cli.md`; preserved the existing branch and unrelated local work.
- Verified build/tests, native read commands, full volume growth, fixture Trash/uninstall/restore, display read/set, and timed app-owned keep-awake. Visual/functional user approval remains the merge gate.

## [2026-09-13] CLI verification and native probes | Fix cold-cache verdict subprocesses
- Audited every CLI command and exercised fixture cleanup/uninstall/restore, display controls and timed sleep. Replaced brew/otool probes with native receipt/header reads; added malformed-input regressions and expanded CLI smoke. See docs/pulse-cli-audit-2026-09-13.md for results and remaining release gates.
## [2026-09-19] fix | Bundle Pulse Agent runtime, skill, and CLI; resolve its app-resource path and allow first-run dependency setup to complete.
## [2026-09-19] fix | Correct Agno streamed-run handling: `arun` and `acontinue_run` return async generators, not awaitable values. Verified with OpenRouter DeepSeek V4.1 Flash.
## [2026-09-19] fix | Package skill under its required `pulse` name and load persisted user-visible session history instead of clearing conversation on selection.
