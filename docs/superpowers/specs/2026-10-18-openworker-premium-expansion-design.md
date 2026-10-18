# Pulse: OpenWorker feature expansion and premium application shell

Date: October 18, 2026. Status: design approved October 18, 2026 (user: “go ahead”); implementation complete for the adapted Mac workspace; validation and user review in progress. User requested all non-connector OpenWorker capabilities adapted for Mac optimization and utility, including detached agent-generated conversation titles. This document makes the proposed boundaries reviewable; it does not claim feature parity or approval.

## Evidence and baseline

- Upstream: https://github.com/andrewyng/openworker. Source reviewed at `5bf0d2fb8c728932fdbc6b49a24113aebc2a4ddd`, the same pin already used by Pulse, in `/tmp/pulse-openworker-research-20261017`. Public repository README also checked online. This is a pinned-source comparison, not a claim to have audited every subsequent upstream change.
- Live OpenWorker app inspected through its macOS UI: conversation transcript/composer/sidebar; automation list, templates and unsaved creation form; General and Memory settings. No automation created, settings saved, or model prompt submitted. Installed app advertises an available v0.3.1 update; its exact running revision was not established. Pinned source and installed UI may differ.
- Live Pulse inspected at this workspace's `pulse/dist/Pulse.app`: native navigation plus embedded conversation rail currently creates two sidebars; long generic/prompt-fragment session names make recents difficult to scan.
- Read Pulse `index.md`, product spec §12 decisions, previous OpenWorker port design, runtime/frontend READMEs, server/storage/memory, native agent lifecycle, root/sidebar/theme and web bridge.
- Workspace HEAD `6604390`, branch `feat/openworker-pulse-runtime`; remote main `cb1b283`, 22 commits behind HEAD and no commits ahead. Existing runtime work is in open PR #89 into main. Preserve it and unrelated untracked user files. Do not reset the workspace or merge PR #89 without user approval.

## Approaches

1. **Expand the current native host and pinned engine (recommended).** Port OpenWorker product semantics and selected UI source, keep Pulse kernel collectors, native controls, signing, authenticated bridges and local storage. One application shell, one native tool execution path. Lowest lifecycle and permissions risk.
2. Embed the complete upstream frontend/server. Closest general-purpose parity, but imports always-on scheduling, connectors, shell/workspace management, cloud/team coupling and another navigation/settings model. Conflicts with Pulse's lightweight native background operation.
3. Restyle current screens only. Smallest diff, but does not deliver automations, richer memory or detached titles. Insufficient for this request.

## Product scope and delivery order

This spans independent systems. Deliver complete vertical slices in order; do not hide unfinished buttons behind a visual redesign.

| Slice | Included behavior | Existing code to extend / upstream reference |
| --- | --- | --- |
| 1. Conversations and titles | Search canonical chat text, rename, pin, group/filter recents, archive/restore, per-session drafts, stable selection; independent title-agent jobs | `conversation_store.py`, `server.py`, `AgentClient.swift`, `AgentModel.swift`, `SidebarView.swift`, web bridge; upstream `conversations.py`, `sessions.py`, `Sidebar.tsx`, manager auto-title methods |
| 2. Automations and attention inbox | Create/edit/pause/resume, daily/weekdays/weekly/one-time schedules, timezone and next-run preview, run now, per-run transcripts/status, catch-up and overlap rules, cancellation and attention routing | Native app lifecycle plus durable schedule/run records; upstream `automation/models.py`, `store.py`, `scheduler.py`, `tools.py`, `inbox.py` and automation UI |
| 3. Memory and working context | Search/add/edit/remove explicit memories, provenance and evidence, editable user instructions, enable/disable, visible save receipt with Undo; tasks/plan/evidence drawer | Existing `memory.py`, SQLite memories, typed bridge and cards; upstream Memory settings, `RightRail.tsx`, `tools/todo.py` |
| 4. Whole-app design | Unified navigation, shared native/web tokens, matching headers/forms/cards/settings, all Mac utility screens and menu-bar popover, polished responsive empty/loading/error/result states | `Theme.swift`, `ThemePreset.swift`, `RootView.swift`, `SidebarView.swift`, existing views; upstream `styles.css`, `Sidebar.tsx`, `Composer.tsx`, `Transcript.tsx`, `SettingsView.tsx` |
| 5. Broader non-connector features | Local attachments and inspectable report artifacts, bundled Mac-specialist skills/personas, bounded delegated investigations and voice input | Upstream attachments/artifact handling, skills/personas, `tools/subagent.py`, voice settings; requires separate focused designs for file grants, artifact viewing and microphone permission/provider disclosure |

Connectors are excluded as requested. Full generic OpenWorker parity also includes cloud accounts, remote machines, team work boards, arbitrary workspace/shell execution, security scanners, sandbox provisioning and automatic approval rules. Proposed adaptation retains their useful Mac-facing outcomes through typed native operations, rather than importing these infrastructure systems. This boundary needs the user's design approval; it is not an assertion that every upstream non-connector capability is already covered. Voice/files/delegation are tracked scope, not silently dropped or claimed shipped by slices 1–4.

