# Pulse Changelog & Wiki Log

## [2026-07-16] Fix | Sub-zero brightness persistence and OSD UI
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

