#!/usr/bin/env python3
"""Run on an idle Hyprland session with cc, wtype, and resident capture enabled.

Usage: python test/manual/resident_capture_lock.py /path/to/release/bundle/remya_screen_capture
Temporarily stops the installed resident service, then restores it on exit.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from resident_capture_helpers import (
    cancel_screenshot, idle_outputs, overlays, request_screenshot, resident_reply, wait_for,
)

UNIT = "top.remya.screen_capture.gui.service"


def main(bundle):
    count = len(idle_outputs())

    def open_and_cancel():
        request_screenshot()
        wait_for(lambda: overlays() == count, "overlays on all outputs")
        cancel_screenshot()

    with tempfile.TemporaryDirectory() as directory:
        fault = Path(directory) / "fault.so"
        source = Path(__file__).with_name("overlay_close_fault.c")
        subprocess.run(["cc", "-shared", "-fPIC", source, "-ldl", "-o", fault], check=True)
        service = ["systemctl", "--user"]
        subprocess.run([*service, "is-active", "--quiet", UNIT], check=True)
        subprocess.run([*service, "stop", UNIT], check=True)
        try:
            with (Path(directory) / "resident.log").open("w+") as log:
                resident = subprocess.Popen(
                    [bundle, "--background"],
                    env={**os.environ, "LD_PRELOAD": str(fault), "REMYA_TEST_FAIL_CLOSE": str(count)},
                    stdout=log,
                    stderr=log,
                )
                try:
                    wait_for(
                        lambda: resident_reply("invalid") == "b false", "resident service registration"
                    )
                    open_and_cancel()
                    log.seek(0)
                    if "Injected overlay close failure" not in log.read():
                        raise RuntimeError("The fault hook did not run")
                    open_and_cancel()
                    if resident.poll() is not None:
                        raise RuntimeError("The resident process exited")
                except Exception:
                    log.seek(0)
                    print(log.read(), file=sys.stderr, end="")
                    raise
                finally:
                    resident.terminate()
                    try:
                        resident.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        resident.kill()
                        resident.wait()
        finally:
            subprocess.run([*service, "start", UNIT], check=True)
    print("The resident process released its lock and reopened after a close failure.")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(strict=True))
