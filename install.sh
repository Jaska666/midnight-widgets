#!/usr/bin/env bash
# Install or upgrade the Midnight widgets for the current user (Plasma 6).
#   ./install.sh            install every widget
#   ./install.sh weather    just the ones named (flipclock weather type calendar dock title)
#   ./install.sh --away     also build + enable the "slide away when idle" helper
set -euo pipefail
cd "$(dirname "$0")"
command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 not found — Plasma 6 is required"; exit 1; }

away=0; picks=()
for a in "$@"; do [ "$a" = --away ] && away=1 || picks+=("$a"); done
[ ${#picks[@]} -eq 0 ] && picks=(flipclock weather type calendar dock title)

for w in "${picks[@]}"; do
  d="widgets/dev.jacoblewis.midnight$w"
  [ -d "$d" ] || { echo "no such widget: $w"; exit 1; }
  if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "dev.jacoblewis.midnight$w"; then
    kpackagetool6 -t Plasma/Applet -u "$d" >/dev/null && echo "upgraded  $w"
  else
    kpackagetool6 -t Plasma/Applet -i "$d" >/dev/null && echo "installed $w"
  fi
done

mkdir -p ~/.config/systemd/user
if [ $away = 1 ]; then
  command -v wayland-scanner >/dev/null || { echo "--away needs wayland-scanner (wayland package) and gcc"; exit 1; }
  dest=~/.local/share/midnight-widgets/away
  mkdir -p "$dest"; cp extras/away/* "$dest/"
  (cd "$dest" && bash build.sh)
  cp extras/systemd/midnight-away.service ~/.config/systemd/user/
  systemctl --user daemon-reload
  systemctl --user enable --now midnight-away.service
  echo "away helper running (idle seconds: MIDNIGHT_AWAY_IDLE in the unit)"
fi

cat <<'MSG'

Done. Right-click the desktop -> Add or Manage Widgets -> search "Midnight".
Upgrades show after restarting Plasma:  systemctl --user restart plasma-plasmashell
Optional services are in extras/systemd (see README).
MSG
