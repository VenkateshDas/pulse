# Accessible Pulse implementation checklist

Approved by the user's October 11 instruction to implement in goal mode. Branch: `feat/accessible-pulse-redesign`. Follow the complete [design](../specs/2026-10-11-accessible-pulse-redesign.md).

## Foundation

- [x] Research, audit, design approval, product and design context.
- [ ] Readable theme pairs, shared typography, Larger text, restrained surfaces.
- [ ] Native adaptive navigation, stable route identifiers, contextual navigation, search.
- [ ] Shared accessible headings, rows, loading/empty states, results and chart summaries.

## First experience

- [ ] Home condition explanation, common tasks, meaningful status and actual recent results.
- [ ] Attention actions review before removal; clear action labels and snoozing.
- [ ] Welcome without expertise choice; contextual permissions with actionable recovery.
- [ ] Menu bar popover and command search use the same reviewed action paths.

## Space and apps

- [ ] Storage sub-navigation: Cleanup, Files, Duplicates, Changes, Trash.
- [ ] Cleanup review, selections, progress, cancellation, schedule, outcome accounting.
- [ ] Files/list/map, inspector, breadcrumbs, protection and folder evidence.
- [ ] Duplicate folders, retained copies, selection names and honest clone accounting.
- [ ] Changes/date ranges and missing-history guidance.
- [ ] Trash, recent removals, restores, permanent-delete confirmation.
- [ ] App search/removal review, running apps, related-file confidence, orphan scan.

## Everyday controls

- [ ] Battery & energy, desktop/unavailable states, estimate labels and details.
- [ ] Internet: manual test, opt-in automatic tests, explicit location request, cancellation.
- [ ] Displays: adjustable labeled controls, unsupported states, sync/manual override.
- [ ] Settings: groups, appearance/text, named toggles, validation, permission/provider help.

## Remaining tools

- [ ] App activity and process inspector; safe quit and coverage explanations.
- [ ] Slowdown investigation, start/stop, context, comparison and limitations.
- [ ] Maintenance selection/previews, explicit effects, privilege and results per task.
- [ ] Diagnostics, startup helpers and benchmarks remain reachable.
- [ ] Activity: observations, storage history and actual removal journal kept distinct.
- [ ] Ask Pulse: provider setup, labeled composer, approval impact, errors, sessions.
- [ ] Shortcuts share reviewed action behavior, named recorder and conflict guidance.

## Validation and delivery

- [ ] Meaningful tests for routing, contrast, selected actions, opt-in network work and results.
- [ ] `make build`, `make test`, `make bundle` from `pulse/`.
- [ ] Runtime page/keyboard/accessibility/screenshot matrix at compact and default size.
- [ ] Light/dark/theme/Larger text/accessibility setting and localization stress checks.
- [ ] Baseline and redesigned release CPU/RSS measurements with visibility states.
- [ ] Update product-spec decisions, wiki and change log with verified results/limitations.
- [ ] Commit, push, open/attach PR, wait for required macOS CI.
- [ ] Hand running app to user for visual/functional review; do not merge automatically.

## Evidence and limitations

Record authoritative commands, runtime checks and remaining limitations here as stages finish. Human usability study and hardware configurations unavailable locally must be reported honestly; do not fabricate verification.

### Implementation checkpoint

Shared palette, Larger text, native task navigation, Home, welcome and contextual permission help are implemented; runtime/accessibility review is pending. Storage routing now opens cleanup first. Duplicate removal requires an explicit scan and retained-copy review, and verifies current file hashes before moving selected copies. Display brightness uses a named native slider and turns off automatic matching on manual override. Network tests are manual by default, use bounded native HTTPS transfers, identify estimates and support cancellation. Maintenance now runs only reviewed selections; fixture tests cover omitted and unavailable tasks.

