"""Performance pane — battery health, thermal/power, sleep assertions, quick wins."""
from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, DataTable

from rich.text import Text

from mac_monitor import collectors
from mac_monitor.widgets.box import Box
from mac_monitor.widgets import meter


def _quick_wins(perf: dict, startup: dict, assertions: list[dict]) -> list[str]:
    wins = []
    if perf.get("temp_critical") or perf.get("temp_elevated"):
        wins.append("🔴 [bold #e74c3c]High CPU temperature[/] — find the heat source in the Processes tab (sort by CPU)")
    pressure = perf.get("mem", {}).get("pressure")
    if pressure == "critical":
        wins.append("🔴 [bold #e74c3c]Critical memory pressure[/] — close unused apps/tabs, or restart memory-heavy apps")
    elif pressure == "warning":
        wins.append("🟠 [bold #f1c40f]Memory pressure elevated[/] — consider closing some browser windows")
    if assertions:
        apps = ", ".join(sorted({a["app"] for a in assertions}))
        wins.append(f"🟠 [bold #f1c40f]{len(assertions)} sleep assertion(s) active[/] ({apps}) — these drain battery overnight; kill them from the table")
    if startup.get("bloat_level") == "high":
        wins.append(f"🟠 [bold #f1c40f]Startup bloat is high[/] (score {startup.get('bloat_score')}) — trim login items in System Settings")
    elif startup.get("bloat_level") == "moderate":
        wins.append(f"🟡 [bold #f1c40f]Startup load is moderate[/] (score {startup.get('bloat_score')}) — review LaunchAgents")
    if not perf.get("on_ac") and perf.get("watts", 0) > 15:
        wins.append(f"🟡 [bold #f1c40f]Drawing {perf.get('watts')} W on battery[/] — close heavy apps to extend runtime")
    if not wins:
        wins.append("🟢 [bold #2ecc71]No issues detected[/] — system looks healthy")
    return wins


