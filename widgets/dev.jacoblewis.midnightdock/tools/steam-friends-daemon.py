#!/usr/bin/env python3
"""
Midnight Dock -- Steam "friends online" badge.

Unlike Proton Mail/Discord (Electron -> libunity -> D-Bus, see
unity-badge-daemon.py), Steam never calls the Unity badge API at all -- its
binary has zero references to libunity, verified by grepping it directly. It
uses a completely different tray protocol (Ayatana/AppIndicator) that carries
no numeric badge concept, so there is nothing to bridge for it.

Steam's own unread-chat-count is undocumented, reverse-engineered-per-plugin
state living inside its internal (and unstable -- Valve's own first-party UI
for it has disappeared from the beta channel before: steam-for-linux#10478)
JS client. Reading it means live-loading exploratory code into the running
Steam client itself. Deliberately NOT done -- see CLAUDE.md/session notes.

"Friends currently online" is different: it's exactly what Valve's OFFICIAL,
documented Web API is for (GetFriendList + GetPlayerSummaries), needs no
access to Steam's internal client at all, and poses zero risk to a live
Steam session. This just polls that.

Writes its OWN file (steam-badge.json), never badges.json -- that one belongs
to unity-badge-daemon.py. Two independent writers on one file race each other
with no lock; "one writer per file" is the same rule this codebase already
applies to request-resolve.sh / booth-message.sh.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

ENV_PATH = os.path.expanduser("~/.config/midnight-dock/steam.env")
OUT_PATH = os.path.expanduser("~/.cache/midnight-dock/steam-badge.json")
POLL_SECONDS = 60  # friend presence doesn't need to be fresher than this,
                    # and it's a shared API -- no reason to hammer it.

APPID = "steam.desktop"  # confirmed against the live TasksModel's AppId role


def load_env():
    env = {}
    with open(ENV_PATH) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k] = v
    return env


def atomic_write(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.load(r)


def online_friend_count(key: str, steamid: str) -> int:
    friends = fetch_json(
        f"https://api.steampowered.com/ISteamUser/GetFriendList/v1/"
        f"?key={key}&steamid={steamid}&relationship=friend"
    )["friendslist"]["friends"]
    ids = [f["steamid"] for f in friends]

    online = 0
    # GetPlayerSummaries takes at most 100 ids per call.
    for i in range(0, len(ids), 100):
        batch = ",".join(ids[i:i + 100])
        players = fetch_json(
            f"https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/"
            f"?key={key}&steamids={batch}"
        )["response"]["players"]
        # personastate: 0=Offline, 1=Online, 2=Busy, 3=Away, 4=Snooze,
        # 5=Looking to trade, 6=Looking to play -- anything nonzero is a
        # friend actually present in some form, not just offline.
        online += sum(1 for p in players if p.get("personastate", 0) != 0)
    return online


def main():
    env = load_env()
    key = env.get("STEAM_API_KEY")
    steamid = env.get("STEAM_ID64")
    if not key or not steamid:
        print("missing STEAM_API_KEY/STEAM_ID64 in", ENV_PATH, file=sys.stderr)
        sys.exit(1)

    while True:
        try:
            count = online_friend_count(key, steamid)
            atomic_write(OUT_PATH, {APPID: count} if count > 0 else {})
        except urllib.error.HTTPError as e:
            # A private friends list, a revoked key, or Valve's API having a
            # bad day all land here -- log it and keep the last-good count on
            # disk rather than blanking the badge over a transient failure.
            print("HTTP error:", e.code, e.reason, file=sys.stderr)
        except Exception as e:
            print("poll failed:", e, file=sys.stderr)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
