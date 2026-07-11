# Pulse Changelog & Wiki Log

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
