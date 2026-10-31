# Pulse Changelog & Wiki Log

## [2026-09-19] Fix | Resume Agno human approvals without breaking Agent chat
- Retained the resumable `RunOutput` emitted after `RunPausedEvent`, rather than incorrectly attempting to resume the notification event.
- Kept mutation confirmation enforced; unavailable or failed resumes now yield safe terminal Agent events rather than closing the SSE response mid-stream.
- Added focused sidecar regressions for pause capture and continuation.

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
## [2026-09-19] fix | Coalesce eight streamed Agent answer chunks per SwiftUI publication; prevents provider token bursts from monopolizing the main actor.
## [2026-09-19] fix | Keep Agno tool-event content out of final answers, preserve complete final text, collapse tool details by default, and clear working progress when answer begins.

## [2026-10-10] Diagnostic investigation | Correct PID enumeration and CPU accounting; add native VM/storage interval activity, bounded shared observation, process detail/tree/grouping, network timing, history with coverage limits, startup/sleep inspection, identity-bound graceful quit, Monitor investigation UI, agent failure preservation and focused Pulse skill references. Optimize reports successful Trash moves without claiming reclaimed space.
## [2026-10-11] Redesign research and proposal | Updated main to ef7ac5c and created feat/accessible-pulse-redesign. Audited SwiftUI pages, shared controls, runtime dashboard accessibility, permissions, cleanup accounting, and performance constraints. Added a source-backed whole-app redesign proposal with task-led navigation, readable native UI, explicit outcomes/recovery, complete surface coverage, implementation stages, and validation gates. Design review pending; no app code changed.

## [2026-10-11] Accessible redesign foundation | Implemented approved task-led navigation, readable light/dark themes, Larger text, Home and onboarding; native brightness control, reviewed duplicate workflows, opt-in bounded native network estimates and explicitly selected maintenance tasks. Build passed; whole-app implementation and runtime/CI verification remain in progress.

## [2026-10-11] Accessible redesign workflows | Added search-first app removal review, task-led menu bar, adaptive inspectors, cleanup cancellation, estimated energy explanations, actual removal records, provider setup and robust conversation stop handling. Removed prohibited legacy shell collection/action paths and kept truthful unavailable guidance. Fixed a runtime split-view sizing failure; Home, Apps/search and Battery/Internet inspected in the release app. 351 tests passed; remaining runtime matrix, release performance, final review and PR/CI gates remain open.

## [2026-10-11] Redesign implementation checkpoint | Task-led shell and reviewed interactions committed in 52a2e2a; 351-test suite and latest debug build pass. Release/runtime/performance gates remain open. Recovery audit identified GUI Trash journaling and main-thread Finder event fixes for the next checkpoint.

## [2026-10-11] Harden GUI removal recovery | Native app and related-file Trash moves now journal atomically with rollback. Finder permission events run on MainActor only for denied file moves. Added three recovery fixtures; 354-test suite passed before final error typing. Release UI verified Internet first layer; visible RSS exceeds budget and remains an open gate.

Final recovery refinement: make test passed 354 tests in 80 suites; Battery overview disclosures and charge-history accessibility were checked in the release app.

## [2026-10-11] Display accessibility audit | Runtime revealed brightness slider missing from accessibility tree despite visual rendering. Simplified grouping and labels; matching disabled without external screen. Native heap inspection identified activity-store retention as a performance investigation lead; budget remains unverified.

## [2026-10-11] Verify native display accessibility and improve history/startup controls | Native NSSlider exposes adjustable role/value in release AX tree. Activity breakdowns now native buttons with chart summary; startup helpers use named switches, pending guards and coverage/effect guidance. Restored 2-second sample/chart alignment with sparse process enumeration. Debug builds pass; full test rerun active.

Accessibility checkpoint validation: make test passes 354 tests in 80 suites. Activity/Startup release layout and final cadence CPU/RSS remain pending.

## [2026-10-11] Clarify performance test and recorded attention | Replaced unsupported benchmark ratings with adaptive measurements and method/effect explanations. Home/menu-bar summaries distinguish recorded attention from clear current readings. Added three regressions; 357 tests in 81 suites pass.

## [2026-10-11] Guard stale conversation-stop replies | Cancellation acknowledgement is scoped to its run generation. Controlled out-of-order regression passes; make test passes 358 tests in 82 suites.

