#!/usr/bin/env python3
"""Midnight away detector — writes ~/.cache/midnight/away ("away" / "here").

Runs the screensaver's ext_idle_notifier_v1 watcher (midnight-idle) with a
input-idle timeout (--input). The desktop widgets watch the file (wait-away.py) and slide
off the screen while it says "away", back in on the first input.
--input IGNORES idle inhibitors, so a Firefox video or a full-screen game does
not keep them on screen: away = no keyboard/mouse for the timeout, whatever is
playing (user 2026-10-14). The screensaver keeps respecting inhibitors.
Env: MIDNIGHT_AWAY_IDLE  seconds (default 30)
"""
import os, subprocess, sys

IDLE = int(os.environ.get("MIDNIGHT_AWAY_IDLE", "30"))
BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "midnight-idle")
OUT = os.path.expanduser("~/.cache/midnight/away")


def write(state):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        f.write(state)
    os.replace(tmp, OUT)
    print(state, flush=True)


write("here")   # a restart must never leave the widgets hidden
p = subprocess.Popen([BIN, "--input", str(IDLE * 1000)], stdout=subprocess.PIPE, text=True)
for line in p.stdout:
    line = line.strip()
    if line == "idle":
        write("away")
    elif line == "resume":
        write("here")
write("here")
sys.exit(p.wait() or 1)   # non-zero so systemd restarts us