class PerformancePane(Vertical):
    """Battery health, thermal/power readouts, sleep assertions, quick wins."""

    BINDINGS = [
        Binding("k", "kill_assertion", "Kill assertion holder"),
    ]

    def compose(self) -> ComposeResult:
        yield Box("battery health & power", id="box-health", classes="box box-wide")
        
        with Horizontal(classes="box-row", id="row-tables"):
            with Vertical(id="box-sessions", classes="box"):
                yield DataTable(id="sess-table", zebra_stripes=True)
            with Vertical(id="box-assertions", classes="box"):
                yield DataTable(id="assert-table", cursor_type="row", zebra_stripes=True)

        with Horizontal(classes="box-row", id="row-info"):
            yield Box("startup load", id="box-startup", classes="box")
            yield Box("quick wins", id="box-quickwins", classes="box")

    def on_mount(self) -> None:
        self.query_one("#box-sessions", Vertical).border_title = "battery sessions (last 15)"
        self.query_one("#box-assertions", Vertical).border_title = "sleep / wake assertions (k = kill)"
        
        self.query_one("#sess-table", DataTable).add_columns("Start", "End", "From", "To", "Hrs", "Drop", "Rate")
        self.query_one("#assert-table", DataTable).add_columns("PID", "App", "Type", "Reason")
        self._assertions: list[dict] = []
        # First load happens on pane_activated — nothing runs while hidden.
        self._timer = self.set_interval(20.0, self.refresh_data, pause=True)

    def pane_activated(self) -> None:
        self._timer.resume()
        self.refresh_data()
        # Focus the assertions table so `k` works without an extra click.
        self.query_one("#assert-table", DataTable).focus()

    def pane_deactivated(self) -> None:
        self._timer.pause()

    def refresh_data(self) -> None:
        self.run_worker(self._collect, exclusive=True, thread=True)

    def _collect(self) -> None:
        perf = collectors.collect_perf_light()
        battery = collectors.collect_battery()
        assertions = collectors.collect_assertions()
        startup = collectors.collect_startup()
        self.app.call_from_thread(self._apply_snapshot, perf, battery, assertions, startup)

    def _apply_snapshot(self, perf: dict, battery: dict, assertions: list[dict], startup: dict) -> None:
        health = battery.get("health", {})
        cap = health.get("max_capacity_pct")
        cycles = health.get("cycle_count")
        cond = health.get("condition", "Unknown")
        
        # Battery Health Box
        body_health = Text()
        body_health.append(f"power source   ", style="grey70")
        body_health.append(f"{'AC' if perf.get('on_ac') else 'Battery'}\n", style="bold white")
        
        watts = perf.get('watts', 0)
        body_health.append(f"draw           ", style="grey70")
        body_health.append(f"{watts} W\n", style="bold #f1c40f")
        
        body_health.append(f"cpu / gpu temp ", style="grey70")
        tcolor = "#e74c3c" if perf.get("temp_critical") else "#f1c40f" if perf.get("temp_elevated") else "#2ecc71"
        body_health.append(f"{perf.get('cpu_temp', 0)}°C ", style=f"bold {tcolor}")
        body_health.append(f"/ {perf.get('gpu_util', 0)}%\n\n", style="bold white")
        
        cap_val = cap if cap is not None else 100
        cap_color = "#e74c3c" if cap_val < 80 else "#2ecc71"
        body_health.append("health         ", style="grey70")
        body_health.append(meter(cap_val, width=24, fixed_color=cap_color))
        body_health.append(f" {cap_val}%", style=f"bold {cap_color}")
        body_health.append(f"   cycles: {cycles if cycles is not None else '?'}   condition: {cond}", style="grey85")
        
        self.query_one("#box-health", Box).update(body_health)

        # Battery Sessions Table
        sess_table = self.query_one("#sess-table", DataTable)
        sess_table.clear()
        for s in battery.get("sessions", []):
            rate_color = "red" if s["rate"] > 15 else "yellow" if s["rate"] > 10 else "green"
            sess_table.add_row(s["start"], s["end"], f"{s['s_pct']}%", f"{s['e_pct']}%",
                               f"{s['dur_h']}", f"-{s['drop']}%", f"[{rate_color}]{s['rate']}%[/]")
        if not battery.get("sessions"):
            sess_table.add_row("—", "—", "—", "—", "—", "—", "no completed sessions found")

        # Sleep Assertions Table
        self._assertions = assertions
        a_table = self.query_one("#assert-table", DataTable)
        a_table.clear()
        for i, a in enumerate(assertions):
            a_table.add_row(str(a["pid"]), a["app"], a["type"], a["reason"][:40], key=str(i))
        if not assertions:
            a_table.add_row("—", "none active", "—", "—")

        # Startup Box
        agents = startup.get("launch_agents", [])
        noisy = [a["label"] for a in agents if a["noisy"]]
        bloat_score = startup.get('bloat_score', 0)
        bloat_level = startup.get('bloat_level', '?')
        
        b_color = "#e74c3c" if bloat_level == "high" else "#f1c40f" if bloat_level == "moderate" else "#2ecc71"
        
        body_startup = Text()
        body_startup.append(f"bloat score    ", style="grey70")
        body_startup.append(meter(min(bloat_score*2, 100), width=18, fixed_color=b_color))
        body_startup.append(f" {bloat_score} ({bloat_level})\n\n", style=f"bold {b_color}")
        
        body_startup.append(f"login items    {len(startup.get('login_items', []))}\n", style="bold white")
        body_startup.append(f"launch agents  {len(agents)}\n", style="bold white")
        body_startup.append(f"launchd svcs   {startup.get('service_count', 0)}\n\n", style="bold white")
        body_startup.append(f"noisy agents   ", style="grey70")
        body_startup.append(f"{', '.join(noisy) if noisy else 'none'}", style="grey85")
        self.query_one("#box-startup", Box).update(body_startup)

        # Quick Wins Box
        wins = _quick_wins(perf, startup, assertions)
        self.query_one("#box-quickwins", Box).update("\n\n".join(f"• {w}" for w in wins))

    def action_kill_assertion(self) -> None:
        table = self.query_one("#assert-table", DataTable)
        if table.row_count == 0 or table.cursor_row is None:
            return
        row_key = table.coordinate_to_cell_key(table.cursor_coordinate).row_key
        try:
            idx = int(row_key.value)
        except (TypeError, ValueError):
            return
        if not (0 <= idx < len(self._assertions)):
            return
        pid = self._assertions[idx]["pid"]
        ok, msg = collectors.kill_process(pid)
        # Notify user (since quickwins is overwritten, we use app.notify)
        self.app.notify(msg, severity="information" if ok else "error")
        self.refresh_data()