## Detached conversation title agent

Upstream manager `_maybe_autotitle` retains independent asyncio tasks and `_generate_autotitle` makes a small, non-streaming completion on the session's model. It uses up to two opening user messages plus 400 characters of the first assistant reply; skips generic small talk; preserves manual titles and updates live viewers.

Pulse will create a separate, retained, tool-free title-agent run with a bounded excerpt of the first exchange and an immutable provider snapshot. It has no telemetry, memory-write or native tool capability and does not share the conversational engine or approval state. Trigger after first useful exchange; bounded second opportunity for a greeting-only opening. A provisional title appears immediately. Title failure leaves that fallback and does not fail the conversation.

Persist title origin (`provisional`, `generated`, `manual`) and revision. Commit generated titles only if the conversation still exists, revision is unchanged, and no manual title won meanwhile. One in-flight title per session; bounded global capacity shared with existing provider worker limits, explicit timeout and cancellation at shutdown. No untracked background threads, per-token title calls or permanent retry loop. Account for title tokens/cost in the existing durable usage ledger with a distinct purpose; report incomplete billing honestly. Notify the host after completion rather than adding sidebar polling. Include title jobs in daemon-idle leases so the current two-second teardown cannot kill them silently.

## Automations without an always-on agent daemon

Upstream scheduler polls every 30 seconds in the always-on server. It catches up once after downtime, skips overlaps and records each fire. Pulse currently stops Python/native RPC after two hidden idle seconds. Copying upstream scheduler directly would either miss schedules or retain Python indefinitely.

Use a native deadline timer in the already-running menu-bar app, with no timer when no schedules are enabled. Persist schedules and durable occurrence claims behind a single native scheduling owner. Use native Calendar/timezone calculations for supported repeat presets; no custom cron parser or extra always-on service. Reconcile after launch, wake, significant clock/timezone change and schedule edits. Never wake a sleeping or quit Mac, change keep-awake or enable launch-at-login implicitly. State this behavior in the editor.

On a due occurrence, atomically claim its identity before starting work; start the existing agent runtime on demand, execute a fresh bounded run, persist its transcript/result, and release runtime leases afterward. The run identity must survive an uncertain HTTP acknowledgement so retries cannot launch duplicate work. A crashed in-progress occurrence becomes interrupted, never silently replayed as a new mutation. Catch up once for a missed interval, then resume the future schedule; do not replay every missed period. Skip overlapping runs for the same automation. Respect global provider/native concurrency limits and retain pending due work when capacity is full. Pausing prevents future fires; cancelling the current run is a separate visible action.

Unattended mutations never self-approve. Use existing exact-action preview/decision gates; route outstanding decisions into a durable attention inbox. A waiting item must survive daemon teardown without retaining a live approval coroutine or actionable expired preview: reopening performs fresh preview/revalidation before approval and execution. Never automatically retry a previously committed action. Scheduled runs cannot create recursive schedules or change memory/instructions without explicit review.

Seed templates with real Pulse tools: morning Mac check, weekly storage-growth report, battery/energy review. Reports distinguish missing historical coverage from healthy/zero. Do not offer connector-backed templates or claim folder sorting when no native move tool implements it. Automation editor previews the model/provider and potential paid usage; disabled provider configuration produces an actionable blocked state.

## Memory, instructions and progress

Extend the existing bounded store; do not create a second memory database or unbounded automatic extraction loop. Add validated editing and user-authored instructions, with revisions and truthful provenance. Preserve the current 100-row, 400-character memory/evidence limits and 6 KB recall bound unless measurements justify changes. Memory off continues to disable both recall and saves; upstream off only stops saving, which is deliberately not copied. Editing/deleting affects future context construction, not already submitted model requests.

Memory content and instructions cannot grant native permissions. Existing best-effort secret/path filters remain, but are not described as proof of secret detection. Undo of a save deletes only that exact unchanged memory revision; concurrent edits cannot be erased accidentally. No hidden transcript-derived memory extraction call in the initial memory slice. Make actual saved preferences and verified lessons visible beside chats.

The optional right drawer shows current plan/tasks, timestamped native evidence, action receipts and usage. Canonical persisted IDs reconcile live and reopened state. Completed/failed/declined/unknown remain distinct. No display reasoning, arbitrary HTML, executable artifact preview or duplicate tool authority.

## Visual specification

Audience: Mac owners investigating slowness, storage and everyday utility. Primary job: see what needs attention, ask Pulse to investigate, review evidence and approve exact remedies.

One resizable 240–280 pt sidebar: Pulse wordmark; New conversation, Search, Automations and Memory; recent chats; grouped Mac tools; Settings/status footer. Keep all existing routes, command palette and shortcuts reachable. Remove the second web conversation rail once native navigation owns recents. Ask Pulse has a centered session title/model header, readable 720–820 pt transcript, anchored rounded composer and optional 300–340 pt evidence drawer. Narrow windows collapse the drawer first; no fixed three-column squeeze at 860 pt. Preserve unsent drafts during layout/view teardown.

