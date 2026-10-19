# Ask Pulse context, token and session-cost visibility

Status: approved by user and implemented on feat/openworker-pulse-runtime, 2026-10-17; validation and user merge review tracked in the implementation plan.

## Request and chosen design

Add context visibility beside the existing Ask before changes selector, matching the supplied screenshot. A compact context button opens an accessible breakdown. Show session token consumption and cost in the same composer footer; retain the selected session's values after reopening.

Recommended: compact footer plus click-to-open details. Always-expanded details make the composer too tall; hover-only tooltips are poor for keyboard/accessibility and cannot accommodate billing coverage. No separate analytics page is needed.

Illustrative footer, not measured values:

`Ask before changes   Context ~18.4K / 32K · 58%   Session 146K tokens · $0.0182`

The details label the context measurement as the latest model request, with time/model, configured context limit and separate output reserve. Estimated categories: instructions, tool definitions, native snapshot, memory/skill context, recent dialogue, earlier-conversation summary, tool calls/results and serialization overhead. Disclose estimation; do not present category estimates as exact provider tokenization. Account for embedded skill content as tool-result evidence unless it can be categorized without double counting. Categories sum to the same conservative estimator used by the runtime. Do not count output reserve as already consumed input.

Show provider-reported prompt/context tokens separately when available. Context occupancy is one request; cumulative session tokens sum every billed model round-trip, including repeated history, tool follow-ups and compaction calls. Report fresh input, cached input/cache writes, output and total without double counting cached/reasoning subsets. Track missing reports explicitly.

## Data and runtime boundary

Capture a bounded aggregate context snapshot immediately before actual model requests. Capture raw billing metadata at the provider transport seam before pinned OpenWorker normalizes it away. Current upstream TokenUsage preserves normalized input/output/cache read/write, but streamed OpenAI-compatible AssistantTurn discards raw usage cost. Avoid copying the entire upstream provider implementation.

Persist an idempotent per-request usage ledger in the existing canonical SQLite DB, keyed by stable request identity, with session/run/model/provider, purpose (answer or compaction), reported counts, cost/currency/source and completeness flags. Persist the latest context snapshot per session. Replay or reconnect must never add usage twice. Store usage before emitting observation events; the native client can reload aggregates after restart/session selection.

All actual provider calls, including summary/compaction and successful retry attempts that report usage, contribute. A cancelled/failed call without a final usage report remains unknown; never infer zero billing. Historical token sidecars may support a labeled partial backfill, but historical missing costs/compaction usage cannot be reconstructed exactly. Show tracking coverage and unavailable/partial state.

Provider-reported cost is preferred. OpenRouter documents final streamed usage.cost as the amount charged and provides cache/reasoning detail. Do not substitute upstream_inference_cost for the user's charge. Other providers without a monetary amount show cost unavailable unless a separately verified pricing source is implemented; no guessed rate tables. Zero is displayed only when reported or explicitly verified, not when a field is absent.

Keep credentials in Keychain/runtime only. No additional inference call is needed for metering. Expose aggregates/categories through authenticated session usage API and versioned events, then AgentClient → AgentModel → existing incremental snapshot bridge → footer/detail surface. No prompt, result or key content goes into metering logs. No background polling, per-token SQLite writes or telemetry animation.

## Behavior and validation

New conversation: usage not measured yet; no fabricated meter or historical cost. During a run: context changes at model request boundaries, totals change on reported usage. Session selection/reopen loads its saved totals and coverage. Draft editing does not send draft text merely for measurement. Errors do not interrupt the run if cost data is absent/malformed; persistence errors are explicit and cannot silently produce authoritative totals.

Test normalized cache counts, non-negative bounded billing values, Decimal cost aggregation, cost zero vs missing, cross-model session totals, separate compaction calls, cancelled requests, duplicate/replayed events, session isolation and reopen persistence. Verify category sums/output reserve and no double counting. Native reducer/bridge tests cover updates and session reset. UI fixture covers narrow footer wrapping, keyboard/Escape/focus return for details, partial/unavailable cost and provider-reported vs estimated labels. Use make build/test/agent-test/assistant/bundle. Required CI plus user visual/functional approval remain merge gates.

## Primary research

- Pinned local OpenWorker coworker/providers/base.py: TokenUsage input excludes cache reads/writes; context_tokens sums them, output may include thinking.
- Pinned coworker/providers/openai_provider.py: complete retains raw response; streaming normalizes usage and does not attach raw cost to final AssistantTurn.
- OpenRouter usage accounting: https://openrouter.ai/docs/cookbook/administration/usage-accounting (consulted 2026-10-17). Cost and token usage are returned in the final streamed response; missing final chunks can leave tracking incomplete.
- OpenRouter models/pricing metadata: https://openrouter.ai/docs/api/api-reference/models/get-models . Rate estimates would need cache/request pricing and source timestamp; provider-reported charges avoid inventing those assumptions.

Spec self-review: current-request vs cumulative usage separated; cached/reasoning counts not counted twice; missing historical billing not fabricated; compaction included; no secrets or expensive background work; UI placement follows user screenshot. User approved this presentation/data contract before implementation. Actual provider/native review remains a release gate.

## Implementation notes

Usage capture uses a run-owned wrapper on OpenAI SDK Chat/Responses create calls, retaining raw OpenRouter cost before upstream normalization. Other transports use normalized counts and show monetary cost unavailable. Retries create separate records; a failed/unfinished attempt without a usage report stays unknown. Raw reports win over normalized reports. Provider-reported USD charges are accepted only from the documented OpenRouter host; no remote pricing lookup or inference request was added.

Existing sessions are marked as containing untracked history before a new prompt is appended. No speculative historical cost or summary-token backfill. Compaction output reserve uses its actual requested limit. Bundled skill reads are included under tool calls/results; static skill catalog is part of instructions. Context categories are diagnostic estimates, not exact tokenizer allocation.
