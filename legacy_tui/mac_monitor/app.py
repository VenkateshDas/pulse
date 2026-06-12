"""Mac Monitor — standalone Textual TUI for monitoring, controlling and
optimizing macOS: live process table with kill, file browser with delete,
disk/battery/thermal charts, and one-click optimization actions."""
from __future__ import annotations

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Vertical
from textual.screen import ModalScreen
from textual.widgets import Header, Footer, Label, Static, TabbedContent, TabPane

from mac_monitor.screens.dashboard import DashboardPane
from mac_monitor.screens.processes import ProcessesPane
from mac_monitor.screens.storage import StoragePane
from mac_monitor.screens.performance import PerformancePane
from mac_monitor.screens.network import NetworkPane
from mac_monitor.screens.apps import AppsPane


HELP_TEXT = """\
[bold #6cb6ff]Global[/]            [bold #6cb6ff]Processes (2)[/]        [bold #6cb6ff]Storage (3) — tree[/]
 1-6  switch tab    s  cycle sort          enter  expand/collapse
 r    refresh tab   t  tree view           u/g/h  root up/data/home
 q    quit          k  kill selected       f      reveal in Finder
 ?    this help     /  focus filter        d      trash · r reload

[bold #6cb6ff]Storage (3) — smart scan[/]
 space/enter toggle · a select all safe · c clear · t trash selected
 e empty Trash (frees the space for real) · s rescan

[bold #6cb6ff]Health (4)[/]         [bold #6cb6ff]Network (5)[/]          [bold #6cb6ff]Apps (6)[/]
 k  kill assertion  k  kill selected       u  uninstall + leftovers
                                           r  rescan\
"""


class HelpModal(ModalScreen[None]):
    """Single-keystroke cheat sheet for every pane's bindings."""

    DEFAULT_CSS = """
    HelpModal { align: center middle; }
    #help-box {
        width: 76; height: auto;
        border: round #6cb6ff; padding: 1 2; background: $surface;
    }
    """

    BINDINGS = [Binding("escape,question_mark,q", "dismiss_help", "Close")]

    def compose(self) -> ComposeResult:
        with Vertical(id="help-box"):
            yield Label("[bold]Keyboard shortcuts[/]   [dim](esc to close)[/]")
            yield Static("")
            yield Static(HELP_TEXT)

    def action_dismiss_help(self) -> None:
        self.dismiss()


class MacMonitorApp(App):
    """Tabbed control center for monitoring and optimizing a Mac."""

    CSS_PATH = "app.tcss"
    TITLE = "Mac Monitor"
    SUB_TITLE = "monitor · control · optimize"

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh_active", "Refresh"),
        Binding("question_mark", "show_help", "Help", key_display="?"),
        Binding("1", "show_tab('dashboard')", "Dashboard", show=False),
        Binding("2", "show_tab('processes')", "Processes", show=False),
        Binding("3", "show_tab('storage')", "Storage", show=False),
        Binding("4", "show_tab('health')", "Health", show=False),
        Binding("5", "show_tab('network')", "Network", show=False),
        Binding("6", "show_tab('apps')", "Apps", show=False),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        with TabbedContent(initial="dashboard"):
            with TabPane("Dashboard", id="dashboard"):
                yield DashboardPane()
            with TabPane("Processes", id="processes"):
                yield ProcessesPane()
            with TabPane("Storage", id="storage"):
                yield StoragePane()
            with TabPane("Health", id="health"):
                yield PerformancePane()
            with TabPane("Network", id="network"):
                yield NetworkPane()
            with TabPane("Apps", id="apps"):
                yield AppsPane()
        yield Footer()

    def on_mount(self) -> None:
        # Only the visible tab polls/scans — every pane defers its first load
        # to pane_activated, so startup costs exactly one pane's collectors
        # instead of all seven (Apps/Cleanup/Health scans used to all fire here).
        def _sync() -> None:
            tabbed = self.query_one(TabbedContent)
            for tab_pane in tabbed.query(TabPane):
                for pane in tab_pane.children:
                    if tab_pane.id == tabbed.active:
                        if hasattr(pane, "pane_activated"):
                            pane.pane_activated()
                    elif hasattr(pane, "pane_deactivated"):
                        pane.pane_deactivated()

        # Defer until children have mounted (their timers exist by then).
        self.call_after_refresh(_sync)

    def on_tabbed_content_tab_activated(self, event: TabbedContent.TabActivated) -> None:
        tabbed = self.query_one(TabbedContent)
        active_id = tabbed.active
        for tab_pane in tabbed.query(TabPane):
            for pane in tab_pane.children:
                if tab_pane.id == active_id:
                    if hasattr(pane, "pane_activated"):
                        pane.pane_activated()
                elif hasattr(pane, "pane_deactivated"):
                    pane.pane_deactivated()

    def action_show_help(self) -> None:
        self.push_screen(HelpModal())

    def action_show_tab(self, tab_id: str) -> None:
        self.query_one(TabbedContent).active = tab_id

    def action_refresh_active(self) -> None:
        tabbed = self.query_one(TabbedContent)
        pane = tabbed.get_pane(tabbed.active)
        for child in pane.children:
            if hasattr(child, "refresh_data"):
                child.refresh_data()
