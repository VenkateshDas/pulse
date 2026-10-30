# Pain → useful outcome → proof — 2026-10-30

## User direction

Restore useful scenario, capability and trust content from the earlier landing page. Lead with a familiar frustration, show a concrete way forward, then demonstrate what the user gets. Keep the current Pulse green/cool style, waitlist-first offer, minimal Three.js motion and privacy constraint.

The supplied screenshots are content references, not a request to restore their dark styling, AI-provider claims, downloadable beta offer, unconditional cleanup claims or a universal undo window.

## Page story

1. Hero: “Your Mac feels off. Know where to start.” Home remains the primary product visual.
2. Three pain/action pairs: full disk → explore folder sizes; slow Mac → review system and grouped app signals; unwanted app → review matched related files.
3. Authentic native indicators: actual SwiftUI components, rendered with fictional fixtures.
4. Existing storage, App activity and app-removal demonstrations retain their specific context and action limits.
5. Eight-capability overview: monitoring, storage, app review, network checks, supported display brightness, temporary keep-awake sessions, menu-bar controls and startup helpers. Maintenance and recorded activity are secondary mentions, not “one-click optimization” promises.
6. Trust: reviewable manual actions; local system readings with network-operation context; current open-source MIT code; recovery only while recorded Trash items remain available.
7. Early-access invitation, FAQ and privacy. Signup remains closed until MailerLite is configured.

## Native proof without personal data

`landing/scripts/render-native-indicators.sh` copies the actual `VitalCard.swift`, `Theme.swift`, `ThemePreset.swift` and `ThemeManager.swift` from native PR #95 commit `b698bfd` into an isolated temporary Swift package. It compiles through a temporary Make target invoked from `pulse/`, retaining the repository’s toolchain workarounds. A SwiftUI ImageRenderer renders five native cards with authored data; the CPU card also shows the sample GPU reading.

No DashboardModel, engine, sensors or samplers are started. The running app and `pulse/dist/Pulse.app` are untouched. Native component source is unchanged. The PNG is encoded losslessly as `landing/assets/pulse-native-indicators.webp`, 2240 × 722, ~67 KB; the adjacent JSON records origin. This is an authentic native component render with example values, not a screenshot of the owner’s live readings and not an AI-redrawn interface.

Examples: CPU 18%, GPU 12%, memory 6.4/16 GB (40%), disk 64 GB free out of 512 GB (87.5% used, displayed rounded to 88%), nominal thermal state and illustrative wired transfer rates. Hardware availability is qualified. Other interface previews remain fictional SVG replicas; FAQ distinguishes the methods.

Run the optional generator on macOS with Swift 6.2: `landing/scripts/render-native-indicators.sh /tmp/pulse-native-indicators.png`. The pinned commit must exist locally (fetch native PR #95 if using a shallow checkout). Use `cwebp -lossless` for the shipped WebP. No renderer/build dependencies are added to the production app or website build.

The Three.js scroll transform now wraps the native proof figure. Narrow viewports show an original-scale, horizontally scrollable capture with explicit arrow-key support, rather than shrinking text to a thumbnail. Full-size opening remains available through the image. Print removes scrolling constraints.

## Claim evidence

- Monitoring / GPU / thermal fallback: `DashboardView.swift`, `PulseKit/Sensors/GPUSampler.swift`.
- Folder exploration and manual review: `StorageView.swift`, `CleanView.swift`, `UninstallView.swift`.
- Network activity / optional tests: `NetworkView.swift`, `NetworkModel.swift`.
- Display support: `DisplaysView.swift` and native brightness engine.
- Keep awake: `PulseKit/Sensors/KeepAwake.swift`.
- Menu-bar hiding / readings: `MenuBarManager.swift`, `SettingsView.swift`, menu-bar label renderer.
- Startup helpers: `HealthView.swift` startup scope; these are launch helpers, not every login app.
- Recovery: `PulseKit/UndoJournal.swift`; no fixed universal recovery-duration claim.
- Licensing: repository LICENSE (MIT). No AI-provider functionality or beta-download CTA restored.

## Verification

The isolated native fixture builds through Make and renders successfully. Image inspected for clipping and private content; raster provenance scan reports no missing metadata. HTML IDs/ARIA/fragment/local assets and SVG XML pass; obsolete real-capture URLs return 404. JS/shell syntax and whitespace checks pass.

Browser: 1440px and 390px fullpage plus normal native/capability captures; 320px no page overflow. Horizontal native preview keyboard pan verified 0 → 283 → 566 px and back to 0. Light/Dark controls work; FAQ explains authentic components versus replicas. Reduced-motion fixture restores original DOM; missing-module fixture preserves the loaded native image. No Mac preferences modified by these fixtures.

Fresh independent finish review inspected all three user references, source, desktop/mobile and normal viewport proofs: ship. Documenter preserved existing DESIGN.md. `docs/product_spec.html` remains absent, so its lessons section could not be read; repository AGENTS lessons and available product/design context were used.

Earlier real-data images remain in historical PR commits, not current assets; no Git history purge. No analytics, signup activation, deployment or merge. Required CI and explicit user visual approval remain the merge gates.
