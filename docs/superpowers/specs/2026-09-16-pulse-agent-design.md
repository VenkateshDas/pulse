# Pulse Agent Design

## Purpose

Add a local, opt-in Agno-powered assistant to Pulse. It diagnoses the Mac, inspects storage, and proposes or performs supported Pulse actions. Pulse remains the user-facing authority for all consequential actions.

## Architecture

The native SwiftUI app owns the UI, approval controls, and sidecar lifecycle. A local Python AgentOS sidecar is permitted by product decision. It binds only to loopback and accepts a random bearer token created by Pulse for that launch. The sidecar invokes the existing Pulse CLI and Pulse Skill through typed tools.

Settings stores the provider base URL and model in UserDefaults, and the provider API key in the macOS Keychain. OpenRouter defaults to `https://openrouter.ai/api/v1`; any OpenAI-compatible HTTP(S) endpoint and model identifier may be used.

The agent is one agent, not a team. It stores sessions in SQLite and sends bounded context: four recent turns, a structured session summary, the current compact Pulse snapshot, and relevant tool evidence. Durable memories are opt-in and limited to user preferences. Tool outputs, paths, raw scans, API keys, and telemetry do not become durable memory.

## Event protocol

The sidecar translates Agno events to Pulse-owned, versioned SSE envelopes. Every envelope contains `version`, `eventId`, `sequence`, `runId`, `sessionId`, `timestamp`, `kind`, and `payload`. The client deduplicates by event ID and only accepts increasing sequences. A reconnect requests events after the last sequence.

Required event kinds:

* `run.started`, `run.completed`, `run.failed`, `run.cancelled`
* `reasoning.summary.delta`, `reasoning.summary.completed`
* `answer.delta`, `answer.interim`, `answer.final`
* `tool.started`, `tool.progress`, `tool.completed`, `tool.failed`
* `approval.requested`, `approval.resolved`, `run.paused`, `run.continued`
* `stream.heartbeat`, `stream.reconnecting`, `stream.gap`

Pulse never presents raw chain-of-thought. It may render provider-supplied reasoning summaries in a collapsed "Working on it" section. An interim answer is explicitly labelled as progress and cannot be formatted as a conclusion. A final answer is only rendered from `answer.final` or a successful terminal event.

## Safety

Read tools execute immediately. Cleanup, uninstall, restore, brightness changes, and keep-awake changes require native approval. Cleanup and uninstall must preview before their mutating call. Server policy, not instructions, enforces this. Unsupported shell and arbitrary filesystem tools are absent.

An approval card states operation, affected items, estimated bytes, safety grade, reversibility, and exact action. It records approved/rejected outcome in the session. A rejection never triggers retry.

## UI

The Agent page appears below Dashboard in the Overview sidebar group. It has a session rail, main chronological timeline, optional evidence inspector, and pinned composer. Timeline defaults to user messages, final answers, concise progress, and compact tool cards. Selecting a tool opens exact arguments and structured evidence. Pending approval stays visible and blocks the run. Tool-derived values are monospace and fixed-width where practical. No data-driven animation is used.

## State machine

`idle -> running -> awaitingApproval -> running -> completed | failed | cancelled`.

`AgentRunReducer` is pure. It maps envelopes to one run timeline and prevents duplicate cards. The page starts no sidecar while hidden. It starts lazily on first send and stops showing live UI on disappearance; a currently accepted run remains resumable through AgentOS persistence.

## Verification

Test reducer cases for streamed content, tool start/completion/failure, duplicate event, out-of-order event, pause/continue, cancellation, error, and final-answer replacement. Test server authorization, preview-before-commit policy, and event envelope generation. Build and test with `make` from `pulse/`.
