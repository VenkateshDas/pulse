# Pulse diagnosis, observation, and targeted remedies

User-approved scope: implement the gap audit across the native app, CLI, agent toolkit, and portable skill. Reuse PulseKit and existing pages; no new dependencies or background daemon. Keep existing visibility gating, cleanup protections, and the user merge gate.

## Implementation sequence
1. Correct native PID enumeration and CPU timing; share native process identity, detail and coverage; add independent workload/coverage checks.
2. Add VM swap/compression deltas and native storage I/O, with explicit unavailability. Extend snapshots and structured CLI vitals without breaking old fields.
3. Add a bounded, cancellable observation engine (2-second cadence) with synchronized samples, weighted resource summaries, persistence evidence, process contributors and actionable findings. CLI `observe` and Monitor use the same report. No observation starts automatically.
4. Expose process detail/grouping, read-only network configuration, bounded HTTP timing, existing metric/storage/battery histories, startup inventory, and independent sleep assertions. Native app shows the same evidence on existing pages or the Monitor diagnostic sheet.
5. Add a native graceful application quit with exact identity, preview, user consent and post-action status. Do not expose legacy blanket optimization tasks or force-kill system processes.
6. Correct proxy and Wi-Fi gates, retain partial-failure exits in agent tools, and synchronize the portable skill with CLI capabilities and symptom-directed workflows.
7. Validate via make build/test/cli-smoke, native runtime observation and bounded UI review; update index/log/docs; open a PR, wait for CI, then hand off for user visual/functional approval. Never merge without it.

## Data and limits
RSS and footprint are separate; summed RSS is not exclusive physical usage. Per-process CPU uses one core = 100%; whole-system CPU = 100% across all cores. Counters and PID identity must reset on process restart. Unreadable processes and missing sensors are disclosed. Historical events do not prove coverage; old PID-only records do not identify a current process. Current activity and cached evidence carry timestamps.

Browser helper roles are derived from bounded native argument reads. Exact tab mapping uses the browser's task manager; Pulse will not enable debugging ports or scrape browsing history. Network timing measures one explicitly selected public HTTP(S) destination, no speed-test fiction. Startup inspection is read-only; disabled helper removal and blanket maintenance remain outside diagnosis.

## UI
Monitor gets an Investigate button opening a scrollable evidence sheet: observe/stop, current coverage, VM/disk activity, contributors, process identity/role, network checks, history, startup and sleep evidence. Results stay reviewable after completion and can be copied. Navigating away or hiding the window cancels observations. Existing Monitor process detail exposes footprint, executable and helper role.

## Acceptance
A slow-Mac/browser request yields reproducible interval evidence, distinguishes sustained from transient load, discloses blind spots, identifies app/helper contributors and offers a targeted remedy. The CLI and UI consume shared structs. Before/after observations allow verification without assuming causality. Failed reads never count as healthy or successful actions. No new shell-based data collectors.
