# Ask Pulse interface

React + assistant-ui ExternalStoreRuntime embedded in the existing Swift app through WKWebView. Swift owns runs, sessions, approvals and credentials; React renders snapshots and emits a small versioned command vocabulary. There is no browser connection to the daemon and no API key in JavaScript.

`make -C pulse assistant` installs the npm lock, typechecks and builds directly into `pulse/Sources/Pulse/Resources/Assistant`. Commit generated assets so native builds work offline. CI rebuilds and checks for drift. The custom asset scheme serves only packaged files; CSP disallows remote scripts, connections and images. Markdown excludes HTML and images. User-activated HTTP(S) links open through macOS.

The chat uses stable messages, coalesced streaming, collapsed tool groups, requirement-specific approval cards, paginated conversations and memory controls. The renderer is released when the page/window is hidden; the Python runtime stops after hidden idle. Active runs continue until completion, cancellation or expiry.

Interactive Python/WebKit resources are separate from Pulse's background telemetry budget. See the validation record for measured results and remaining user review.
