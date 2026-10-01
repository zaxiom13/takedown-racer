#!/usr/bin/env bash
# Runs tests/drive_capture.gd under Xvfb (software GL) and writes screenshots to $1 (default /tmp/cap).
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}"
out="${1:-/tmp/cap}"; mkdir -p "$out"; rm -f "$out"/*.png
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 \
	-s res://tests/drive_capture.gd -- "$out" ${2:-} 2>&1 | grep -vE "ALSA|audio|^\s*at:|^$|snd_"
