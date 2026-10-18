# Ask Pulse on Home: design and research

Date: October 18, 2026. Status: design approved and implementation authorized in chat ("go ahead with the implementation"). Implementation completed; validation and user review are tracked in the companion plan.

## Product decision

Add a persistent, labeled **Ask Pulse** bubble inside the Home page. Clicking it opens a compact conversation panel above the bubble. People can finish a short conversation there, then expand into the existing Ask Pulse workspace when they need more room. The user explicitly chose short conversations on Home and selected the first generated design.

The experience should feel like a calm Mac assistant: available when asked, specific about its capabilities, and clear about what it observed and what it changed. A healthy Mac does not require intervention. The bubble must not suggest there is a problem merely because it exists.

Research produced this design before implementation. The implemented feature reuses the current agent/model/renderer and adds no provider configuration or permission grants. See the companion plan for actual validation and remaining review gates.

## Research and evidence

Reviewed current source at `8c1c22e` on `feat/openworker-premium`, the running Home screen, `index.md`, `PRODUCT.md`, `DESIGN.md`, the product specification's Build Log & Decisions, and the existing Ask Pulse implementation. Home currently leads with Storage, Battery, and Internet, followed by simultaneous technical/activity columns. Preserve that hierarchy.

External sources were checked on October 18, 2026. They supply design guidance and examples, not proof of outcomes in Pulse. Dimensions and release criteria below are proposed Pulse decisions requiring native validation.

