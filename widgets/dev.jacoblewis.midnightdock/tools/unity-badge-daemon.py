#!/usr/bin/env python3
"""
Midnight Dock — Unity LauncherEntry badge bridge.

Electron apps (Proton Mail, Discord, Vesktop...) call app.setBadgeCount() on
Linux, which dlopen's libunity and broadcasts com.canonical.Unity.LauncherEntry
Update signals on the session bus. That signal is silently never SENT unless
something owns the well-known bus name "com.canonical.Unity" first — that's
libunity's own Inspector.unity_running gate (unity-inspector.vala), checked via
NameHasOwner and watched live. KDE Plasma has nothing that claims that name, so
on a stock KDE desktop no Electron app's badge count ever reaches D-Bus at all,
regardless of any dock/task manager code. Confirmed by direct libunity C-API
test: zero signals with the name unclaimed, immediate signal the moment it's
claimed — including from an ALREADY-RUNNING app with no restart, because
libunity's LauncherEntry re-syncs its current state the instant unity_running
flips true (on_unity_running_changed in unity-launcher.vala).

This process is that missing piece: it claims "com.canonical.Unity" (so every
Electron app's existing setBadgeCount() calls start actually reaching D-Bus),
listens for the resulting Update signals, and writes the current counts to a
small JSON file the dock plasmoid polls. It does not implement anything else
of the real Unity protocol (no scopes, no lenses) -- those need no consumer
here and were never wired up.
"""
import json
import os
import sys

from PyQt6.QtCore import QCoreApplication, QObject, pyqtSlot
from PyQt6.QtDBus import QDBusConnection, QDBusMessage

OUT_PATH = os.path.expanduser("~/.cache/midnight-dock/badges.json")
# desktop id -> the unique bus name that set it. Persisted so a daemon restart
# can keep badges whose app is still alive: Electron (Vesktop) emits Update
# itself, only when the count CHANGES, and never re-announces -- so wiping on
# start lost Vesktop's badge until its next new message.
OWNERS_PATH = os.path.expanduser("~/.cache/midnight-dock/badge-owners.json")


def desktop_id_from_app_uri(app_uri: str) -> str:
    # Unity's own prefixes (unity-launcher.vala APP_PREFIX/FILE_PREFIX).
    for prefix in ("application://", "file://"):
        if app_uri.startswith(prefix):
            return os.path.basename(app_uri[len(prefix):])
    return os.path.basename(app_uri)


def atomic_write(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


class Badges(QObject):
    def __init__(self):
        super().__init__()
        self.counts = {}
        # unique bus name (":1.234") -> desktop ids it has badged. An app that
        # QUITS never sends a final count of 0, so without this its last count
        # stayed on the dock forever (Proton Mail read "2" with the app closed).
        self.owners = {}

    def _write(self):
        atomic_write(OUT_PATH, self.counts)
        by_id = {d: n for n, ids in self.owners.items() for d in ids
                 if d in self.counts}
        atomic_write(OWNERS_PATH, by_id)

    def restore(self, bus):
        """Keep previous badges whose sender is still on the bus. Unique names
        are never reused within a bus session, so a live name IS the same app."""
        try:
            counts = json.load(open(OUT_PATH))
            by_id = json.load(open(OWNERS_PATH))
        except (OSError, ValueError):
            counts, by_id = {}, {}
        iface = bus.interface()
        for d, sender in by_id.items():
            if d in counts and iface.isServiceRegistered(sender).value():
                self.counts[d] = int(counts[d])
                self.owners.setdefault(sender, set()).add(d)
        self._write()

    # Taking the whole QDBusMessage (rather than "(sa{sv})" unpacked) is what
    # gives us message.service() -- the sender's unique name.
    @pyqtSlot(QDBusMessage)
    def handle_update(self, msg):
        args = msg.arguments()
        if len(args) < 2:
            return
        app_uri, props = args[0], args[1] or {}
        desktop_id = desktop_id_from_app_uri(str(app_uri))
        sender = msg.service()

        count = int(props.get("count", self.counts.get(desktop_id, 0)))
        visible = bool(props.get("count-visible", count > 0))
        new_val = count if visible else 0

        if new_val > 0 and sender:
            self.owners.setdefault(sender, set()).add(desktop_id)
        if self.counts.get(desktop_id, 0) == new_val:
            return
        if new_val > 0:
            self.counts[desktop_id] = new_val
        else:
            self.counts.pop(desktop_id, None)
        self._write()

    @pyqtSlot(str, str, str)
    def owner_changed(self, name, old, new):
        # A unique name losing its owner = that process left the bus.
        if new or not name.startswith(":"):
            return
        ids = self.owners.pop(name, None)
        if not ids:
            return
        # Another live sender may still own the same app's badge (a second
        # window/process) -- only clear ids nobody else has claimed.
        still = set().union(*self.owners.values()) if self.owners else set()
        changed = False
        for d in ids - still:
            if self.counts.pop(d, None) is not None:
                changed = True
        if changed:
            self._write()


def main():
    app = QCoreApplication(sys.argv)
    bus = QDBusConnection.sessionBus()

    # The presence beacon. Owning this name is the entire trick -- see the
    # module docstring. Never released for the life of this process.
    if not bus.registerService("com.canonical.Unity"):
        print("could not claim com.canonical.Unity:", bus.lastError().message(),
              file=sys.stderr)
        sys.exit(1)

    badges = Badges()
    ok = bus.connect(
        "", "", "com.canonical.Unity.LauncherEntry", "Update",
        badges.handle_update,
    )
    bus.connect("org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "NameOwnerChanged",
                badges.owner_changed)
    if not ok:
        print("could not subscribe to LauncherEntry.Update:",
              bus.lastError().message(), file=sys.stderr)
        sys.exit(1)

    # Keep only badges whose app is still running -- a stale count from a dead
    # app must not survive, but a live Electron app will not re-send its own.
    badges.restore(bus)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
