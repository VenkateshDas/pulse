# Mac Monitor — Power-Up Plan

Researched comparable tools (iStat Menus, Activity Monitor, btop, mactop/macmon,
Sensei/CleanMyMac) before writing this. Findings:

- **Pure monitors** (iStat, Activity Monitor, btop, mactop): show data, no
  recommendations or actions. Activity Monitor explicitly criticized for
  "raw data without interpretation." btop has process tree view, per-process
  disk I/O, network graphs — things we lack. mactop/macmon expose
  E-core/P-core cluster usage + fan RPM on Apple Silicon (sudoless, same
  private API `macmon` already wraps).
- **Monitor+optimize hybrids** (Sensei, CleanMyMac): combine monitoring with
  cleanup, app uninstaller (removes leftover files, not just the .app),
  battery diagnostics. This is the category we're in — and our edge is being
  free, sudoless, scriptable, and a TUI (vs. paid GUI apps).

Differentiator to lean into: the "optimize" half (grade, quick wins, kill,
delete) is what neither btop nor iStat have. Add the gaps they DO have
(I/O, network, tree view, core breakdown), then go further on actions
(cleanup center, app uninstaller, login item management) than any free tool does.

## Tier 1 — close monitor gaps vs. btop / iStat / mactop

1. ~~**Per-process disk I/O**~~ — DONE, but adapted: `psutil.Process.io_counters()`
   doesn't exist on macOS (kernel hides it without root — confirmed via
   AttributeError). Used `top -stats pid,pageins` (sudoless) as a real proxy:
   per-process page-fault-from-disk rate, new sortable "Disk" column +
   "Sort: Disk" button in Processes. Also added `disk_throughput_mb_s()`
   (system-wide read/write MB/s via `psutil.disk_io_counters()` deltas) for
   later use on the Dashboard.
2. ~~**Network tab**~~ — DONE. `psutil.net_connections()` (system-wide) needs
   root on macOS, but `nettop -P -x -l 1 -J bytes_in,bytes_out` gives real
   per-process cumulative byte counts sudoless (~5s sample cost → 8s refresh
   interval). New tab: throughput chart + "top talkers" table (rates, totals,
   established-connection counts via per-process `net_connections`), kill action.
3. **Process tree view** — toggle in Processes pane showing parent → child
   hierarchy (helps answer "what spawned this renderer/helper").
4. ~~**E-core/P-core + fan RPM on Dashboard**~~ — DONE (core split only; fan
   RPM isn't in `macmon`'s JSON — confirmed via `--help`/output inspection,
   would need raw SMC access. This Mac may be fanless anyway). Surfaced
   `ecpu_usage`/`pcpu_usage` (freq + utilization) and `ane_power` — fields
   `collect_perf_light` was already receiving from macmon but discarding.
   New "APPLE SILICON CORES" KPI row + trend chart, auto-hidden on Intel Macs
   via `has_core_split`.

## Tier 2 — the optimization layer (our actual differentiator)

5. ~~**Cleanup Center**~~ — DONE. New "Cleanup" tab: scans 10 known
   regenerable locations (User Caches, Logs, Xcode DerivedData/Archives, iOS
   Simulators, Homebrew/npm/pip caches, iOS device backups, Trash), shows
   sizes + a one-line "why it's safe" hint, checkbox-style multi-select
   (toggle/select-all/clear), bulk confirm-and-trash. Found 1.4 GB
   reclaimable on first scan (1.2 GB in `~/Library/Caches` alone) in 0.4s.
6. ~~**App uninstaller**~~ — DONE. New "Apps" tab: lists `/Applications` +
   `~/Applications`, resolves bundle ID via `defaults read .../Info
   CFBundleIdentifier` (sudoless), scans 9 standard leftover locations
   (Application Support, Caches, Preferences, Containers, HTTPStorages,
   WebKit, Logs, LaunchAgents, Saved Application State), confirm-modal +
   bulk Trash. Found a real 9.7 GB leftover in `~/Library/Application
   Support/Claude` on first run — proof this is genuinely useful, not just
   a demo feature.
7. **Login items / LaunchAgents — disable, not just count** — `launchctl
   bootout`/unload (user domain, no sudo) + `osascript` to remove login items.

## Tier 3 — staying power

8. **SQLite history** — persist snapshots so trends/grade survive restarts;
   queryable multi-day history (no competitor offers this in a lightweight
   local form).
9. **Threshold alerts** — `osascript -e 'display notification'` when thermal/
   memory/disk/battery cross configured limits, even when not focused.
10. Duplicate-file finder, scheduled background scans (cache results so
    Storage tab doesn't cost ~9s every open).

## Sequencing decided

Start with **#1 + #2** (cheap, psutil-only, closes the most-cited gap vs. btop),
then **#6 app uninstaller** (highest "wow" factor, reuses the existing
Trash-based delete pattern from Storage).

