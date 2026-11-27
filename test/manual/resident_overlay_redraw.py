#!/usr/bin/env python3
"""Check two screenshot sessions on the installed, running resident service.

Run on an idle Hyprland desktop with grim, wtype and a working ydotool daemon:
    python test/manual/resident_overlay_redraw.py [output-name]
"""

import json
import subprocess
import sys
import time

from resident_capture_helpers import (
    cancel_screenshot, idle_outputs, output, overlays, request_screenshot, wait_for,
)


def warp(x, y):
    output("hyprctl", "eval", f"hl.dispatch(hl.dsp.cursor.move({{x={x}, y={y}}}))")


def main(name=None):
    monitors = idle_outputs()
    if name is None:
        monitor = next(m for m in monitors if m["focused"])
    else:
        monitor = next((m for m in monitors if m["name"] == name), None)
        if monitor is None:
            raise SystemExit(f"No active output named {name}")
    size = (monitor["width"], monitor["height"])
    if monitor["transform"] % 2:
        size = size[::-1]
    width, height = (round(pixels / monitor["scale"]) for pixels in size)
    x, y = monitor["x"], monitor["y"]
    previous_row, launch_row = y + height // 3, y + height * 2 // 3
    # Sample the launch row far from the pointer, loupe and toolbar.
    geometry = f"{x + width // 8},{launch_row - 5} 16x10"

    def point_at(row):
        warp(x + width // 2, row)
        # A compositor warp alone does not reliably deliver a Flutter hover.
        subprocess.run(["ydotool", "mousemove", "--", "4", "0"], check=True)

    def pixels():
        return subprocess.check_output(
            ["grim", "-s", "1", "-g", geometry, "-t", "ppm", "-"], timeout=3
        )

    original = json.loads(output("hyprctl", "-j", "cursorpos"))
    try:
        for session in (1, 2):
            point_at(launch_row)
            request_screenshot()
            try:
                wait_for(lambda: overlays() == len(monitors), "all screenshot overlays")
                time.sleep(0.5)
                # Capture the initial frame before sending any pointer input.
                initial = pixels()
                point_at(previous_row)
                time.sleep(0.4)
                without_line = pixels()
                point_at(launch_row)
                wait_for(
                    lambda: pixels() != without_line,
                    f"session {session} to paint the launch row",
                )
                if session == 2 and pixels() != initial:
                    raise RuntimeError("The reopened overlay showed stale pixels before pointer input")
                point_at(previous_row)
                wait_for(
                    lambda: pixels() == without_line,
                    f"session {session} to clear the launch row",
                )
            finally:
                cancel_screenshot()
    finally:
        warp(original["x"], original["y"])
    print("The reopened resident overlay displayed the new crosshair before pointer input.")


if __name__ == "__main__":
    main(*sys.argv[1:])
