# Pulse Agent Workspace Design

## Outcome

Upgrade native Agent page using proven OpenWorker interaction patterns without importing its web stack: persistent recent sessions, streaming chronological chat, collapsed work summaries, pinned composer, compact tool evidence, and native mutation approval.

## Layout

- 216pt recent-session rail. Active live session is inserted on `run.started`, remains selected while streaming, then refreshes from durable SQLite sessions at completion.
- Main timeline holds user prompts, provider-supplied work summaries, final answers, tool cards, and approval cards. Provider summaries remain available in a collapsed Thinking disclosure; no private chain-of-thought appears.
- Tool events remain adjacent as one chronological work trace, including tools emitted after answer streaming begins; the final answer follows that trace.
- Final answers render native Markdown blocks (headings, emphasis, lists, quotes, code, rules, and tables) inside a responsive wide reading lane.
- Selecting a tool reveals typed Pulse evidence inspector. It is absent until requested, protecting normal conversation width.
- Composer is pinned. Approval pauses sending and exposes Decline / Approve only for native policy-gated actions.

## Constraints

Use existing SwiftUI/HALO tokens and typed SSE reducer. No web view, dependency, arbitrary shell, data-driven animation, or background polling. Tool values are monospaced and selection changes only on user input.

## Verification

Build with `make build`; run `make test`. Manually verify new/live/history session selection, streamed answer, selected evidence tool, and both approval outcomes.