Upstream-derived neutral tokens: dark canvas `#191B1F`, chrome `#16171B`, raised surface `#212329`, text `#E5E7EB`, blue action `#4C8DFF`; light canvas `#FFFFFF`, chrome `#FAFAFA`, ink `#17191C`, border `#E8EAED`, action `#2563EB`. Keep semantic health colors separate from the accent. Add these through HALO rather than styling web and native pages independently; retain paired appearance modes and existing user theme settings.

Use native system typography in SwiftUI and a matching system stack in WebKit; monospaced digits/data and code. This deliberately adapts upstream Inter/Manrope/JetBrains typography to avoid extra fonts and mismatched native metrics. Page titles 26–30 pt, body 14–15 pt, utility labels at least 12 pt; preserve Larger text and contrast. Hairline divisions, restrained 10–16 pt radii, generous page spacing, minimal shadows. Signature: calm investigation workspace with exact evidence close at hand. No decorative gradients, ambient motion, spinning token cursors or telemetry-driven animation.

Apply the same header/spacing/form/row treatment to Home, storage, Apps, energy, Internet, Displays, Activity, advanced tools, Settings and popover; changing only Ask Pulse does not meet the whole-app request. Preserve native lists, lazy evidence loading, stable changing text, permission feedback, keyboard navigation and VoiceOver labels.

## Validation and release gates

- Title fixtures: independent task, model error/timeout, greeting retry, manual-rename race, archive/delete while in flight, provider switch, billing, reopening and idle lease release.
- Chat fixtures: canonical search pagination, archive/restore, selection/drafts, malformed IDs and stale writes; history changes never modify UndoJournal receipts.
- Automation fixtures: exact occurrence claiming, duplicate dispatch, DST gap/repeat, timezone changes, sleep/quit catch-up, overlap, capacity exhaustion, edit/pause/run-now, crash/restart, cancellation and pending review with fresh previews. No shell collectors or unattended approval bypass.
- Memory fixtures: edit validation, disabled recall/writes, bounded context, concurrent Undo, provenance, instructions never granting permissions.
- UI review: actual bundled WKWebView and native pages in light/dark, Larger text, keyboard/VoiceOver, minimum window, long transcripts, reopen and scroll retention. Verify source-derived changes with existing React fixtures.
- Run `make agent-test`, `make assistant`, `make build`, `make test` and `make bundle` from `pulse/` as appropriate. Measure quiet hidden two-second monitoring separately from interactive agent/WebKit/scheduled-run costs. Existing 59.1 MiB hidden measurement remains an unresolved baseline, not budget compliance.
- Branch from refreshed main; carry the already-reviewed runtime dependency without dropping it, and make PR dependency/scope explicit. No commit to main, no merge of #89 or successor on CI alone. Required macOS CI, running app handoff and explicit user visual/functional approval remain mandatory.
- Retain MIT provenance for adapted OpenWorker code. Update READMEs, index, log and product decisions as each slice actually ships; never label the roadmap as implementation.

## Review decision

Recommended: approve this native-host adaptation and sequence, including the bounded detached title agent, native scheduling wakeups and the explicit broader-feature follow-up scope. Implementation must not silently replace this with a cosmetic-only change or claim all upstream features shipped. Research is complete enough to start the first focused implementation design after approval; no implementation or live-provider tests have run for this expansion.


## Implemented boundary (October 18)

Implementation follows the native-host approach on `feat/openworker-premium`, retaining runtime dependency #89. One native sidebar fronts real workspace feature pages. Chat metadata/search, independent bounded title jobs, native app-resident schedules, read-only unattended runs and review drafts, editable memory/instructions with revision-guarded Undo, persisted task progress, evidence/export drawer, bounded tool-free second opinions and Mac specialist focus modes are implemented. Selected UTF-8 text attachments and Markdown export use native panels. Dictation uses only supported on-device recognition, explicit permission requests, thirty-second bounds and session/generation cancellation.

Deliberate adaptations: supported schedules use native repeat presets rather than a cron editor. Archived search is an exclusive filter. Attachments are selected text files (8 KB), not arbitrary binary documents or a filesystem browser. Specialists are bounded diagnostic focus profiles with existing Pulse skill/tools, not independent cloud/team agents. Delegation is a single tool-free second opinion per run. Automation review prepares an unsent draft, never replays expired approval or commits a scheduled mutation. Notifications require existing macOS authorization. Full upstream team/cloud/remote-machine/sandbox/workspace infrastructure, connectors and automatic action approval are not imported. These are explicit product boundaries, not hidden claims of full OpenWorker parity.

Local deterministic checks currently pass: 75 backend tests, 402 Swift tests, React fixtures/typecheck/production asset build. Source review corrected standalone server route registration, stale task writes, cold startup coalescing, cancellation forwarding, paused-task edits, one-time catch-up consumption, Unicode request bounds and dictation generation/session races. Final bundle/visual/resource evidence and CI are recorded in the companion plan; this paragraph does not certify live providers, full VoiceOver, dictation hardware/languages or background RSS compliance.
