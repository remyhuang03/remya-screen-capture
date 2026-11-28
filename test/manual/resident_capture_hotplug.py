#!/usr/bin/env python3
"""Pass a bundle executable in a private Hyprland and D-Bus session with one
Wayland output, resident startup enabled, and grim and wtype in PATH.
"""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

from resident_capture_helpers import (
    cancel_screenshot, idle_outputs, lock_held, output, overlays, request_screenshot,
    resident_reply, wait_for,
)


def main(bundle):
    if len(idle_outputs()) != 1 or resident_reply("invalid"):
        raise RuntimeError("Use an idle, private session with one output and no resident service")
    grim = shutil.which("grim")
    if grim is None:
        raise RuntimeError("grim is required for the screencopy gate")
    monitor = "CAPTURE-HOTPLUG"
    with tempfile.TemporaryDirectory() as scratch:
        directory = Path(scratch)
        started = directory / "started"
        proceed = directory / "proceed"
        gate = directory / "grim"
        gate.write_text(
            '#!/bin/sh\ntouch "$CAPTURE_TEST_GATE/started"\n'
            'while ! test -f "$CAPTURE_TEST_GATE/proceed"; do sleep .02; done\n'
            f'exec {shlex.quote(grim)} "$@"\n'
        )
        gate.chmod(0o700)
        env = {**os.environ, "CAPTURE_TEST_GATE": scratch,
               "PATH": scratch + os.pathsep + os.environ["PATH"]}
        with subprocess.Popen([bundle, "--background"], env=env) as resident:
            plugged = False
            try:
                wait_for(lambda: resident_reply("invalid") == "b false", "resident startup")
                request_screenshot()
                wait_for(started.exists, "screencopy to start")
                assert lock_held() and not overlays()
                assert output("hyprctl", "output", "create", "wayland", monitor).strip() == "ok"
                plugged = True
                wait_for(lambda: monitor in output("hyprctl", "-j", "monitors"), "new output")
                proceed.touch()
                wait_for(lambda: not lock_held(), "release after hotplug during startup")
                wait_for(lambda: resident_reply("screenshot") == "b true", "capture retry")
                wait_for(lambda: overlays() == 2, "overlays on both outputs")

                assert output("hyprctl", "output", "remove", monitor).strip() == "ok"
                plugged = False
                wait_for(lambda: not overlays() and not lock_held(), "cancel after unplug")
                wait_for(lambda: resident_reply("screenshot") == "b true", "capture after unplug")
                wait_for(lambda: overlays() == 1, "overlay on the remaining output")
                cancel_screenshot()
                assert resident.poll() is None
            finally:
                proceed.touch()
                resident.terminate()
                try:
                    resident.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    resident.kill()
                    resident.wait()
                if plugged:
                    output("hyprctl", "output", "remove", monitor)
    print("The same resident reopened after hotplug during startup and unplug during selection.")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(strict=True))
