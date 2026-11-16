#!/usr/bin/env python3
"""Generate the OpenCode TUI theme "omarchy" from the active Omarchy palette.

The theme keeps OpenCode's semantic token tree (theme-base.json) and rebuilds
every hue scale from colors.toml, so the TUI follows `omarchy theme set`.
"""

import json
import os
import subprocess
import sys
import tempfile

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")

COLORS = os.path.join(STATE, "omarchy", "current", "theme", "colors.toml")
BASE = os.path.join(CONFIG, "opencode", "theme-base.json")
OUT_DIR = os.path.join(CONFIG, "opencode", "themes")
OUT = os.path.join(OUT_DIR, "omarchy.json")


def read_palette():
    raw = subprocess.run(
        ["omarchy-theme-color", "--file", COLORS, "--all"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    palette = {}
    for line in raw.splitlines():
        key, _, value = line.partition("\t")
        value = value.strip()
        if value.startswith("#") and len(value) == 7:
            palette[key] = value
    return palette


def rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def to_hex(channels):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in channels)


def mix(a, b, amount):
    """amount = 0 -> a, 1 -> b."""
    ra, rb = rgb(a), rgb(b)
    return to_hex(tuple(x + (y - x) * amount for x, y in zip(ra, rb)))


def main():
    palette = read_palette()

    def col(*keys):
        for key in keys:
            if key in palette:
                return palette[key]
        return palette.get("foreground", "#ffffff")

    with open(BASE, encoding="utf-8") as handle:
        base = json.load(handle)

    bg = col("background")
    fg = col("foreground")
    muted = col("muted", "dark_foreground")

    # Anchored neutral scale: 800 is the terminal background, 700/600/500 the
    # raised surfaces, 400 muted text, 200 normal text, 100 highlights.
    gray = {
        "100": mix(fg, "#ffffff", 0.35),
        "200": fg,
        "300": col("light_foreground", "foreground"),
        "400": muted,
        "500": mix(bg, fg, 0.16),
        "600": mix(bg, fg, 0.10),
        "700": col("lighter_background", "background"),
        "800": bg,
        "900": col("darker_background", "background"),
    }

    def scale(hue):
        return {
            "100": mix(hue, "#ffffff", 0.35),
            "200": hue,
            "300": mix(hue, bg, 0.20),
            "400": mix(hue, bg, 0.36),
            "500": mix(hue, bg, 0.52),
            "600": mix(hue, bg, 0.64),
            "700": mix(hue, bg, 0.74),
            "800": mix(hue, bg, 0.84),
            "900": mix(hue, bg, 0.91),
        }

    hues = {
        "gray": gray,
        "red": scale(col("red", "bright_red")),
        "orange": scale(col("accent", "orange")),
        "yellow": scale(col("yellow", "bright_yellow")),
        "green": scale(col("green", "bright_green")),
        "cyan": scale(col("cyan", "bright_cyan")),
        "blue": scale(col("blue", "bright_blue")),
        "purple": scale(col("magenta", "bright_magenta")),
        "accent": "$hue.orange",
        "interactive": "$hue.cyan",
        "neutral": "$hue.gray",
    }

    # OpenCode ships a few literal colors in its token tree; point them at the
    # palette too so no stock blue/grey survives a theme change.
    base["categorical"] = ["orange", "purple", "green", "cyan", "red"]
    base["text"]["feedback"]["warning"]["base"] = "$hue.yellow.200"
    base["border"]["base"] = "$hue.neutral.600"
    base["scrollbar"]["base"] = "$hue.neutral.500"

    diff = base["diff"]
    diff["text"]["added"] = "$hue.green.200"
    diff["text"]["removed"] = "$hue.red.200"
    diff["text"]["context"] = "$hue.neutral.300"
    diff["text"]["hunkHeader"] = "$hue.cyan.300"
    diff["background"]["added"] = mix(bg, col("green", "bright_green"), 0.18)
    diff["background"]["removed"] = mix(bg, col("red", "bright_red"), 0.18)
    diff["highlight"]["added"] = "$hue.green.300"
    diff["highlight"]["removed"] = "$hue.red.300"
    diff["lineNumber"]["text"] = "$hue.neutral.400"
    diff["lineNumber"]["background"]["added"] = mix(bg, col("green", "bright_green"), 0.11)
    diff["lineNumber"]["background"]["removed"] = mix(bg, col("red", "bright_red"), 0.11)

    base["syntax"]["number"] = "$hue.yellow.200"
    base["syntax"]["type"] = "$hue.cyan.200"
    base["markdown"]["blockQuote"] = "$hue.purple.200"
    base["markdown"]["emphasis"] = "$hue.purple.200"
    base["markdown"]["strong"] = "$hue.orange.200"

    theme = {
        "$schema": "https://opencode.ai/theme.json",
        "base": base,
        "dark": {"hue": hues},
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    rendered = json.dumps(theme, indent=2) + "\n"

    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as handle:
            if handle.read() == rendered:
                return 0

    fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix=".omarchy-", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(rendered)
    os.replace(tmp, OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
