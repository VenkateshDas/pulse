# Ask Pulse harness

Agno 3.0.9 runs locally on demand. Swift owns telemetry and executes the closed native command grammar in process; Python never launches a collector. The optional runtime requires `uv` and Python 3.12. `start.sh` installs the committed lock into Application Support, where sessions, memories, offloaded results and a private runtime log live. First setup needs network access; subsequent startup uses the installed environment.

## Context and tools

Each run gets an immutable provider configuration, a timestamped native snapshot and up to four complete history runs. Large tool results use Agno ResultStore (6,000 character threshold, 1,000 character preview, seven day expiry). Summaries run every four turns. A conservative UTF-8 prompt estimate reserves the configured output budget before each model request. Provider tokenization remains authoritative; the estimate cannot guarantee every model's context window.

Typed tools use authenticated loopback RPC, bounded connections/output and short caching for cheap reads. Independent performance reads are batched. Mutations are never automatically retried. Cleanup, uninstall, quit and restore require a fresh, consumed preview plus Agno requirement-specific human approval. Native guards and UndoJournal remain authoritative. Stopping cancels provider/native tasks cooperatively; already-started file operations may still finish.

One writer per session, four active runs, 32 retained runs, 512 replay events and a 15 minute run expiry bound runtime state. Replay gaps are explicit. History uses supported Agno storage APIs and paginated user/assistant messages. Legacy `~/.pulse/agent.db` is backed up into Application Support without deleting the original.

## Memory

A custom Agno LearningStore saves at most 100 explicit preferences or troubleshooting lessons, with bounded evidence, session provenance and a stable local user namespace. No automatic extraction model runs. The agent is instructed to record lessons only after before/after observation; validation requires evidence text but cannot independently prove its truth. Treat recalled memory as untrusted context. Inspect, disable, remove or clear it in the interface. Disable prevents both recall and writes. Changes wait until active runs stop. Secret/path filters are a best-effort safeguard, not complete data-loss prevention.

## Models

Settings selects OpenAI Chat compatible, OpenAI Responses, Anthropic, Google Gemini or Ollama. Remote endpoints require TLS. Local Chat/Ollama endpoints can omit a key. Anthropic/Gemini use their SDK-supported official endpoints. Keys remain in native Keychain and the sidecar process; they never enter browser state. Selected models must support tools and the configured output/context budget. No claim that every arbitrary model has those capabilities.

## Development

From `pulse/`: `make agent-test`, `make assistant`, `make build`, `make test`, `make bundle`. Deterministic model fixtures exercise actual Agno streaming, tools, storage and checkpoint summaries without paid API calls or operations on real user files.
