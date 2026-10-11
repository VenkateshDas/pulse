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
