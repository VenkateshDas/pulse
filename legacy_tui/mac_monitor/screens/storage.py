"""Storage pane — lazy collapsible filesystem tree with size + date metadata.

Memory/compute strategy: the tree only materializes nodes for paths the user
has actually expanded (collapsed branches hold nothing). Each expand is two
phase — `os.scandir` fills names/file-sizes/dates instantly (no subprocess),
then a single background `du -k -d 1` pass computes recursive directory sizes
for the whole level at once and re-sorts biggest-first. Loaded nodes are cached
(re-expanding is instant); nothing walks the whole disk up front.
"""
from __future__ import annotations

import os
import time
from datetime import datetime

from rich.text import Text

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical, Horizontal
from textual.screen import ModalScreen
from textual.widgets import Static, Tree, Button, Label, DataTable
from textual.widgets.tree import TreeNode

from mac_monitor import collectors
from mac_monitor.widgets import meter

HOME = collectors.HOME
# On APFS macOS the writable data volume is mounted here ("/" is the read-only
# system volume); this is the real "everything" root and what df reports.
DATA_VOL = "/System/Volumes/Data"


def _fmt_date(mtime: float) -> str:
    try:
        return datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
    except (OSError, ValueError, OverflowError):
        return "—"


def _size_style(n: int | None) -> str:
    if n is None:
        return "grey42"
    if n >= 1 << 30:            # >= 1 GB
        return "#e74c3c"
    if n >= 100 * (1 << 20):    # >= 100 MB
        return "#f1c40f"
    return "grey62"


class ConfirmDeleteModal(ModalScreen[bool]):
    DEFAULT_CSS = """
    ConfirmDeleteModal { align: center middle; }
    #del-box {
        width: 70; height: auto;
        border: heavy $error; padding: 1 2; background: $surface;
    }
    #del-buttons { height: auto; layout: horizontal; margin-top: 1; }
    #del-buttons Button { margin-right: 1; }
    """

    def __init__(self, path: str):
        super().__init__()
        self.path = path

    def compose(self) -> ComposeResult:
        with Vertical(id="del-box"):
            yield Label(f"Move to Trash:\n[bold]{self.path}[/]")
            yield Label("[dim]Safe delete — goes to macOS Trash, not permanently removed.[/]")
            with Horizontal(id="del-buttons"):
                yield Button("Move to Trash", variant="error", id="del-yes")
                yield Button("Cancel", id="del-no")

    @on(Button.Pressed, "#del-yes")
    def _yes(self) -> None:
        self.dismiss(True)

    @on(Button.Pressed, "#del-no")
    def _no(self) -> None:
        self.dismiss(False)


SAFETY_BADGE = {
    "safe": "[#2ecc71]● safe[/]",
    "careful": "[#f1c40f]● careful[/]",
    "review": "[#e74c3c]● review[/]",
}


class ConfirmSmartTrashModal(ModalScreen[bool]):
    DEFAULT_CSS = """
    ConfirmSmartTrashModal { align: center middle; }
    #st-box {
        width: 84; height: auto; max-height: 30;
        border: heavy $error; padding: 1 2; background: $surface;
    }
    #st-buttons { height: auto; layout: horizontal; margin-top: 1; }
    #st-buttons Button { margin-right: 1; }
    """

    def __init__(self, items: list[dict], total_mb: float):
        super().__init__()
        self.items = items
        self.total_mb = total_mb

    def compose(self) -> ComposeResult:
        with Vertical(id="st-box"):
            yield Label(f"Move {len(self.items)} item(s) to Trash — "
                        f"reclaiming ~{collectors.fmt_mb(self.total_mb)}:")
            body = "\n".join(f"  {SAFETY_BADGE[it['safety']]} {it['label']} ({it['size_str']})"
                             for it in self.items[:14])
            if len(self.items) > 14:
                body += f"\n  … and {len(self.items) - 14} more"
            yield Static(body)
            yield Label("[dim]Safe delete — everything goes to macOS Trash. "
                        "Double-check red 'review' items: those are real data, not caches.[/]")
            with Horizontal(id="st-buttons"):
                yield Button("Move to Trash", variant="error", id="st-yes")
                yield Button("Cancel", id="st-no")

    @on(Button.Pressed, "#st-yes")
    def _yes(self) -> None:
        self.dismiss(True)

    @on(Button.Pressed, "#st-no")
    def _no(self) -> None:
        self.dismiss(False)


