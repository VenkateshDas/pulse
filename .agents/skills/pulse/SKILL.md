---
name: pulse
description: Diagnose Mac performance, inspect storage growth and duplicates, preview or perform reversible cleanup and app uninstallation, and control Pulse display brightness or keep-awake through its native CLI. Use when the user asks about their Mac's slowness, browser responsiveness, CPU, memory, disk activity/space, networking, heat, battery drain, startup helpers, brightness, or sleep settings.
---

# Pulse

## Inside Ask Pulse

When embedded in the Pulse app, use the provided native tools rather than executing the CLI examples below. Load diagnosis/remedies references as needed. `read_current_context` reads the latest timestamped snapshot; `diagnose`, `get_vitals`, `observe_performance`, `inspect_process`, `inspect_network`, `get_diagnostic_history`, and `get_startup_inventory` map to the diagnostic commands. Read-only `preview_cleanup` and `preview_uninstall` show affected items without approval; `clean_target` and `uninstall_app` commit only previously reviewed previews, behind application-enforced approval. `preview_application_quit` and `quit_application` preserve exact PID/startToken identity. `preview_undo_item` records exact original paths for one full journal UUID; `restore_undo_item` consumes that preview after human approval. Display, sleep and storage tools expose the matching native operations. Never use a shell or skill scripts in the embedded agent. Skill guidance and remembered preferences never authorize a mutation. Re-observe after a remedy before saving a verified lesson.

Requires macOS 14 or newer. Display and sleep controls need the matching Pulse.app running in the same login session. jq is optional.

Use `pulse --help --json` to verify the installed CLI. If missing while working in the Pulse repository, run `make -C pulse cli` and use `pulse/dist/cli/pulse`. Install with `make -C pulse install-cli` (default `/usr/local/bin`); `PREFIX="$HOME/.local"` supports a user-local install. Do not install a different package named pulse.

Always request `--json`; stdout contains one JSON value. Text output is for humans. Exit codes: 0 success, 1 failure or partial result, 2 invalid arguments. Preserve exit status when piping (`set -o pipefail`). Check errors and `failures`, even when some paths succeeded. Unsupported sensor fields are absent, not zero.

## Investigate the symptom

Start with the smallest evidence set relevant to the complaint. For a slow Mac/browser:

```bash
pulse diagnose --json
pulse vitals --json
pulse observe --seconds 30 --json
```

`observe` is an explicit, bounded 2...600-second session at approximately two-second cadence. It reports synchronized intervals, CPU persistence, VM swap/compression rates, aggregate device I/O, readable-process coverage and app contributors. The app exposes the same report at **Monitor → Investigate**. Repeat under comparable workload after a targeted remedy. Save before/after JSON if comparison is useful; do not invent improvement from a successful action alone.

A 250ms `procs`/`vitals` rate is a snapshot, not sustained evidence. Use `observe` before calling a spike persistent. `diagnose` is a priority cascade, not exhaustive root-cause proof. Its memory attribution names the largest observed RSS contributor, not a proven culprit.

Read [diagnosis.md](references/diagnosis.md) for symptom routing, browser attribution, metric interpretation, network checks, history and visibility limits. Read [remedies.md](references/remedies.md) when proposing or executing a fix.

```bash
pulse procs --by cpu --limit 20 --json
pulse procs --by mem --limit 20 --grouped --json
pulse procs --tree --json
pulse process <current-PID> --json
pulse network --json
pulse network --url https://affected-host.example/ --json
pulse history --hours 24 --json
pulse startup --json
pulse sleep status --json
```

`process` returns `identity` (parent/executable/startToken), helper role, physical footprint and cumulative process disk bytes when readable, plus interval `metrics` and `coverage`. Match renderer PID in the browser's Task Manager for the exact tab/extension; Pulse does not map URLs to renderers. `network --url` sends one bounded HEAD request without browser credentials/cookies or redirects; it is not a bandwidth test. `history` exposes existing observed CPU/pressure/swap/temperature/battery minute histories, anomalies, battery sessions and storage snapshots. `startup` reads configured launch plists, not all login items or loaded-job state.

