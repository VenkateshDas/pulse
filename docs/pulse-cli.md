# Pulse native CLI and agent skill

Implemented on 2026-09-08 from the supplied CLI plan. The initial draft contained command files but did not build; this implementation wires them to the real PulseKit APIs and adds safety, tests and app control.

## Build and install

From `pulse/`:

```sh
make build
make test
make cli                    # dist/cli/pulse
make cli-smoke              # creates and restores only its own fixtures
make install-cli            # /usr/local/bin/pulse
# Alternative: make install-cli PREFIX="$HOME/.local"
make bundle                 # dist/Pulse.app, stable local signature when available
```

SwiftPM names the CLI product `pulse-cli` to avoid colliding with GUI product `Pulse` on case-insensitive macOS filesystems. Installed command remains `pulse`. No new Swift package dependencies were added. The CLI links existing PulseKit dependencies; “zero dependency” means no additional runtime, parser library, or server package.

The skill source is `.agents/skills/pulse/SKILL.md`; `.claude/skills/pulse` links to it. Codex and current Antigravity discover `.agents/skills`, while Claude Code discovers `.claude/skills`. The skill follows the [Agent Skills specification](https://agentskills.io/specification), [Antigravity's skill discovery rules](https://antigravity.google/docs/skills), and [Claude Code's skill layout](https://code.claude.com/docs/en/skills). It requires no MCP server. Skill availability outside this repository requires placing its folder in the chosen agent's skill location.

## Command contract

All commands accept `--json` and `--help`. JSON output is one compact, sorted-key value; dates use ISO8601. Human output uses colors only on a TTY. Exit codes: 0 success, 1 runtime failure or partial action, 2 invalid usage. Unknown options, repeated options, missing values, nonfinite numbers and invalid ranges fail before dispatch. `--` ends option parsing.

| Command | Behavior |
| --- | --- |
| `vitals [--lite]` | Two native snapshots separated by 250ms; lite omits process enumeration. Does not write GUI disk history. |
| `diagnose` | Diagnosis cascade and health score from a measured interval. |
| `procs [--by cpu|mem] [--limit N]` | Sorts the complete sampled list, then limits it; includes owning app names. |
| `attention` | Existing prioritized/snoozed-filtered attention engine. |
| `anomalies [--hours N]` | App-recorded historical sustained events. |
| `growth [--days N] [--limit N]` | Existing volume scan; recently modified file sizes, not a baseline-derived delta. |
| `verdict <directory>` | Existing forensic folder verdict and evidence. |
| `clean [--scan | --target ID | --all-safe] [--dry-run] [--yes]` | Catalog-only scan. IDs are exact paths. No substring targeting. |
| `uninstall [--list | <app>] [--dry-run] [--yes]` | Exact, unambiguous name, bundle ID or path; bundle plus safe-confidence leftovers. |
| `display [get | set <value>] [--display ID]` | App-owned -1...1 brightness. Negative values retain software overlays after CLI exit. |
| `sleep [status | prevent [--until seconds] | allow]` | Reads/changes the running app's IOKit assertion. |
| `sensors` | Native SMC/GPU/battery snapshot; unsupported optional fields are absent. |
| `undo [list | restore <ID>]` | Locked journal snapshot and conflict-preserving restore. Prefixes must be unique and at least eight characters. |
| `duplicates <directory> [--min-size-mb N]` | Existing BLAKE3 pipeline with configurable minimum; device-qualified hard-link and native APFS clone identity checks. |
| `speedtest [--cached]` | Extra draft command retained as history-only. Does not execute `networkQuality`. |

## Safety and persistence

`clean` and `uninstall` default to preview. `--dry-run` and `--scan` override `--yes`; `--force` does not exist. Bare `clean --yes` is a usage error. The CLI refuses protected roots, symlinks, Pulse state, complete agent-data roots (including `.codex` and `.claude`), user-excluded paths and paths with observed active files. It does not trust a catalog's “safe” grade alone. Inspection uses native libproc and the running-app list, not subprocesses. It is a point-in-time observation bounded by process/FD visibility; quitting the owning app/tool remains appropriate before cleanup.

Uninstall refuses running apps, protected bundles and ambiguous names. A bundle move failure stops leftover removal. macOS permission failures are surfaced rather than bypassed with shell elevation. The CLI never empties Trash or deletes duplicate groups.

Each successful CLI Trash move is journaled before the next one. Journal operations acquire a separate `flock` file, reload current disk state, mutate, and atomically save. This prevents lost updates between GUI and CLI. Corrupt journals fail closed on CLI operations. A persistence preflight precedes the move; a subsequent save failure attempts rollback. The existing GUI's nonthrowing record API retains compatibility and exposes/logs persistence errors.

Results report `bytesMovedToTrash`, not freed disk space. Physical space is retained until Trash is emptied. Undo never overwrites a re-created destination; partial/missing recovery exits 1 with counts. Successful restores remove only their recovered journal entries.

## App-control lifecycle

`AppControlServer` starts from the app delegate. Requests use a fixed distributed-notification name, a UUID response name, typed JSON and a closed list of non-destructive sleep/display verbs. There are no sockets, shell execution, arbitrary paths or polling while idle. The CLI waits at most five seconds for acknowledgment, and does not retry mutations. Invalid values are validated again in the receiver.

Run the matching rebuilt app in the same login session. An already-running older binary must be restarted; opening its replaced bundle does not update the running process. Controls intentionally fail when no matching app responds. Query state after a timeout before retrying. The app owns sleep timers and dimming overlays, so those actions survive CLI exit and end when the app exits. Manual brightness disables adaptive sync. DDC writes are awaited with a bound; hardware refusal is returned as an error. External brightness reads reflect the app's requested map rather than an independently verified monitor reading.

## Verification and limits

Parser, JSON encoding, safety selection, shared journal reload/conflicts/corruption, control-message rejection, BLAKE3 minimum filtering, hard links and available APFS clone identity have automated checks. `make cli-smoke` covers structured error exits, duplicate/verdict fixtures, cleanup/undo and synthetic app uninstall/undo. It touches only generated fixtures in temporary storage, user caches and user Applications; it does not test removal of real apps.

Manual terminal verification also covered all read commands, a full growth scan, display read/set at the existing level, and timed keep-awake surviving CLI exit then expiring. Visual approval is still required before merging, particularly for external DDC displays, negative dimming and permission-gated real app removal.

A release `vitals --lite` invocation measured 0.69s and 18,219,008 bytes peak RSS (about 17.4 MiB). The CLI was installed at `~/.local/bin/pulse` on this machine.

The proposed <10ms/<15MB blanket target is not a valid contract for filesystem scans or fresh CPU/network rates. On this machine, debug telemetry measured approximately 0.4–0.7s, history reads approximately 10ms, and a full growth scan approximately 46s. These are observations, not guarantees. CLI invocation adds no background sampler. Physical duplicate savings remain estimates because APFS sharing/compression can differ from logical size; unavailable clone metadata is not proof of independent blocks.

## September 13 native probe correction

The original cold-cache `verdict` path indirectly invoked `brew uses` and `otool -L` through UsageGraphScanner. This violated the CLI contract and CI timed out after 120 seconds. Both collectors now read files directly: Homebrew keg receipts supply installed runtime dependencies; Mach-O headers supply library load paths. Header reads are bounded to 1 MiB, universal tables to 64 architectures, and malformed input is rejected. The cache namespace is `usage-cache-native-v1`, so existing shell-derived caches cannot mask the new readers.

Receipt evidence does not include build-only dependencies or changed formula definitions. Mach-O inspection covers thin/universal binaries, both byte orders, absolute paths and loader/executable-relative paths; unresolved `@rpath` names are omitted. These are static clues, not a complete dependency proof.

See [September 13 CLI and skill audit](pulse-cli-audit-2026-09-13.md) for command coverage, action recovery, performance and remaining release gates.

## October 10 diagnostic upgrade

`observe --seconds 2...600` runs a bounded native session at approximately two-second cadence. JSON contains measured intervals, weighted mean/peak CPU, pressure persistence, swap/compression rates, aggregate storage I/O, process coverage, contributors, findings and limits. First counter reads have no rate baseline. Monitor → Investigate consumes the same PulseKit report, preserves the previous completed interval for comparison, and stops when dismissed, the command-center window is hidden, or the screen locks. Normal focus changes do not stop observation.

`process PID` returns `identity` (executable, parent, startedAt, exact startToken, helper role, footprint, cumulative disk counters), interval `metrics`, and `coverage`. `procs --grouped` aggregates owning apps; `procs --tree` exposes parent linkage. Monitor has Apps aggregation and selected-process role/footprint/executable details. Individual CPU 100% means one core; system CPU 100% means all cores. RSS totals are not exclusive physical usage.

`network [--url HTTP(S)-URL]` reads Wi-Fi/proxy/primary-interface context. The optional probe sends one ten-second-bounded, cookie-free HEAD request, follows no redirects and reports timing stages when available. It is not a speed test. `history --hours N` exposes minute CPU, pressure (1=normal, 2=warning, 4=critical), swap occupancy (bytes), CPU temperature (Celsius) and battery-level (%) histories, anomalies, battery sessions and daily storage snapshots. Missing/corrupt files are disclosed. New anomalies record start tokens; monitoring/leak detection reset on restart. `startup` provides bounded read-only launch-plist configuration, not a complete modern login-item inventory. These contexts are visible in Monitor's investigation sheet; Health retains its existing battery and reversible user-agent controls.

`sleep status` reads assertions without a responding GUI; app-owned keep-awake state then remains absent. `quit PID --started-at START-TOKEN` previews graceful application quit. `--yes` requests it only after consent. Helpers, protected apps, Pulse, and stale identities are refused; no force quit. Results distinguish requested/terminated; incomplete termination exits 1. Monitor uses the same quit boundary after confirmation.

Native correctness: proc_listallpids returns a PID count, not bytes. Task time and mach wall deltas use the same native ticks; an independent POSIX workload check guards the CPU units. Coverage records unreadable tasks; start tokens reset reused-PID baselines. Unavailable measurements do not imply health. Aggregate I/O reports activity, not latency or saturation; storage layers can overlap and I/O throughput remains outside the health score.

No new dependency, shell collector, daemon, browser debugging port or blanket optimization command was introduced. Legacy shell-backed optimization remains outside the diagnostic CLI. Optimize journals successful Trash moves individually and reports moved bytes rather than reclaimed capacity.

Regression checks cover PID coverage, POSIX CPU accounting, bounded/cancelled observations, identity/roles, stale/protected quit rejection, probe validation, CLI grammar, agent partial exits and preview identity gating. The portable skill routes symptom-directed diagnosis and remedies through supporting references. Bundles copy the entire skill folder, including references.