class ConfirmEmptyTrashModal(ModalScreen[bool]):
    DEFAULT_CSS = """
    ConfirmEmptyTrashModal { align: center middle; }
    #et-box {
        width: 70; height: auto;
        border: heavy $error; padding: 1 2; background: $surface;
    }
    #et-buttons { height: auto; layout: horizontal; margin-top: 1; }
    #et-buttons Button { margin-right: 1; }
    """

    def __init__(self, size_mb: float | None, count: int):
        super().__init__()
        self.size_mb = size_mb
        self.count = count

    def compose(self) -> ComposeResult:
        what = (collectors.fmt_mb(self.size_mb) if self.size_mb
                else f"{self.count} item(s)")
        with Vertical(id="et-box"):
            yield Label(f"Empty Trash — permanently delete [bold]{what}[/]?")
            yield Label("[bold #e74c3c]This cannot be undone.[/] "
                        "[dim]Only emptying the Trash actually returns free space to the disk.[/]")
            with Horizontal(id="et-buttons"):
                yield Button("Empty Trash", variant="error", id="et-yes")
                yield Button("Cancel", id="et-no")

    @on(Button.Pressed, "#et-yes")
    def _yes(self) -> None:
        self.dismiss(True)

    @on(Button.Pressed, "#et-no")
    def _no(self) -> None:
        self.dismiss(False)


