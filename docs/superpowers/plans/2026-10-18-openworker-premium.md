# OpenWorker premium expansion implementation plan

> **For agentic workers:** Execute approved design in this chat, with focused cavecrew investigations/builds and review between slices. User authorized execution on October 18, 2026.

**Goal:** Make Pulse a premium native Mac investigation workspace with durable agent productivity features.

**Architecture:** Keep Swift app, kernel collectors, authenticated bridge and pinned TurnEngine. SQLite owns conversational state; native deadline scheduling owns wakeups. One native sidebar and shared native/web tokens avoid duplicate shells.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation Calendar, Python asyncio/SQLite/FastAPI, React 19/TypeScript, existing pinned OpenWorker providers.

**Spec:** `docs/superpowers/specs/2026-10-18-openworker-premium-expansion-design.md` (approved by user: “go ahead”).

## Global constraints

- No collector subprocesses, no arbitrary shell tools, no automatic mutation approval.
- Background two-second sampling target: <1% CPU, <50 MB RSS; report interactive costs separately.
- No data-driven animation. Publish only visible UI. Keep changing readings layout-stable.
- Existing explicit memory bounds, Keychain, provider binding and UndoJournal remain authoritative.
- Existing runtime PR #89 is an unmerged dependency; fresh feature branch starts from updated main and fast-forwards that dependency. No merge without explicit user review approval.
- Build/test through `make` from `pulse/`. Preserve unrelated untracked user content.

## 1. Durable conversations and detached titles

Files: `pulse-agent/conversation_store.py`, `server.py`, new `title_agent.py`, `test_workspace.py`; `PulseKit/AgentClient.swift`, native `AgentModel.swift` and web bridge.

- [x] Extend SQLite with additive conversation metadata (manual/generated origin, revision, pinned, archived) and validated bounded cross-conversation search. Preserve existing inserts/imports by using a separate metadata table.
- [x] Expose authenticated list/search/metadata updates; reject updates to active session writers. Archive restores history, never erases UndoJournal.
- [x] Add retained independent tool-free title jobs with immutable config, shared provider worker bounds, timeout, optimistic revision updates and durable purpose-specific billing.
- [x] Test migration compatibility, chat search/archiving, title race/failure/greeting handling and billing through `make agent-test`.

## 2. Memory and instructions

Files: existing store/memory/server, new workspace tests, native model/client and feature page.

- [x] Centralize existing memory validation; add user editing, provenance/revision and exact-revision Undo. Add bounded persisted user instructions, never action authority.
- [x] Expose authenticated edits with active-run guards; preserve memory off = no recall/no writes.
- [x] Verify existing memory tests plus edit/duplicate/secret/disabled/instructions behavior using `make agent-test`.

## 3. Native scheduled runs

Files: new `PulseKit/AutomationSchedule.swift` and tests, new native `AutomationModel.swift`; app/RootView lifecycle, existing AgentModel/client/server.

- [x] Implement Calendar-backed once/daily/weekdays/weekly schedules with pinned timezone and DST behavior. Verify deterministic date tests through `make test`.
- [x] Persist bounded task/run records atomically in Application Support; one timer at next deadline, launch/wake/timezone reconciliation, catch-up once and overlap skip.
- [x] Claim occurrence durably before dispatch; use occurrence ID as runtime request ID. Runs use native tools in investigate mode; requests for changes become durable attention items, never unattended mutation commits.
- [x] Run on-demand agent with global runtime leases, independent of visible conversation; store run transcript/session ID, cancellation/errors, notify only when enabled and granted.
- [ ] UI creates/edits/pauses/runs/cancels and opens run transcripts; explain app-running/sleep/catch-up semantics. Verify fixtures and actual bundled app.

## 4. Unified shell and rich assistant pages

Files: `RootView.swift`, `SidebarView.swift`, `ThemePreset.swift`, `Theme.swift`, native web bridge, `pulse-assistant/src/{bridge.ts,main.tsx,style.css}` and focused feature components.

- [x] Move recents into native sidebar with New, Search, Automations, Memory, Mac tools and footer settings. Preserve command palette, shortcuts, native utility routes and drafts.
- [x] Remove second web rail; add centered conversation header, readable transcript, anchored composer and responsive evidence drawer. Native/web colors use one token palette.
- [x] Build real memory/search/automation/inbox pages with keyboard-accessible forms, error/result states, no decorative feature stubs.
- [x] Apply shared page headers/cards/control typography and neutral premium theme throughout native utility pages/popover. Preserve contrast, Larger text, native list performance and exact-action review.
- [ ] Run `make assistant`, `make build`, `make test`; capture light/dark/minimum-window bundled app states.

## 5. Broader Mac utility features

Files: dedicated bounded backend capability module, toolkit integration, native web commands and assistant utility controls.

- [x] Add local text attachment ingestion with explicit picker, size/type bounds and disclosure; no implicit directory grants. Safe report export uses native save panel.
- [x] Add Mac-specialist modes/bundled skills, bounded tool-free second-opinion delegation, task checklist persisted with conversations, optional native dictation route through macOS where available without adding external voice dependency.
- [x] Verify trust boundaries, cancellation, limits and no hidden provider calls. Expose only working supported features.

## 6. Review and delivery

- [x] Review source diff for races, duplicate scheduling, stale previews/permissions, data retention and lifecycle leaks. Correct findings before completion.
- [x] Update design status, README/source provenance, index/log and product decisions with actual implemented boundaries and validation.
- [ ] Run required make checks, package through `make bundle`, launch correct workspace bundle and verify feature paths. Measure background after hidden idle; distinguish baseline failures.
- [ ] Commit feature branch, push/open draft PR with dependency #89 clearly stated, wait required macOS CI. Hand app to user for visual/functional review. Do not merge.


## Validation record — October 18, 2026

- Design approved in chat (“go ahead”). Feature branch created from refreshed main, then fast-forwarded unmerged runtime dependency `6604390`; original PR #89 remains untouched.
- `make agent-test`: **75 passed**, deterministic providers only; includes detached title cancellation/races/billing, task ownership, standalone route registration, memory edits/Undo and approval-gated automation tools.
- `make test`: **399 passed in 92 suites**. New Calendar DST/timezone tests and scheduler persistence/recovery/overlap/capacity/cancellation/manual catch-up/duplicate-creation checks.
- `make assistant`: fixtures, TypeScript and production bundle pass. `make build` debug passes. `make bundle` produced an arm64 review app signed with installed `Pulse Local Signing`; final source-set rebuild recorded below after completion.
- Review corrected packaged `__main__` route ordering, startup coalescing, cancellation forwarding, run-owned tasks, paused automation editing, Unicode bounds, late dictation callbacks, native draft publication, title billing refresh and duplicate scheduled tasks.
- **UI validation blocked:** macOS computer-use tool reports “The Mac is locked and automatic unlock could not unlock it.” User asked asynchronously to unlock. Existing Pulse was quit for review-bundle restart; no Pulse process currently runs. Did not bypass lock, activate microphone, change provider settings, submit paid prompts or create production test automations.
- Full bundled light/dark/minimum-size/accessibility/voice checks, live-provider semantic checks and quiet background CPU/RSS measurements remain unverified. Existing hidden 59.1 MiB baseline remains unresolved; no claim of performance-budget compliance.
- PR/CI and final review-bundle status appended on completion. No merge authorization granted.