| Source | Relevant guidance | Application to Pulse |
| --- | --- | --- |
| [Apple HIG: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai?changes=lat__5) | Identify AI, guide inputs, keep people in control, provide dismissal and recovery, and retain useful non-AI paths. | Use “AI assistant,” scoped starters, visible Minimize/Stop, and existing reviewed native actions. Home remains useful without a provider. |
| [NN/G: 10 Guidelines for Designing Your Site’s AI Chatbots](https://www.nngroup.com/articles/ai-chatbots-design-guidelines/) | Consolidate chat, offer contextual prompt buttons, keep responses manageable, respect reading position, and allow more room. | One shared conversation; three starting prompts; existing expandable evidence and Latest control; expand to the full workspace. Keep the persistent sidebar return path when leaving Home. |
| [Microsoft: redesigned Microsoft 365 Copilot](https://www.microsoft.com/en-us/copilot/blog/2026/05/28/introducing-a-new-design-for-microsoft-365-copilot/) | Shows an assistant integrated with the surrounding work and movement between conversational surfaces. | Adapt the contextual entry and workspace handoff; retain Pulse's native shell and visual tokens. This is a product precedent, not a controlled usability study. |
| [Intercom: Set up and customize the Messenger](https://www.intercom.com/help/en/articles/6612589-set-up-and-customize-the-messenger) | Supports direct conversation entry, launcher visibility, and product-aligned appearance. | Click the launcher to reach conversation immediately, without a separate assistant landing screen. Reuse the interaction pattern, not Intercom's SDK. |
| [Carbon AI Chat: Launcher](https://chat.carbondesignsystem.com/version/v1.19.0-rc.1/docs/documents/UI_customization.Launcher.html) | Separates launcher presentation from chat and supports unread indication. | Keep a lightweight native launcher separate from the expensive renderer. Indicate only real conversation state; never create fake unread badges. |
| [W3C: Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html) | Announce meaningful asynchronous changes without moving focus. | Announce ready, completion, failure, and review-needed states. Do not read every streamed token. |
| [W3C: Focus Not Obscured](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-enhanced) | Sticky elements and nonmodal dialogs can hide keyboard-focused controls. | Keep Home interactive and ensure focused Home controls are revealed when the panel overlaps them. This enhanced criterion is used as a design target, not a conformance claim. |

### Alternatives considered

1. **Anchored conversation — selected and recommended.** A labeled bottom-right bubble opens a floating compact conversation. Small resting footprint and close fit to the user's request. Open state temporarily covers part of Home; requires careful keyboard focus and narrow-window handling.
2. **Inline companion.** Conversation appears below the at-a-glance summary. Discoverable and avoids overlap, but pushes the technical/activity content down and changes the recently agreed Home hierarchy.
3. **Docked copilot.** A conversation column reserves space on the right. Useful for extended work, but reduces dashboard width and overlaps the purpose of the full workspace.

Selection is based on fit to Pulse and user preference. It is not a measured claim that floating chat outperforms the alternatives.

## Visual design

The selected image is visual direction, not a pixel-accurate implementation specification. Generated mockups can change chart density, wording, or layout. Preserve the actual existing Home layout; apply only the assistant addition. Mock answers and readings are illustrative and must never ship as live output. Screenshots and generation prompts are linked in the companion [plan](../plans/2026-10-18-home-ask-pulse.md).

### Resting bubble

- Place within the Home detail viewport, aligned to the trailing/bottom edges with 24 pt inset; use 16 pt at compact widths. It stays available while Home scrolls. It is not a system-wide floating window.
- Use a 44 pt minimum control height, a speech-bubble SF Symbol with Pulse's waveform identity, and the persistent label **Ask Pulse**. Size to content; never shrink to an unlabeled orb.
- Use existing HALO interactive/surface/ink tokens. Provide light, dark, and selected-theme variants through the existing theme machinery.
- No breathing animation, glow, greeting popup, auto-open, or fabricated unread count. Explicit user-triggered transitions may use existing motion tokens, respecting Reduce Motion.
- Reserve bottom scroll space so the last Home action can move clear of the bubble. Outside the control, pointer events pass to Home.

### Expanded panel

- Preferred size: 400 pt wide × 540 pt high, with a 12 pt gap above the bubble. Clamp to the Home viewport, with a useful minimum width around 360 pt where available. These are logical points, not retina screenshot pixels.
- Header: Pulse symbol, **Ask Pulse**, subordinate **AI assistant**, **Open in Ask Pulse**, **Minimize**, and a secondary menu containing **New conversation**. Give icon actions names and tooltips.
- Empty body: “Understand your Mac and choose a next step.” Offer three compact buttons: **Help with a slowdown**, **Review storage options**, **Explain these readings**. Clicking a starter sends that exact, visible request once readiness and provider disclosure permit it. Do not replace a nonempty draft; preserve it and ask the user to send or clear it first.
- Transcript: reuse current answer rendering, investigation groups, clarification buttons, and approval cards. Keep evidence collapsed until requested. Do not summarize or truncate approval targets to fit.
- Composer stays anchored below the independently scrollable transcript. Keep Send/Stop, mode, and context/usage access. Put attachments, dictation, and settings in an accessible secondary control if necessary. Keep at least 12 pt supporting text and wrap rather than compress controls.
- Show the actual provider identity and an accessible disclosure: **Your selected provider receives your question, cached Mac readings, and requested diagnostic results. Provider charges may apply.** Do not imply local-only processing.
- Use opaque surfaces, a subtle border, maximum 12 pt content radius, and existing elevation tokens only where needed to distinguish the floating panel. Body 13–14 pt; no new font or icon package.

### Window adaptation

Measure the actual detail viewport after sidebar width, toolbar, and Larger text are accounted for. At less than 600 pt detail width or 640 pt usable detail height, use an in-place Home assistant region spanning the detail area, keeping the sidebar and a **Back to Home** action. This still permits conversation without routing to the full Ask Pulse page. Return to the dashboard on minimize.

At the app's current 860 × 600 minimum window, the compact fallback is expected. On a larger window, the floating panel must not reflow or narrow the existing technical/activity columns. The selected generated image is not authority to change their widths.

No draggable or freely resizable bubble/panel in v1. “Open in Ask Pulse” supplies the larger reading surface. Reassess resizing after user testing.

## Conversation and navigation contract

One application-owned `AgentModel` remains the source of truth. Home and the workspace are two presentations of its current conversation, not independent chats.

| Event | Required behavior |
| --- | --- |
| Open bubble with no current conversation | Show setup, startup, or ready empty state as appropriate. Do not send an automatic prompt. |
| Open with an existing session | Display that conversation with a “Continuing conversation” indication and its title where available. New conversation is explicit. |
| Open during an active run or approval | Attach to the current run; do not reset, restart, or submit another question. |
| Minimize / Escape | Preserve transcript and draft; stop dictation; return focus to launcher. Running work continues under existing bounded execution rules. |
| Open in Ask Pulse | Select conversation page, preserve session/run/approval identity, unsent draft, mode and specialist. Do not invoke `newConversation()` or `send()`. |
| Leave Home for another Mac page | Collapse Home presentation. Current conversation/review remains reachable through existing sidebar behavior and recents. No automatic reopening or focus theft. |
| Return Home | Show bubble collapsed; opening resumes the shared conversation. |
| New conversation | Use existing guarded reset only when not busy. Existing chat history remains available in sidebar. |
| Provider Settings | Preserve draft and remember an in-memory return destination. Provide a clear way back to Home chat after configuration; no automatic send on return. |
| Hide, close window, or lock screen | Remove hidden rendering and stop dictation. Keep run and automation leases authoritative; no hidden polling added. |

A running minimized bubble reads **Pulse is working…**; an outstanding decision reads **Review request**. A newly completed minimized Home run may show **Answer ready** until opened. These are actual state transitions, announced once, without animation or numeric counts. Only show completion notice for a run the user has not already viewed; do not infer unread state from restored historical answers.

Keep the launcher visible on Home only for this scope. Persistent sidebar access supports continuation elsewhere. Broader app-wide floating chat is a separate decision; this deliberately limits the reach of the across-pages research recommendation.

## Safety, setup, and recovery

- **No provider:** explain connection in place; **Connect a model** opens existing Settings. Home telemetry and native tasks remain usable. Do not show the composer as if a connection exists.
- **Starting:** visible text such as “Starting local agent…”; prevent duplicate sends. An elapsed startup does not imply provider readiness. Reuse existing startup deadlines and surface failure clearly.
- **No snapshot / old sample:** show unavailable or timestamped evidence. Do not manufacture readings, infer health from absence, or claim continuous observation. Reuse the existing 30-second freshness warning where appropriate; a fresh read remains a native tool operation.
- **Failure:** retain the user's question and any partial answer. Offer reconnect and an explicit next question. Never automatically replay a run that could have completed actions.
- **Stop:** reuse existing cancellation and honest receipt semantics: already-started actions can still finish. Minimize is distinct from Stop. Do not claim rollback.
- **Approval:** reuse existing exact-target preview, native authorization, stale-decision checks and UndoJournal. If details need more space, expand the same session for review; do not approve from a shortened summary. While minimized, review remains pending and expires under existing policy.
- **Read-only mode:** remain visibly available and retain current user choice. Home never grants new tool permissions or changes mode implicitly.
- **Privacy:** do not add automatic screenshot capture, screen reading, file access, microphone activation, or network calls on each telemetry sample. Explain the cached context already shared by the existing integration.

## Reuse and architecture

| Existing component | Reuse | Narrow planned change |
| --- | --- | --- |
| `DashboardView.swift` | Current Home hierarchy, samplers, actions | Add launcher/panel presentation and bottom clearance, without observing full streamed text in dashboard cards. |
| `RootView.swift` / `PulseNavigation` | Stable destinations, window visibility and screen lock | Own presentation selection and route the same chat into the workspace; do not change launch destination in this feature. |
| `AgentModel.swift` / `AgentWorkspace.swift` | Drafts, sessions, bounded runs, cancellation, leases and startup coalescing | Derive visibility centrally and track lightweight presentation/return state separately from runtime/session state. |
| `AgentView.swift` / `AgentWebView.swift` | Existing packaged renderer, snapshots and authenticated command bridge | Add explicit compact/workspace presentation input; centralize lifecycle ownership. |
| `pulse-assistant/src/main.tsx`, `bridge.ts`, `style.css` | Transcript, Markdown, streaming, review cards, composer, usage and scroll-follow logic | Add compact chrome/layout and starter content; extract only shared pieces that actually need a seam. |
| `AgentWorkspaceBridge.swift`, `AgentNativeBridge.swift`, `PulseCommands` | Existing closed command vocabulary and native tools | Allowlisted presentation-only expand/minimize actions if required; no new broad agent tool or endpoint. |
| `Theme.swift` / `ThemeManager` | Theme tokens, Larger text and existing native/web palette | Reuse existing semantic tokens and icon dependencies. |

**Lifecycle ownership is the principal technical risk.** `AgentView` currently toggles a single `surfaceVisible` flag from appearance, visibility changes and disappearance; its startup can launch the optional runtime. Two mounted views could fight over shutdown or both publish. Root must choose one presentation owner: none, Home, or workspace. Derive visibility from that owner plus window visibility and lock state; move surface lifecycle calls into this one owner. Do not add a second independently managed `AgentModel` or solve this with unrelated global reference counting.

At most one assistant WKWebView is mounted at a time. A host transfer may recreate the web view from canonical model state; it must not restart the provider run. Preserve native draft state immediately and restore a conversation reading anchor across an explicit transfer where feasible. The current scroll-follow behavior must continue respecting a user reading earlier content.

`AgentView.task` is not sufficient context bootstrap once Home can initiate chat. Reuse the app-level `bootstrap(dashboard:)` and existing native cached-vitals provider. Avoid duplicating context registration or injecting a fresh synthetic user message every two seconds. Deterministic local starters need no model request.

The existing optional Python runtime is already an approved interactive exception in product decisions. This feature introduces no additional process, collector subprocess, shell tool, server, LLM service, storage schema, or dependency. Native collectors remain the only source of telemetry.

## Performance and accessibility acceptance

- Collapsed Home owns only a native button and lightweight state. It must not instantiate WKWebView, call `AgentModel.start()`, read Keychain, poll daemon readiness, or call the model solely because Home appeared.
- Opening is an explicit interaction and may start the existing runtime. Rendering stops immediately when hidden. Hidden idle runtime keeps the current two-second shutdown grace, provided no active run or automation/workspace lease owns it.
- No sampled-value animation, typewriter effect, looping bubble animation, or publication while hidden. Keep existing bounded/coalesced streaming and native sampling cadence.
- Measure native app, WebKit children and optional runtime separately and together. Background target remains <1% CPU and <50 MB RSS. Existing documented 59.1 MiB hidden baseline means compliance is not yet established; this feature cannot claim to fix that through design alone.
- Open focuses the composer or setup action, never steals focus on completion. Escape closes the innermost disclosure/modal first, then minimizes. Return sends and Shift-Return inserts a line break; honor IME composition.
- Provide a named nonmodal assistant region and a discoverable keyboard action in the existing command palette. Verify crossing SwiftUI/WKWebView boundaries with native VoiceOver; web-only checks are insufficient.
- Keep Home keyboard focus visible. If focus moves to a Home control behind the floating panel, minimize the panel before revealing that control, preserving the chat.
- Announce statuses once; keep streamed text outside a token-by-token live announcement. Retain full text for reading. Use symbols plus text for status and visible focus outlines.
- Validate light/dark, selected themes, Larger text, Reduce Motion, Reduce Transparency, narrow windows, long responses, tables, approval details, and disconnected providers.

## Scope and success

V1 includes the Home bubble, compact ongoing conversation, setup/recovery states, existing safe action reviews, full-workspace handoff, responsive fallback, lifecycle protection, and accessibility validation. It excludes a new personality/mascot, proactive LLM health analysis, new tools, new voice pipeline, multiple simultaneous chats, global desktop overlay, fresh analytics collection, and arbitrary chat resizing.

In a formative check with five representative Mac users, target at least four finding the bubble and submitting a relevant question within 30 seconds without instruction. Each should be able to minimize/reopen, distinguish Stop from Minimize, and find the same chat in the full workspace. Treat this as a proposed usability gate, not measured evidence or a statistically validated conversion target.

Technical release gates: no duplicate run during handoff, no lost draft, no approval bypass, no hidden renderer/runtime retained by the bubble, existing Home layout preserved, relevant make checks green, required macOS CI green, and explicit user visual/functional approval before merge.
