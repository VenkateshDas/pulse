# Agent Instructions

This repository is maintained as an **LLM Wiki** and contains the source code for **Pulse**, a Swift 6 macOS command center for performance and storage.

You, the AI coding assistant, are responsible for maintaining the wiki structure, respecting the strict architectural constraints of Pulse, and executing commands safely.

---

## 1. Project Context & Constraints
Pulse operates under an extremely strict performance budget: **< 1% CPU, < 50 MB RSS** while sampling every 2 seconds. You must strictly adhere to the following rules:

- **Zero Subprocesses**: Never use subprocesses or shell commands for data collection. Everything must read kernel APIs directly (e.g., `host_processor_info`, `host_statistics64`, `libproc`).
- **No Data-Driven Animations**: Never attach `.animation` to data-driven values. Every animation frame re-runs the entire hosting view's layout, destroying performance. Use springs for user-initiated transitions only.
- **Efficient Rendering**: Publish snapshots only while something is on-screen. Ensure changing text is layout-stable (use monospaced, fixed-width formats).

---

## 2. LLM Wiki Operations
This repository uses the LLM Wiki pattern to ensure knowledge compounds rather than decays. 
1. **The Wiki**: The `.md` files (`index.md`, `log.md`, and this file) map the repository and track knowledge.
2. **Ingest/Update**: Whenever you modify the codebase or add documentation, update `index.md` to reflect the current state.
3. **Log**: Whenever you complete a significant task or structural change, append an entry to `log.md`. Format: `## [YYYY-MM-DD] <action> | <description>`.
4. **Research First**: Before making blind changes, read `index.md` and check `pulse/graphify-out/` to find relevant context.
5. **Lessons Learnt**: Always review the "Lessons Learnt & Decisions Taken" section in the product specification (`docs/product_spec.html`) before continuing implementation to ensure alignment with recent design choices and constraints.

---

## 3. Tools & Workflows
- **Graphify**: We use `graphifyy` (CLI: `graphify`) to generate knowledge graphs of codebases. If significant architectural changes are made, re-run `graphify update pulse` at the root directory to update the graph without needing LLM access for semantic extraction.
- **Build & Test**: Always go through `make` rather than raw `swift build` or `swift test`. This ensures you use the required workarounds for local toolchain issues.

### Essential Commands
- `make build` — Run a debug build.
- `make test` — Run the core test suite.
- `make run` — Run the app directly from the terminal.
- `make bundle` — Package the app into `dist/Pulse.app`.

---

## 4. Codebase Map
- `pulse/Sources/PulseKit/`: UI-independent core logic (CPU, memory, disk, processes).
- `pulse/Sources/CPulse/`: C shim exposing `libproc.h` to Swift.
- `pulse/Sources/Pulse/`: SwiftUI app implementation (menu bar extra, dashboard window).
- `pulse/Tests/PulseKitTests/`: Swift Testing suite for the core.
- `legacy_tui/`: Archived Python-based `mac-monitor` TUI code. Read-only reference.
- `docs/`: Product specifications and mockups.
