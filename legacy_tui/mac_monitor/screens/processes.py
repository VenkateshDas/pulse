"""Processes pane — live, sortable, searchable process table with kill action."""
from __future__ import annotations

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical, Horizontal
from textual.screen import ModalScreen
from textual.widgets import Static, DataTable, Input, Button, Label
from mac_monitor.widgets.box import Box
from rich.text import Text

from mac_monitor import collectors

ROLE_COLOR = {"system": "dim", "browser": "cyan", "dev": "green", "user": "white"}
SORT_KEYS = [("cpu", "CPU"), ("mem_pct", "Mem"), ("disk_activity", "Disk")]


class ConfirmKillModal(ModalScreen[bool]):
    """Confirm before killing a process."""

    DEFAULT_CSS = """
    ConfirmKillModal {
        align: center middle;
    }
    #confirm-box {
        width: 60;
        height: auto;
        border: heavy $error;
        padding: 1 2;
        background: $surface;
    }
    #confirm-buttons {
        height: auto;
        layout: horizontal;
        margin-top: 1;
    }
    #confirm-buttons Button {
        margin-right: 1;
    }
    """

    def __init__(self, pid: int, name: str):
        super().__init__()
        self.pid = pid
        self.proc_name = name

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-box"):
            yield Label(f"Kill [bold]{self.proc_name}[/] (pid {self.pid})?")
            yield Label("[dim]Sends SIGTERM, escalates to SIGKILL after 3s.[/]")
            with Horizontal(id="confirm-buttons"):
                yield Button("Kill", variant="error", id="confirm-yes")
                yield Button("Cancel", variant="default", id="confirm-no")

    @on(Button.Pressed, "#confirm-yes")
    def _yes(self) -> None:
        self.dismiss(True)

    @on(Button.Pressed, "#confirm-no")
    def _no(self) -> None:
        self.dismiss(False)


