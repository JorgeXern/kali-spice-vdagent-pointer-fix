#!/usr/bin/env bash
#
# Remove vdagent-watch. Use it once Kali ships a fixed spice-vdagent and the
# pointer stays aligned without the script. The SPICE agent keeps running.

set -euo pipefail

bin="$HOME/.local/bin/vdagent-watch"
desktop="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/vdagent-watch.desktop"

pkill -u "$UID" -f 'bash [^ ]*/vdagent-watch$' || true
pkill -u "$UID" -xf 'xev -root -event randr' || true  # older versions
rm -f "$bin" "$desktop"

echo "vdagent-watch removed."