class StoragePane(Vertical):
    """Disk summary + filesystem tree (left) + smart-scan suggestions (right)."""

    BINDINGS = [
        Binding("u", "root_up", "Up a root"),
        Binding("g", "root_data", "Root = data volume"),
        Binding("h", "root_home", "Root = home"),
        Binding("d", "delete_selected", "Delete"),
        Binding("f", "reveal_finder", "Reveal in Finder"),
        Binding("r", "reload", "Reload"),
        Binding("space", "toggle_suggestion", "Toggle", show=False),
        Binding("a", "select_safe", "Select safe"),
        Binding("c", "clear_selection", "Clear", show=False),
        Binding("t", "trash_suggestions", "Trash selected"),
        Binding("s", "rescan_smart", "Rescan smart"),
        Binding("e", "empty_trash", "Empty Trash"),
    ]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.root_path = DATA_VOL
        # Bumped on every (re)build so stale background workers from a previous
        # load/reparent can't mutate a rebuilt tree.
        self._load_gen = 0
        self._suggestions: list[dict] = []
        self._checked: set[int] = set()

    def compose(self) -> ComposeResult:
        yield Static("Loading disk info…", id="disk-summary", classes="dim")
        with Horizontal(id="storage-split"):
            with Vertical(id="storage-left"):
                yield Static("FILESYSTEM  (enter = expand · u/g/h roots · f = Finder · d = trash · r = reload)",
                             classes="section-title")
                yield Tree("", id="fs-tree")
            with Vertical(id="storage-right"):
                yield Static("SMART SCAN  (space = toggle · a = select safe · t = trash · e = empty trash · s = rescan)",
                             classes="section-title")
                yield Static("Scanning…", id="smart-summary", classes="dim")
                yield DataTable(id="smart-table", cursor_type="row", zebra_stripes=True)
        yield Static("", id="storage-status", classes="dim")

    def on_mount(self) -> None:
        tree = self.query_one("#fs-tree", Tree)
        tree.show_root = True
        tree.guide_depth = 2
        table = self.query_one("#smart-table", DataTable)
        table.add_columns("✓", "Safety", "Category", "Size", "What")
        self._loaded = False
        # Live df refresh — cheap (~10ms) and keeps the top bar honest while
        # files are trashed/emptied or other apps write to disk.
        self._df_timer = self.set_interval(
            5.0, lambda: self.run_worker(self._load_disk, exclusive=True,
                                         thread=True, group="storage-df"),
            pause=True)

    # ---- activation (tab pause/resume contract) -----------------------------
    def pane_activated(self) -> None:
        # Build the tree + run the smart scan on first visit only.
        if not self._loaded:
            self._loaded = True
            self._build_tree()
            self.run_worker(self._load_disk, exclusive=True, thread=True, group="storage")
            self._run_smart_scan()
        # Focus the suggestions table so space/a/t/s work immediately —
        # without this, focus stays on the tab bar and pane keys go dead.
        self.query_one("#smart-table", DataTable).focus()
        self._df_timer.resume()

    def pane_deactivated(self) -> None:
        self._df_timer.pause()

    def refresh_data(self) -> None:
        self._build_tree()
        self.run_worker(self._load_disk, exclusive=True, thread=True, group="storage")
        self._run_smart_scan()

    # ---- smart scan ----------------------------------------------------------
    def _run_smart_scan(self, force: bool = False) -> None:
        self.query_one("#smart-summary", Static).update(
            "[dim]Analyzing caches, dev junk, old installers, large & old files…[/]")
        self.run_worker(lambda: self._smart_scan(force), exclusive=True,
                        thread=True, group="smart")

    def _smart_scan(self, force: bool) -> None:
        rows = collectors.smart_scan(force=force)
        self.app.call_from_thread(self._render_suggestions, rows)

    def _render_suggestions(self, rows: list[dict]) -> None:
        self._suggestions = rows
        self._checked = set()
        self._populate_suggestions()
        total = sum(r["size_mb"] for r in rows)
        safe = sum(r["size_mb"] for r in rows if r["safety"] == "safe")
        self.query_one("#smart-summary", Static).update(
            f"[bold yellow]{collectors.fmt_mb(total)}[/] reclaimable · "
            f"[#2ecc71]{collectors.fmt_mb(safe)} fully safe[/] · {len(rows)} suggestions"
        )

    def _populate_suggestions(self) -> None:
        table = self.query_one("#smart-table", DataTable)
        table.clear()
        for i, r in enumerate(self._suggestions):
            mark = "[green]✔[/]" if i in self._checked else " "
            table.add_row(mark, SAFETY_BADGE[r["safety"]], r["category"],
                          r["size_str"], r["label"][:38], key=str(i))

    def _suggestion_cursor_idx(self) -> int | None:
        table = self.query_one("#smart-table", DataTable)
        if table.row_count == 0 or table.cursor_row is None:
            return None
        row_key = table.coordinate_to_cell_key(table.cursor_coordinate).row_key
        try:
            idx = int(row_key.value)
        except (TypeError, ValueError):
            return None
        return idx if 0 <= idx < len(self._suggestions) else None

    def action_toggle_suggestion(self) -> None:
        idx = self._suggestion_cursor_idx()
        if idx is None:
            return
        self._checked.symmetric_difference_update({idx})
        self._populate_suggestions()

    @on(DataTable.RowSelected, "#smart-table")
    def _suggestion_row_selected(self, event: DataTable.RowSelected) -> None:
        try:
            idx = int(event.row_key.value)
        except (TypeError, ValueError):
            return
        if 0 <= idx < len(self._suggestions):
            self._checked.symmetric_difference_update({idx})
            self._populate_suggestions()

    def action_select_safe(self) -> None:
        """Select every green 'safe' suggestion — the one-keystroke quick win."""
        self._checked = {i for i, r in enumerate(self._suggestions)
                         if r["safety"] == "safe"}
        self._populate_suggestions()

    def action_clear_selection(self) -> None:
        self._checked = set()
        self._populate_suggestions()

    def action_rescan_smart(self) -> None:
        self._run_smart_scan(force=True)

    def action_trash_suggestions(self) -> None:
        if not self._checked:
            self.query_one("#storage-status", Static).update(
                "[yellow]Select suggestions first (space/enter on a row, or a = all safe)[/]")
            return
        items = [self._suggestions[i] for i in sorted(self._checked)]
        # The Trash row can't be "moved to Trash" — route it to `e` instead.
        trash_path = os.path.join(HOME, ".Trash")
        if any(it["path"] == trash_path for it in items):
            items = [it for it in items if it["path"] != trash_path]
            self.query_one("#storage-status", Static).update(
                "[yellow]Trash itself is emptied with e, not t[/]")
            if not items:
                return
        total_mb = sum(it["size_mb"] for it in items)

        def _on_confirm(confirmed: bool | None) -> None:
            if not confirmed:
                return
            ok_count, fail_count = 0, 0
            for it in items:
                ok, _msg = collectors.delete_path(it["path"])
                if ok:
                    ok_count += 1
                else:
                    fail_count += 1
            self.query_one("#storage-status", Static).update(
                f"[green]Trashed {ok_count} item(s)[/]"
                + (f", [red]{fail_count} failed[/]" if fail_count else "")
                + f" — [yellow]now in Trash; press e to empty it and actually free "
                  f"{collectors.fmt_mb(total_mb)}[/]"
            )
            self._run_smart_scan(force=True)
            self.run_worker(self._load_disk, exclusive=True, thread=True, group="storage")

        self.app.push_screen(ConfirmSmartTrashModal(items, total_mb), _on_confirm)

    def action_empty_trash(self) -> None:
        self.query_one("#storage-status", Static).update("[dim]Checking Trash…[/]")
        self.run_worker(self._check_trash_worker, exclusive=True,
                        thread=True, group="storage-trash")

    def _check_trash_worker(self) -> None:
        size_mb, count = collectors.trash_info()
        self.app.call_from_thread(self._show_empty_trash_modal, size_mb, count)

    def _show_empty_trash_modal(self, size_mb: float | None, count: int) -> None:
        if count == 0 and not size_mb:
            self.query_one("#storage-status", Static).update("[dim]Trash is already empty[/]")
            return

        def _on_confirm(confirmed: bool | None) -> None:
            if not confirmed:
                self.query_one("#storage-status", Static).update("")
                return
            self.query_one("#storage-status", Static).update("[dim]Emptying Trash…[/]")
            self.run_worker(self._empty_trash_worker, exclusive=True,
                            thread=True, group="storage-trash")

        self.app.push_screen(ConfirmEmptyTrashModal(size_mb, count), _on_confirm)

    def _empty_trash_worker(self) -> None:
        ok, msg = collectors.empty_trash()
        def _done() -> None:
            self.query_one("#storage-status", Static).update(
                f"[{'green' if ok else 'red'}]{msg}[/]")
            self._run_smart_scan(force=True)
            self.run_worker(self._load_disk, exclusive=True, thread=True, group="storage")
        self.app.call_from_thread(_done)

    # ---- disk summary -------------------------------------------------------
    def _load_disk(self) -> None:
        disk = collectors.collect_disk_usage()
        self.app.call_from_thread(self._render_disk, disk)

    def _render_disk(self, disk: dict) -> None:
        summary = self.query_one("#disk-summary", Static)
        if not disk:
            summary.update("[red]Could not read disk usage[/]")
            return
        pct = disk.get("pct", 0)
        body = Text()
        body.append(meter(pct, width=40))
        body.append(f" {pct}% used   ", style="bold")
        body.append(f"size {disk.get('size')} · used {disk.get('used')} · "
                    f"free {disk.get('avail')} · {disk.get('mount')}", style="grey62")
        summary.update(body)

    # ---- tree ---------------------------------------------------------------
    def _build_tree(self) -> None:
        self._load_gen += 1
        tree = self.query_one("#fs-tree", Tree)
        data = {"name": self.root_path, "path": self.root_path, "is_dir": True,
                "size": None, "mtime": self._safe_mtime(self.root_path), "loaded": False}
        tree.reset(self._node_label(data, root=True), data)
        tree.root.expand()   # fires NodeExpanded → lazy load

    @staticmethod
    def _safe_mtime(path: str) -> float:
        try:
            return os.stat(path).st_mtime
        except OSError:
            return 0.0

    def _node_label(self, e: dict, root: bool = False) -> Text:
        t = Text()
        if root:
            t.append("🖴 ", style="grey70")
            t.append(e["path"], style="bold")
        else:
            t.append("📁 " if e["is_dir"] else "  ", style="grey70")
            t.append(e["name"])
        t.append("   ")
        t.append(collectors.fmt_size(e["size"]), style=_size_style(e["size"]))
        if not root:
            t.append("   ")
            t.append(_fmt_date(e["mtime"]), style="grey42")
        return t

    def _add_entry(self, node: TreeNode, e: dict) -> None:
        if e["is_dir"]:
            node.add(self._node_label(e), data=e, allow_expand=True)
        else:
            node.add_leaf(self._node_label(e), data=e)

    @on(Tree.NodeExpanded, "#fs-tree")
    def _on_expand(self, event: Tree.NodeExpanded) -> None:
        node = event.node
        e = node.data
        if not e or not e.get("is_dir") or e.get("loaded"):
            return
        e["loaded"] = True
        gen = self._load_gen
        self.run_worker(lambda: self._scan_node(node, e["path"], gen),
                        exclusive=False, thread=True, group="storage")

    # Above this many child directories, fall back to one blocking `du -d 1`
    # pass instead of spawning a `du -sk` per child (avoids a process storm).
    _PARALLEL_CHILD_CAP = 200

    def _scan_node(self, node: TreeNode, path: str, gen: int) -> None:
        # Phase 1: instant listing (scandir, no subprocess).
        children = collectors.list_children_fast(path)
        self.app.call_from_thread(self._add_children, node, children, gen)

        # Phase 2: recursive directory sizes. Run `du -sk` per child in a
        # bounded thread pool so results stream in as each finishes (small
        # folders in <1s, big ones later) and multiple cores are used.
        dir_children = [e for e in children if e["is_dir"]]
        if not dir_children:
            return
        if len(dir_children) > self._PARALLEL_CHILD_CAP:
            sizes = collectors.dir_sizes_depth1(path)
            for e in dir_children:
                sz = sizes.get(os.path.normpath(e["path"]))
                if sz is not None:
                    self.app.call_from_thread(self._update_one_size, node, e["path"], sz, gen)
            self.app.call_from_thread(self._resort, node, gen)
            return

        import concurrent.futures
        max_workers = min(8, (os.cpu_count() or 4))
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as ex:
            futs = {ex.submit(collectors.du_size_bytes, e["path"]): e for e in dir_children}
            for fut in concurrent.futures.as_completed(futs):
                if gen != self._load_gen:    # tree was rebuilt — abandon stale work
                    break
                e = futs[fut]
                try:
                    sz = fut.result()
                except Exception:
                    sz = None
                if sz is not None:
                    self.app.call_from_thread(self._update_one_size, node, e["path"], sz, gen)
        self.app.call_from_thread(self._resort, node, gen)

    def _add_children(self, node: TreeNode, children: list[dict], gen: int) -> None:
        if gen != self._load_gen:
            return
        try:
            node.remove_children()
            if not children:
                node.add_leaf(Text("(empty or no access)", style="grey42"),
                              data={"is_dir": False, "path": None})
                return
            for e in children:
                self._add_entry(node, e)
        except (KeyError, ValueError):
            pass

    # Throttle live re-sorts so big folders bubble up during a long load
    # (e.g. the data volume's Users branch) without churning on every update.
    _RESORT_INTERVAL = 1.2
    _RESORT_MAX_CHILDREN = 150

    def _update_one_size(self, node: TreeNode, path: str, sz: int, gen: int) -> None:
        if gen != self._load_gen:
            return
        target = os.path.normpath(path)
        for child in node.children:
            e = child.data
            if e and e.get("is_dir") and os.path.normpath(e["path"]) == target:
                e["size"] = sz
                child.set_label(self._node_label(e))
                break
        # Periodically re-sort biggest-first while sizes are still streaming in.
        pdata = node.data or {}
        if (len(node.children) <= self._RESORT_MAX_CHILDREN
                and time.monotonic() - pdata.get("_last_sort", 0.0) >= self._RESORT_INTERVAL):
            pdata["_last_sort"] = time.monotonic()
            self._resort(node, gen)

    def _resort(self, node: TreeNode, gen: int) -> None:
        if gen != self._load_gen:
            return
        # Never reorder a level once any child has begun loading or been
        # expanded — reordering removes+re-adds nodes, which would detach an
        # actively-loading child subtree (its in-flight worker would then mutate
        # removed nodes → KeyError). Once you drill in, this level's order
        # freezes; that's fine, the sizes still update in place.
        if any((c.data and c.data.get("loaded")) or c.is_expanded or c.children
               for c in node.children):
            return
        ordered = sorted(
            (c.data for c in node.children if c.data and c.data.get("path") is not None),
            key=lambda e: -(e["size"] or 0),
        )
        if not ordered:
            return
        try:
            node.remove_children()
            for e in ordered:
                self._add_entry(node, e)
        except (KeyError, ValueError):
            pass

    # ---- selection / actions ------------------------------------------------
    def _selected(self) -> dict | None:
        tree = self.query_one("#fs-tree", Tree)
        if not tree.has_focus:   # d/f keys act on the focused panel only
            return None
        node = tree.cursor_node
        if node and node.data and node.data.get("path"):
            return node.data
        return None

    def action_root_up(self) -> None:
        parent = os.path.dirname(self.root_path.rstrip("/")) or "/"
        if parent != self.root_path:
            self.root_path = parent
            self._build_tree()

    def action_root_data(self) -> None:
        self.root_path = DATA_VOL
        self._build_tree()

    def action_root_home(self) -> None:
        self.root_path = HOME
        self._build_tree()

    def action_reload(self) -> None:
        self.refresh_data()

    def action_reveal_finder(self) -> None:
        entry = self._selected()
        if not entry:
            self.query_one("#storage-status", Static).update("[yellow]Select a file or folder first[/]")
            return
        ok, msg = collectors.reveal_in_finder(entry["path"])
        self.query_one("#storage-status", Static).update(f"[{'green' if ok else 'red'}]{msg}[/]")

    def action_delete_selected(self) -> None:
        entry = self._selected()
        if not entry:
            self.query_one("#storage-status", Static).update("[yellow]Select a file or folder first[/]")
            return

        def _on_confirm(confirmed: bool | None) -> None:
            if not confirmed:
                return
            ok, msg = collectors.delete_path(entry["path"])
            self.query_one("#storage-status", Static).update(f"[{'green' if ok else 'red'}]{msg}[/]")
            if ok:
                tree = self.query_one("#fs-tree", Tree)
                node = tree.cursor_node
                parent = node.parent if node else None
                if parent and parent.data:
                    parent.data["loaded"] = False
                    parent.collapse()
                    parent.expand()

        self.app.push_screen(ConfirmDeleteModal(entry["path"]), _on_confirm)