class ProcessesPane(Vertical):
    """Live process table — search, sort by CPU/Mem/Disk, tree view, kill selected."""

    BINDINGS = [
        Binding("s", "cycle_sort", "Sort"),
        Binding("t", "toggle_tree", "Tree"),
        Binding("k", "kill_selected", "Kill"),
        Binding("slash", "focus_filter", "Filter", key_display="/"),
    ]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._procs: list[dict] = []
        self._visible: list[dict] = []
        self._sort_by = "cpu"
        self._tree_view = False
        self._selected_pid: int | None = None

    def compose(self) -> ComposeResult:
        with Horizontal(id="proc-toolbar", classes="toolbar"):
            yield Input(placeholder="Filter by name / pid / role…", id="proc-filter")
        yield DataTable(id="proc-table", cursor_type="row", zebra_stripes=True)
        yield Box("process inspector", id="proc-inspector", classes="box")
        yield Static("", id="proc-status", classes="dim")

    def on_mount(self) -> None:
        table = self.query_one("#proc-table", DataTable)
        table.add_columns("PID", "Name", "Role", "CPU%", "Memory", "Disk", "User", "Note")
        # First load happens on pane_activated — nothing runs while hidden.
        self._timer = self.set_interval(3.0, self.refresh_data, pause=True)

    def pane_activated(self) -> None:
        self._timer.resume()
        self.refresh_data()
        # Focus the table so s/t/k bindings work without an extra click.
        self.query_one("#proc-table", DataTable).focus()

    def pane_deactivated(self) -> None:
        self._timer.pause()

    def refresh_data(self) -> None:
        self.run_worker(self._collect, exclusive=True, thread=True)

    def _collect(self) -> None:
        procs = collectors.snapshot_processes(limit=200)
        self.app.call_from_thread(self._apply_snapshot, procs)

    def _apply_snapshot(self, procs: list[dict]) -> None:
        self._procs = procs
        self._populate()
        if self._selected_pid:
            self.run_worker(self._update_inspector, exclusive=True, thread=True)

    def _populate(self) -> None:
        table = self.query_one("#proc-table", DataTable)
        filter_text = self.query_one("#proc-filter", Input).value.strip().lower()
        sort_key = self._sort_by

        if self._tree_view:
            ordered = collectors.build_process_tree(self._procs, sort_key=sort_key)
            rows = [p for p, _depth in ordered][:200]
            depths = {p["pid"]: d for p, d in ordered}
        else:
            rows = self._procs
            if filter_text:
                rows = [p for p in rows
                        if filter_text in p["comm"].lower()
                        or filter_text in p["role"].lower()
                        or filter_text == str(p["pid"])]
            rows = sorted(rows, key=lambda p: -(p.get(sort_key) or 0))[:120]
            depths = {}
        self._visible = rows
        sort_label = dict(SORT_KEYS).get(sort_key, sort_key)
        view_label = "tree" if self._tree_view else "flat"
        status_extra = f"sort: {sort_label} (s) · view: {view_label} (t) · k = kill selected"

        table.clear()
        for i, p in enumerate(rows):
            anomaly = p["alarm"] is not None and p["cpu"] > p["alarm"]
            note = "⚠ anomaly" if anomaly else ""
            role_color = ROLE_COLOR.get(p["cat"], "white")
            cpu_style = "bold red" if anomaly else ("yellow" if p["cpu"] > (p["exp_max"] or 999) else "")
            disk_act = p.get("disk_activity", 0.0)
            disk_str = f"{disk_act:.0f}/s" if disk_act >= 1 else "—"
            disk_style = "yellow" if disk_act > 200 else "dim"
            depth = depths.get(p["pid"], 0)
            prefix = ("  " * depth + "└─ ") if depth else ""
            name_cell = (prefix + p["comm"])[:34]
            mem_mb = p['rss_mb']
            mem_str = f"{mem_mb / 1024:.1f} GB" if mem_mb > 1000 else f"{mem_mb} MB"
            table.add_row(
                str(p["pid"]),
                name_cell,
                f"[{role_color}]{p['role']}[/]",
                f"[{cpu_style}]{p['cpu']:.1f}[/]" if cpu_style else f"{p['cpu']:.1f}",
                f"{mem_str} ({p['mem_pct']:.1f}%)",
                f"[{disk_style}]{disk_str}[/]",
                p["user"],
                f"[red]{note}[/]" if anomaly else "",
                key=str(i),
            )
        self.query_one("#proc-status", Static).update(
            f"[dim]{len(rows)} shown / {len(self._procs)} total · {status_extra}[/]"
        )

    @on(Input.Changed, "#proc-filter")
    def _on_filter(self, event: Input.Changed) -> None:
        self._populate()

    @on(DataTable.RowHighlighted, "#proc-table")
    def _row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        row_key = event.row_key
        try:
            idx = int(row_key.value)
            if 0 <= idx < len(self._visible):
                self._selected_pid = self._visible[idx]["pid"]
                self.run_worker(self._update_inspector, exclusive=True, thread=True)
        except (TypeError, ValueError):
            pass

    def _update_inspector(self) -> None:
        if not self._selected_pid:
            return
        details = collectors.get_process_details(self._selected_pid)
        self.app.call_from_thread(self._render_inspector, details)
        
    def _render_inspector(self, details: dict | None) -> None:
        box = self.query_one("#proc-inspector", Box)
        if not details:
            box.update("[dim]Process no longer exists or access denied.[/]")
            return
        
        t = Text()
        t.append("Identity\n", style="bold underline cyan")
        t.append(f"Name: ", style="dim")
        t.append(f"{details['comm']:<20}  ", style="bold white")
        t.append(f"User: ", style="dim")
        t.append(f"{details['user']:<15}  ", style="white")
        t.append(f"Threads: ", style="dim")
        t.append(f"{details['threads']}\n", style="white")
        t.append("Command: ", style="dim")
        t.append(f"{details['args'][:250]}\n\n", style="italic")

        t.append("Resource Usage\n", style="bold underline yellow")
        
        rss_mb = details['rss_mb']
        vms_mb = details['vms_mb']
        rss_str = f"{rss_mb / 1024:.1f} GB" if rss_mb > 1000 else f"{rss_mb} MB"
        vms_str = f"{vms_mb / 1024:.1f} GB" if vms_mb > 1000 else f"{vms_mb} MB"
        
        t.append(f"Memory: ", style="dim")
        t.append(f"{rss_str} ", style="bold green")
        t.append(f"(Physical)  |  ", style="dim")
        t.append(f"{vms_str} ", style="bold")
        t.append(f"(Virtual Reserved)\n", style="dim")
        
        t.append(f"CPU Time: ", style="dim")
        t.append(f"{details['cpu_user_t']}s ", style="bold green")
        t.append(f"(User)  /  ", style="dim")
        t.append(f"{details['cpu_sys_t']}s ", style="bold")
        t.append(f"(System)\n\n", style="dim")

        t.append("System Impact Metrics\n", style="bold underline magenta")
        pfaults = details['pfaults']
        ctx_vol = details['ctx_vol']
        ctx_invol = details['ctx_invol']
        
        pf_level = "High" if pfaults > 50000 else "Moderate" if pfaults > 10000 else "Low"
        pf_color = "red" if pf_level == "High" else "yellow" if pf_level == "Moderate" else "green"
        
        ctx_level = "High" if ctx_vol > 50000 else "Moderate" if ctx_vol > 10000 else "Low"
        ctx_color = "red" if ctx_level == "High" else "yellow" if ctx_level == "Moderate" else "green"
        
        t.append(f"Hard Drive Thrashing: ", style="dim")
        t.append(f"{pf_level} ", style=f"bold {pf_color}")
        t.append(f"({pfaults} Page Faults)\n", style="dim")
        
        t.append(f"CPU Churn: ", style="dim")
        t.append(f"{ctx_level} ", style=f"bold {ctx_color}")
        t.append(f"({ctx_vol + ctx_invol} Context Switches)\n", style="dim")
        
        if details.get('fix'):
            t.append("\nDiagnosis\n", style="bold underline red")
            t.append(f"💡 {details['fix']}", style="white")
            
        box.update(t)

    def action_focus_filter(self) -> None:
        self.query_one("#proc-filter", Input).focus()

    def action_cycle_sort(self) -> None:
        keys = [k for k, _label in SORT_KEYS]
        self._sort_by = keys[(keys.index(self._sort_by) + 1) % len(keys)]
        self._populate()

    def action_toggle_tree(self) -> None:
        self._tree_view = not self._tree_view
        self._populate()

    def action_kill_selected(self) -> None:
        self._kill_current_row()

    @on(DataTable.RowSelected, "#proc-table")
    def _row_selected(self, event: DataTable.RowSelected) -> None:
        self._kill_current_row()

    def _kill_current_row(self) -> None:
        table = self.query_one("#proc-table", DataTable)
        if table.cursor_row is None or table.row_count == 0:
            return
        row_key = table.coordinate_to_cell_key(table.cursor_coordinate).row_key
        try:
            idx = int(row_key.value)
        except (TypeError, ValueError):
            return
        if not (0 <= idx < len(self._visible)):
            return
        proc = self._visible[idx]
        pid = proc["pid"]

        def _on_confirm(confirmed: bool | None) -> None:
            if not confirmed:
                return
            ok, msg = collectors.kill_process(pid)
            self.query_one("#proc-status", Static).update(
                f"[{'green' if ok else 'red'}]{msg}[/]"
            )
            self.refresh_data()

        self.app.push_screen(ConfirmKillModal(pid, proc["comm"]), _on_confirm)
