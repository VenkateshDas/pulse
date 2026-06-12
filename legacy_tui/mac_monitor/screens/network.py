"""Network pane — system throughput sparkline + per-process top talkers."""
from __future__ import annotations

from collections import deque

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical
from textual.widgets import Static, DataTable

from mac_monitor import collectors
from mac_monitor.widgets import sparkline
from mac_monitor.widgets.box import Box
from rich.text import Text

HISTORY_LEN = 60


class NetworkPane(Vertical):
    """Throughput readout + sortable table of top network-active processes."""

    BINDINGS = [
        Binding("k", "kill_selected", "Kill selected"),
    ]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.sent_hist: deque[float] = deque(maxlen=HISTORY_LEN)
        self.recv_hist: deque[float] = deque(maxlen=HISTORY_LEN)
        self._talkers: list[dict] = []

    def compose(self) -> ComposeResult:
        yield Static("NETWORK", classes="section-title")
        yield Static("Collecting…", id="net-summary")
        yield Static("TOP TALKERS  (↓/↑ rate · k = kill selected)", classes="section-title")
        yield DataTable(id="net-table", cursor_type="row", zebra_stripes=True)
        yield Box("network inspector", id="net-inspector", classes="box")
        yield Static("", id="net-status", classes="dim")

    def on_mount(self) -> None:
        table = self.query_one("#net-table", DataTable)
        table.add_columns("PID", "Process", "↓ KB/s", "↑ KB/s", "Total ↓", "Total ↑", "Conns")
        # First load happens on pane_activated — nothing runs while hidden.
        self._timer = self.set_interval(8.0, self.refresh_data, pause=True)

    def pane_activated(self) -> None:
        self._timer.resume()
        self.refresh_data()
        self.query_one("#net-table", DataTable).focus()

    def pane_deactivated(self) -> None:
        self._timer.pause()

    def refresh_data(self) -> None:
        self.run_worker(self._collect, exclusive=True, thread=True, group="network")

    def _collect(self) -> None:
        net = collectors.collect_network()
        self.app.call_from_thread(self._apply_snapshot, net)

    def _apply_snapshot(self, net: dict) -> None:
        sent, recv = net.get("sent_kb_s", 0.0), net.get("recv_kb_s", 0.0)
        self.sent_hist.append(sent)
        self.recv_hist.append(recv)
        peak = max(max(self.sent_hist, default=0), max(self.recv_hist, default=0), 1)

        self.query_one("#net-summary", Static).update(
            f"[dim]{'↓ recv':<8}[/] [bold cyan]{recv:7.1f} KB/s[/]  [dim]{sparkline(list(self.recv_hist), width=28, vmax=peak)}[/]\n"
            f"[dim]{'↑ sent':<8}[/] [bold magenta]{sent:7.1f} KB/s[/]  [dim]{sparkline(list(self.sent_hist), width=28, vmax=peak)}[/]\n"
            f"[dim]lifetime: {net.get('total_recv_mb', 0)} MB received · {net.get('total_sent_mb', 0)} MB sent[/]"
        )

        self._talkers = net.get("talkers", [])
        table = self.query_one("#net-table", DataTable)
        table.clear()
        for i, t in enumerate(self._talkers):
            active = t["in_kb_s"] > 1 or t["out_kb_s"] > 1
            style = "bold yellow" if active else ""
            table.add_row(
                str(t["pid"]),
                t["name"][:50],
                f"[{style}]{t['in_kb_s']:.1f}[/]" if style else f"{t['in_kb_s']:.1f}",
                f"[{style}]{t['out_kb_s']:.1f}[/]" if style else f"{t['out_kb_s']:.1f}",
                f"{t['total_in_mb']:.1f} MB",
                f"{t['total_out_mb']:.1f} MB",
                str(t["connections"]),
                key=str(i),
            )
        self.query_one("#net-status", Static).update(
            f"[dim]{len(self._talkers)} processes with network activity since launch · refreshes every 8s[/]"
        )


    @on(DataTable.RowHighlighted, "#net-table")
    def _row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        row_key = event.row_key
        try:
            idx = int(row_key.value)
            if 0 <= idx < len(self._talkers):
                self._selected_pid = self._talkers[idx]["pid"]
                self._selected_name = self._talkers[idx]["name"]
                self.run_worker(self._update_inspector, exclusive=True, thread=True)
        except (TypeError, ValueError):
            pass

    def _update_inspector(self) -> None:
        if not getattr(self, "_selected_pid", None):
            return
        details = collectors.get_network_details(self._selected_pid)
        self.app.call_from_thread(self._render_inspector, details)

    def _render_inspector(self, details: dict) -> None:
        box = self.query_one("#net-inspector", Box)
        t = Text()
        
        t.append("Identity\n", style="bold underline cyan")
        t.append(f"Process: ", style="dim")
        t.append(f"{getattr(self, '_selected_name', 'Unknown'):<30}  ", style="bold white")
        t.append(f"PID: ", style="dim")
        t.append(f"{getattr(self, '_selected_pid', 'Unknown')}\n\n", style="white")

        conns = details.get("connections", [])
        if not conns:
            t.append("No active network sockets found or access denied.\n", style="dim")
        else:
            t.append(f"Active Connections ({len(conns)})\n", style="bold underline yellow")
            for c in conns:
                proto = c['proto']
                state = f"({c['state']})" if c['state'] else ""
                lat = f"[{c['latency']}]" if c['latency'] else ""
                t.append(f"[{proto}] ", style="bold magenta")
                t.append(f"{c['local']:<25} ", style="cyan")
                t.append(f"<-->  ", style="dim")
                t.append(f"{c['remote']:<30} ", style="cyan")
                t.append(f"{state:<14} ", style="yellow")
                t.append(f"{lat}\n", style="dim green")
        
        box.update(t)

    def action_kill_selected(self) -> None:
        table = self.query_one("#net-table", DataTable)
        if table.row_count == 0 or table.cursor_row is None:
            return
        row_key = table.coordinate_to_cell_key(table.cursor_coordinate).row_key
        try:
            idx = int(row_key.value)
        except (TypeError, ValueError):
            return
        if not (0 <= idx < len(self._talkers)):
            return
        pid = self._talkers[idx]["pid"]
        ok, msg = collectors.kill_process(pid)
        self.query_one("#net-status", Static).update(f"[{'green' if ok else 'red'}]{msg}[/]")
        self.refresh_data()
