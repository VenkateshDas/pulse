# Ask Pulse on Home: implementation plan

Date: October 18, 2026. Status: implementation authorized in chat and completed; validation/review in progress. User selected the first visual direction and then requested implementation.

Design: [Home Ask Pulse design and research](../specs/2026-10-18-home-ask-pulse-design.md).

## Planning work completed

- [x] Read wiki, recent source history, product/design guidance and product decisions.
- [x] Inspect running Home and capture visual reference.
- [x] Research Apple, NN/G, Microsoft, Intercom, Carbon and W3C patterns.
- [x] Clarify whether conversation stays on Home: user chose yes.
- [x] Compare anchored, inline and docked approaches; user selected the first visual.
- [x] Specify layout, session handoff, lifecycle, errors, approvals and accessibility.
- [x] Identify reuse and prepare scoped implementation/validation slices.
- [x] User authorized implementation: "go ahead with the implementation".

## Repository and dependency gate

Planning source: `feat/openworker-premium` at `8c1c22e`. That work is represented by PR #90 and remains the intended integration direction. Do not fold new work into it silently, transplant overlapping older branches, or merge it based on CI alone.

Before implementation, refresh main and create `feat/home-ask-pulse` following repository workflow. If #90 is not merged, record it as an explicit dependency and bring its verified commit into the feature branch without rewriting the original branch. Review the resulting PR dependency diff before publication. Prefer beginning the feature after #90 is merged with user approval so the PR stays focused; do not merge #90 merely to unblock this work.

Preserve unrelated untracked `.serena/`, `.superpowers/`, `scratch/`, and `pulse_architecture.tldraw`. Implementation branch `feat/home-ask-pulse` was created from refreshed main (`cb1b283`) and fast-forwarded to the verified #90 dependency (`8c1c22e`) without modifying its branch. Commit reviewed docs with the feature, never directly on protected main/release branches.

## Slice 1: presentation ownership and lifecycle

Likely files: `RootView.swift`, `AgentView.swift`, `AgentModel.swift`; a small `HomeAssistantState.swift` only if it makes the transitions independently understandable.

1. Represent presentation separately from session/run state: no surface, Home compact, full workspace. Keep Home-open preference transient; app relaunch starts with bubble collapsed.
2. Make Root the sole surface-visibility owner, combining route, window occlusion and screen lock. Remove competing per-view appear/disappear ownership. Keep runtime leases and active-run guards authoritative.
3. Define open/minimize/expand/settings-return transitions. Shared conversation always retains session ID, draft, mode, specialist, active run and decision ID. Explicit New uses existing busy guard.
4. Ensure navigation from non-conversation agent pages sets `page = conversation` before opening the current chat; never reset its session.
5. Reuse app-level context bootstrap. Collapsed Home has no startup task or daemon health check.

**Validate:** focused state/model tests for active-run reopen, startup handoff, rapid open/minimize, window-hide/lock, idle shutdown grace, and outstanding automation leases. No provider calls needed. Demonstrate that transferring the view never calls send or creates a second runtime.

## Slice 2: native bubble and compact host

Likely files: `DashboardView.swift`, new `Views/HomeAssistantView.swift`, `RootView.swift`, existing command palette route.

1. Add labeled 44 pt launcher with real state labels and named accessibility actions.
2. Anchor the overlay outside Home's scrolling content. Reserve bottom clearance; keep hit testing limited to assistant controls.
3. Add native header with full-workspace, minimize, and explicit New controls. Opening the full workspace uses existing navigation.
4. Clamp 400 × 540 pt panel to available space and implement the specified compact-detail fallback. Keep Home hierarchy and two-column breakpoint unchanged outside fallback.
5. Return focus to the launcher on minimize. Expose an **Ask Pulse on Home** command without introducing a conflicting global shortcut. When keyboard focus moves behind an overlay, minimize and reveal the target.

**Validate:** native visual checks at minimum 860 × 600, common laptop windows, wide windows, wider sidebar and Larger text. Check Home scroll-end actions remain reachable and the overlay does not introduce extra metric publication.

## Slice 3: reuse the conversation renderer

Likely files: `AgentWebView.swift`, `pulse-assistant/src/bridge.ts`, `main.tsx`, `style.css`; presentation commands in the existing native bridge only if needed.

