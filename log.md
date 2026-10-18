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

## [2026-10-11] Research Ask Pulse harness | Pulled main to a5fdf0d, audited existing Agno/Swift lifecycle and tool boundary, researched official Agno context/memory/learning cookbooks and assistant-ui runtimes, and wrote a proposed design and implementation sequence on feat/pulse-agent-harness. Design approval pending; no implementation or performance claims.

## [2026-10-11] Implement approved Ask Pulse harness | Pin Agno and lock Python/npm runtimes; share native command execution without collector subprocesses; isolate runs, provider configuration and approvals; add bounded history/result offloading/checkpoint summaries and inspectable opt-out memory; embed assistant-ui with packaged assets, restricted native messaging and visibility teardown. Follow-up conversation identity and Undo exact-path preview corrected. Deterministic Agno integration and local build validation recorded in the implementation plan; visual review and required macOS CI remain the merge gates.

Harness verification: 367 Swift tests/86 suites and 20 Python tests pass; CLI smoke and frontend typecheck/build pass. Deterministic harness turn median 21.4 ms, excluding model/network/UI. Packaged visual inspection is blocked by the locked Mac; uncontrolled Home sample exceeds numerical background targets and is not a valid visibility-controlled compliance result. Record limitations in the implementation plan. Keychain main-thread blocking, explicit lock gating, parent exit cleanup and native approval expiry addressed. PR #85 requires final CI and user visual/functional approval; never merge on the earlier design approval.

## [2026-10-11] Verify unlocked Ask Pulse | Actual packaged WKWebView streams a local fixture answer with Markdown table and native tool evidence; follow-up stays in one session, memory inspection opens, and close/reopen retains context. Owned Python/WebKit processes exit after closing. Controlled 30-second background sample: 0.80% CPU; RSS settles from 54.4 to 45.6 MiB (later 42.4 MiB), with transient post-close excess recorded. Fix provider tool ID reuse by scoping timeline identity to run; 368 native tests pass. No paid model call or real mutation. User visual/functional merge approval remains required.

## [2026-10-11] Fix renderer Observation dependency | Repeat packaged startup revealed stale browser state after the backend became ready. Compute the complete renderer snapshot in the visible SwiftUI body, then pass it into the representable/coordinator; hidden views read no chat snapshot. Add an Observation regression test (369 native tests now pass). Remove empty copy actions on tool-only messages and replace the ineffective startup Stop button with a disabled startup indicator.

## [2026-10-11] Restore real provider and bound credential startup | Removed local fixture launch/server and restored OpenRouter endpoint with the saved DeepSeek model. Keychain startup now has a three-second deadline, coalesces blocked reads and passes one result to the daemon. Credentials are bound to their saved endpoint to prevent forwarding a provider secret to a different server. 370 native tests pass; real-provider packaged verification pending.

Live provider verification: packaged OpenRouter/DeepSeek replied to a minimal prompt, then used the bundled Pulse skill and explained its approval/identity rules in the same session. Cached native context accompanies provider questions; no targeted diagnostic tools or mutations ran. Settings unlocked the existing Keychain read; re-entering Ask Pulse reached Ready. Hidden owned sidecar exited.

## [2026-10-11] Preserve dialogue after large tool results | Live reopen exposed empty provider history after a large skill read consumed the history budget. Budget conversational text and let Agno discard historical tool calls/results while preserving complete dialogue turns. Added an actual Agno restart regression with a 24 KB tool result; all 21 Python tests pass. Final real-provider hidden sample: 0.70% CPU, RSS 66.3→59.1 MiB over 30 seconds; strict RSS target remains unmet in this sample.

Cold launch correction: user opening Ask Pulse requests interactive existing-Keychain access directly; Settings is no longer required first. Interactive access allows 30 seconds for macOS authentication; silent reads have a five-second deadline. Reads coalesce separately.

Live restart regression verified: the real DeepSeek provider recalled the original “Pulse live provider connected.” response after reopening the persisted conversation and corrected its earlier missing-history answer.

## [2026-10-11] Keep proven chat-only teardown | Removed whole-window navigation teardown after close/reopen became unreliable, and removed allocator pressure relief without controlled evidence of a benefit. Retain renderer/owned-sidecar teardown and bounded conversation state. Later resource sampling overlapped the user’s live native-tool questions; those samples are invalid idle evidence. Strict RSS compliance remains unresolved.

## [2026-10-11] Release closed native tool connections | Connection timeout closures captured every NWConnection strongly for 660 seconds, even after cancellation and removal from the bridge. Use a weak capture so completed tool sockets can release immediately. Keep the existing timeout and connection limits.
## [2026-10-17] Fix grouped app quit | Grouped App activity rows select the regular application PID rather than the busiest helper; preserves aggregate metrics and existing graceful-quit identity/protection checks. Added CPU/memory grouping regression coverage.

## [2026-10-17] Publish beta download | Release v0.3.0-beta.5 from main with grouped-app quit fix; expose direct DMG download on landing page and clarify optional waitlist.

## [2026-10-17] Refresh landing feature coverage | Align feature grid, advanced tools, metadata, illustrative demos, FAQ and beta offer with released main. Include Ask Pulse, duplicates, battery history, investigations and CLI; correct privacy, recovery and performance claims. Desktop and 390px mobile review verified wrapping and FAQ expansion; clip decorative overflow and remove fixed FAQ answer-height cap.

## [2026-10-17] Sync Ask Pulse harness with main | Merge latest main into feat/pulse-agent-harness, preserving both wiki histories and including grouped-app quit and landing-page updates. Rebuild the local app for continued harness work.
## [2026-10-17] Research OpenWorker port | Pinned upstream at 5bf0d2fb8c728932fdbc6b49a24113aebc2a4ddd; mapped runtime, providers, tools, approvals, context, persistence, memory and React UI to current Ask Pulse. User scoped first delivery to runtime/UI. Proposed design records source limitations, native constraints and staged acceptance gates; implementation awaits design approval.

