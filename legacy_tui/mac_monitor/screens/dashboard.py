"""Dashboard — btop/mactop-style dense tiled grid.

Layout (btop-style Top/Bottom split):
  Top Half: massive CPU block graph (left) + core/gpu/power stats (right)
  Bottom Left (40% width): Network, Memory, Disks stacked vertically.
  Bottom Right (60% width): Deep process list (top 20).
"""
from __future__ import annotations

from collections import deque

from rich.text import Text
from rich.table import Table

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static

from mac_monitor import collectors
from mac_monitor.widgets import (
    meter, block_graph, sparkline, mini_sparkline, stacked_bar, temp_badge,
)
from mac_monitor.widgets.box import Box

HISTORY_LEN = 240  # ~10 min at 2.5s ticks — enough columns to fill a wide terminal


class DashboardPane(Vertical):
    """Dense btop-style overview — massive CPU top, split bottom."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        # History deques for all sparklines/graphs
        self.cpu_hist: deque[float] = deque(maxlen=HISTORY_LEN)
        self.mem_hist: deque[float] = deque(maxlen=60)
        self.recv_hist: deque[float] = deque(maxlen=60)
        self.sent_hist: deque[float] = deque(maxlen=60)
        self.read_hist: deque[float] = deque(maxlen=60)
        self.write_hist: deque[float] = deque(maxlen=60)

    def compose(self) -> ComposeResult:
        # Top Half: CPU
        yield Box("cpu", id="box-cpu", classes="box")
        
        # Bottom Half: Split
        with Horizontal(id="dashboard-bottom"):
            # Bottom Left: Net, Mem, Disk
            with Vertical(id="dashboard-left"):
                yield Box("network", id="box-net", classes="box")
                yield Box("memory", id="box-mem", classes="box")
                yield Box("disk", id="box-disk", classes="box")
            
            # Bottom Right: Processes
            yield Box("processes", id="box-proc", classes="box")

    def on_mount(self) -> None:
        # First load happens on pane_activated — nothing runs while hidden.
        self._timer = self.set_interval(2.5, self.refresh_data, pause=True)

    def pane_activated(self) -> None:
        self._timer.resume()
        self.refresh_data()

    def pane_deactivated(self) -> None:
        self._timer.pause()

    def refresh_data(self) -> None:
        self.run_worker(self._collect_and_render, exclusive=True, thread=True)

    def _collect_and_render(self) -> None:
        vitals = collectors.collect_vitals()
        perf = collectors.collect_perf_light()
        disk = collectors.collect_disk_usage()
        net = collectors.collect_network_light()
        disk_io = collectors.disk_throughput_mb_s()
        # Fetch top 20 processes with username
        top_procs = collectors.top_processes_fast(20)
        
        self.app.call_from_thread(
            self._apply_snapshot, vitals, perf, disk, net, disk_io, top_procs
        )

    # ---- rendering ----------------------------------------------------------

    def _apply_snapshot(self, vitals: dict, perf: dict, disk: dict,
                        net: dict, disk_io: tuple, top_procs: list) -> None:
        self._render_cpu(vitals, perf)
        self._render_net(net)
        self._render_mem(perf)
        self._render_disk(disk, disk_io)
        self._render_proc(top_procs)

    # ---- Top: CPU + Cores + Silicon -----------------------------------------

    def _render_cpu(self, vitals: dict, perf: dict) -> None:
        overall = vitals.get("cpu_overall", 0.0)
        self.cpu_hist.append(overall)
        per_core = vitals.get("per_core", [])
        ctemp = perf.get("cpu_temp", 0)
        gtemp = perf.get("gpu_temp", 0)
        watts = perf.get("watts", 0)
        
        # Rich grid: history graph fills all width left of the fixed stats column.
        STATS_W = 32
        table = Table.grid(expand=True)
        table.add_column("graph", ratio=1)
        table.add_column("stats", width=STATS_W)

        box = self.query_one("#box-cpu", Box)
        graph_h = max(5, box.size.height - 2) if box.size.height else 10
        graph_w = max(40, box.size.width - STATS_W - 4) if box.size.width else 80

        graph = block_graph(list(self.cpu_hist), width=graph_w, height=graph_h, vmax=100)
        
        # --- Right: Stats ---
        stats = Text()
        # Overall CPU
        stats.append("total ", style="bold")
        stats.append(meter(overall, width=15))
        stats.append(f" {overall:5.1f}%\n", style="bold")
        
        # Apple Silicon / Cores
        if perf.get("has_core_split"):
            eutil = perf.get("ecpu_util", 0)
            stats.append("e-cores ", style="grey70")
            stats.append(meter(eutil, width=13))
            stats.append(f" {eutil:3.0f}%\n", style="bold")
            
            putil = perf.get("pcpu_util", 0)
            stats.append("p-cores ", style="grey70")
            stats.append(meter(putil, width=13))
            stats.append(f" {putil:3.0f}%\n", style="bold")
        else:
            # Fallback to per-core list if no split
            for i, c in enumerate(per_core):
                stats.append(f"C{i:<2} ", style="grey62")
                stats.append(meter(c, width=15))
                stats.append(f" {c:3.0f}%\n", style="grey85")
                
        # GPU & Neural
        gpu_util = perf.get("gpu_util", 0)
        stats.append("gpu     ", style="grey70")
        stats.append(meter(gpu_util, width=13))
        stats.append(f" {gpu_util:3.0f}%\n", style="bold")
        
        ane = perf.get("ane_power", 0)
        ane_pct = min(100, ane / 5 * 100)
        stats.append("neural  ", style="grey70")
        stats.append(meter(ane_pct, width=13))
        stats.append(f" {ane:.1f}W\n" if ane else "  idle\n", style="grey62")
        
        stats.append("\n")
        # Temperatures and Power
        stats.append(temp_badge(ctemp, label="cpu "))
        stats.append("  ", style="grey23")
        stats.append(temp_badge(gtemp, label="gpu "))
        stats.append("\n")
        
        stats.append("power  ", style="grey70")
        src = "AC" if perf.get("on_ac") else "Batt"
        stats.append(f"{src} ", style="bold white")
        stats.append(f"{watts:.1f}W", style="bold #f1c40f")

        table.add_row(graph, stats)
        
        box.update(table)
        box.border_subtitle = (f"{vitals.get('chip_label', '')} · up {vitals.get('uptime', '?')}"
                               f" · load {vitals.get('load_avg', [0])[0]:.2f}")

    # ---- Bottom Left: Network, Memory, Disk ---------------------------------

    def _render_net(self, net: dict) -> None:
        recv = net.get("recv_kb_s", 0.0)
        sent = net.get("sent_kb_s", 0.0)
        self.recv_hist.append(recv)
        self.sent_hist.append(sent)
        peak = max(max(self.recv_hist, default=0), max(self.sent_hist, default=0), 1)

        body = Text()
        # Recv line
        body.append("↓ recv ", style="grey70")
        body.append(f"{recv:7.1f} KB/s ", style="bold cyan")
        body.append(mini_sparkline(list(self.recv_hist), width=15, vmax=peak))
        body.append("\n")

        # Send line
        body.append("↑ sent ", style="grey70")
        body.append(f"{sent:7.1f} KB/s ", style="bold magenta")
        body.append(mini_sparkline(list(self.sent_hist), width=15, vmax=peak))
        body.append("\n")

        # Totals
        body.append(f"total: {net.get('total_recv_mb', 0)} MB ↓", style="grey62")
        body.append(f" · {net.get('total_sent_mb', 0)} MB ↑", style="grey62")

        self.query_one("#box-net", Box).update(body)

    def _render_mem(self, perf: dict) -> None:
        total = perf.get("mem_total_gb", 0) or 1
        used_pct = perf.get("mem_used_pct", 0)
        free_pct = perf.get("mem_free_pct", 0)
        mem = perf.get("mem", {})
        comp_gb = mem.get("comp_gb", 0)
        swap_gb = mem.get("swap_gb", 0)
        used_gb = total * used_pct / 100

        self.mem_hist.append(used_pct)

        body = Text()

        # Stacked composition bar: used (red-ish) + free (green)
        used_frac = used_pct / 100
        free_frac = free_pct / 100
        body.append(stacked_bar([
            (used_frac, "#e74c3c", f"used {used_pct:.0f}%"),
            (free_frac, "#2ecc71", f"free"),
        ], width=34))
        body.append("\n")

        # Stats line 1: used/total
        body.append(f"{used_gb:.1f}", style="bold #e74c3c")
        body.append(f" / {total:.1f} GB used", style="grey70")
        body.append(f"   free ", style="grey70")
        body.append(f"{total - used_gb:.1f} GB\n", style="bold #2ecc71")

        # Stats line 2: compressed + swap
        body.append(f"compressed ", style="grey70")
        comp_color = "#f1c40f" if comp_gb > 1 else "grey85"
        body.append(f"{comp_gb:.1f}G", style=f"bold {comp_color}")
        body.append(f"  swap ", style="grey70")
        swap_color = "#e74c3c" if swap_gb > 1 else "#f1c40f" if swap_gb > 0.3 else "grey85"
        body.append(f"{swap_gb:.2f}G\n", style=f"bold {swap_color}")

        # Pressure indicator with colored dots
        pressure = mem.get("pressure", "?")
        pcolor = {"normal": "#2ecc71", "warning": "#f1c40f", "critical": "#e74c3c"}.get(pressure, "grey70")
        dots = {"normal": "●○○", "warning": "●●○", "critical": "●●●"}.get(pressure, "○○○")
        body.append("pressure ", style="grey70")
        body.append(dots, style=pcolor)
        body.append(f" {pressure}", style=f"bold {pcolor}")

        # Memory trend sparkline
        body.append("  ", style="grey70")
        body.append(mini_sparkline(list(self.mem_hist), width=10, vmax=100))

        box = self.query_one("#box-mem", Box)
        box.update(body)

    def _render_disk(self, disk: dict, disk_io: tuple) -> None:
        read_mb, write_mb = disk_io
        self.read_hist.append(read_mb)
        self.write_hist.append(write_mb)

        body = Text()
        if not disk:
            body.append("could not read disk usage", style="#e74c3c")
        else:
            pct = disk.get("pct", 0)
            # Capacity bar
            body.append("capacity ", style="grey70")
            body.append(meter(pct, width=20))
            body.append(f" {pct:3.0f}%\n", style="bold")

            # Stats: total · used · free
            body.append(f"{disk.get('size', '?')} total", style="grey85")
            body.append(f" · {disk.get('used', '?')} used", style="grey85")
            body.append(f" · ", style="grey50")
            body.append(f"{disk.get('avail', '?')} free\n", style="#2ecc71")

            # Live I/O throughput with sparklines
            body.append("R ", style="bold cyan")
            body.append(f"{read_mb:5.1f} MB/s ", style="cyan")
            body.append(mini_sparkline(list(self.read_hist), width=8, vmax=max(max(self.read_hist, default=1), 1)))
            body.append("\nW ", style="bold magenta")
            body.append(f"{write_mb:5.1f} MB/s ", style="magenta")
            body.append(mini_sparkline(list(self.write_hist), width=8, vmax=max(max(self.write_hist, default=1), 1)))

        box = self.query_one("#box-disk", Box)
        box.update(body)
        if disk:
            box.border_subtitle = disk.get("mount", "")

    # ---- Bottom Right: Process List -----------------------------------------

    def _render_proc(self, top_procs: list) -> None:
        table = Table(show_header=True, header_style="bold grey62", box=None, expand=True)
        table.add_column("PID", style="grey62", justify="right", width=6)
        table.add_column("User", style="grey70", width=10)
        table.add_column("Command", style="white")
        table.add_column("Mem", style="grey85", justify="right", width=6)
        table.add_column("Cpu%", style="bold white", justify="right", width=6)
        
        for p in top_procs:
            cpu_color = "#e74c3c" if p["cpu"] > 50 else "#f1c40f" if p["cpu"] > 10 else "white"
            mem_str = f"{p['rss_mb']/1024:.1f}G" if p["rss_mb"] > 1000 else f"{p['rss_mb']}M"
            
            table.add_row(
                str(p["pid"]),
                p["user"],
                p["name"],
                mem_str,
                Text(f"{p['cpu']:.1f}", style=cpu_color)
            )

        box = self.query_one("#box-proc", Box)
        box.update(table)
