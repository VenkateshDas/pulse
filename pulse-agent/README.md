# Ask Pulse harness

Pinned OpenWorker `TurnEngine` runs locally on demand inside the existing Swift host. Pulse constructs the engine directly: upstream SessionManager, shell, workspace probes, connectors and sandbox tools are never assembled or registered. Swift owns telemetry, native command execution, Keychain and UndoJournal. Python never launches a collector. `uv` and Python 3.12 are required; `start.sh` installs the committed lock into Application Support. First setup needs network access.

## Source boundary

OpenWorker MIT source is pinned to `5bf0d2fb8c728932fdbc6b49a24113aebc2a4ddd` in `pyproject.toml` and `uv.lock`; see `OPENWORKER-LICENSE`. Upstream owns turn iteration, pairing repair, provider transports and compaction algorithms. `openworker_runtime.py` adapts async Pulse tools, consent, cancellation, context/result bounds and persistence. `providers.py` constructs immutable provider clients. `server.py` retains authenticated loopback HTTP/SSE. Agno 3.0.9 and SQLAlchemy remain solely for one-time legacy import through public storage APIs; they do not execute runs.

## Long conversations and recovery

`conversation_store.py` stores canonical messages, restart checkpoints, decisions, executions, memories and offloaded results in transactional SQLite WAL. Structured compaction state survives reopen without nesting old summaries inside new summaries. Earlier canonical dialogue remains searchable; summary failure uses an explicit trim notice rather than inventing remembered details. UTF-8 prompt estimates reserve tool schema and output capacity before requests. Provider tokenization remains authoritative.

Large nested tool results spill above 6 KB into session-scoped storage, with 1,000-character previews, bounded 4,000-character retrieval pages, a 4 MB item cap, seven-day expiry and 128 MB quota. Canonical history is paginated 50 rows at a time. It deliberately remains on disk until users manage local app data; it is not loaded wholesale for rendering. Checkpoint message IDs make uncertain transaction retries idempotent. A separate bounded replay buffer retains 512 events per run. Reconnect resumes observation without resubmitting model/native actions; replay gaps fail explicitly and cancel the unseen run. Restart marks unfinished executions interrupted and expires decisions.

Only one writer per conversation and four active runs are allowed; 32 retained runs, 15-minute run expiry, 128 KB answers, 16 tool calls and 12 model iterations bound work. Streaming uses a 128-item queue. A shared four-worker limit includes blocked provider streams and compaction calls until their threads actually exit. Stop cooperates with provider/native cancellation and preserves partial output; already-started file operations may finish. Transport inactivity and interaction deadlines prevent indefinite waits. The SDKs may retain blocked threads until their own network deadlines; capacity remains reserved during that interval.

## Tools and consent

The closed registry contains the existing Pulse tools plus bounded skill loading, conversation search, result paging, explicit memory, questions and plans. Unknown tools fail closed. Native preview/revalidation and UndoJournal remain authoritative. Every mutation requires its own exact, single-use decision; plan acceptance never grants mutation authority. Investigate mode denies mutations and persistent memory writes. Questions require text answers and cannot approve actions. Mutations are never automatically retried.

## Memory and migration

At most 100 explicit preferences/lessons are stored with bounded evidence and provenance; there is no automatic extraction model. Disabled memory stops both recall and writes. Inspect/delete controls remain native. Evidence validation cannot independently prove an agent's claim. Secret/path filters are best-effort safeguards.

Legacy Agno sessions and explicit memory import once, after a SQLite backup including WAL contents. Import and marker commit together; failures roll back and can be retried. The old DB and backup remain intact. Historical approvals are never imported as authority. Large imported dialogue has a bounded initial replay tail; canonical dialogue stays searchable.

## Credentials and diagnostics

