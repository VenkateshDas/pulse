# Ask Pulse: production harness and assistant-ui

Status: researched proposal; implementation awaits design approval.
Date: October 11, 2026. Base: main at a5fdf0d. Branch: feat/pulse-agent-harness.

## Goal

Make Ask Pulse a responsive, model-configurable Mac assistant with durable conversations, bounded context, useful memory, efficient native tools, precise approvals, and an assistant-ui React interface inside the existing macOS app.

## Findings in the current implementation

- `context.py` synchronously launches vitals and diagnosis CLI processes when the agent is constructed. That adds startup work, leaves the initial context stale, and violates the current zero-subprocess collection constraint.
- `pulse_toolkit.py` launches the CLI for each tool. Preview sets belong to the shared toolkit rather than a run, and mutation confirmation also applies to previews.
- `server.py` shares one Agent, uses unbounded event/run dictionaries, confirms every pending requirement through one Boolean, and its cancel endpoint only removes a paused run. It does not stop an active run.
- Session APIs query assumed Agno SQL tables directly and return empty lists on schema errors. History extraction can duplicate messages already carried in successive runs.
- `agent.py` has four recent runs, tool-result compression, and automatic session summaries, but no durable user memory or learning policy. Anthropic environment credentials take priority over explicitly configured OpenAI settings.
- Dependencies have open lower bounds; startup installs a different dependency set from `pyproject.toml`. Packaging copies a fixed Python file allowlist.
- The native frontend already has generation-aware cancellation, grouped tools, and asynchronous final Markdown parsing. Recent hang fixes replaced lazy SwiftUI transcript layout with native List. Preserve these lifecycle lessons in the React adapter.

Reviewed `index.md`, Pulse skill, AgentModel/AgentClient/AgentDaemonManager, packaging and Makefile, and product specification §12 (Build Log & Decisions, the current lessons section). Background publication gating, truthful receipts, native collection and user merge approval remain requirements.

## Architecture options

| Option | Benefits | Cost |
| --- | --- | --- |
| Swift host + on-demand WKWebView + assistant-ui (recommended) | Actual assistant-ui components; retains existing PulseKit, AppKit permissions and packaging | Requires a narrow Swift/JavaScript bridge and measurement of WebKit memory |
| SwiftUI inspired by assistant-ui | Smallest UI runtime change; native accessibility | Does not deliver the requested React framework; Markdown/tables and chat interactions remain custom |
| Tauri app shell | Rust/webview desktop architecture | Requires migrating existing Swift app integration, permissions, menu bar and release lifecycle; unnecessary for one chat page |

Use the first option. Keep Pulse's Swift host and load packaged React assets only when Ask Pulse is visible. Tauri uses a separate core process and webview processes; adding a Rust shell does not remove webview resource costs. A WKWebView recommendation is an architectural inference, not a performance guarantee.

## Native tool boundary

The optional Python Agno runtime remains a separately launched component; launching that runtime is distinct from collecting telemetry. All agent telemetry and actions use a closed, authenticated native bridge in the running Pulse app, backed by existing PulseKit engines. Remove CLI spawning from the sidecar. Retain the standalone CLI for external agents.

Native bridge requests carry protocol version, request ID, run ID, session ID, named operation and validated parameters. Use authenticated loopback requests with an unpredictable per-launch credential and a strict operation allowlist. No arbitrary shell, executable, file-read or JavaScript operation. Impose request/response byte limits, bounded concurrency, timeouts and cancellation tokens. Offload expensive scans from the main actor; UI-owned actions enter the main actor explicitly. Reuse GUI safety guards and UndoJournal instead of implementing a second deletion engine.

Provide a cheap timestamped context snapshot from existing native state. No automatic filesystem scan, process observation interval, or network test before the first answer. Missing/stale evidence is labeled. Each conversation has its own toolkit and preview state. Identical cheap read requests may share fresh evidence within a run; mutations and long scans are never cached. Start with symptom-relevant tools, with a bounded read-only diagnostic batch for independent readings. Enforce a maximum tool budget and a single writer for each session.

## Agno context, memory and learning

