# Ask Pulse interface

React 19 + react-markdown inside the existing Swift WKWebView. Conversation grouping, transcript/composer behavior and interaction cards adapt OpenWorker's MIT design to Pulse; see `OPENWORKER-LICENSE` and the pinned-source map. The large upstream App/SessionManager, Tauri, voice and broader product features are excluded. assistant-ui was removed.

Swift owns runs, sessions, approval decisions, drafts and credentials. React receives sanitized snapshots and incremental item/metadata patches and emits a small versioned command vocabulary. JavaScript has no daemon connection, API key or bridge token. Existing packaged-asset scheme, restrictive CSP, main-frame checks and native external-link handling remain. Markdown excludes raw HTML and images; streaming renders plain text until settled.

The transcript groups narration and tools, leaves final answers and pending reviews visible, distinguishes action/question/plan, retains partial answers, and preserves scroll position while reading history. ResizeObserver follows layout growth only while following the latest answer. Copy confirms only after native pasteboard success. Native per-session drafts survive renderer teardown. Investigate mode is read-only. History pages, explicit memory controls and recent-session selection retain the native host UI.

`make -C pulse assistant` installs the npm lock, runs three grouping/patch regression tests, typechecks and builds into `pulse/Sources/Pulse/Resources/Assistant`. Commit generated assets for offline native builds; CI verifies drift. Runtime/renderer release on hidden idle remains managed by Swift. Active work continues until completion, cancellation or expiry.

Session rename/archive/delete/search UI, todo editing, arbitrary attachments and a standalone evidence drawer are deferred. Tool details and agent-driven bounded result retrieval are available. No automatic model-turn retry button is exposed because completed native mutations must not be replayed. Full VoiceOver, live-provider and background performance review remain release gates; browser fixtures alone do not establish native macOS behavior.

The composer context button opens keyboard-accessible usage details: estimated instructions/tools/history/summary/evidence categories, separate output reserve, reported input, and cumulative session tokens/cost. Summary tokens are already included in session totals. Cache/reasoning subsets are not added twice. Missing reports/history show incomplete coverage; zero cost is never inferred from missing data. Monetary cost currently requires provider-reported OpenRouter USD charges.

## Premium workspace expansion

Native sidebar now owns New, Search, Automations, Inbox, Memory, Specialists, recents and existing Mac tool routes. WebKit renders one content area with an optional evidence/tasks/export drawer. `Features.tsx` supplies real memory/instruction editing, schedules/run history/review, canonical chat search/management and specialist entry points. `AgentWorkspaceBridge.swift` validates the closed command vocabulary. Native HALO colors resolve into web tokens, respecting saved themes; typography, neutral surfaces and quiet page/card treatment follow the pinned OpenWorker reference.

Attachments are selected text only; exported reports contain the latest answer. Voice uses on-device native recognition when supported. Search's Archived filter searches archived conversations exclusively. No connector controls or nonfunctional full-parity placeholders are exposed. Bundled native UI and actual model behavior still require user visual/functional review; deterministic tests do not prove every provider, microphone/language combination or accessibility flow.
