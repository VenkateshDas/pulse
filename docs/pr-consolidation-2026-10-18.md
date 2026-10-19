# Ask Pulse PR consolidation — October 18, 2026

The user selected `feat/openworker-premium` / PR #90 as the intended direction and authorized closing overlapping or superseded PRs while retaining complementary features.

Reviewed application head: `2e847b04e8052470575a0842db16ba0914b7324c`.

| PR | Comparison against #90 | Decision |
| --- | --- | --- |
| #89 — OpenWorker runtime and context/cost visibility | Head `66043904f57dafd69c116e0b1395e585e493347f` is an ancestor of #90; zero commits missing. | Close as included in #90. |
| #85 — native agent harness | Head `809d20370aecb0aae85b23cab5cc97f0d063e427` is an ancestor of #90; zero commits missing. | Close as included in #90. |
| #82 — earlier agent workspace | Head `a4cbdac8ffe4ee866ef5f97eec50a7d75900c171` has eight commits outside #90. Reviewed all changed source and regression files; useful capabilities have replacements below. | Close as superseded by #90. |

## #82 feature comparison

| Earlier capability | Current implementation in #90 |
| --- | --- |
| Recent/live sessions and conversation selection | Native shared workspace/sidebar, `AgentModel` and conversation storage; additionally search, rename, pin, archive and detached titles. |
| Optional evidence inspector | `pulse-assistant/src/main.tsx` Investigation drawer with task progress and expandable tool evidence; inline grouped tool results remain available. The old inspector also displayed text rather than adding a distinct typed visualization. |
| Native mutation approval and composer Stop | Native bridge remains authoritative; React review/composer controls invoke scoped approvals and cancellation. `AgentModel.cancel()` flushes partial answers; `AgentClient` cancels terminated streams. |
| Markdown headings, lists, tables, code and quotes | Memoized React Markdown with GFM renders completed answers; streaming answers remain plain text. SwiftUI Markdown/parser/layout patches target the replaced renderer. |
| Paged visible history | `AgentModel.loadEarlier()`, `AgentClient.fetchHistoryPage()` and canonical `ConversationStore.history()`; current history also retains tool evidence. |
| Large-answer/follow-up context protection | Pinned OpenWorker compaction/checkpoints, searchable canonical dialogue, output bounds and explicit trim notices replace the earlier Agno history/summary tuning. Existing regressions cover oversized imports and 120 turns with reopening. |
| Bounded replay and monotonic sequences | Current server has bounded per-run deques, sequence counters, run capacity/expiry and explicit replay-gap recovery. |
| Collapsed work and transcript layout stability | Grouped narration/tools, visible answers/consent, stable incremental patches and a browser scroll container replace the earlier SwiftUI layout workarounds. Provider reasoning stays private. |

No distinct complementary feature was found to transplant. Merging #82 would combine obsolete Agno execution and native chat-renderer changes with their replacements. Its native-only/no-web constraint is also superseded by the approved harness and OpenWorker designs in the product specification.

## Scope and validation

Git ancestry and source comparison only; no application code changed and no new runtime tests or live provider calls were performed for this consolidation. Existing PR CI results are separate evidence. Keep #90 open and retain the older branches for reference. Closure does not mean the changes have reached `main`.

The user visual/functional merge gate and the recorded live-provider, accessibility, dictation and background-resource checks remain pending on #90.
