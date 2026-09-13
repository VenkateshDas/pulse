# Native verdict probes

User approved native probe replacement on 2026-09-13 after the CLI deployment audit found a cold-cache CI timeout and subprocess calls through UsageGraphScanner.

Replace Homebrew `brew uses` execution with installed keg `INSTALL_RECEIPT.json` runtime dependency reads. Replace `otool -L` execution with bounded native Mach-O load-command reads, including thin 32/64-bit and universal binaries in either byte order. Keep text/plist and symlink reference probes. Preserve UsageEdge and the verdict interface; no additional dependencies or polling.

Readers validate lengths and offsets before reads, skip malformed/nonregular files, and never execute inspected binaries. Mach-O linkage includes absolute dependency paths and resolves loader/executable-relative paths where possible; unresolved rpath linkage remains a documented static-analysis limitation. Receipt evidence describes installed runtime dependencies, not current formula definitions or build-only dependencies. Refresh cache namespace so old shell-derived indexes cannot mask the new path.

Validation: fixture-only receipt and Mach-O tests (including malformed/truncated input), full make test, CLI smoke, cold-cache verdict, release build and app-control tests. Existing user data and unrelated workspace edits are preserved. Merge remains gated on green CI and user visual/functional approval.

Self-review: scope and non-goals explicit; bounded reads and malformed inputs covered; no new protocol or user-facing options required.
