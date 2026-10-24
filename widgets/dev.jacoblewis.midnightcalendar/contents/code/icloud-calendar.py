#!/usr/bin/env python3
"""
icloud-calendar.py — iCloud (CalDAV) -> ~/.cache/midnight/calendar.json for the
Midnight Calendar desktop widget (dev.jacoblewis.midnightcalendar).

    icloud-calendar.py              sync once (what the user timer runs)
    icloud-calendar.py --setup      print the one-time credential steps
    icloud-calendar.py --fixture F  build the JSON from a local .ics (testing only)

ONE-WAY, READ-ONLY. It reads every iCloud calendar that holds events and writes a small
JSON agenda (yesterday .. +45 days, recurring events expanded). It never writes to iCloud.

⚠️ CREDENTIALS NEVER LIVE IN A FILE. The Apple ID (not secret) is in
~/.config/midnight/icloud.conf; the APP-SPECIFIC PASSWORD is in KWallet via the Secret
Service and is read with `secret-tool lookup service midnight-icloud account <apple id>`.
iCloud refuses the real Apple ID password over CalDAV anyway — it has to be an
app-specific one from account.apple.com -> Sign-In and Security -> App-Specific Passwords.

⚠️ THE WIDGET NEVER SEES A FAILURE AS "NO EVENTS". Every failure writes the JSON with an
`error` key and the LAST GOOD events kept, so a dropped connection shows yesterday's
agenda with a quiet "offline" mark instead of an empty, falsely clear day.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

CONF = os.path.expanduser("~/.config/midnight/icloud.conf")
OUT = os.path.expanduser("~/.cache/midnight/calendar.json")
ROOT_URL = "https://caldav.icloud.com/"
DAYS_BACK, DAYS_AHEAD = 1, 45
NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav",
      "a": "http://apple.com/ns/ical/", "cs": "http://calendarserver.org/ns/"}
UA = "MidnightCalendar/1.0 (+https://github.com/Jaska666/midnight-widgets)"

SETUP = """\
Midnight Calendar — one-time iCloud setup
1. account.apple.com -> Sign-In and Security -> App-Specific Passwords -> "+",
   name it "Midnight". Copy the xxxx-xxxx-xxxx-xxxx password it shows.
2. Tell the widget your Apple ID (not secret):
     mkdir -p ~/.config/midnight && echo 'apple_id=you@icloud.com' > ~/.config/midnight/icloud.conf
3. Store the app-specific password in KWallet (you type it at the prompt):
     secret-tool store --label='Midnight iCloud' service midnight-icloud account you@icloud.com
