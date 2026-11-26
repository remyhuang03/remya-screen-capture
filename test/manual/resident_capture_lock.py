#!/usr/bin/env python3
"""Run on an idle Hyprland session with cc, wtype, and resident capture enabled.

Usage: python test/manual/resident_capture_lock.py /path/to/release/bundle/remya_screen_capture
Temporarily stops the installed resident service, then restores it on exit.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

UNIT = "top.remya.screen_capture.gui.service"
RESIDENT = "top.remya.screen_capture.Resident"
OPEN = [
    "busctl", "--user", "--timeout=1s", "call", RESIDENT,
    "/top/remya/screen_capture/Resident", RESIDENT, "Open", "ss",
]


def output(*command):
    return subprocess.check_output(command, text=True)


def overlays():
    layers = json.loads(output("hyprctl", "-j", "layers"))
    return sum(
        layer["namespace"] == "top.remya.screen_capture/overlay"
        for monitor in layers.values()
        for level in monitor["levels"].values()
        for layer in level
    )


def lock_held():
    return "top.remya.screen_capture.lock" in output("lslocks", "-n", "-o", "PATH")


def wait_for(predicate, description):
    deadline = time.monotonic() + 8
    while not predicate():
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Timed out waiting for {description}")
        time.sleep(0.05)


def main(bundle):
    signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    outputs = json.loads(output("hyprctl", "-j", "monitors"))
    count = sum(monitor["mirrorOf"] == "none" for monitor in outputs)
    if not count or overlays() or lock_held():
        raise RuntimeError("Use an idle session with at least one active output")

    def resident_ready():
        response = subprocess.run(
            [*OPEN, "invalid", signature], capture_output=True, text=True
        )
        return response.stdout.strip() == "b false"

    def open_and_cancel():
        if output(*OPEN, "screenshot", signature).strip() != "b true":
            raise RuntimeError("The resident process rejected a new screenshot")
        wait_for(lambda: overlays() == count, "overlays on all outputs")
        # The compositor may map the surface before giving it keyboard focus.
        for _ in range(5):
            time.sleep(0.25)
            if not overlays():
                break
            subprocess.run(["wtype", "-P", "Escape", "-s", "80", "-p", "Escape"], check=True)
        wait_for(lambda: not overlays(), "all overlays to close")
        wait_for(lambda: not lock_held(), "the screenshot lock to be released")

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
                    wait_for(resident_ready, "resident service registration")
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
