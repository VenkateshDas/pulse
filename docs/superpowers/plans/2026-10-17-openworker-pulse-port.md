# OpenWorker → Pulse implementation and validation

Date: 2026-10-17. Branch: `feat/openworker-pulse-runtime`. Upstream: MIT OpenWorker `5bf0d2fb8c728932fdbc6b49a24113aebc2a4ddd`. Scope: agent runtime and conversation UI, retaining Swift host/native tools/Keychain. User asked to implement and deepen reliability after source research. This is not merge approval.

## Sequence completed

1. Inspected pinned upstream runtime, assembly, providers, context/compaction, tools/risk/permissions, sessions/memory, server and React components. Recorded component map, upstream pitfalls and deliberate Pulse differences in the source design. Baseline existing harness tests passed.
2. Replaced Agno execution with direct construction of real upstream TurnEngine. Adapted async native tools, closed allowlist, exact mutation consent and native cancellation; immutable explicit provider clients. Deleted obsolete Agno agent/budget modules. Agno and SQLAlchemy remain migration-only.
3. Added canonical SQLite WAL, stable canonical identities, transactional checkpoints/decisions, structured compaction restore, session-scoped result offload/paging, searchable dialogue and explicit memory. Legacy import backs up SQLite with WAL, preserves data/provenance and rolls back on failure. Imported approvals never execute.
4. Bounded queues, shared blocked-worker capacity, prompt/output/result/replay/run limits, summary/interaction deadlines and provider inactivity. Stop before setup is recorded as a bounded tombstone. SSE reconnect observes existing work; exhausted observation/replay failures cancel unseen work. No mutation retries. Storage cleanup errors cannot suppress terminal events. Checkpoint retries do not duplicate messages.
5. Replaced assistant-ui with adapted React transcript/composer/review behavior and safe Markdown. Added native per-session drafts, read-only mode, separate questions/plans, truthful tool status/history, partial answers, copy acknowledgment and incremental bridge patches. Fixed final-answer clipping under content-visibility layout changes with scroll-follow resize observation.
6. Keychain Save writes first, caches immediately and updates config only on success. No routine authentication UI. Off-main bounded/coalesced reads, generation invalidation, endpoint snapshots and form-load revisions prevent stale keys/config. Added private rotating JSONL diagnostics and native OSLog timing/status. Startup log appends/rotates; never inject keys into browser state.

## Local evidence

- `make agent-test`: **38 tests pass**. Real pinned engine fixtures cover native reads, restart history, exact approvals/duplicates, read-only mutation/memory denial, questions separated from action authority, unknown shell denial, nested-result paging/isolation, compaction budgets/deadlines/cancel, shared blocked-worker limits, pending expiry, early Stop, partial output, replay/lost-continuation recovery, transactional retry identities, real Agno public-API migration/backup/idempotence/rollback, memory limits/filters and diagnostic redaction.
- Long-session regression runs **120 turns**, repeatedly reconstructing the engine from persisted checkpoints. Checks bounded outbound context and structured compaction rather than recursive rendered summaries; canonical early details remain searchable. Fixture summary quality is deterministic and does not prove a real model's summarization quality.
- `make test`: **380 tests in 88 suites pass**. Includes six isolated credential lifecycle cases and native reducer/control regressions. Tests use injected credential closures; no user Keychain modification.
- `make assistant`: **3 frontend tests pass**, TypeScript and Vite build pass. Generated assets committed; tests cover grouped transcript boundaries/stable identity and incremental patches.
- Browser fixture, 1280×720: 60 earlier conversation items, collapsed investigation, final Markdown table and composer visible; corrected follow-to-latest after layout growth. Question fixture rejects a 15 KB Unicode answer, accepts a bounded answer and disables resolved controls. Screenshot: `/tmp/pulse-openworker-long-conversation.png`; earlier question screenshot `/tmp/pulse-openworker-question.png`. Fixtures use a fake native bridge, no paid API or real Mac actions. Temporary fixture entry points removed from source after verification.
- `git diff --check`: pass. Release bundle/CI results are appended below after completion.

## Source manifest

| Upstream responsibility | Pulse integration |
| --- | --- |
| `coworker.engine.TurnEngine`, compaction, events, registry | `pulse-agent/openworker_runtime.py`; pinned dependency, narrow subclass seams |
| Provider transports | `pulse-agent/providers.py`; immutable explicit keys/endpoints/timeouts |
| Session and audit semantics | `conversation_store.py`, `server.py`, `diagnostics.py`; transactional WAL instead of SQLite+JSONL dual writes |
| Transcript/Composer/interaction behavior | `pulse-assistant/src/main.tsx`, `timeline.ts`, bridge, CSS; source attribution + MIT license |
| Host, credentials, native execution | Existing Swift host/AgentModel/Client/Daemon/Bridge/Settings; no upstream native host copied |

Full OpenWorker package is a pinned runtime dependency, not a stripped fork. Its broad tool modules exist in the installed distribution but are never assembled/registered. Tests prove unknown shell calls fail closed. Future dependency updates require re-review of engine seams and import-time behavior.

## Remaining release gates and scope limits

- User visual + functional review of the built app; **never merge on CI alone**.
- Live provider smoke with selected user's model: long conversation/reopen, stop/reconnect, real summary fidelity and safe tool outcomes. No paid/provider calls were made by this implementation validation.
- Stable-signature real Keychain save/relaunch behavior with the user's key. Security ACL/locked Keychain denial remains possible and is reported without an authentication prompt.
- Full VoiceOver/tab/focus review in actual WKWebView, cold/warm latency and repeated close/reopen resource teardown. Browser fixtures cannot prove macOS accessibility or native performance.
- Controlled hidden CPU/RSS measurement. Previous branch baseline was 0.70% CPU / 59.1 MiB RSS, exceeding the <50 MB target. This change does not claim to fix or meet that background memory target. Interactive Python/WebKit is measured separately.
- Provider tokenization differs from conservative prompt estimates. SDK cancellation cannot forcibly kill a blocked Python thread; worker capacity stays reserved until its real exit. Canonical on-disk dialogue has no retention UI yet; replay/results are bounded separately.
- Deferred UI: session rename/archive/delete/search, todo editing, standalone evidence drawer and safe model-only retry. Current recent-session/history/memory controls, tool details, result reader and dialogue search remain functional. Connectors/teams/schedules/remote/voice are outside selected scope.

Production robustness improved and deterministic contracts pass; release readiness still requires these live/native gates.
