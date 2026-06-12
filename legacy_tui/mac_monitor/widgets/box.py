from textual.widgets import Static

class Box(Static):
    """A bordered panel with a corner title — the btop/mactop unit."""

    def __init__(self, title: str, subtitle: str = "", **kwargs):
        super().__init__("", **kwargs)
        self._title = title
        self._subtitle = subtitle

    def on_mount(self) -> None:
        self.border_title = self._title
        if self._subtitle:
            self.border_subtitle = self._subtitle
