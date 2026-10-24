#!/usr/bin/env python3
"""wait-live.py <known-md5> [timeout] — the desktop widgets' one live feed.

Prints ONE compact JSON line {"away": "here"|"away", "hue": {...hue.json...}} as soon
as it differs (by md5 of that line) from what the caller already holds, then exits.
Every Midnight desktop widget runs this through its Live.qml (executable DataSource,
re-armed on each return). One waiter per widget for BOTH feeds — away state
(midnight-away.service) and the album colour (midnight-hue.service) — rather than one
per feed per widget. Raw inotify via ctypes (inotify-tools is not installed).
"""
import ctypes, hashlib, json, os, select, sys

D = os.path.expanduser("~/.cache/midnight")
known = sys.argv[1] if len(sys.argv) > 1 else ""
timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 600


def line():
    try:
        away = open(os.path.join(D, "away")).read().strip() or "here"
    except OSError:
        away = "here"
    try:
        hue = json.load(open(os.path.join(D, "hue.json")))
    except (OSError, ValueError):
        hue = {}
    return json.dumps({"away": away, "hue": hue}, separators=(",", ":"), sort_keys=True)


os.makedirs(D, exist_ok=True)
libc = ctypes.CDLL("libc.so.6", use_errno=True)
fd = libc.inotify_init1(os.O_CLOEXEC)
libc.inotify_add_watch(fd, D.encode(), 0x8 | 0x80 | 0x100)  # CLOSE_WRITE|MOVED_TO|CREATE
while True:
    s = line()
    if hashlib.md5(s.encode()).hexdigest() != known:
        print(s)
        break
    r, _, _ = select.select([fd], [], [], timeout)
    if not r:
        print(s)
        break
    os.read(fd, 4096)
