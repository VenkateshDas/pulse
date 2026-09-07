---
name: pulse
description: Diagnose Mac performance, inspect storage growth and duplicates, preview or perform reversible cleanup and app uninstallation, and control Pulse display brightness or keep-awake through its native CLI. Use when the user asks about their Mac's CPU, memory, fan noise, disk space, brightness, or sleep settings.
---

# Pulse

Requires macOS 14 or newer. Display and sleep controls need the matching Pulse.app running in the same login session. jq is optional.

Use `pulse --help --json` to verify the installed CLI. If missing while working in the Pulse repository, run `make -C pulse cli` and use `pulse/dist/cli/pulse`. Install with `make -C pulse install-cli` (default `/usr/local/bin`); `PREFIX="$HOME/.local"` supports a user-local install. Do not install a different package named pulse.

Always request `--json`; stdout contains one JSON value. Text output is for humans. Exit codes: 0 success, 1 failure or partial result, 2 invalid arguments. Preserve exit status when piping (`set -o pipefail`). Check errors and `failures`, even when some paths succeeded. Unsupported sensor fields are absent, not zero.

## Diagnose first

```bash
pulse diagnose --json | jq '{score, verdict, severity, triggeredFactor, culprit}'
pulse procs --by cpu --limit 5 --json | jq '.[] | {pid, name, cpuPercent, residentBytes}'
pulse anomalies --hours 24 --json | jq '.[] | {processName, kind, date, sustainedSeconds}'
```

Use `--by mem` for memory ranking. `vitals [--lite]` samples CPU, memory, disk, network, battery and GPU; lite skips process enumeration. `sensors` reports temperature, fans and battery health. `attention` returns prioritized alerts. CPU/network rates use a 250ms interval and are not sustained-load evidence; correlate with anomalies. These reads work without Pulse.app. Historical anomalies require previous app observation; empty history does not prove no problem occurred.

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

## Display and sleep control

Run the rebuilt Pulse.app first. Controls are acknowledged by that app; they do not create a daemon or hold assertions in an exiting CLI process.

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
