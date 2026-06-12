"""btop/mactop-style inline renderables — gradient fill-meters and block-column
history graphs built from block characters, plus a one-line sparkline. These are
returned as Rich `Text` so they can live inside bordered Static boxes (no heavy
chart widgets)."""
from __future__ import annotations

from rich.text import Text

_BLOCKS = " ▁▂▃▄▅▆▇█"          # 0..8 eighths, used by graphs + sparkline
_BLOCKS_H = " ▏▎▍▌▋▊▉█"        # 0..8 eighths horizontal, used by meters


def _grad(f: float) -> str:
    """green → yellow → red hex color for a 0..1 fraction (btop gradient)."""
    f = max(0.0, min(1.0, f))
    if f < 0.5:
        t = f / 0.5
        a, b = (46, 204, 113), (241, 196, 15)
    else:
        t = (f - 0.5) / 0.5
        a, b = (241, 196, 15), (231, 76, 60)
    r = int(a[0] + (b[0] - a[0]) * t)
    g = int(a[1] + (b[1] - a[1]) * t)
    bl = int(a[2] + (b[2] - a[2]) * t)
    return f"#{r:02x}{g:02x}{bl:02x}"


def sparkline(values: list[float], width: int = 24, vmax: float | None = None) -> str:
    """Single-line block sparkline (plain string, no color)."""
    if not values:
        return _BLOCKS[0] * width
    sample = values[-width:]
    hi = vmax if vmax is not None else max(sample) or 1.0
    hi = hi or 1.0
    out = []
    for v in sample:
        idx = min(8, max(0, int((v / hi) * 8)))
        out.append(_BLOCKS[idx])
    return "".join(out).rjust(width, _BLOCKS[0])


def meter(pct: float, width: int = 20, *, fixed_color: str | None = None) -> Text:
    """Horizontal gradient fill-meter, e.g. btop's memory/cpu bars."""
    pct = max(0.0, min(100.0, pct))
    text = Text()
    filled = (pct / 100.0) * width
    full = int(filled)
    frac = filled - full
    for i in range(width):
        col_frac = (i + 1) / width
        color = fixed_color or _grad(col_frac)
        if i < full:
            text.append("█", style=color)
        elif i == full and frac > 0:
            text.append(_BLOCKS_H[max(1, int(frac * 8))], style=color)
        else:
            text.append("─", style="grey23")
    return text


def block_graph(values: list[float], width: int = 40, height: int = 6,
                vmax: float | None = None) -> Text:
    """Multi-row block-column history graph with a vertical green→red gradient
    (bottom rows green, top rows red) — the mactop power-graph / btop look."""
    sample = list(values)[-width:]
    if len(sample) < width:
        sample = [0.0] * (width - len(sample)) + sample
    hi = vmax if vmax is not None else (max(sample) if sample else 1.0)
    hi = hi or 1.0
    eighths = [min(height * 8, max(0, int((v / hi) * height * 8))) for v in sample]

    text = Text()
    for row in range(height):                 # row 0 = top of the graph
        from_bottom = height - 1 - row        # 0 = bottom row
        frac = (from_bottom + 1) / height      # color band (top = red)
        color = _grad(frac)
        for total in eighths:
            level = total - from_bottom * 8
            if level >= 8:
                text.append("█", style=color)
            elif level <= 0:
                text.append(" ")
            else:
                text.append(_BLOCKS[level], style=color)
        if row < height - 1:
            text.append("\n")
    return text


def bar(pct: float, width: int = 10, fill: str = "█", empty: str = "░") -> str:
    """Plain fixed-width solid bar string (no color)."""
    pct = max(0.0, min(100.0, pct))
    filled = round((pct / 100.0) * width)
    return fill * filled + empty * (width - filled)


def mini_sparkline(values: list[float], width: int = 6, vmax: float = 100.0) -> Text:
    """Compact colored sparkline — fits 4-8 chars. Color follows the *latest*
    value on the green→yellow→red gradient so you can read urgency at a glance."""
    if not values:
        return Text(_BLOCKS[0] * width, style="grey23")
    sample = values[-width:]
    hi = vmax or 1.0
    latest_frac = max(0.0, min(1.0, (sample[-1] / hi))) if sample else 0.0
    color = _grad(latest_frac)
    chars = []
    for v in sample:
        idx = min(8, max(0, int((v / hi) * 8)))
        chars.append(_BLOCKS[idx])
    line = "".join(chars).rjust(width, _BLOCKS[0])
    return Text(line, style=color)


def stacked_bar(segments: list[tuple[float, str, str]], width: int = 34) -> Text:
    """Multi-segment horizontal bar. Each segment is (fraction_0_to_1, color, label).
    Segments fill left-to-right; remaining space is dim background."""
    text = Text()
    remaining = width
    for frac, color, label in segments:
        chars = max(0, min(remaining, round(frac * width)))
        if chars <= 0:
            continue
        # Center the label inside the segment if it fits
        if len(label) <= chars:
            pad_l = (chars - len(label)) // 2
            pad_r = chars - len(label) - pad_l
            text.append("█" * pad_l + label + "█" * pad_r, style=f"bold {color}")
        else:
            text.append("█" * chars, style=color)
        remaining -= chars
    if remaining > 0:
        text.append("░" * remaining, style="grey23")
    return text


def temp_badge(temp: float, label: str = "", thresholds: tuple[float, float] = (60.0, 80.0)) -> Text:
    """Inline temperature badge: '● 39.8°C' colored green/yellow/red by threshold."""
    if temp <= 0:
        return Text(f"{label}n/a", style="grey50")
    if temp >= thresholds[1]:
        color, dot = "#e74c3c", "●"
    elif temp >= thresholds[0]:
        color, dot = "#f1c40f", "●"
    else:
        color, dot = "#2ecc71", "●"
    t = Text()
    if label:
        t.append(f"{label}", style="grey70")
    t.append(f"{dot} ", style=color)
    t.append(f"{temp:.0f}°C", style=f"bold {color}")
    return t