## [2026-10-17] Port Ask Pulse runtime and UI to OpenWorker | Direct pinned TurnEngine replaces Agno execution; retains Swift native tools, Keychain, exact mutation gates and UndoJournal. Adds transactional canonical history and structured compaction recovery, bounded result paging/search, backed-up migration, bounded provider workers/replay, early Stop and reconnect cleanup, read-only mode and separate questions/plans. React transcript/composer replaces assistant-ui with incremental native patches and persistent drafts. Keychain Save commits immediately; routine access stays silent and endpoint-bound. Private rotating metadata diagnostics and native status/timing aid debugging. Local validation: 38 real-engine contract tests, 380 Swift tests and 3 UI tests pass; 120-turn reopen regression and browser fixtures verified. Live model, native accessibility and strict background RSS validation remain open; user visual/functional approval required before merge.

## [2026-10-17] Package OpenWorker review build | Stable local signed `pulse/dist/Pulse.app` built and signature verified; runtime resources match source. CLI fixture smoke passes. Opened PR #89 for required macOS CI and user visual/functional review; no merge or release publication.

## [2026-10-17] Preserve safe provider failure metadata | Transport diagnostics retain exception class, bounded HTTP status and elapsed time before upstream translates errors; provider response bodies remain excluded. Regression verifies a secret-bearing 401 response cannot enter metadata logs. Runtime tests: 39 pass; review bundle rebuilt.

## [2026-10-17] Design context and session-cost visibility | Mapped composer placement, estimated context categories, reported token/cache counts and persistent idempotent per-request billing including compaction. OpenRouter supplies actual cost but pinned upstream stream normalization drops it. Proposed design records missing-history and cancelled-call limits; no implementation changes yet.

## [2026-10-17] Add context and session billing visibility | Approved compact composer meter opens context categories, output reserve and reported input; persistent session ledger totals fresh/cache/output tokens and summary calls with provider-reported OpenRouter USD charges. Capture precedes upstream normalization; retries/replay cannot double count. Old or interrupted missing reports remain explicitly incomplete. 51 runtime and 386 Swift tests pass; UI build and browser keyboard/coverage fixtures verified. Review build/PR #89 require final CI and user visual/functional approval.

## [2026-10-18] Research OpenWorker expansion | Inspected pinned upstream source, live OpenWorker conversations/automations/settings/memory, and current Pulse runtime/native/web navigation. Recorded proposed feature slices, detached title-agent lifecycle, native scheduling adaptation and whole-app visual direction in docs/superpowers/specs/2026-10-18-openworker-premium-expansion-design.md. Design approval pending; no expansion code implemented.

## [2026-10-18] Implement premium AI workspace | Approved OpenWorker adaptation adds unified navigation/theme, canonical chat management, detached title-agent jobs/billing, native deadline automations and read-only run inbox, editable memory/instructions/Undo, persisted tasks/evidence, bounded independent review, Mac specialists, selected text attachments/report export and opt-in on-device dictation. 75 backend and 402 Swift tests plus frontend fixtures/typecheck/build pass. Bundled UI, CI, background measurements and user visual/live-provider review tracked in docs/superpowers/plans/2026-10-18-openworker-premium.md. No merge approval granted.

## [2026-10-18] Harden premium workspace review | Keep startup busy through readiness awaits, synchronize native draft edits by revision, and preserve older unread automation reviews through display/storage limits. Explicit Mark reviewed acknowledges receipts without replaying actions. 402 Swift tests and four renderer fixtures pass; PR #90 open, CI pending.

## [2026-10-18] Preserve active conversation access | Keep Current conversation and Stop visible in the native sidebar when users navigate to another feature during a run or approval. Returning preserves active run/session/decision identity. 402 Swift tests pass.

## [2026-10-18] Prioritize Your Mac navigation | Move Your Mac above chat controls and conversations, remove the Mac tools disclosure and its expansion state, and label the following Ask Pulse group. Advanced tools retains its disclosure. User-requested refinement to PR #90.

## [2026-10-18] Fix dictation and prioritize Home telemetry | Correct Swift 6 actor isolation at Speech permission and audio callbacks after reproducing a microphone-triggered crash. Make ⌘Q close the window while explicit Quit Pulse remains available. Promote technical cards to the top of Home with condition/attention beside them and task actions below.

## [2026-10-18] Place activity beside technical details | Replace the bottom activity disclosure with adjacent native segmented tabs above the main Home panel; condition/attention remains at the side and task actions follow. Bound the process list height within the activity panel.

## [2026-10-18] Show Home details simultaneously | User clarified separate columns, both visible. Replace the tabs with technical cards on the left and activity charts/processes on the right; condition/attention follows the cards, and task actions follow both panels. Narrow windows stack the panels.

## [2026-10-18] Lead Home with the Mac state summary | Move the existing Storage, Battery and Internet summary above the technical/activity columns for a quick first glance. Preserve the same live readings and navigation actions.

## [2026-10-18] Consolidate Ask Pulse PRs | User selected #90 as the intended direction and authorized closing overlapping work. Verified #85 and #89 are fully included ancestors; reviewed #82's eight unique commits and mapped its sessions, evidence, Stop, Markdown, paged history and context/replay protections to current replacements. No complementary feature transplant needed. Close #82/#85/#89 as superseded/included, retain branches and keep #90 for integration. Analysis: docs/pr-consolidation-2026-10-18.md. No application code changed or new runtime tests run; merge approval remains pending.