Pin a released Agno version after checking its installed APIs against the cookbook patterns; documentation may describe APIs newer than the current unpinned installation. Lock Python dependencies and frontend dependencies. Startup validates the locked runtime instead of accepting any importable Agno version.

Use four recent completed turns plus a compact session summary of decisions, verified findings and unresolved work. Select history against a configurable context budget with output reserve; preserve paired tool calls/results and pending requirements. Report estimated token usage as estimated when the provider supplies no actual usage. Avoid loading full scans into every future prompt.

Prefer Agno result offloading with a bounded preview, result reference, paged reads and search. Configure expiry/quota and explicit storage-failure handling. Compression and offloading are mutually exclusive in current Agno; disable existing CompressionManager when enabling offloading. Offloading avoids a model call on its write path. Summary updates happen at defined context boundaries rather than indiscriminately on every turn. Evidence is recoverable locally and never silently replaced with a false claim of completeness.

Use one stable installation-local user ID across sessions. Agno agentic user memory captures durable preferences and explicitly useful decisions; avoid Always extraction on every turn. Reusable troubleshooting lessons need verified outcomes and provenance, are scoped to this user/device, and never confer authorization. Exclude API credentials, raw scans, transient CPU values and provider reasoning. Memory has source, creation/update time and bounded content. The UI supports inspect/delete/clear and a memory toggle; disabling memory prevents recall and writes. Clearing memory must remove recalled state as well as database records. Learning is runtime persistence, not model training.

Use Agno storage APIs rather than querying internal SQL table layouts. Put the database in Application Support/Pulse/agent; provide an explicit migration from ~/.pulse/agent.db with a backup and failure reporting. Paginate history and avoid repeated embedded history when reconstructing turns.

## Providers

Expose provider, model ID, endpoint and credential settings. Initial supported transports: OpenAI Chat-compatible endpoints (including hosted gateways/local servers), OpenAI Responses, Anthropic, Google Gemini, and Ollama. Use Agno provider classes with explicit credentials and parameters; avoid environment-based priority surprises. Keep keys in native Keychain and runtime memory, outside frontend storage, transcripts and event logs.

Validate URLs both in Swift and on the runtime boundary: remote HTTPS, loopback HTTP for local providers, no embedded credentials. Local no-key endpoints work. Declare tool/streaming capability requirements and produce actionable errors for unsupported models. Model configurability cannot guarantee that every model supports tools or that arbitrary vendor APIs are compatible. Additional Agno providers can be registered with their required authentication fields. Provider changes apply to new runs; resumptions retain the original provider configuration. Do not retry uncertain side-effecting tool execution or silently send user context to a fallback vendor.

## Runs, approvals and transport

Keep Pulse-owned versioned events. One isolated execution context per run; session serialization; idempotent terminal transitions. Stream text in bounded batches (target 30–50 ms flush) while flushing tools and approvals immediately. Sequence events monotonically, store a bounded replay window, and return an explicit replay-gap response if a cursor has expired. Bound output, pending approvals, retained runs and retention time. Event rendering never exposes provider chain of thought.

Cancellation marks intent, invokes Agno cancellation and closes pending provider/bridge work where possible. Agno cancellation is cooperative; a native mutation already started may finish and is not rolled back by Stop. Report this accurately. Browser disconnect stops streaming work unless a durable paused approval owns the run. Clean tasks in finally blocks; expire approvals and handle restart as an explicit unavailable approval.

Split read-only previews from commit tools. An approval identifies exactly one pending requirement, its operation, parameters and preview revision; server code enforces single-use resolution. Revalidate process identity/file eligibility before commit. A single button must never approve unrelated requirements. Show exact affected items, consequences and refusals before confirmation. Preserve partial-failure receipts and undo identifiers. Memory and skill instructions cannot bypass approval.

## Pulse skill

Load the bundled Pulse skill through Agno LocalSkills for progressive disclosure of diagnosis/remedy references. Add embedded-agent guidance mapping CLI examples to native tool names; keep external CLI guidance working. Disable skill script execution and general shell tools. Verify the loader discovers the skill correctly from the packaged directory. Missing skill files are an explicit setup error.

## Frontend

