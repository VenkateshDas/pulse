# Context and session usage implementation

User approved design on 2026-10-17. Implement on existing unmerged Ask Pulse branch/PR #89 as continuation; do not merge without visual/functional approval. Writing-plans skill absent from installed roots; this plan records the sequence directly.

1. Add idempotent per-request SQLite usage ledger and last-request breakdown, keeping missing usage/cost distinct from zero.
2. Capture raw OpenRouter billing at run-owned SDK seam; wrap provider normalized usage for other transports and compaction. Include actual retries without double counting.
3. Emit bounded metadata updates; add session usage endpoint and native Codable/client/reducer reload path.
4. Add compact composer usage controls and keyboard-accessible details using existing HALO tokens.
5. Validate cache normalization, Decimal costs, duplicates, compaction, failed/cancelled calls and restart/session isolation. Exercise native reducer and UI fixture. Build/test/bundle through make; update docs/wiki; CI plus user merge gate.

## Validation evidence

- `make agent-test`: 51 tests pass. New coverage includes cache/reasoning normalization, Decimal cost aggregation, reported zero vs unavailable, retry identity/double-count protection, cancelled streams, compaction, session/restart isolation, historical coverage, context category sums and summary output reserve. A real OpenAI SDK + pinned OpenWorker provider with HTTPX mock transport proves streamed OpenRouter cost survives parsing; no real network/model call. Server SSE usage snapshots match the persisted session usage endpoint.
- `make test`: 386 tests in 90 suites pass. New tests verify usage observation/renderer snapshot, event replacement/replay, foreign session/run rejection, reset, cache split and decimal-string wire preservation.
- `make assistant`: 3 frontend regression tests, TypeScript and Vite pass. Browser fixture verifies footer placement, model/context estimate vs reported input, all categories, session total and summary inclusion, incomplete billing warnings, dialog Escape and focus return. Screenshots `/tmp/pulse-context-meter.png`, `/tmp/pulse-context-breakdown.png`, `/tmp/pulse-context-partial-usage.png` use illustrative values. Temporary fixture entry points removed before commit.
- Review bundle and required CI are tracked on PR #89. Build uses stable local signing; no auto-merge. No live paid model call or actual key read/write was needed for metering tests.

## Limits

Tracking begins with this update. Older conversation costs and missing historical compaction calls cannot be reconstructed from the stored normalized messages; totals disclose partial history. Stopped calls lacking a final report remain unknown. Other providers can report tokens without USD cost; monetary value then remains unavailable. Estimates attribute content by serialized request shape, not model-native category tokenization. Usage is updated at request/report boundaries, not per generated token. Ledger aggregation runs off-main and streams rows; no background polling.

Review artifact: `PULSE_VERSION=0.3.0-beta.5-context.dev make bundle` passes; `pulse/dist/Pulse.app` signed with stable Pulse Local Signing identity. Strict codesign verification passes; packaged runtime byte-matches source and includes usage_accounting.py. UI fixtures used illustrative billing values and made no provider calls. Header close remains visible while scrolling details.
