#!/usr/bin/env python3
"""Block until a badge file in ~/.cache/midnight-dock changes, then exit.

The dock runs this through its executable DataSource and re-arms it every time it
returns, so badge reads are EVENT-DRIVEN. ⚠️ FolderListModel could not do this: the
daemons write with os.replace (atomic rename), and a directory watch never reported
the new content — counts only refreshed on the 60s fallback (found 2026-10-06).
Raw inotify via ctypes because inotify-tools is not installed (needs sudo).
Exits after `timeout` seconds regardless, so a stale waiter can never pile up.
"""
import ctypes, os, select, sys

IN_CLOSE_WRITE, IN_MOVED_TO, IN_CREATE = 0x8, 0x80, 0x100
d = os.path.expanduser("~/.cache/midnight-dock")
os.makedirs(d, exist_ok=True)
libc = ctypes.CDLL("libc.so.6", use_errno=True)
fd = libc.inotify_init1(os.O_CLOEXEC)
if fd < 0 or libc.inotify_add_watch(fd, d.encode(), IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE) < 0:
    sys.exit(1)
timeout = float(sys.argv[1]) if len(sys.argv) > 1 else 300
while True:
    r, _, _ = select.select([fd], [], [], timeout)
    if not r:
        print("timeout"); break
    buf = os.read(fd, 4096)
    i, hit = 0, False
    while i < len(buf):
        ln = int.from_bytes(buf[i + 12:i + 16], "little")
        name = buf[i + 16:i + 16 + ln].rstrip(b"\0").decode(errors="ignore")
        if name.endswith("badge.json") or name.endswith("badges.json"):
            hit = True
        i += 16 + ln
    if hit:
        print("changed"); break
