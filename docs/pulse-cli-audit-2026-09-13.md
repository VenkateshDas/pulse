# Pulse CLI and skill deployment audit — 2026-09-13

Scope: all 15 CLI commands, portable skill, shared native probes, build/test/package paths and app-owned controls. This is not a claim that every GUI page or every external monitor model has been visually tested.

## Results

- Baseline: 323 tests across 68 suites passed; local CLI smoke passed, but PR #80 CI had failed because cold-cache verdict exceeded 120 seconds.
- Corrected verdict probes: native Homebrew receipts and bounded Mach-O headers replace shell execution. Regression failed before the fix. Updated suite: 327 tests across 69 suites passed. Expanded smoke passed; first native-cache verdict took 0.76 seconds locally.
- Debug build, final native release rebuild, local signed app bundle and strict signature verification passed. Staged install and user-local install passed; corrected release CLI is installed at `~/.local/bin/pulse`. Fresh rebuilt app passed display writes and timed/indefinite sleep with expiry/allow. Required CI status is tracked on [PR #80](https://github.com/VenkateshDas/pulse/pull/80).
- All 15 commands returned parseable JSON with expected exit status. Human and JSON help were checked. Additional 54 live JSON/argument/safety calls passed.

| Component | Verification |
| --- | --- |
| Help/parser | All 15 help and unknown-option paths; missing/duplicate flags, nonfinite/range errors, unknown command, mutation gates |
| vitals | Full and lite native snapshots; CPU structure and plausible range |
| diagnose | Live score/verdict output |
| procs | CPU and memory lists, limit 5, descending numeric order |
| attention | Structured prioritized results |
| anomalies | Historical read, 24-hour filter |
| sensors | Live temperature, battery and GPU data; optional fields supported |
| growth | Full volume scan, limit 5, nonzero scanned file count; 47.37 seconds |
| verdict | Generated directory; native cold cache; receipt/Mach-O regressions |
| duplicates | Identical fixtures found; threshold excludes small files; hard-link/clone core tests |
| clean | Catalog scan; exact fixture selection; default preview; dry-run overrides yes; scan overrides yes; protected targets and active-file refusal; fixture Trash move |
| uninstall | Installed-app listing; synthetic app preview/removal; protected/nonexistent target refusal |
| undo | Journal listing; both fixture restores; occupied destination rejected and preserved, then restore succeeds; corruption/concurrency covered by core tests |
| display | Built-in and external reads; writes at existing levels, including negative external dimming; unknown ID error; app-absent timeout |
| sleep | Status; three-second assertion survives CLI exit and expires; indefinite assertion; allow; app-absent timeout |
| speedtest | Cached-only history read |
| Skill | Discovered `.agents/skills/pulse/SKILL.md`; Claude symlink resolves; used exact IDs, preview, fixture action, returned UUID and restore; no real cache/app removal |

## Live state and performance

App-absent display/sleep requests returned structured exit 1 after approximately 5.4 seconds. The rebuilt app responded after startup; an initial check only three seconds after launch was too early. External requested brightness changed during app startup, so brightness persistence across restart is not certified by this audit. Sleep was inactive at the start and restored inactive after tests. Fixture-only Trash moves were restored and generated fixtures removed.

Baseline release `vitals --lite`: 0.89 seconds wall time, 18,333,696 bytes maximum RSS (17.5 MiB). This is one invocation under ambient workload, not a sustained GUI CPU-budget measurement. Full volume scans remain permission- and machine-dependent.

## Remaining release gates

- Required macOS CI must pass on the corrected commit.
- User visual/functional approval remains mandatory before merge; external physical luminance/DDC behavior and real permission-gated app removal are not certified by synthetic tests.
- Local bundle uses `Pulse Local Signing`, arm64 only. Developer ID notarization and universal execution were not validated locally.
- Current release workflow publishes the app DMG only; the CLI and portable skill are source-installable, but no standalone CLI/skill release artifact is shipped. Public CLI/skill distribution needs an explicit packaging decision.
- Existing actor-isolation warnings remain in GUI code. They did not fail the current build.

No release tag, merge, real app uninstall or real cache purge was performed.