`make build` from `pulse/` passed after the maintenance changes. `make test` passed: 344 tests in 75 suites, including colour contrast, maintenance selections and historical speed-test decoding; do not treat this checkpoint as whole-app completion. Remaining page redesign, runtime validation, release performance measurement and PR/CI are still required. Existing shell-backed maintenance engines require an architecture audit before delivery.

### Second implementation checkpoint

Apps now leads with search and an explicit review, native selection controls and accurate related-file confidence/recovery language. The menu bar leads with a condition explanation, optional readings and reviewed cleanup/maintenance routes; Trash confirmation/results stay inline. Battery distinguishes hardware readings and estimated processor-based attribution. Activity shows actual removal records separately from observations. Ask Pulse explains provider setup, exposes conversation controls and named send/stop actions, preserves cancelled drafts and rejects late stopped-stream events. Navigation handoffs survive a closed window.

Runtime release checks through CUA verified Home, app navigation, search empty guidance and Battery/Internet. The app list initially expanded outside the window; constraining detail content to the split view geometry fixed it, verified by screenshot and successful search interaction. Internet has since been simplified further and requires another runtime review. Sidebar/table content is still being audited at compact size and Larger text. The latest unit run passed 351 tests in 79 suites.

Cleanup now has cancellation propagated to native scanners; Files/App activity adapt inspectors to a sheet at narrow widths. Diagnostics is manually refreshed and separates sensors/properties/open files. Shortcut identities remain stable but destructive/expensive routes open review pages. Legacy shell-backed maintenance and history/snapshot collection were disabled to meet current repository instructions, with explicit unavailable states; previous records remain. These are material capability limits and must appear in the final PR. Native saved-window-state maintenance skips active apps. Icon retention is now bounded to small 2× list rasters; release performance measurement is pending.

The latest full test run remains green at 351 tests after bounded icon rasters, readable text without shrinking, and opt-in notification/reminder changes. Notifications no longer prompt on launch; the weekly option accurately describes a reminder rather than an unbuilt report. The automatic-cleanup card now requires an explicit enable review, and its manual action opens candidates for review rather than silently clearing all recommended files. Latest UI copy/control edits are receiving a build check.

### Implementation checkpoint — task shell and recovery audit

Commit `52a2e2a` captures the full current redesign across 73 files. The latest debug build succeeded (61.55s); the previously completed full suite passed 351 tests. Window title and occlusion filter now both use Pulse, hidden shortcut controls are excluded from accessibility, and secondary navigation has a visible More heading. Release packaging is running; memory and whole-surface runtime validation are not yet proven. The recovery audit found the GUI app mover sends Finder Apple Events off-main and related-file recovery recording is non-atomic; these require correction before delivery.

### Recovery correction and release observation

The release bundle succeeded with the stable Pulse Local Signing identity. Runtime confirms Pulse window title, More navigation heading, and Internet connection/manual test/expandable-details first layer. A fresh visible instance measured 98,672 KiB RSS, above the required memory budget; no performance compliance is claimed. GUI native app, related-file and leftover-helper moves now use atomic journal Trash operations; Finder Apple Events run on MainActor only for a typed denied file-move error. Journal/rollback failures cannot enter Finder fallback. Three disposable fixture tests cover native move/restore, failed journal leaving app intact and protected bundle refusal; 354 tests in 80 suites passed before the final typed-error refinement, with verification running again.

Final typed-error refinement verification: `make test` passed 354 tests in 80 suites. Runtime Battery overview confirms hardware/history/condition disclosures start collapsed and charge-history accessibility includes range, latest reading and gaps.

### Display accessibility and memory inspection

Runtime shows a native brightness slider visually, but the accessibility tree exposes only container/text. Removed wrapping group label and hidden value-label modifiers; explicitly named the slider and matching toggle. Matching is disabled without an external screen. Release verification is running. Native vmmap/heap on the redesign instance reported 80.1 MiB footprint (104 MiB peak), 30.9 MiB allocated heap, including a 2.1 MiB folder-activity dictionary and 2.6 MiB string storage. This provides a retained-memory lead; it does not prove RSS budget compliance. No actual brightness or matching changes were made.

