# Ask Pulse implementation sequence

Status: approved design implemented; validation and user review in progress.
Design: ../specs/2026-10-11-pulse-agent-harness-design.md

1. Pin the runtime and inspect installed Agno APIs. Lock dependencies; unify development and bundled bootstrap; define the protocol migration and storage migration. Preserve current native frontend until the replacement works.
2. Add the typed native tool bridge using PulseKit engines. Port the current toolkit operations, previews and safeguards; remove agent collection subprocesses. Add a cheap, timestamped context snapshot and bounded independent read batching.
3. Isolate runs and session writers. Implement real cancellation, limits, provider configuration snapshots, requirement-specific approvals, expiry and bounded replay. Replace internal SQL assumptions with supported storage APIs and paginated history.
4. Implement bounded context with result offloading, output reserve and checkpoint summaries. Add user-scoped agentic memory/verified learning, inspect/delete/clear controls and memory-disable semantics. Adapt and package the Pulse skill with script execution disabled.
5. Add explicit provider settings and capability validation across OpenAI-compatible, Responses, Anthropic, Gemini and Ollama. Preserve Keychain-backed credentials; support local no-key endpoints and actionable setup errors.
6. Build the assistant-ui React surface with ExternalStoreRuntime, safe Markdown, tool cards, exact approvals, session navigation and memory controls. Embed packaged assets through WKWebView and a restricted Swift message bridge. Implement view release/recovery and native keyboard/focus handling.
7. Integrate packaging and make targets. Verify targeted contracts: session isolation, stale/double approval, cancellation/disconnect, replay gaps, context bounds, deleted memory, provider switching, missing skill/runtime assets and schema migration. Use deterministic fake providers and temporary data for mutations; do not operate on real user files for verification.
8. Build and required CI through make; measure cold/warm startup, render latency, long histories and app/Python/WebKit resources. Reopen repeatedly and verify background budget after teardown. Record observed measurements and any unmet target.
9. Update index.md/log.md/product decisions, commit, push and open a PR into main. Wait for required macOS CI, then hand off the running packaged app for user visual/functional review. Merge only with explicit user approval.

## Validation record

- `make assistant`: typecheck and production build pass; packaged JS 751 kB / 227 kB gzip, CSS 11 kB. No remote runtime assets.
- `make agent-test`: actual Agno fixtures cover streaming, native tools, four persisted turns and checkpoint summary, plus contract tests for budgets, memory, providers, cancellation, previews and replay.
- `make build`, `make test`, `make cli-smoke`: native build and compatibility checks pass; final rerun recorded before PR.
- No paid provider calls or destructive operations on real user files are used for validation.
- Token counting is a conservative estimate; arbitrary providers still enforce their own token limits. Memory evidence is agent supplied, not an independent verifier.
- Cold/warm startup, actual WKWebView visual checks and resource measurements are recorded below as they complete. Background budget compliance is not assumed from passing tests.

### Local results (October 11)

- Final native suite: 367 tests in 86 suites pass; agent suite: 19 tests pass. CLI fixture smoke, React build/typecheck and signed release bundle pass.
- Ten deterministic Agno runs with temporary SQLite, memory disabled and synthetic native RPC: first construction 23.0 ms, warm construction median 4.4 ms, first answer median 17.6 ms, completed median 21.4 ms. These exclude imports, network/model inference, UI rendering and real native collection; they are harness overhead measurements only.
- CUA reported that the Mac is locked and automatic unlock failed. User was asked to unlock. Actual WKWebView appearance, cold/warm startup, long-history scrolling, repeated reopen/teardown and functional review remain pending.
- An uncontrolled locked-session launch on Home measured 1.77% CPU over 30 seconds and 68.3→66.9 MiB RSS. Window visibility could not be controlled, so this is not proof of the required hidden-background budget. It exceeds the numerical targets and must not be presented as compliance. No Python agent was started in that launch. A main-thread Keychain wait found during the earlier inspection was corrected; automatic reads now avoid prompting, Settings reads are asynchronous.
- Lock notifications now gate the renderer explicitly (lock does not reliably change window occlusion). Native approval expiry also releases a hidden idle runtime. The sidecar observes parent exit without launching a process.
- PR: https://github.com/VenkateshDas/pulse/pull/85. Required CI is running; no merge authorized by the earlier design approval.