Save writes the endpoint-bound API key immediately to native Keychain, then updates settings only on success. Reads coalesce off-main, time out and cache successful saves; routine Security operations prohibit authentication UI. JavaScript receives no keys or bridge tokens. A locked Keychain or changed signing identity can still deny access: Pulse reports failure rather than repeatedly requesting a password. Use the stable development signing identity when testing across rebuilds.

Application Support/Pulse/agent contains `harness.jsonl` (2 MB × four files) and rotated startup `runtime.log`. Settings → Show Ask Pulse debug logs opens this folder. Structured diagnostics allow only metadata: run/session/call IDs, operation, provider, status, error type, timing, estimates and counts. They exclude prompts, arguments, results, API keys, endpoint URLs and display reasoning. Provider continuity sidecars may remain in the private checkpoint DB when required by a transport; they never enter public history, browser state or structured logs. Native OSLog records credential status codes and bridge timing. Startup stderr can include dependency/runtime diagnostics; inspect it before sharing externally.

## Development

From `pulse/`: `make agent-test`, `make assistant`, `make build`, `make test`, `make bundle`. Deterministic providers exercise the real pinned engine without paid model calls or operations on user files. See `docs/superpowers/plans/2026-10-17-openworker-pulse-port.md` for verified evidence and release gates.

## Context and session billing

The composer exposes latest-request context estimates and cumulative session usage separately. `usage_accounting.py` captures normalized token/cache counts plus raw OpenRouter charges through run-owned SDK methods; it does not fork the upstream provider. SQLite request IDs prevent replay/double counting. Compaction calls and transport retries are included; absent reports stay unknown. Costs sum Decimal strings and are accepted as USD only from OpenRouter's documented usage field. Other transports expose token counts and unavailable monetary cost. No historical bill is invented. Session selection/reopen reloads saved aggregates over authenticated `/sessions/{id}/usage`; active events update at request/report boundaries, not per token. No pricing lookup, extra inference or background polling.

## Workspace features

The native app now owns one navigation rail for conversations, search, automations, memory and Mac tools. Conversation metadata is additive: pin, manual rename, archive/restore and bounded canonical-text search do not rewrite history. Independent, tool-free title-agent jobs snapshot the provider, retain shared worker capacity until blocking transports exit, and apply generated titles only while the original provisional revision still matches. Manual titles win. Title/second-opinion calls contribute to the existing usage ledger without replacing the conversation context meter.

Memory supports validated user edits, explicit user instructions and exact-revision Undo of a new save. Learned memory off stops recall and saves; explicit user instructions are a separate user-authored setting. Task progress is bounded to twenty entries and guarded by the live run's durable identity. The tool-free second-opinion analyst sees only supplied evidence, can run once per turn and incurs an extra provider call; it cannot collect data, delegate or approve actions.

Automations use native Calendar deadlines in the resident menu-bar app. No enabled schedule means no timer. Daily/weekdays/weekly/one-time schedules retain their chosen timezone; launch/wake/clock reconciliation catches up once and skips overlaps. Durable claims precede requests, two automations may run concurrently, and a stopped/crashed occurrence is not silently retried. Python is started only for actual work. Unattended runs are read-only; denied changes or blocking questions become review items. Review loads the saved conversation and prepares an unsent draft for fresh evidence/approval. Quitting/sleeping does not wake or launch Pulse. Chat creation/enable/pause tools use the same authenticated native scheduler and exact human consent; scheduled runs cannot create recursive schedules.

Text attachments use an explicit native picker, UTF-8/regular-file checks and an 8 KB limit; combined draft stays under 12 KB. Selected content is reviewed in the draft before sending to the configured provider. Export saves the latest answer as Markdown through a native save panel. Mac-specialist modes change diagnostic focus with the same closed native tools. On-device dictation starts only from its button, requests macOS Speech/Microphone permission then, requires supported local recognition and stops after thirty seconds or view/session changes. No connectors, generic shell/workspace access, team/cloud infrastructure, arbitrary skill installation or remote execution were introduced.
