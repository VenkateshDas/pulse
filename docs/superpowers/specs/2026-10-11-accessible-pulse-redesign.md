# Pulse for everyday Mac users — research and redesign proposal

Date: October 11, 2026
Status: **Proposed; awaiting design approval before implementation.**
Branch: `feat/accessible-pulse-redesign`
Source baseline: `main` at `ef7ac5c` (PR #83, native performance investigations).

## Purpose and audience

Pulse helps people understand their Mac, resolve a specific problem, and know what happened afterward. Its audience includes teachers, students, administrators, designers, business owners, and developers. Technical knowledge must never be a prerequisite for a routine task.

Success means someone can answer three questions: “Is anything wrong?”, “What can I do about it?”, and “Did it work?” More attractive telemetry alone does not satisfy this brief. A person should also be able to decide that no intervention is needed.

Design register: product. Personality: calm, clear, capable. The physical scene is a person working on a Mac in a classroom, office, or home, opening Pulse briefly because storage is filling up or work feels slow. Follow the person's system appearance and accessibility preferences; never require a dark console aesthetic.

## Research and its application

These are design recommendations based on published guidance and inspection, not findings from user testing. No claim of verified usability or accessibility compliance is made yet.

| Source | Principle applied to Pulse |
| --- | --- |
| [Apple: Make your Mac app more accessible to everyone, WWDC25](https://developer.apple.com/videos/play/wwdc2025/229/) | Group related content for assistive navigation; give controls meaningful names; verify the experience with VoiceOver rather than treating labels as sufficient. |
| [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | Use familiar Mac navigation, controls, feedback, and user control as the design starting point. |
| [Nielsen Norman Group: usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/) | Use familiar language, visible status, error prevention, and recoverable actions. |
| [Nielsen Norman Group: recognition and recall](https://www.nngroup.com/articles/recognition-and-recall/) | Visible task labels and contextual next steps reduce the need to remember where a tool lives. |
| [Nielsen Norman Group: progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/) | Show the explanation and common action first; retain readings and specialist tools behind clearly named disclosures. |
| [W3C: minimum text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) | Use 4.5:1 for ordinary text and 3:1 for large text as measurable design targets. WCAG is a useful benchmark, not a substitute for native accessibility testing. |
| [Apple: Reduce Motion environment](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion) | Respect Reduce Motion; live readings never animate. |
| [Apple: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) | Evaluate native adaptive navigation for the shell, retaining existing model visibility gates. |
| [Apple: string catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) | Prepare complete sentences, plural forms, and localizable labels. Verify resource behavior with this SwiftPM build before selecting a catalog pipeline. |

### Approaches considered

1. **Recommended: task-led native Mac utility.** Put familiar tasks in the sidebar, explanations before metrics, and a measured result after actions. Retains direct access and works without an AI provider. Requires changes throughout the UI and selected model interfaces.
2. **Guided assistant as the primary interface.** Strong for open-ended questions, but provider setup, latency, connectivity, and ambiguous conversational actions introduce barriers. Keep Ask Pulse optional instead.
3. **Visual refresh of the existing dashboard.** Least disruptive, but preserves the need to understand CPU, memory, health scores, and twelve destinations. Does not meet the user's stated problem.

The recommendation uses progressive disclosure within a single coherent interface. Avoid asking newcomers to classify themselves as “Simple” or “Pro” before they understand the product.

## Current experience audit

Inspection covered the SwiftUI source inventory, theme and shared components, display modes, network model, onboarding, navigation, action flows, and product-spec build decisions. The running app's dashboard and accessibility tree were also inspected. Its installed version was not matched to the checked-out source, so observations from that app are visual evidence only, not a baseline performance measurement.

| Finding | Evidence | Consequence and redesign response |
| --- | --- | --- |
| Feature-led navigation | `SidebarItem` exposes 12 destinations, grouped as Overview/Insights/System/Tools. | Users must understand the implementation's categories. Organize around everyday tasks. |
| Partial simplification | Simple mode gates only Monitor/Diagnostics and dashboard detail; existing installations default to Pro. | A toggle cannot resolve inconsistent page complexity. Give each page a comprehensible first layer. |
| Console visual language | Tracked uppercase labels, repeated gauges, mesh/glow treatments, extensive monospaced text, frequent 9–11 pt labels. | Hierarchy competes with comprehension. Use system typography, opaque content surfaces, and fewer visual signals. |
| Mixed messages | Running dashboard showed an “excellent” score alongside a memory warning. | Lead with the actual diagnosis and its confidence; keep the score secondary with an explanation. Do not change scoring in this redesign. |
| Technical leakage | Duplicate Finder advertises BLAKE3/APFS; monitor and diagnostics expose RSS/PIDs/SMC; cleanup uses SAFE/CAREFUL/REVIEW terminology. | Explain the consequence first, retaining implementation terms in details. |
| Misleading safety promise | Onboarding says nothing is deleted for good; Trash has a permanent erase action. | Describe recovery per action and never promise universal undo. |
| Cleanup accounting needs visibility | Optimize distinguishes moved bytes from freed bytes, but the distinction is easy to miss. | Preserve it as first-class result language across every entry point. |
| Permission-heavy onboarding | Welcome asks for a mode and proceeds to a permission checklist. | Let users reach an overview immediately; request permission at the task that needs it. |
| Surprise network work | `NetworkModel.start()` starts recurring speed tests; entering Network requests location. | Make bandwidth-consuming automatic tests opt-in and location requests explicit. Show existing saved results with timestamps. |
| Inconsistent accessibility coverage | Several custom views have no explicit accessibility modifiers; duplicate selection uses unnamed toggles. | Native controls can already be accessible, so modifier counts alone are not a verdict. Audit roles, names, values, focus, grouping, and alternative chart access at runtime. |
| Rigid layout | Root minimum 1080×720; several pages impose fixed card heights and columns. | Support a compact window, larger text, and long translated content without truncating critical meaning. |
| Documentation drift | Product spec still mentions older subprocess allowances and Vault behavior; current AGENTS rules are stricter. | Current user instructions and AGENTS constraints win. Verify actual restore routes before naming them in UI. |

## Information architecture

The primary sidebar becomes:

- **Home** — current condition, attention, and common tasks.
- **Free up space** — review cleanup, browse files, find duplicates, see changes, and inspect Trash.
- **Apps** — installed apps and removal; app activity remains reachable from a named link.
- **Battery & energy** — charge, capacity, usage, and relevant sleep settings.
- **Internet** — connection and an explicit speed test.
- **Displays** — brightness and synchronization.
- **Activity** — actions, storage history, and detected events, with distinct filters.

Secondary access: **Ask Pulse**, **Advanced tools** (app activity, maintenance, diagnostics, benchmarks, startup helpers), and **Settings**. Advanced tools remain reachable by search and contextual links. The sidebar scrolls at short window heights; Settings is always reachable.

Preserve destination identifiers, saved preferences, CLI behavior, and notification routes. Separate identifiers from translated display titles; do not change persisted enum raw values just to rename a page. Existing shortcuts continue to target the same tools; the menu and search expose those shortcuts accurately.

### Home wireframe

```text
┌──────────────────┬──────────────────────────────────────────┐
│ Pulse            │ Home                     Search tasks ⌘K │
│                  │                                          │
│ Home             │ Your Mac needs some attention            │
│ Free up space    │ Several apps are putting memory under    │
│ Apps             │ pressure. Review them before closing any.│
│ Battery & energy │                         [Review app use] │
│ Internet         │                                          │
│ Displays         │ Storage      Battery       Internet      │
│ Activity         │ 81 GB free   76%, charging Connected     │
│                  │                                          │
│ Ask Pulse        │ What would you like to do?               │
│ Advanced tools ▸ │ Review cleanup                 →         │
│                  │ Remove an app                  →         │
│ Settings         │ Adjust brightness              →         │
│                  │                                          │
│                  │ Recent activity                          │
│                  │ 12 items moved to Trash · View activity  │
└──────────────────┴──────────────────────────────────────────┘
```

Illustrative readings above are examples only. The implemented UI uses real snapshots; unavailable data stays unavailable.

The signature is an **outcome summary**: a quiet, persistent result that connects an action to what was actually achieved. Example: “12 items moved to Trash · 1.2 GB · Review in Trash.” After successful permanent removal: “Trash emptied · 1.2 GB removed.” Report increased available space only when measured. For performance: “Observation complete,” followed by before/after readings and workload caveats, never an unsupported “Your Mac is faster.”

## Visual system proposal

Preserve Pulse's name, SF Symbols, and a restrained green identity. Remove the luminous banner treatment from in-app branding; use a compact Pulse wordmark and a small solid mark. Keep alternate themes selectable, but apply the readability floor to every theme.

### Proposed light palette

| Role | Value | Use |
| --- | --- | --- |
| Canvas | `#F5F7F8` | Main window background |
| Surface | `#FFFFFF` | Content groups needing containment |
| Ink | `#172126` | Primary text |
| Secondary ink | `#4F6068` | Supporting text |
| Pulse green | `#176B56` | Primary action and selection |
| Divider | `#CCD5DA` | Group boundaries; not a sole focus indicator |

Dark counterparts: canvas `#171D21`, surface `#222B30`, ink `#F2F6F7`, secondary ink `#B5C2C9`, green `#70D6B3`, divider `#52616A`. Dark primary buttons use dark ink on the lighter green fill. Semantic warning/error colors require separate contrast-tested foreground/background pairs and a text label plus symbol. Do not reuse bright chart colors for small status text.

Calculated sRGB token contrast: light primary text on white 16.38:1; light secondary on canvas 6.10:1; white on green action 6.41:1; dark primary on surface 13.25:1; dark secondary on surface 7.91:1; dark ink on green action 9.33:1. These validate the proposed base pairs only; actual rendered themes, semantic states, opacity, and focus indicators still require verification.

Typography: SF system default for body and controls; restrained SF rounded for the Pulse wordmark only; system monospaced digits for changing readings. Page title 24 pt semibold, section heading 17 pt semibold, body/control 13–14 pt, supporting text 12 pt minimum. Advanced tables can use 12 pt; no critical instruction depends on smaller text. Offer Standard/Larger text in Appearance; layout expands vertically rather than shrinking the font to fit.

Spacing: 4/8/12/16/24/32 pt. Page inset 24 pt, compact inset 16 pt. Native toolbar and sidebar selection. Content groups use at most 12 pt corners, one subtle separator or border, and no decorative wide shadow. Cards only for independently actionable summaries; settings and lists use rows rather than nested cards.

Window target: 860×600 minimum, approximately 1120×760 default. Wide layouts can use two columns; compact layouts stack them. Detail inspectors move to sheets when the content cannot remain usable side by side. Core tasks must fit with sidebar collapse and larger text; the minimum is a validation target, not yet verified.

No ambient animation or data-driven transitions. User-triggered disclosures may use a brief non-bouncing transition, suppressed by Reduce Motion. Opaque alternatives apply under Reduce Transparency. Preserve native keyboard focus; never replace a Button with an on-tap text label.

### Design self-critique

A dashboard made of five recolored metric cards would preserve the original problem. The proposed Home instead has one condition explanation, a small contextual summary, visible tasks, and recent outcomes. Green is reserved for actions and positive state, rather than sprayed across gauges. Native familiarity is intentional: the distinctive decision is to make results and reversibility the product's organizing language.

## Every page and interaction

| Existing surface/files | Redesigned first layer | Interaction and edge states |
| --- | --- | --- |
| `RootView`, `SidebarView` | Task-led shell with visible search and native selection. | Keyboard navigation, stable shortcuts, scrollable sidebar, deep links that reveal their destination, focus returns after dismissing a sheet. |
| `DashboardView`, `HealthHero`, `AttentionSection`, `VitalCard` | Home explains condition and next action; detailed vitals are secondary. | Initial “Checking your Mac…”; timestamped stale readings; unavailable values are not zero. Review names its destination; quit saves user control; snooze remains discoverable and reversible. |
| `DiskView` | Free up space starts with cleanup review. Sub-navigation: Cleanup, Files, Duplicates, Changes, Trash. | Preserve existing integer tab mapping for notifications while changing presentation order; selected tab is explicitly labeled for assistive technology. No cleanup starts on navigation. |
| `CleanView`, `CleanModel` | “Review items you can remove,” grouped by recognizable file kinds. | Display reason, size, destination, and recovery. “Select recommended” acts only on eligible items; personal/shared/uncertain files require review. Scan has progress, cancellation, and partial-access coverage. Scheduled cleanup remains opt-in and clearly scoped. |
| `StorageView`, `StorageComponents`, `StorageDetailPanel` | Files list answers what takes space; map becomes an optional view. | Breadcrumbs, search, sort, named selection, expandable details, Reveal in Finder, keyboard equivalents for map interactions. Protected system data is informational, not a cleanup recommendation. Snapshot thinning remains an explicit advanced action with its real recovery limits. |
| `FolderVerdictView` | “Review this folder” with evidence and uncertainty. | Explain what is known and unknown; keep path available in details; enable Trash only at the existing protected-path boundary; no “safe” guarantee from a weak match. |
| `DuplicateView` | “Find duplicate files”; explain keeping one copy. | Choose folders, scan/cancel, select per group, preview originals, and label retained copy. Identical content does not imply redundant user intent. Clones/hard links explain why saved space may be zero. Trash wording must match actual removal behavior after engine audit. |
| `GrowthView` | Changes show where files were recently written. | Date range, plain-language explanation of modification dates versus net growth, missing-history state, actionable Finder links, no invented prior baseline. |
| `TrashView` | Trash and Recent removals use familiar names. | Show recoverability per item; restore conflicts and missing files need actionable results. Empty Trash confirmation names count/size and permanent effect; Cancel is the safe default. No automatic second step from cleanup to permanent erasure. |
| `UninstallView`, `UninstallModel` | Apps list with search; choose an app, then review removal. | Drag-and-drop is optional, never the only entry. App and related files are separate groups; ambiguous/shared files start unchecked. Explain running-app quit and permission steps. Completion distinguishes removed app, moved leftovers, and failures. Protect system apps. |
| `MonitorView`, `TopProcessesPanel`, `MonitorModel` | Advanced App activity shows recognizable app groups with CPU explained as processor use. | Search/sort/inspect with named columns; label process coverage. PIDs, threads, FDs, and raw process CPU normalization live in details. Graceful quit is distinct from force quit, and existing protections remain. |
| `InvestigationView` | “Check a slowdown” leads through observe → review → optional repeat. | Explain the person should reproduce the issue. Start/Stop, duration, measurement coverage, limitations, and copy report remain visible. Destination test explains the request; result avoids claiming a root cause from one interval. |
| `NetworkView`, `NetworkModel` | Internet shows connection state, then Test internet speed. | Wi-Fi signal is distinct from internet speed/reachability. No location prompt on arrival; explicit Show network name explains it. Automatic tests become opt-in, with data-use explanation and cancellation. Failure preserves prior result with its date. |
| `DisplaysView`, `DisplaySliderView`, `DisplaysPopoverSection` | Recognizable screen names and labeled brightness sliders. | Keyboard-adjustable values, unavailable control explanation, explicit “Match built-in brightness”; manual changes disable sync as today. Software dimming is named “Dim below minimum” and explained as overlay dimming; disconnected displays clear safely. |
| `HealthView` | Battery & energy starts with charge/capacity and useful context. | Desktop Macs show a purposeful no-battery state, not failure. Attribution is an estimate. Battery sessions/trends are details; startup helpers and benchmarks move to Advanced tools with links. Bluetooth denied/unavailable is distinct from no devices. |
| `TimelineView`, `TimelineModel` | Activity uses human-readable events and dates. | Keep action history, observations, and storage snapshots distinct; do not imply every engine already emits a unified event. Filter and drill down, empty state explains future records, gaps remain gaps. Restore links reference actual journal entries only. |
| `OptimizeView`, `OptimizeModel` | Advanced Maintenance explains each supported task and previews its effect. | Replace blanket “Optimize now” with review of selected tasks, explicit privilege/recovery information, and results per task. Skipped tasks are not successful tasks. Requires a model interface supporting selection, not just a cosmetic button rename. |
| `DevModeView`, `DevModeModel` | Diagnostics remains a specialist tool with a concise purpose statement. | Search, copy, named columns, unavailable readings; readable typography. Keep raw data available without exposing it on everyday pages. |
| `AgentView`, `AgentModel`, agent settings | Ask Pulse is an optional way to get help. | Friendly suggested questions, explicit provider configuration and external data explanation, visible Send/Stop labels, session selection, errors and retry. Approvals name the action, affected items, and recovery limits. Tool evidence is collapsed. No transcript-driven scrolling regressions or rich-text layout loops. |
| `MenuBarContent`, menu-bar label/settings | Compact status, a few named actions, Open Pulse. | Primary action reviews cleanup rather than silently removing items. Existing authorized in-place operations retain progress and results. Empty Trash requires the same permanent-action confirmation. Label brightness/awake states; manager controls remain accessible and opt-in. |
| `CommandPaletteView`, `KeybindingActions`, `ShortcutRecorderField` | Search tasks with ordinary-language aliases. | Label field, selection and shortcut; keyboard selection/Return/Escape; visible no-results guidance; help links explain missing permissions. Search/shortcuts dispatch the same reviewed action flows as page controls, never bypassing confirmation. |
| `OnboardingView`, `PermissionsView` | Welcome explains three useful tasks and offers Get started. | Remove forced expertise choice. Ask permissions at first relevant action with reason, Open Settings, Continue without access, and checked status after returning. Never imply App Management and Full Disk Access are interchangeable. |
| `SettingsView`, `ThemeManager`, `ThemePreset`, `DisplayMode` | Native grouped settings: General, Appearance, Menu bar, Notifications, Cleanup, Permissions, Ask Pulse, Shortcuts, About. | Meaningful labels for every toggle/picker, readable current values and validation, secure API key field, persistent errors/results. Preserve saved defaults and TCC identity. Existing detail preference maps to technical disclosure, not a separate low-quality UI. |
| `Components`, `HistoryChart`, `Sparkline`, `CoreHeatmap`, `Theme` | Shared readable headings, rows, status, results, loading and empty states. | Charts have textual summaries/accessible data; loading is truthful, not a fake percentage. Native buttons expose focus. Critical messages wrap and are selectable when useful; state is never color-only. |

## Common action contract

All entry points use the same flow: **understand → review → act → result → recovery when available**.

1. Name the action with a verb and object: Move 12 items to Trash, Remove app, Test internet speed, Start observation.
2. Preview actual targets and effect; include estimated size only when available. Make authorization or permanent effects visible before the action.
3. Show determinate progress only when the engine knows total work; otherwise show what is being checked. Prevent duplicate execution. Support cancellation where the engine can safely stop and describe already completed work.
4. Report success, partial success, skipped work, failure, or cancellation separately. Keep the result inline until dismissed or replaced by another action.
5. Offer the actual recovery mechanism: journal Restore, Finder Put Back, review in Trash, or none. Never show an Undo button without a functional route.

Example failure: “3 items could not be moved. They are still in their original folders.” Show reasons and Retry failed items only if the engine supports it. Confirmation is required for permanent deletion and process force quit; routine navigation and read-only scans stay direct.

## Accessibility and international use

- Verify keyboard-only completion of every routine flow, including file selection, duplication groups, brightness, permission help, and recovery. Native controls retain a visible focus ring.
- VoiceOver groups: sidebar, toolbar, condition summary, tasks, results, and detail content. Avoid both a flat wall of elements and excessive nesting. Icon-only controls get specific names; unnamed toggles get file/app context.
- Status always has a text label and symbol. Text targets: 4.5:1 ordinary, 3:1 large; interactive boundaries/focus indicators target 3:1 where needed. Measure all themes and states, including selected/hover/disabled explanations.
- Support Reduce Motion, Reduce Transparency, Increase Contrast, and Larger text. Do not continuously announce changing two-second readings.
- Use complete localizable strings with plural forms; locale-aware date/time/byte/number formatting. Support long text and right-to-left layout using leading/trailing alignment. Do not split sentences for grammatical interpolation.
- English is the initial editorial language. This scope prepares localization and validates pseudo-localized/RTL layouts; it does not claim human-reviewed translations for every language.
- Don't claim “private/on-device” for Ask Pulse or internet testing. Explain external services at their respective opt-in points without burdening offline tools with provider setup.

## Architecture and performance boundaries

Reuse PulseKit samplers and action engines. No new monitoring subprocesses, no shell-backed readings, no per-page polling loops, no animation attached to sampled data. User-initiated Finder authorization remains in-process Apple Events on the main thread.

Separate presentation titles from stable routing identifiers. Keep `DashboardModel`'s visible-view and screen-lock gates, `MonitorModel` and `HealthModel` appearance lifetimes, and lazy advanced panes. Navigation changes must not instantiate all models/views or leave subscriptions running for abandoned pages.

Shared UI components should have narrow purposes: page heading, explained status row, task row, action result, permission explanation, and empty/loading state. Don't add a global workflow framework. Derive a result from typed existing engine output; add a small adapter only where necessary. Keep changing digits layout-stable and rich text bounded.

Action entry points in pages, popover, search, and shortcuts must converge on the same authorization/confirmation logic. Backend adjustments are limited to selected maintenance tasks, opt-in speed tests, supported cancellation, accurate outcome fields, and routing needed by the redesign. Audit existing operations before promising their reversibility.

The existing budget remains a release gate: under 1% CPU and 50 MB RSS at two-second sampling in the agreed steady-state measurement. Measure a release build on a quiet Mac with the window visible, closed/occluded, and screen locked; separately record transient scans and optional agent work. If the current baseline already exceeds the budget, document it and do not declare performance verified from an unchanged sampler.

## Implementation order after approval

| Stage | Changes | Exit criteria |
| --- | --- | --- |
| 1 — Foundation | Write approved `PRODUCT.md`/`DESIGN.md`; tokens, contrast pairs, text sizing, shared components; navigation/title separation and adaptive shell. | All themes readable; routing/shortcuts preserved; compact/larger-text shell usable. |
| 2 — First experience | Home, attention, onboarding, contextual permissions, popover, task search. | New user reaches useful status without permissions/provider setup; tasks and results are understandable. |
| 3 — Space and apps | Cleanup, files/map, duplicates, changes, Trash/history, folder review, uninstaller. | Review/confirmation/recovery flows exercised against disposable fixtures; no false space-freed or undo claims. |
| 4 — Everyday controls | Battery, internet, displays, settings; speed-test opt-in model change. | Denied/unavailable hardware works; manual brightness override preserves sync protections; no surprise network tests. |
| 5 — Remaining tools | App activity, investigations, maintenance, diagnostics, benchmarks, startup helpers, Activity, Ask Pulse. | Every feature remains reachable; provider/approval failures and advanced detail are usable. |
| 6 — Validation | Full screenshot/keyboard/VoiceOver pass, localization stress, performance, local tests, CI and reviewable app. | All gates below met and PR ready for user visual/functional approval. |

Each stage is a commit-sized series within this feature branch, not a claim that the whole app is done when Home is refreshed. Maintain a page checklist in the implementation plan and revise it when runtime inspection finds additional dialogs.

## Validation and release gates

Run `make build`, `make test`, and `make bundle` from `pulse/`. Use a stable dev identity for permission-gated verification; do not reset or grant the user's permissions automatically. Focus tests on changed routing, action selection, permission states, outcome accounting, and cancellation—not snapshots that merely mirror styling.

Visual matrix: light/dark/all themes, compact/default/wide window, Standard/Larger text, Reduce Motion/Transparency/Increase Contrast. State matrix: loading, empty, stale, unavailable, denied, selected, running, canceled, partial, failed, restored, and permanent removal. Include a desktop Mac/no battery and unsupported external brightness control where hardware or mocks permit. Report untested hardware explicitly.

Usability targets to validate with at least five people outside software engineering: locate cleanup within 20 seconds; distinguish Trash from permanent deletion; identify an actual next step from a slowdown explanation; complete an app-removal review without help; describe what changed afterward. These are proposed acceptance targets, not results.

Open the implementation PR into `main`, attach it to this chat, wait for required **Build & Test (macOS)** CI, and provide the running app for user visual/functional testing. **Never merge without explicit user approval.** The design approval needed now authorizes implementation, not merging.

## Review requested

Approve the task-led native direction, proposed navigation, outcome summaries, and accessibility-first visual system. That approval also confirms the strategic product context for impeccable setup. All current capabilities remain reachable, technical detail becomes secondary, and automatic bandwidth-consuming tests become opt-in. Implementation follows after this design review.
