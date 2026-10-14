#!/usr/bin/env bash
#
# Install vdagent-watch for the current user and start it at every login.
# Run it inside the Kali VM, from the graphical session, as your normal user:
#
#   ./install.sh            (add --force to skip the version check)
#
# Only missing packages need sudo; everything else goes into your home.

set -euo pipefail

src_dir=$(cd "$(dirname "$0")" && pwd)
bin="$HOME/.local/bin/vdagent-watch"
desktop="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/vdagent-watch.desktop"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not with sudo." >&2
  exit 1
fi

# 0. Debian/Kali 0.23.0-4 already contains the official fix (LP: #2168964).
#    Install anyway with --force, e.g. to test it.
fixed_version="0.23.0-4"
installed=$(dpkg-query -W -f='${Version}' spice-vdagent 2>/dev/null || true)
if [ "${1:-}" != "--force" ] && [ -n "$installed" ] &&
   dpkg --compare-versions "$installed" ge "$fixed_version"; then
  echo "spice-vdagent $installed already includes the fix: you do not need"
  echo "vdagent-watch. Reboot the VM if the pointer still drifts."
  echo "To install it anyway: ./install.sh --force"
  exit 0
fi

# 1. Dependencies: xev is in x11-utils, xrandr in x11-xserver-utils.
missing=()
command -v xev >/dev/null           || missing+=(x11-utils)
command -v xrandr >/dev/null        || missing+=(x11-xserver-utils)
command -v spice-vdagent >/dev/null || missing+=(spice-vdagent)
if [ ${#missing[@]} -gt 0 ]; then
  echo "Installing missing packages: ${missing[*]}"
  sudo apt-get install -y "${missing[@]}"
fi

# 2. Stop a running copy (including older versions installed by hand).
pkill -u "$UID" -f 'bash [^ ]*/vdagent-watch$' || true
pkill -u "$UID" -xf 'xev -root -event randr' || true
for _ in 1 2 3 4 5 6 7 8 9 10; do   # wait up to 2 s so it releases its lock
  pgrep -u "$UID" -f 'bash [^ ]*/vdagent-watch$' >/dev/null || break
  sleep 0.2
done

# 3. Install the script.
install -Dm755 "$src_dir/vdagent-watch" "$bin"

# 4. Autostart entry. Desktop files do not expand $HOME: write the full path.
mkdir -p "$(dirname "$desktop")"
cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=vdagent-watch
Comment=Keep the SPICE pointer aligned (Kali bug #9653)
Exec=$bin
Terminal=false
EOF

echo "Installed: $bin"
echo "Autostart: $desktop"

# 5. Start it now if we are inside the graphical session.
if [ -n "${DISPLAY:-}" ]; then
  nohup "$bin" >/dev/null 2>&1 &
  echo "Running now. Log: journalctl -t vdagent-watch -f"
else
  echo "No graphical session detected: it will start at your next login."
fi
