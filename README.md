# Midnight widgets for KDE Plasma 6

A set of frameless desktop widgets that share one design language: a dark
violet / mint palette, Inter + JetBrains Mono, no panel backgrounds — just type,
glyphs and a soft shadow, so they sit directly on your wallpaper.

| Widget | What it does |
|---|---|
| **Flip Clock** | Big split-flap clock; the cards flip on every minute. |
| **Weather** | Current conditions pill + a 7-day forecast sheet. [Open-Meteo](https://open-meteo.com), no API key. Set your location in the widget's settings (US ZIP or coordinates). |
| **Type** | Typing races on the desktop: a pace ghost runs at your personal best, WPM / accuracy history. |
| **Calendar** | Month grid + today's events, with an add-event sheet. Syncs iCloud over CalDAV (setup below). |
| **Dock** | Icons-only dock with macOS-style magnification, running indicators and unread badges. Put it in a panel. |
| **Title** | The active app's name and window title, pinned to the centre of a panel. |

All of them are Plasma 6 / Qt 6, Wayland-friendly, and need nothing but Python 3
for their small helper scripts.

## Install

```bash
git clone https://github.com/Jaska666/midnight-widgets
cd midnight-widgets
./install.sh            # or: ./install.sh weather flipclock
```

Then right-click the desktop → **Add or Manage Widgets** → search "Midnight".

## Optional extras

**Slide away when idle** — every widget slides off the nearest screen edge after
30 s without keyboard or mouse input, and back on the first input. Needs `gcc`
and `wayland-scanner` (it uses the `ext-idle-notify-v1` Wayland protocol):

```bash
./install.sh --away
```

**Dock badges** — unread counts from apps that publish Unity LauncherEntry counts
(Discord/Vesktop, Thunderbird, Electron mail apps, …):

```bash
cp extras/systemd/midnight-unity-badges.service ~/.config/systemd/user/
systemctl --user enable --now midnight-unity-badges.service
```

A Steam "friends online" badge is also available
(`extras/systemd/midnight-steam-friends.service`); it reads `STEAM_API_KEY` and
`STEAM_ID64` from `~/.config/midnight-dock/steam.env`.

**Calendar (iCloud)**:

1. Create an app-specific password at appleid.apple.com.
2. ```bash
   mkdir -p ~/.config/midnight && echo 'apple_id=you@icloud.com' > ~/.config/midnight/icloud.conf
   secret-tool store --label='Midnight iCloud' service midnight-icloud account you@icloud.com
   cp extras/systemd/midnight-calendar.{service,timer} ~/.config/systemd/user/
   systemctl --user enable --now midnight-calendar.timer
   ```
   Needs the Python packages `icalendar` and `recurring-ical-events`
   (Arch: `python-icalendar python-recurring-ical-events`). The password stays in
   your keyring (KWallet / Secret Service); the widget never sees it.

## Album colours

The widgets also follow a now-playing album's colours when a file
`~/.cache/midnight/hue.json` (`{"on": true, "accent": "#rrggbb", "c": [...]}`)
exists. Nothing writes it out of the box — it is a hook for a music player.

## Licence

Per widget, as declared in each `metadata.json` (MIT or GPL-2.0-or-later).