4. Sync now:   systemctl --user start midnight-calendar.service
"""


# ── output ────────────────────────────────────────────────────────────────
def previous():
    try:
        return json.load(open(OUT))
    except Exception:
        return {}


def write(payload):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # ⚠️ ATOMIC (tmp + os.replace): the widget watches this directory and reads on change,
    # so a half-written file must never be visible — same rule as the dock's badge files.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(OUT), prefix=".calendar.")
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, OUT)


def fail(state, msg):
    prev = previous()
    write({"updated": prev.get("updated", 0), "checked": int(dt.datetime.now().timestamp()),
           "state": state, "error": msg,
           "calendars": prev.get("calendars", []), "events": prev.get("events", [])})
    print(f"{state}: {msg}", file=sys.stderr)
    raise SystemExit(0 if state == "setup" else 1)


# ── credentials ───────────────────────────────────────────────────────────
def credentials():
    try:
        conf = dict(l.strip().split("=", 1) for l in open(CONF) if "=" in l
                    and not l.lstrip().startswith("#"))
    except FileNotFoundError:
        fail("setup", "Connect iCloud: run scripts/icloud-calendar.py --setup")
    user = conf.get("apple_id", "").strip()
    if not user:
        fail("setup", "apple_id missing from ~/.config/midnight/icloud.conf")
    try:
        pw = subprocess.run(["secret-tool", "lookup", "service", "midnight-icloud",
                             "account", user], capture_output=True, text=True,
                            timeout=20).stdout.strip()
    except Exception as e:
        fail("error", f"KWallet unavailable: {e}")
    if not pw:
        fail("setup", "No app-specific password in KWallet (see --setup)")
    return user, pw


# ── CalDAV ────────────────────────────────────────────────────────────────
def dav(session, method, url, body, depth="0"):
    r = session.request(method, url, data=body.encode(), timeout=30,
                        headers={"Depth": depth, "Content-Type": "application/xml; charset=utf-8",
                                 "User-Agent": UA})
    if r.status_code in (401, 403):
        fail("auth", "iCloud rejected the Apple ID / app-specific password")
    if r.status_code >= 400:
        fail("error", f"{method} {url} -> HTTP {r.status_code}")
    return ET.fromstring(r.content), r.url


def href_of(tree, path):
    el = tree.find(path, NS)
    return el.text.strip() if el is not None and el.text else None


def discover(session):
    from urllib.parse import urljoin
    t, base = dav(session, "PROPFIND", ROOT_URL,
                  '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>')
    principal = href_of(t, ".//d:current-user-principal/d:href")
    if not principal:
        fail("error", "CalDAV: no current-user-principal")
    t, base = dav(session, "PROPFIND", urljoin(base, principal),
                  '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                  '<d:prop><c:calendar-home-set/></d:prop></d:propfind>')
    home = href_of(t, ".//c:calendar-home-set/d:href")
    if not home:
        fail("error", "CalDAV: no calendar-home-set")
    home = urljoin(base, home)
    t, _ = dav(session, "PROPFIND", home,
               '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
               'xmlns:a="http://apple.com/ns/ical/"><d:prop><d:displayname/><d:resourcetype/>'
               '<a:calendar-color/><c:supported-calendar-component-set/><d:current-user-privilege-set/>'
               '</d:prop></d:propfind>',
               depth="1")
    cals = []
    for resp in t.findall("d:response", NS):
        if resp.find(".//d:resourcetype/c:calendar", NS) is None:
            continue
        comps = [c.get("name") for c in resp.findall(".//c:supported-calendar-component-set/c:comp", NS)]
        if comps and "VEVENT" not in comps:
            continue          # Reminders lists are VTODO-only calendars
        name = (resp.findtext(".//d:displayname", "", NS) or "").strip() or "Calendar"
        color = (resp.findtext(".//a:calendar-color", "", NS) or "").strip()
        privs = {el.tag.split("}")[-1] for el in resp.findall(".//d:current-user-privilege-set/d:privilege/*", NS)}
        cals.append({"url": urljoin(home, resp.findtext("d:href", "", NS)),
                     "name": name, "color": norm_color(color),
                     # a shared calendar can be read-only; the widget only offers writable ones
                     "writable": bool(privs & {"write", "write-content", "all", "bind"}) or not privs})
    return cals


def norm_color(c):
    # Apple sends #RRGGBBAA; QML wants #RRGGBB (or #AARRGGBB). Drop the alpha.
    m = re.fullmatch(r"#?([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?", c or "")
    return "#" + m.group(1).upper() if m else "#9A8CFF"


def fetch_ics(session, cal, start, end):
    s, e = (x.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") for x in (start, end))
    t, _ = dav(session, "REPORT", cal["url"],
               '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
               '<d:prop><c:calendar-data/></d:prop><c:filter><c:comp-filter name="VCALENDAR">'
               f'<c:comp-filter name="VEVENT"><c:time-range start="{s}" end="{e}"/>'
               '</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>', depth="1")
    return [el.text for el in t.findall(".//c:calendar-data", NS) if el.text]


# ── expansion ─────────────────────────────────────────────────────────────
def expand(ics_texts, cal, start, end):
    import icalendar
    import recurring_ical_events
    out = []
    for text in ics_texts:
        try:
            vcal = icalendar.Calendar.from_ical(text)
            occ = recurring_ical_events.of(vcal).between(start, end)
        except Exception as e:
            print(f"  skipped an unparsable event in {cal['name']}: {e}", file=sys.stderr)
            continue
        for ev in occ:
            if str(ev.get("STATUS", "")).upper() == "CANCELLED":
                continue
            s, e2 = ev.decoded("DTSTART"), ev.decoded("DTEND", None)
            all_day = not isinstance(s, dt.datetime)
            if all_day:
                e2 = e2 or (s + dt.timedelta(days=1))
                s_local = dt.datetime.combine(s, dt.time.min).astimezone()
                e_local = dt.datetime.combine(e2, dt.time.min).astimezone()
            else:
                if e2 is None:
                    dur = ev.decoded("DURATION", dt.timedelta(0))
                    e2 = s + dur
                # floating (no tz) times are local wall-clock by RFC 5545
                s_local = (s if s.tzinfo else s.astimezone()).astimezone()
                e_local = (e2 if e2.tzinfo else e2.astimezone()).astimezone()
            out.append({
                "title": str(ev.get("SUMMARY", "")).strip() or "(No title)",
                "start": int(s_local.timestamp() * 1000),
                "end": int(e_local.timestamp() * 1000),
                "allDay": all_day,
                "location": str(ev.get("LOCATION", "")).strip(),
                "cal": cal["name"], "color": cal["color"],
            })
    return out


# ── adding an event (the widget's + sheet) ────────────────────────────────
# ⚠️ THE WIDGET PASSES ONE ARGUMENT: encodeURIComponent(JSON.stringify(event)) with ' also
# escaped, inside single quotes. That alphabet cannot break out of the shell, so a title
# like `$(rm -rf ~)` arrives as text. Never splice user text into the command any other way.
# Prints ONE JSON line ({"ok":true} / {"ok":false,"error":...}) — the widget reads it.
def add_event(arg):
    import uuid
    from urllib.parse import unquote
    import requests
    import icalendar

    def answer(ok, error=""):
        print(json.dumps({"ok": ok, "error": error}))
        raise SystemExit(0 if ok else 1)

    try:
        ev = json.loads(unquote(arg))
        title = str(ev["title"]).strip()
        cal_name = str(ev["cal"])
        all_day = bool(ev.get("allDay"))
        start = dt.datetime.fromtimestamp(int(ev["start"]) / 1000).astimezone()
        end = dt.datetime.fromtimestamp(int(ev["end"]) / 1000).astimezone()
        location = str(ev.get("location", "")).strip()
    except Exception as e:
        answer(False, f"bad event: {e}")
    if not title:
        answer(False, "Title is empty")
    if end <= start and not all_day:
        answer(False, "End is before start")

    cal = next((c for c in previous().get("calendars", []) if c.get("name") == cal_name), None)
    if not cal or not cal.get("url"):
        answer(False, f"Unknown calendar {cal_name!r} — sync first")
    if not cal.get("writable", True):
        answer(False, f"{cal_name} is read-only")

    vcal = icalendar.Calendar()
    vcal.add("prodid", "-//Midnight Widgets//Midnight Calendar//EN")
    vcal.add("version", "2.0")
    vev = icalendar.Event()
    uid = str(uuid.uuid4()).upper()
    vev.add("uid", uid)
    vev.add("dtstamp", dt.datetime.now(dt.timezone.utc))
    vev.add("summary", title)
    if all_day:
        d0 = start.date()
        d1 = max(end.date(), d0 + dt.timedelta(days=1))
        vev.add("dtstart", d0)
        vev.add("dtend", d1)
    else:
        # UTC: unambiguous, and every client renders it in its own zone
        vev.add("dtstart", start.astimezone(dt.timezone.utc))
        vev.add("dtend", end.astimezone(dt.timezone.utc))
    if location:
        vev.add("location", location)
    vcal.add_component(vev)

    user, pw = credentials()
    url = cal["url"].rstrip("/") + f"/{uid}.ics"
    try:
        r = requests.put(url, data=vcal.to_ical(), auth=(user, pw), timeout=30,
                         headers={"Content-Type": "text/calendar; charset=utf-8",
                                  "If-None-Match": "*", "User-Agent": UA})
    except requests.RequestException as e:
        answer(False, f"iCloud unreachable: {e.__class__.__name__}")
    if r.status_code in (401, 403):
        answer(False, "iCloud refused the write (read-only calendar or sign-in)")
    if r.status_code >= 300:
        answer(False, f"iCloud said HTTP {r.status_code}")
    # pull it straight back so the widget shows it without waiting for the timer
    try:
        subprocess.run([sys.executable, os.path.abspath(__file__)], timeout=90,
                       capture_output=True)
    except Exception:
        pass
    answer(True)


def window():
    today = dt.datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    return today - dt.timedelta(days=DAYS_BACK), today + dt.timedelta(days=DAYS_AHEAD)


def publish(cals, events):
    events.sort(key=lambda x: (x["start"], not x["allDay"], x["title"].lower()))
    write({"updated": int(dt.datetime.now().timestamp()), "checked": int(dt.datetime.now().timestamp()),
           "state": "ok", "error": "",
           "calendars": [{"name": c["name"], "color": c["color"], "url": c.get("url", ""),
                          "writable": c.get("writable", False)} for c in cals],
           "events": events})
    print(f"ok: {len(events)} events from {len(cals)} calendars")


def main():
    if "--setup" in sys.argv:
        print(SETUP)
        return
    if "--add" in sys.argv:
        add_event(sys.argv[sys.argv.index("--add") + 1])
        return
    start, end = window()
    if "--fixture" in sys.argv:
        path = sys.argv[sys.argv.index("--fixture") + 1]
        cal = {"name": "Fixture", "color": "#9A8CFF"}
        publish([cal], expand([open(path).read()], cal, start, end))
        return
    # credentials FIRST: an unconfigured widget should say "Connect iCloud", not report a
    # library problem the user has no reason to know about yet
    user, pw = credentials()
    try:
        import icalendar, recurring_ical_events  # noqa: F401
    except ImportError:
        fail("error", "missing python-icalendar / python-recurring-ical-events (pacman -S)")
    import requests
    session = requests.Session()
    session.auth = (user, pw)
    try:
        cals = discover(session)
        events = []
        for cal in cals:
            events += expand(fetch_ics(session, cal, start, end), cal, start, end)
    except requests.RequestException as e:
        fail("offline", f"iCloud unreachable: {e.__class__.__name__}")
    publish(cals, events)


if __name__ == "__main__":
    main()
