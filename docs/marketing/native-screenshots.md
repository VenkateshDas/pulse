# Native Pulse alignment and real screenshots

The user approved carrying the waitlist landing page's established light/green identity into the native app, using Impeccable and Ponytail ultra. This is a shared-style refinement, not a feature rewrite or a new telemetry system.

## Implementation

- Existing paired colors and NSApp appearance switching provide System, Light and Dark; Contrast/Slate and saved preset identifiers remain available.
- Dynamic NSColor names include the selected preset so switching palettes cannot retain a previously cached tint.
- Shared page titles use 28 pt system type. The sidebar uses the existing landing-style p mark, muted green surface and native button rows with selected accessibility traits. Native button activation, keyboard task shortcuts and the command palette remain available.
- Home uses flat opaque grouped surfaces and keeps technical details before task actions. Vitals no longer use material blur or hover scaling/shadows.
- The Home condition action uses a native bordered control with semantic text, including when inactive. No data-driven animations, new sampling or collection subprocesses are introduced.

## Evidence and limits

Use only the repository bundle at `pulse/dist/Pulse.app`; an older Pulse app in another checkout has the same application name. Quit an old process before reopening the rebuilt path.

Light/dark captures must come from the running app, with real readings and technical details collapsed so SSIDs, process lists and personal paths are absent. Captured values are one Mac's observations, not guaranteed performance or cleanup outcomes. No staged demo state is added to the app. Screenshot provenance is recorded with the captured assets.

Validate build, tests and bundle through make. Review Home and Settings in both modes, persistence across relaunch, existing navigation actions, keyboard access and a compact window. Human visual/functional approval remains required before merge. No distribution signing purchase, notarization or release is included.

The landing-page PR remains separate. Screenshot assets are ready for its real-image swap; they do not imply a new public release or a live waitlist.

## Verified on October 30

- `make build`, `make test` (357 tests in 81 suites) and `make bundle` pass. Bundle uses the stable Pulse Local Signing identity.
- Running repository build: Light and Dark render correctly, Dark persists after quit/relaunch, System option works, Up from Settings selects Diagnostics and Down returns to Settings with focus. Compact 882×652-point window remains scrollable and readable.
- Source review found and verified the arrow-navigation correction. Visual review matched the established identity; its cursor-halo finding was resolved by recapturing both assets, then independently scored resolved. No UI code changed after captures.
- `landing/assets/pulse-home-light.webp` and `pulse-home-dark.webp` are 2288×1660 lossless real captures with the 104-pixel OS toolbar cropped out. Provenance lives in adjacent JSON files. No SSID, process list or personal file path is visible; technical details were verified collapsed before each capture. The remaining readings are actual observations, not representative benchmarks.
- Raw full-window PNGs and compact evidence remain in `/tmp/pulse-home-light.png`, `/tmp/pulse-home-dark.png` and `/tmp/pulse-home-compact.png` for this local review session. Shared assets are the WebP files, not those temporary paths.

No sampling/performance-budget recertification is claimed for this UI-only change. Background publication gates and sampling code are unchanged; the strict background budget remains a product requirement.