Display follow-up: the first grouping/label change did not expose the SwiftUI slider in the release accessibility tree. Replaced it with native AppKit NSSlider, with explicit label/value description, continuous manual brightness updates and persistence after mouse/keyboard editing. `make build` passed; release runtime recheck is in progress. Activity audit also found historical breakdown rows using mouse-only tap gestures and a disk-growth label even for decreases; keyboard controls and clearer summaries remain to fix.

### Verified native slider and broader accessibility corrections

Release runtime now exposes brightness as a settable slider with a monitor-specific label, numeric value and percentage description. Matching is disabled on the tested single-screen Mac. Activity rows now use native buttons for recorded breakdowns, storage-change copy covers decreases, and the chart has a text summary; debug build passes. Startup helpers now use named native switches, explain next-sign-in effects and coverage, keep raw identifiers/programs in expandable details, and block duplicate changes while applying; debug build passes. Restored 2-second unlocked sampling so 900 samples match the stated 30-minute chart window, with process enumeration kept sparse (10s visible / 24s hidden). Full tests running. Apple allocator documentation confirms pressure-relief API exists, but no allocator tuning was introduced without evidence of a suitable lifecycle trigger: https://github.com/apple-oss-distributions/libmalloc/blob/main/include/malloc/malloc.h .

`make test` completed successfully after the native slider, Activity, Startup helper and cadence changes: 354 tests in 80 suites. The release native-slider AX check is verified; revised Activity/Startup rendering and final 2-second performance measurements still need the next release runtime pass.

### Performance test and condition wording

Replaced the benchmark rating table and crowded fixed row with an effects explanation, native Start action, explicit running state, adaptive result facts, comparison limits and expandable fixed-reference method. Synthetic scores no longer claim a hardware class or thermal diagnosis. Debug build passes. Home/menu-bar condition summaries now acknowledge recorded attention even when current diagnosis is clear; added three regressions. `make test` passes 357 tests in 81 suites. These latest pages still require release runtime verification.

### Conversation-stop race

Cancellation acknowledgements now carry the generation of the stopped run, so an older acknowledgement cannot overwrite a later conversation’s stop status. Added a controlled two-request asynchronous regression with no provider/network traffic. `make test` passes 358 tests in 82 suites.

### Provider setup and investigation lifecycle

Provider fields now have explicit accessibility labels; saving verifies the Keychain value before claiming success, prevents duplicate saves, and accepts remote HTTPS or HTTP on explicit loopback hosts only (no URL credentials/query/fragment). Existing invalid saved endpoints are blocked before starting Ask Pulse. Two pure endpoint tests cover accepted/rejected addresses without credentials or network calls. Investigation/inspector captions now follow shared 12pt/Larger text typography; investigation occlusion handling matches the renamed Pulse window. `make test` passes 360 tests in 83 suites; the final disabled-Save affordance is a subsequent UI-only change. Runtime confirms renamed Home condition copy, named Startup switches/read-only explanations, and adaptive Performance test facts/method disclosure. No actual helper or benchmark operation was invoked.

### Draft PR and timed measurement

Draft PR #84 is open and attached: https://github.com/VenkateshDas/pulse/pull/84 . Required CI is being checked; no merge approval exists. A 60-second visible Performance-test-page measurement (no test workload) reported redesigned CPU 0.749%, RSS 62,928–79,984 KiB. The existing Pulse instance reported 3.311%, RSS 38,864–113,328 KiB; its window state/build provenance is not sufficient for a formal baseline claim. The source tree of its worktree commit matches main, but the running artifact was not rebuilt as a controlled baseline. User delegated budget interpretation; selected strict background-monitoring target, with explicit interactive-cost reporting. Window-close measurement is running, not yet proven.
