"""Apps pane — uninstaller that finds and removes leftover files, not just the .app."""
from __future__ import annotations

from textual import on
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical, Horizontal
from textual.screen import ModalScreen
from textual.widgets import Static, DataTable, Button, Label

from mac_monitor import collectors


class ConfirmUninstallModal(ModalScreen[bool]):
    DEFAULT_CSS = """
    ConfirmUninstallModal { align: center middle; }
    #uninstall-box {
        width: 80;
        height: auto;
        max-height: 30;
        border: heavy $error;
        padding: 1 2;
        background: $surface;
    }
    #uninstall-buttons { height: auto; layout: horizontal; margin-top: 1; }
    #uninstall-buttons Button { margin-right: 1; }
    """

    def __init__(self, app_name: str, paths: list[str], total_mb: float):
        super().__init__()
        self.app_name = app_name
        self.paths = paths
        self.total_mb = total_mb

    def compose(self) -> ComposeResult:
        with Vertical(id="uninstall-box"):
            yield Label(f"Move [bold]{self.app_name}[/] and {len(self.paths) - 1} "
                        f"leftover location(s) to Trash — reclaiming ~{self.total_mb:.0f} MB:")
            body = "\n".join(f"  • {p}" for p in self.paths[:12])
            if len(self.paths) > 12:
                body += f"\n  … and {len(self.paths) - 12} more"
            yield Static(f"[dim]{body}[/]")
            yield Label("[dim]Safe delete — everything goes to macOS Trash, nothing is permanently removed.[/]")
            with Horizontal(id="uninstall-buttons"):
                yield Button("Uninstall", variant="error", id="ui-yes")
                yield Button("Cancel", id="ui-no")

    @on(Button.Pressed, "#ui-yes")
    def _yes(self) -> None:
        self.dismiss(True)

    @on(Button.Pressed, "#ui-no")
    def _no(self) -> None:
        self.dismiss(False)


class AppsPane(Vertical):
    """List installed apps, scan for leftover files, uninstall completely."""

    BINDINGS = [
        Binding("r", "rescan", "Rescan apps"),
        Binding("u", "uninstall", "Uninstall + leftovers"),
    ]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._apps: list[dict] = []
        self._selected_app: dict | None = None
        self._leftovers: list[dict] = []
        self._bundle_id = ""

    def compose(self) -> ComposeResult:
        yield Static("INSTALLED APPLICATIONS  (select a row to scan for leftovers · r = rescan · u = uninstall)", classes="section-title")
        yield Static("", id="apps-status", classes="dim")
        yield DataTable(id="apps-table", cursor_type="row", zebra_stripes=True)

        yield Static("LEFTOVER FILES FOR SELECTED APP", classes="section-title")
        yield Static("Select an app above to scan", id="leftover-info", classes="dim")
        yield DataTable(id="leftover-table", zebra_stripes=True)

    def on_mount(self) -> None:
        self.query_one("#apps-table", DataTable).add_columns("App", "Size", "Path")
        self.query_one("#leftover-table", DataTable).add_columns("Location", "Size")
        self._loaded = False

    def pane_activated(self) -> None:
        # Scan only on first visit — the per-app `du` pass is too expensive
        # to run at app startup for a tab that may never be opened.
        if not self._loaded:
            self._loaded = True
            self.refresh_data()
        self.query_one("#apps-table", DataTable).focus()

    def pane_deactivated(self) -> None:
        pass

    def refresh_data(self) -> None:
        self.query_one("#apps-status", Static).update("[dim]Scanning /Applications…[/]")
        self.run_worker(self._load_apps, exclusive=True, thread=True, group="apps")

    def _load_apps(self) -> None:
        apps = collectors.list_apps()
        self.app.call_from_thread(self._render_apps, apps)

    def _render_apps(self, apps: list[dict]) -> None:
        self._apps = apps
        table = self.query_one("#apps-table", DataTable)
        table.clear()
        for i, a in enumerate(apps):
            table.add_row(a["name"], a["size_str"], a["path"], key=str(i))
        self.query_one("#apps-status", Static).update(f"[dim]{len(apps)} apps[/]")

    def action_rescan(self) -> None:
        self.refresh_data()

    @on(DataTable.RowSelected, "#apps-table")
    def _app_selected(self, event: DataTable.RowSelected) -> None:
        table = self.query_one("#apps-table", DataTable)
        try:
            idx = int(event.row_key.value)
        except (TypeError, ValueError):
            return
        if not (0 <= idx < len(self._apps)):
            return
        self._selected_app = self._apps[idx]
        self._leftovers = []
        self.query_one("#leftover-info", Static).update(
            f"[dim]Scanning leftovers for {self._selected_app['name']}…[/]"
        )
        self.query_one("#leftover-table", DataTable).clear()
        self.run_worker(self._scan_leftovers, exclusive=True, thread=True, group="apps")

    def _scan_leftovers(self) -> None:
        app = self._selected_app
        if not app:
            return
        result = collectors.find_app_leftovers(app["path"], app["name"])
        self.app.call_from_thread(self._render_leftovers, app, result)

    def _render_leftovers(self, app: dict, result: dict) -> None:
        if app is not self._selected_app:
            return
        self._leftovers = result["leftovers"]
        self._bundle_id = result["bundle_id"]
        table = self.query_one("#leftover-table", DataTable)
        table.clear()
        for i, l in enumerate(self._leftovers):
            table.add_row(l["rel"], l["size_str"], key=str(i))
        total = sum(l["size_mb"] for l in self._leftovers)
        self.query_one("#leftover-info", Static).update(
            f"[bold]{app['name']}[/] · bundle id [dim]{self._bundle_id}[/] · "
            f"{len(self._leftovers)} leftover location(s) found "
            f"({collectors.fmt_mb(total)} reclaimable beyond the app itself)"
            if self._leftovers else
            f"[bold]{app['name']}[/] · bundle id [dim]{self._bundle_id}[/] · no leftover files found"
        )

    def action_uninstall(self) -> None:
        app = self._selected_app
        if not app:
            self.query_one("#leftover-info", Static).update("[yellow]Select an app first[/]")
            return
        paths = [app["path"]] + [l["path"] for l in self._leftovers]
        total_mb = app["size_mb"] + sum(l["size_mb"] for l in self._leftovers)

        def _on_confirm(confirmed: bool | None) -> None:
            if not confirmed:
                return
            ok_count, fail_count = 0, 0
            for p in paths:
                ok, _msg = collectors.delete_path(p)
                if ok:
                    ok_count += 1
                else:
                    fail_count += 1
            status = self.query_one("#leftover-info", Static)
            status.update(
                f"[green]Uninstalled {app['name']}[/] — moved {ok_count} item(s) to Trash"
                + (f", [red]{fail_count} failed[/]" if fail_count else "")
            )
            self._selected_app = None
            self._leftovers = []
            self.query_one("#leftover-table", DataTable).clear()
            self.refresh_data()

        self.app.push_screen(ConfirmUninstallModal(app["name"], paths, total_mb), _on_confirm)
