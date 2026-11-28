#!/usr/bin/env python3
"""Run in a private Hyprland + D-Bus session with resident startup enabled,
the copy-and-open color preference, grim and wtype. Pass the bundle executable.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from resident_capture_helpers import (
    cancel_screenshot, idle_outputs, lock_held, output, overlays, resident_reply, wait_for,
)


def exercise(bundle, resident, count, directory):
    def panel():
        return next((w for w in json.loads(output("hyprctl", "-j", "clients"))
                     if w["pid"] == resident.pid and w["mapped"]), None)

    def select(mode):
        wait_for(lambda: resident_reply(mode) == "b true", f"new {mode} session")
        wait_for(lambda: overlays() == count, "overlays on every output")
        for _ in range(5):
            time.sleep(0.35)
            if not overlays():
                break
            subprocess.run(["wtype", "-P", "Return", "-s", "60", "-p", "Return"], check=True)

    def close_panel():
        wait_for(panel, "mapped result window")
        address = panel()["address"]
        output("hyprctl", "dispatch", f'hl.dsp.window.close({{window="address:{address}"}})')
        wait_for(lambda: not panel() and not lock_held(), "closed result window")

    select("colorPicker")
    pending = directory / "copy-pending"
    wait_for(pending.exists, "clipboard helper after picking a color")
    try:
        if overlays():
            raise RuntimeError("The color overlays are still mapped")
        if lock_held():
            raise RuntimeError("Color copying still holds the selection lock")
        with subprocess.Popen([bundle]) as screenshot:
            try:
                wait_for(lambda: overlays() == count, "new screenshot during color copying")
                cancel_screenshot()
                screenshot.wait(timeout=5)
            finally:
                if screenshot.poll() is None:
                    screenshot.kill()
    finally:
        pending.unlink()
    close_panel()

    # Closing a newly mapped editor can coincide with its first full-size GTK draw.
    for _ in range(15):
        select("screenshot")
        close_panel()
    if resident.poll() is not None:
        raise RuntimeError("The resident process exited")


def main(bundle):
    count = len(idle_outputs())
    if resident_reply("invalid"):
        raise RuntimeError("Use a private session without a running resident service")
    with tempfile.TemporaryDirectory() as scratch:
        directory = Path(scratch)
        helper = directory / "wl-copy"
        helper.write_text('#!/bin/sh\ncat >/dev/null\ntouch "$XDG_STATE_HOME/copy-pending"\n'
                          'while test -e "$XDG_STATE_HOME/copy-pending"; do sleep .02; done\n')
        helper.chmod(0o700)
        env = {**os.environ, "XDG_STATE_HOME": scratch,
               "PATH": scratch + os.pathsep + os.environ["PATH"]}
        with subprocess.Popen([bundle, "--background"], env=env) as resident:
            try:
                wait_for(lambda: resident_reply("invalid") == "b false", "resident startup")
                exercise(bundle, resident, count, directory)
            finally:
                resident.terminate()
                try:
                    resident.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    resident.kill()


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(strict=True))