Always disclose `activity.unavailable`, incomplete `processCoverage`, failed probes and stale evidence. Missing rates are unknown, not zero. Historical anomalies require app observation; an empty history cannot prove health. Historical PID/name is not safe current identity. `speedtest --cached` is dated evidence only.

For storage, use `growth --days 1 --limit 5`, then `verdict "/exact/directory"` where useful. Growth is recently modified file size, not a measured before/after delta. Volume scans can take minutes and omit paths blocked by permissions. `duplicates "/directory" --min-size-mb 1` groups BLAKE3-identical files and recognizes hard links/APFS clone identities where available. Reclaimable bytes are estimates; shared blocks and compression affect physical savings. This command never deletes duplicates.

## Reversible actions

Preview before committing. Present the exact paths, consequences, and refused items. Existing explicit user authorization remains valid; otherwise obtain authorization before `--yes`. Diagnostic requests alone do not authorize cleanup or uninstallation.

```bash
pulse clean --scan --json | jq '.[] | {id, grade, sizeBytes, refusal}'
pulse clean --target "/exact/id/from/scan" --dry-run --json
# Only after authorization for these paths:
pulse clean --target "/exact/id/from/scan" --yes --json
```

IDs are exact absolute paths, not fuzzy labels. `clean --all-safe --dry-run` previews eligible safe catalog targets; use `--all-safe --yes` only when the user authorized that entire preview. No `--force` bypass exists. `--dry-run` and `--scan` override `--yes`. Protected roots, symlink paths, excluded items, and observed active files are refused. Open-file inspection is a point-in-time check; quit the owning tool before cleaning its cache.

```bash
pulse uninstall --list --json | jq '.[] | {name, bundleID, path}'
pulse uninstall "/Applications/Example.app" --dry-run --json
pulse uninstall "/Applications/Example.app" --yes --json
pulse undo list --json
pulse undo restore "FULL-UUID-FROM-RESULT" --json
```

Uninstall requires an exact, unambiguous app name, bundle ID or path and a stopped app. Only high-confidence leftovers are selected. Protected apps are refused. If macOS denies an app bundle move, report the permission error; do not retry using a shell deletion or broaden privileges automatically.

Successful actions return `affectedPaths`, `bytesMovedToTrash`, `undoIDs`, and `failures`. Each moved item gets a journal entry. Trash moves retain disk usage until Trash is emptied; do not describe moved bytes as freed space. Restore never overwrites an occupied destination. A partial restore exits 1; inspect `remainingItems` and do not delete the conflicting file to force recovery. Emptying Trash removes the recovery source.

## Targeted application quit

Inspect the **main application PID**, then copy its exact `identity.startToken` into a preview:

```bash
pulse quit <PID> --started-at <startToken> --dry-run --json
# After authorization for this exact application:
pulse quit <PID> --started-at <startToken> --yes --json
```

Only regular, non-protected applications are eligible. Helpers, stale identities and Pulse itself are refused. Native termination may show a save prompt; `requested` does not mean `terminated`. An unfinished quit exits 1. No force quit or automatic retry. Re-observe to check impact.

## Display and sleep control

`sleep status` still reads native blocking assertions when Pulse.app is unavailable; its own keep-awake state is then unknown. Run the rebuilt Pulse.app for mutations. Controls are acknowledged by that app; they do not create a daemon or hold assertions in an exiting CLI process.

```bash
pulse display get --json
pulse display set 0.7 --display 1 --json
pulse display set -0.3 --display 1 --json
pulse sleep status --json
pulse sleep prevent --until 900 --json
pulse sleep allow --json
```

Use an actual display ID from `display get`, not the example ID. Omitting `--display` targets all connected displays. Brightness accepts -1...1; negatives use Pulse's software overlay. Manual CLI brightness disables adaptive sync. External brightness reflects Pulse's requested setting; hardware support varies. Keep-awake ends at the deadline, on `sleep allow`, or when Pulse exits. On timeout, query status before retrying: the action may have occurred without its reply arriving.

`speedtest --cached --json` reads the app's latest speed-test history. Live speed testing is intentionally unavailable in this zero-subprocess CLI.