## [2026-10-11] Validate provider setup and investigation lifecycle | Provider URL/Keychain feedback and accessibility labels hardened, duplicate saves guarded, investigation handles renamed window occlusion and shared typography. 360 tests pass; release verifies Home/Startup/Performance first layers. Timed performance measurements underway.

## [2026-10-11] Open draft redesign PR and measure release | PR #84 attached; 60s visible-page CPU 0.749%, RSS 62,928–79,984 KiB. User delegated target interpretation; strict budget applies to background monitoring, with separate interactive measurements. Closed-window proof and required CI remain pending.

## [2026-10-11] Correct repeated visibility events | Closed-window CPU/RSS missed the budget; found shared appearance counter over-counted repeated window events. Replaced with idempotent window/popover states and added overlap/repeat regressions. Runtime remeasurement required.

## [2026-10-11] Fix collapsed menu-bar popover | User screenshot showed a thin blue strip. MenuBarContent used only maxHeight on a ScrollView, allowing its intrinsic panel height to collapse. Set an explicit 620pt viewport; release bundle passes with stable signing and rebuilt app relaunched. Direct menu-popover visual verification remains pending.

## [2026-10-11] Simplify popover readings | Removed introductory explanation and readings/menu-bar disclosures. Attention shows its concrete title and review action; network shows last download/upload test with named retest/stop icons, progress and failure feedback. Existing bounded speed-test model reused.

## [2026-10-11] Remove blocking storage icon work | Recent unified logs contain DisplayServices traffic but no recorded crash/hang. Cold scan/scroll profile shows CleanView row rendering entering NSWorkspace icon lookup and icon rasterisation on main thread. Move that work to utility tasks with row-local images; make category/protected rows lazy and isolate hover. 364 tests in 85 suites pass, including off-main lookup/cache regression. Original indefinite freeze not reproduced after restart; release scroll verification pending.

Release verification: 12 alternating Cleanup scroll passes and four Files passes returned responsive UI; rows/icons rendered. Before/after 20-second samples show iconForFile on main thread before and zero main-thread iconForFile entries after (lookup now on utility workers). No files moved or preferences changed. Full historical freeze remains unconfirmed; performance budget compliance is not claimed.

## [2026-10-11] Capture recurring Cleanup layout freeze | User recurrence captured PID 23631 at 100% CPU. Five-second sample: main-thread SwiftUI layout sizing/transaction loop, not icon I/O. Prior optimisation did not resolve freeze. Replace nested scroll/lazy stacks with native List sections, preserving category collapse and row actions. Release verification pending.

Native-list release built and relaunched. Keyboard End reaches lower rows with icons/actions rendered. Post-change three-second sample shows main thread waiting in event loop, CPU observation 0%, unlike captured 100% layout loop. Wheel stress automation fails with noWindowsAvailable; full trackpad recurrence verification remains user gate.

## [2026-10-11] Correct Ask Pulse lazy message layout | Captured PID 26445 at 98.7% CPU with main thread repeatedly in LazySubviewPlacements/SwiftUI graph updates. Replace message ScrollView/LazyVStack with native List, stable wrapping and inline Markdown with preserved paragraphs after stream completion. Tool disclosures and approval controls retained. Release verification pending.

## [2026-10-11] Collapse Ask Pulse tool calls | Group consecutive tools behind collapsed native disclosures, keep individual results expandable and approvals visible. Release bundle and all 364 tests across 85 suites pass. Removed an invalid test assumption that NSCache cannot evict under memory pressure; off-main icon lookup and thumbnail checks remain.

## [2026-10-17] Fix grouped app quit | Grouped App activity rows select the regular application PID rather than the busiest helper; preserves aggregate metrics and existing graceful-quit identity/protection checks. Added CPU/memory grouping regression coverage.

## [2026-10-17] Publish beta download | Release v0.3.0-beta.5 from main with grouped-app quit fix; expose direct DMG download on landing page and clarify optional waitlist.

## [2026-10-17] Refresh landing feature coverage | Align feature grid, advanced tools, metadata, illustrative demos, FAQ and beta offer with released main. Include Ask Pulse, duplicates, battery history, investigations and CLI; correct privacy, recovery and performance claims. Desktop and 390px mobile review verified wrapping and FAQ expansion; clip decorative overflow and remove fixed FAQ answer-height cap.