1. Add a typed presentation field with workspace as the backward-compatible default. Swift owns presentation authority; browser commands can request expansion/minimize but cannot execute new native tools.
2. Render existing transcript/review/composer components with compact layout. Avoid a second transcript implementation or a wholesale frontend rewrite.
3. Use the small scoped welcome and three deterministic starter requests. Disable starters for busy/unready states and protect any nonempty draft.
4. Keep mode and usage accessible. Put secondary existing attachment/dictation/settings actions in a compact menu; preserve permissions and text bounds. No new attachment or speech subsystem.
5. Preserve follow/Latest semantics. Stream without forced jumps while reading earlier messages. Capture draft updates immediately and preserve a reading anchor on explicit surface transfer.
6. Keep disclosures readable, render long approval details in full, and allow explicit expansion when room is insufficient. Never let a compact preview approve a different or hidden target set.

**Validate:** deterministic renderer fixtures for compact vs workspace, 360/400 pt widths, long Markdown/tables, many tool results, clarification, action preview, usage, IME, draft synchronization, and scroll behavior. No generated example answer belongs in production state.

## Slice 4: setup, failure and safety paths

Likely files: existing model/view/bridge, Settings return routing; avoid backend changes unless a demonstrated contract gap requires one.

1. Show distinct setup, starting, ready, streaming, awaiting review, failed, cancelled and completed states.
2. Preserve draft through provider setup. Reconnect restores connection without resubmitting the last run or silently clearing a partial answer.
3. Distinguish Minimize and Stop visibly. Show honest completed/partial-action receipts after cancellation.
4. Display provider/context disclosure before a first question. Reuse cached native context with freshness/unavailability labels; no extra sampler or provider call on every Home update.
5. Maintain review-needed access when the panel is closed or navigation changes. Do not auto-open when an answer arrives.

**Validate:** unavailable runtime, missing provider, invalid endpoint, cold startup failure, key/provider changes, expired approval, stale target, failed cancellation and active automation. Verify no automatic mutation replay and no credentials in browser state.

## Slice 5: full validation and review

Run from `pulse/`, only through the Makefile:

```sh
make assistant
make build
make test
make bundle
```

`make assistant` covers renderer tests, TypeScript and generated bundled assets. Run `make agent-test` if backend changes become necessary; avoid broadening backend scope without evidence. Use the stable development signing identity for permission-dependent native checks. Run `make dev-cert` only if no stable identity is installed.

Test the bundled app with native VoiceOver and keyboard navigation, including transitions between native chrome and WKWebView. Exercise light/dark/themes, larger text, reduced motion/transparency, window occlusion, lock, navigation, active runs, exact approval details and context usage. Existing speech controls remain opt-in; use a fixture or user-supervised check rather than activating microphone during automated research.

Measure three comparable release-bundle runs per condition after warmup, with a five-minute idle observation window:

1. Home before feature / equivalent baseline with no assistant opened.
2. Home with collapsed bubble, never opened.
3. Chat opened, then minimized after completion and shutdown grace.
4. Window hidden after interaction; repeat open/close transfers twenty times to check retained resources.

Record average CPU, native RSS, WebKit RSS, runtime RSS, process presence and time to return to idle. Control scheduled-run activity in the test setup and record whether leases explain any retained runtime. Do not count an active authorized run as idle. Do not claim the <50 MB background target passes unless measured; prior hidden-baseline failure remains a release risk. Opening interactive chat is reported separately.

Perform the five-person formative usability check from the design; record observed problems rather than just pass counts. Set no new analytics events or telemetry pipeline for this work.

Update wiki, log, assistant README and product decisions with actual shipped behavior and measured limits. Commit source and generated renderer assets on the feature branch, open a PR into main, and wait for **Build & Test (macOS)**. Hand the running bundle and evidence to the user for visual/functional review. Merge only after explicit user approval.

## Review checklist

- [ ] Opening Home alone does not allocate WebKit or boot the agent.
- [ ] Same conversation/run/approval survives expand, minimize, navigation and busy reopen.
- [ ] No two mounted renderers or lifecycle callers race during transfer.
- [ ] Draft survives setup and surface changes; starters cannot overwrite it.
- [ ] One request per deliberate send; no replay on reconnect.
- [ ] Home hierarchy and column widths remain consistent with existing behavior.
- [ ] Pending approvals stay exact, visible and explicitly authorized.
- [ ] Keyboard/VoiceOver reach every control and never focus obscured Home content.
- [ ] Context/provider/cost claims match the existing runtime and ledger.
- [ ] Hidden/idle behavior is measured, with baseline limits disclosed.
- [ ] Required local/CI checks pass and user approves the running app before merge.

## Visual artifacts

The first generated image was selected in chat. Concepts use the running Home screenshot as reference and illustrative answers. They are not working prototypes. Pixel details that contradict the written layout/accessibility contract are not requirements.

