# Ask Pulse implementation sequence

Status: proposed sequence accompanying the design; code work awaits design approval.
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

No claimed implementation or performance results are recorded yet.