## Post-Tier-2 user feedback: UI overhaul + perf fix

User feedback after using the app: "UI doesn't look like a techie dashboard,
too many big buttons/charts, button clicks feel slow (esp. Storage tab), app
uses too much RAM." Chose **htop/btop style** as the visual direction: dense
info-grids, monochrome/single-accent colors, inline sparklines instead of big
chart widgets, keyboard shortcuts in a status bar instead of button rows.

- ~~**Active-tab-only polling**~~ — DONE. Root cause of RAM/lag complaints:
  all 7 panes ran independent `set_interval` loops + competed for the shared
  worker thread pool regardless of visibility (e.g. Storage's `du` calls
  queued behind Network's ~5s `nettop` scans). Fixed via `set_interval(...,
  pause=True)` + `Timer` stored on each pollable pane (Dashboard, Processes,
  Performance, Network), with `pane_activated`/`pane_deactivated` hooks
  driven by `TabbedContent.TabActivated` in `app.py`. Verified via headless
  pilot: only the active tab's timer runs; switching tabs pauses the old one
  and resumes+immediately refreshes the new one.
- ~~**htop/btop visual redesign**~~ — DONE. Replaced bordered
  `.kpi-card`/`.grade-card`/`.chart-box` tiles with dense monochrome
  info-grid text rows; rewrote `app.tcss` around `.section-title`/`.info-row`/
  `.toolbar` (no borders, height:1 rows, $text-muted labels, single-accent
  highlight only on selection/active state). Added `mac_monitor/widgets/`
  with `sparkline()`/`bar()` block-character helpers — Dashboard now renders
  CPU/Mem/Thermal/Power/E-core/P-core trends as inline `▁▂▃▅▆▇█` strings next
  to the label:value, and `PlotextPlot` was removed entirely from Dashboard
  and Network (was the single biggest "big chart" offender). Converted large
  `Button` rows (Processes 5 buttons, Network 2, Performance 2, Cleanup 5,
  Apps 2, Storage 3) to per-pane `BINDINGS` (`s`=sort, `t`=tree, `k`=kill,
  `space`/`a`/`c`/`t`/`r`=cleanup select ops, `d`/`l`=storage delete/scan,
  `u`=uninstall, etc.) surfaced in the footer — matches "keyboard shortcuts
  in a status bar instead of button rows." Verified every pane via headless
  pilot: tab cycling, sparkline data flow, sort-cycle/tree-toggle/kill/
  select-all bindings all work and reflect real collector data.
- ~~**btop/mactop tiled-grid Dashboard**~~ — DONE. User shared btop + mactop
  screenshots as the concrete target: bordered boxes tiled into a grid, with
  corner titles, terminal-native gradient meters and block-column history
  graphs (not stacked plain-text rows — that earlier minimal pass undershot).
  Kept everything in Textual (btop is C++/mactop is Go — porting would discard
  all collectors + the 7 tabs + actions). Rewrote `widgets/__init__.py` with
  `meter()` (green→yellow→red horizontal fill, Rich Text) and `block_graph()`
  (multi-row block columns, vertical gradient — the mactop power-graph look).
  Rebuilt `dashboard.py` as a `Box` (bordered Static w/ `border_title`) grid:
  wide CPU box (total meter + per-core C0..Cn mini-meters + history graph),
  memory box (used/free/comprs/swap gradient meters), apple-silicon box
  (E/P cores + GPU + ANE meters), power·thermal box (watts graph + temps),
  disk box, and a one-line system-grade box with a colored letter chip.
  Added `per_core`/`cpu_overall`/`core_count` to `collect_vitals()` via
  `psutil.cpu_percent(percpu=True)`. Reworked `app.tcss` around `.box`
  (round border, #6cb6ff titles) + bordered DataTables app-wide for cohesion.
  Verified via pilot + SVG screenshot export (qlmanage→png): dashboard,
  processes, and network all render the paneled look correctly.
- ~~**Storage = lazy collapsible filesystem tree**~~ — DONE. Replaced the flat
  one-level browser with a Textual `Tree` that only materializes nodes for
  paths actually expanded (collapsed branches cost nothing — bounded memory,
  no whole-disk walk up front). Each expand is two-phase: (1) `os.scandir`
  fills names + exact file sizes + mtimes instantly (no subprocess); (2) a
  bounded `ThreadPoolExecutor` runs `du -sk` per child directory in parallel
  (min(8, ncpu) workers) so recursive dir sizes stream in as each finishes —
  small folders <1s, big ones later — and re-sort biggest-first at the end.
  Measured ~79/80 home-dir sizes filled in ~3s vs ~12s for a single blocking
  `du -d 1`. NOTE/finding: tried streaming a single `du -d 1`'s stdout first,
  but macOS block-buffers piped stdout so it all arrives at process exit (0→
  all-at-once) — parallel per-child `du -sk` is what actually streams + uses
  multiple cores. Guard: directories with >200 children fall back to one
  blocking `du -d 1` to avoid a process storm. Loaded nodes are cached
  (collapse/re-expand is instant, no recompute). Metadata per row: relative
  size (B/KB/MB/GB/TB via `fmt_size`, colored red ≥1GB / yellow ≥100MB) +
  mtime date. Root reparenting via keys: `u` up a level, `g` = `/` (whole
  filesystem), `h` = home; `d` trashes the selected node, `r` reloads.
  Default root is now `/System/Volumes/Data` (the APFS writable data volume —
  the real "everything" root that df reports; `/` is the read-only system
  volume), so the tree opens on the whole disk. Added a throttled live re-sort
  (every ~1.2s, ≤150 children) so big folders bubble to the top *during* a
  long load instead of only when the slowest child (Users) finishes — verified
  Users 32.4GB / System 30.9GB / opt 10.3GB sort to top within ~5s. Added
  `list_children_fast`/`du_size_bytes`/`dir_sizes_depth1` + `fmt_size` to
  collectors and `per_core` CPU. Verified via pilot + SVG screenshot.
## Round 3: app-wide speed overhaul (2026-06-12)

User: "app is very slow, TUI layout not effective." Profiled collectors —
`collect_perf_light` was 2.08s per 2.5s dashboard tick (respawned
`timeout 2 macmon pipe` every tick). All fixed:

- ~~**Persistent macmon stream**~~ — DONE. `MacmonStream` class: one long-lived
  `macmon pipe -i 1000` subprocess + daemon reader thread; `collect_perf_light`
  reads the latest cached JSON sample. 2.08s → 0.03s (69×). Auto-respawns if
  macmon dies; degrades to zeros if not installed.
- ~~**Zero-subprocess vitals**~~ — DONE. `psutil.boot_time()` + `os.getloadavg()`
  replace 3 `sysctl` spawns per tick; chip label/arm64 computed once and cached
  forever (`_TTLCache`); `pagesize` cached; AC detection via
  `psutil.sensors_battery()` instead of `ioreg|grep`.
- ~~**TTL caches for slow scans**~~ — DONE. Battery (system_profiler + pmset log,
  ~2.1s) cached 5 min; startup/login items (osascript ~0.6s) cached 2 min;
  per-process pageins `top` sample throttled to every 10s (process snapshot
  0.33s → 0.04s on cached ticks).
- ~~**Lazy first-load per pane**~~ — DONE. All 7 panes used to scan in
  `on_mount` at startup (incl. Apps' per-app `du` and Health's battery scans).
  Now every pane defers its first load to `pane_activated`; `app.on_mount`
  activates only the visible tab (via `call_after_refresh` so child timers
  exist). Startup cost = dashboard only.
- ~~**Parallel du scans**~~ — DONE. `list_apps` and `scan_cleanup_targets` run
  per-target `du -sh` in a bounded ThreadPoolExecutor (0.39s / 0.35s total).
- ~~**Help overlay + UX polish**~~ — DONE. `?` opens a HelpModal cheat sheet of
  every pane's bindings; `/` focuses the Processes filter; dashboard subtitle
  now shows chip · uptime · load.
- ~~**Safety fix**~~ — DONE. `delete_path` now calls osascript via argv (no
  shell) so paths with quotes can't break/escape the Finder-delete script;
  remaining `du` calls use `shlex.quote`.
- Verified via headless pilot: startup 0.08s, all 7 tabs switch cleanly, help
  modal opens/closes, process table populates + sort/tree toggles work,
  cleanup/battery panes load lazily; SVG screenshot confirms dashboard renders.

## Round 4: smart Storage tab — Cleanup merged in (2026-06-12)

User: "make Storage extremely smart — paid-app-level analysis, merge Cleanup."
Researched CleanMyMac/DaisyDisk/Sensei feature set; everything below is
sudoless and Trash-safe:

- ~~**`smart_scan()` engine**~~ — DONE (collectors.py). Four parallel category
  scanners, results cached 5 min, each row carries a safety badge:
  • *caches & logs / system junk* (green **safe**) — the old Cleanup targets;
    iOS backups demoted to red **review**.
  • *old installers* (yellow **careful**) — .dmg/.pkg/.iso/.xip in ~/Downloads
    older than 30d and >5MB.
  • *stale dev junk* (yellow **careful**) — node_modules/.venv/venv/.tox/
    target/.gradle dirs (find -maxdepth 6, prunes Library/.Trash/hidden/
    conda toolchains) whose parent project has been idle ≥60d; sized via
    parallel `du -sk`, ≥20MB only.
  • *large & old* (red **review**) — files >500MB untouched >180d outside
    Library/vm_bundles.
  First real run found 3.2GB (846M caches, 970MB stale node_modules under
  miniforge — later correctly pruned as toolchain, two forgotten 780MB videos).
- ~~**Storage tab = command center**~~ — DONE. Horizontal split: filesystem
  tree (3fr, all old keys) + SMART SCAN panel (2fr): suggestions table with
  ✓/safety/category/size columns, summary line "X reclaimable · Y fully
  safe". Keys: `space`/enter toggle, `a` select-all-**safe** (one-keystroke
  quick win), `c` clear, `t` trash (modal lists badges + warns on review
  items, rescans + refreshes df after), `s` force rescan. Tree `d`/`f` now
  focus-guarded so they can't fire while the suggestions table is focused.
- ~~**Cleanup tab removed**~~ — DONE. cleanup.py deleted, 6 tabs now, help
  overlay + bindings updated.
- Verified: pilot (6 tabs, scan rows render, select-safe → trash modal
  open/cancel, tree still loads 19 nodes) + real PTY run clean quit + SVG
  screenshots of split layout and confirm modal.

## Round 5: smart-scan fixes from live use (2026-06-12)

User hit two real bugs: trashing "User Caches" → "operation cannot be
performed", and pane shortcuts dead/slow sometimes.

- ~~**Granular cache rows**~~ — DONE. Finder refuses to trash
  ~/Library/Caches (and Logs) wholesale — they're system-required dirs. Smart
  scan now expands them into per-app subfolder suggestions (`_expand_cache_dir`,
  parallel du, ≥10MB, top 12) — each individually trashable AND shows which
  app hoards space (found ms-playwright 534MB as top offender).
- ~~**delete_path fallback**~~ — DONE. If Finder's osascript delete errors,
  fall back to same-volume `os.rename` into ~/.Trash (instant, equally
  recoverable, timestamp suffix on name collision). Verified on a test dir
  under ~/Library/Caches.
- ~~**Auto-focus on tab switch**~~ — DONE. Root cause of "shortcuts don't
  work sometimes": after switching tabs, focus sat on the tab bar, so
  pane-level BINDINGS never fired until the user clicked inside. Every
  pane_activated now focuses its primary widget (proc/net/assert/apps/smart
  tables); removed the has_focus guard on smart-table actions. Verified via
  pilot: space/a/c/s work immediately after `3`/`2` with zero clicks.

## Round 6: "free space didn't change" — Empty Trash + live df (2026-06-12)

User trashed ~1GB of suggestions, top df bar didn't move. Not a bug:
Move-to-Trash relocates files into ~/.Trash — space frees only on empty.
Made the model visible + actionable:

- ~~**`e` = Empty Trash**~~ — DONE. `empty_trash()` via Finder osascript,
  confirm modal (red "cannot be undone" warning) showing size, or item count
  when size unknown — macOS TCC blocks du/ls on ~/.Trash without Full Disk
  Access (`trash_info()` falls back to Finder's `count items of trash`,
  which always works). After emptying: forced rescan + df refresh.
- ~~**Post-trash hint**~~ — DONE. Status after `t` now says "now in Trash;
  press e to empty it and actually free X".
- ~~**Trash row in smart scan**~~ — DONE. Generic du-based scan silently
  dropped Trash (TCC → size 0); now a synthetic row shows item count with
  hint "press e to empty". Selecting it with `t` is intercepted (can't trash
  the Trash) and routed to `e`; ~/.Trash added to delete_path's protected set.
- ~~**Live df**~~ — DONE. 5s paused-timer df refresh while Storage tab
  active, so the top bar updates in near-real-time after empty/external writes.
- Verified via pilot: Trash row renders (7 items), `e` opens modal, cancel
  works, df summary live. NOTE: a 2MB test file `zz-macmon-trash-test.bin`
  from verification sits in the user's Trash — disappears on next empty.

- ~~**Storage tab click-lag fix (superseded by the tree above)**~~ — DONE. Root cause: `list_dir()` runs
  `du -h -d 1 <path>` (can take 5-10s+ on large dirs like `~/Library`) and
  the UI gave **zero** feedback until it finished — looked frozen on click.
  Fixed via `StoragePane._navigate()`: clears the table and shows
  "[dim]Loading…[/]" *synchronously* on the UI thread before launching the
  background `du` worker, so every click/Enter/Backspace now reflects
  instantly even though the scan itself still takes the same wall-clock time.
  Verified via pilot: status shows "Loading…" immediately on click, then
  "110 items in …/Library" ~6s later when the real `du` scan completes.