## [2026-10-30] Remove Ask Pulse | Remove chat navigation, provider/model/API-key settings, client/daemon, Python sidecar and related tests; remove AI runtime/skill packaging and landing-page claims. Preserve native monitoring, cleanup and CLI. AI work remains on feat/home-ask-pulse. Debug build, 355 tests across 81 suites and CLI smoke pass; signed release bundle and artifact checks pass. Running Home/sidebar and Settings confirm no Ask Pulse or provider controls; user review pending. CI now rejects bundles containing the removed AI runtime or skills.


## [2026-10-30] Reorder Home and flatten navigation | Move technical details above task actions; show advanced destinations directly in the sidebar, removing More/disclosure and expansion state. User specified layout. Debug build, 355 tests and signed release bundle pass; restarted app verifies requested ordering and flat sidebar. User review remains pending.

## [2026-10-30] Build waitlist-first landing | Replace download-first landing with accessible light/green early-access page, user-controlled illustrative previews, native FAQ and honest signup availability. Remove fake Formspree endpoint and offered-price schema; prepare hosted MailerLite Share URL configuration. No accounts, tracking or live collection enabled. See docs/marketing/waitlist-setup.md for activation and validation gates.

## [2026-10-30] Add real product proof to landing | Replace illustrative interface with actual native Home Light/Dark, App activity and app-removal review captures; frame Home with an image-generated studio backdrop without altering app pixels. Rewrite early-access copy around buyer questions, context and control; remove obsolete mock CSS and legacy backgrounds. Browser responsive/keyboard/FAQ/closed-signup checks pass; design review ship. MailerLite link and user merge approval remain pending.

## [2026-10-30] Add storage showcase with fictional UI previews | User chose Home hero plus dramatic storage section, then rejected real-data captures for privacy. Replace all current real-data landing captures with deterministic SVG interface replicas using fictional apps, folders and readings; remove originals from current assets and preview server. Strengthen hero composition, preserve Light/Dark switch, add enlarged Files columns and explanatory steps, disclose demos throughout. Prior Git commits still retain old captures; no history purge performed.

## [2026-10-30] Showcase technical signals with restrained motion | Remove both annotated landing elements; add fictional CPU/memory/GPU/storage/network/thermal readings and hardware-availability context. Self-host a 55KB Three.js CSS3D subset for on-demand scroll leveling, with reduced-motion, module-failure, offscreen, print and zoom-change fallback paths. Desktop/mobile/narrow, keyboard, fixture fallback and static checks pass; design review ship. Native app, tracking and closed signup unchanged.

## [2026-10-30] Restore pain-led capability and trust story | Relate full storage, slowdowns and app leftovers to specific review workflows; restore capability map and four evidence-backed trust principles. Add a reproducible native SwiftUI component render with fictional fixtures, built through Make in a temporary package without starting samplers or replacing the app bundle. Keep native capture legible via keyboard-accessible horizontal pan on narrow viewports; retain minimal Three.js motion. Fresh design review ship; obsolete AI/beta and universal recovery claims excluded.

## [2026-10-31] Prepare next growth-pipeline steps | Audited closed signup and absent analytics/search setup; added current waitlist-first execution checklist, form/confirmation copy, minimal measurement contract, initial content sequence and official provider references. No tracking, email collection, publication or paid service enabled.

## [2026-10-31] Prepare MailerLite early-access form | Created Pulse early access group and hosted-share form; saved invitation/CTA/check-inbox copy and verified enabled double opt-in. Public form renders; delivery, confirmed membership and unsubscribe await founder-authorized testing. Landing config remains closed; no campaign sent.

## [2026-10-31] Verify waitlist confirmation and prepare branded thank-you | Authorized alias reached Gmail, confirmed Active group membership, then dashboard unsubscribe verified. No campaign sent; recipient unsubscribe link remains untested. Provider thank-you editing is paid-only; prepare a static Pulse early-access confirmation page for custom redirect after approved deployment. Live redirect and closed landing config unchanged.


## [2026-10-31] Integrate approved capability illustration | Replace flat capability hub with the user-selected Pulse-green studio illustration, compressed to 114KB WebP. Retain native eight-feature text for screen readers/search, responsive keyboard/touch pan and hardware/permission qualification. No product screenshots, analytics settings or signup behavior changed.
