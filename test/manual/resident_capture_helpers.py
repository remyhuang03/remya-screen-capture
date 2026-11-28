"""Hyprland and D-Bus helpers for the manual resident capture tests."""

import json
import os
import subprocess
import time

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
    path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "top.remya.screen_capture.lock")
    return path in output("lslocks", "-nu", "-o", "PATH").splitlines()


def wait_for(predicate, description):
    deadline = time.monotonic() + 8
    while not predicate():
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Timed out waiting for {description}")
        time.sleep(0.05)


def idle_outputs():
    monitors = json.loads(output("hyprctl", "-j", "monitors"))
    active = [monitor for monitor in monitors if monitor["mirrorOf"] == "none"]
    if not active or overlays() or lock_held():
        raise RuntimeError("Use an idle session with at least one active output")
    return active


def resident_reply(mode):
    response = subprocess.run(
        [*OPEN, mode, os.environ["HYPRLAND_INSTANCE_SIGNATURE"]],
        capture_output=True, text=True,
    )
    return response.stdout.strip()


def request_screenshot():
    if resident_reply("screenshot") != "b true":
        raise RuntimeError("The resident process rejected a new screenshot")


def cancel_screenshot():
    # The compositor may map the surface before giving it keyboard focus.
    for _ in range(5):
        time.sleep(0.25)
        if not overlays():
            break
        subprocess.run(["wtype", "-P", "Escape", "-s", "80", "-p", "Escape"], check=True)
    wait_for(lambda: not overlays(), "all overlays to close")
    wait_for(lambda: not lock_held(), "the screenshot lock to be released")