Package assistant-ui React assets with Vite and host them in an ephemeral WKWebView. Use ExternalStoreRuntime because Pulse already owns conversation and approval state. Translate the existing event stream through a typed Swift bridge; the web content receives sanitized state, never provider credentials or loopback bearer tokens. Constrain navigation to packaged content; open reviewed external links through macOS; no remote scripts. Remove script handlers and webview resources when the surface is released. Preserve conversation state outside WebKit and resume from history on reopening.

Visual direction: readable document-like transcript, quiet opaque surfaces aligned with Pulse's light/dark tokens, one blue live accent, generous answer typography, a grounded rounded composer and restrained tool rows. Empty state offers symptom-based prompts. Header shows selected model and connection state. Recent conversations and memory controls sit in a compact secondary rail/panel. Streaming status, Stop, retry, copy, tool results and approval cards have explicit states. Render Markdown tables, fenced code and paragraphs safely. Collapse routine tool details; keep action approvals and outcome receipts visible.

Use keyboard navigation, native focus handoff, selectable text, accessible names and VoiceOver validation. Preserve scroll position when reading older text; show a jump-to-latest affordance. Bound/render transcript pages, batch deltas and defer expensive Markdown work. No animations driven by metrics or tokens. WebKit crash/setup failure gets a native recovery view.

## Performance and delivery gates

The background two-second monitoring budget stays <1% CPU and <50 MB RSS. Python and WebKit must be unloaded after no visible Ask Pulse surface, active run or pending approval needs them; allow a short explicit teardown grace period. Idle services must not poll. Measure app, Python and WebKit separately and report their combined interactive cost. Do not describe interactive chat as within the background budget without measurements.

Targets for local overhead, excluding provider/network latency: cached context acquisition <10 ms p95; event-to-render <100 ms p95 under a synthetic stream; bounded replay/history; zero collection subprocesses. These are acceptance targets, not measurements. Report cold/warm startup, time to first provider token, first paint, scan cancellation and resources after repeated open/close cycles.

Build through make in pulse. Run required macOS CI and targeted contract/lifecycle checks, then package a reviewable app and open a PR into main. Wait for user visual/functional approval after green CI. No automatic merge.

## Research sources

Reviewed October 11, 2026; cookbook/API claims need confirmation against the pinned release during implementation.

- [Agno examples index](https://docs.agno.com/examples/introduction): reviewed cookbook categories for context, memory, learning, skills, providers and human-in-the-loop.
- [Tool-result offloading cookbook](https://docs.agno.com/examples/agents/result-offloading/offload-tool-results) and [ResultStore cookbook](https://docs.agno.com/examples/agents/result-offloading/result-store): bounded previews, recoverable references, pagination and expiry; failed storage is explicitly not lossless.
- [Compression](https://docs.agno.com/compression/overview): additional model work and incompatibility with offloading.
- [Context engineering](https://docs.agno.com/context/agent/overview) and [session summaries](https://docs.agno.com/sessions/session-summaries): history/context shaping and summary integration.
- [Agentic learning cookbook](https://docs.agno.com/examples/learning/quickstart/agentic-learn), [learning overview](https://docs.agno.com/learning/overview), [learning modes](https://docs.agno.com/learning/learning-modes): persistence scopes and extraction cost; prompt-based Propose is not an enforcement boundary.
- [Model configuration](https://docs.agno.com/models/model-as-string) and [compatibility](https://docs.agno.com/models/compatibility): explicit provider transport and per-model capability limits.
- [Cancellation](https://docs.agno.com/run-cancellation/overview), [HITL cookbooks](https://docs.agno.com/examples/agents/human-in-the-loop/overview), [skills cookbook](https://docs.agno.com/examples/agents/skills/basic-skills): cooperative stopping, resumable approvals, progressive disclosure and script execution risk.
- [assistant-ui design](https://www.assistant-ui.com/design), [custom runtimes](https://www.assistant-ui.com/docs/runtimes/custom/overview), [ExternalStoreRuntime](https://www.assistant-ui.com/docs/runtimes/custom/external-store): design and integration guidance.
- [Apple WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) and [Tauri process model](https://v2.tauri.app/concept/process-model/): hosting options.