- Selected concept: `../../designs/home-ask-pulse/anchored-conversation.png`.
- Local-only inline alternative: `../../designs/home-ask-pulse/inline-companion.png` (not published with the feature PR).
- Local-only docked alternative, generated during exploration: `../../designs/home-ask-pulse/docked-copilot.png`.
- Generation brief: `../../designs/home-ask-pulse/prompts.md`.

Do not ship the original live Home capture as a product asset; it includes local device context and was used only as a temporary research reference.


## Implementation and validation record

- User authorized implementation on October 18. Created `feat/home-ask-pulse` from refreshed main, then included the explicitly documented #90 dependency. Protected branches and the #90 branch remain unchanged.
- Implemented native Home launcher/header, actual run-state labels, compact/full-detail fallback, Settings return and command-palette entry. Full-detail mode hides/disables covered Home controls.
- Root owns visibility, occlusion, screen lock and startup. A stable ZStack overlay and stable child slot keep a single renderer during Home/workspace transfer. AgentView no longer owns competing lifecycle callbacks; cached native context uses app bootstrap.
- Reused transcript/composer/approvals/evidence/usage and added compact chrome. Starters protect nonempty drafts. Evidence overlay makes covered conversation inert, focuses Close and restores composer focus. Native header and web Escape dismiss the appropriate surface.
- Home focus uses SwiftUI FocusedValues, with a native responder-ancestry guard for WebKit's internal focus changes. Focusing a Home control minimizes the floating panel without stealing the new focus. No event monitor, timer, permission or WebKit accessibility-tree traversal remains. Full VoiceOver/programmatic navigation remains a manual review gate.
- Added seven focused Home tests, including actual two-second shutdown cancellation and active-run/workspace-lease protection using injected shutdown. No real provider or runtime is invoked by those fixtures.
- `make assistant`: four existing renderer regression tests, TypeScript and production asset generation passed. `make build` debug passed. `make test`: **411 tests in 96 suites passed**. One intermediate run exposed an existing timing-dependent automation concurrency fixture: its three identical tasks could have equal timestamps and trip duplicate detection. Distinct fixture titles remove that nondeterminism without changing production behavior or concurrency assertions.
- `make bundle` passed with installed **Pulse Local Signing** identity. Running native app checks confirmed Home launcher, compact panel, full-detail fallback near minimum window width, unsent draft handoff, starter draft protection, Escape minimize and preserved draft on reopening. No paid question was sent, no approval accepted and no microphone permission activated.
- Native inspection exposed empty-welcome autoscroll clipping the heading. Empty transcripts now remain at the top rather than following an absent answer to the bottom. A native header uses a real VStack slot rather than relying on WKWebView safe-area behavior.
- Remaining release/user checks: actual provider response/Stop/approval behavior in compact mode, full VoiceOver and theme/text combinations, five-person formative usability study and repeated five-minute baseline/performance comparison. Short resource checks and CI/PR status are appended below. Existing background memory-target failure is not declared fixed.


### Native keyboard hardening

The initial review build passed deterministic checks but native evidence-close/Tab testing produced two WebKit layer-update SIGSEGV reports. An attempted focus guard traversed WebKit's accessibility tree after Tab; this was removed rather than retained behind timing workarounds. SwiftUI FocusedValues now handles native Home focus, while native NSView responder ancestry prevents a stale focused value from treating WebKit's own Tab movement as a request to close chat. The exact framework-internal crash mechanism is not proven by its stack trace. The original native sequence must be replayed against a static bundle after this change; unit tests alone do not establish the fix. Always stop Pulse before replacing its executable during packaging.


### Final native replay and review handoff

- After removing accessibility traversal and guarding WebKit responder focus, the original evidence → Escape → Tab sequence plus minimize/reopen passed **five consecutive native cycles** in a static stable-signed bundle. No later Pulse crash report appeared during those cycles. The two earlier reports remain local evidence; this does not establish general WebKit crash immunity.
- Verified Provider settings → **Back to Home chat** returns to the compact surface with the entire unsent draft intact. No provider credentials were edited and the test question was not submitted.
- Required CI passed for the initial feature commit. PR **#91** (`https://github.com/VenkateshDas/pulse/pull/91`) contains the feature and focus correction, explicitly depending on #90; checks for the final documentation/source head are tracked on that PR. No merge is authorized.
- Full VoiceOver/theme/text matrix, real provider actions and formal repeated baseline performance/usability checks remain user/release gates. The signed review app is `pulse/dist/Pulse.app`.
