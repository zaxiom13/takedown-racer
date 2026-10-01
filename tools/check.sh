#!/usr/bin/env bash
# Headless project check: import assets, then run the smoke-test scenes.
# Usage: tools/check.sh   (set GODOT=/path/to/godot if not on PATH)
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || command -v godot4 || echo /opt/godot/Godot_v4.7.2-stable_linux.x86_64)}"
log=$(mktemp)
"$GODOT" --headless --path . --import >"$log" 2>&1
"$GODOT" --headless --path . -s res://tests/smoke_test.gd 2>&1 | tee -a "$log"
code=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error|ERROR:" "$log"; then
	echo "check.sh: errors found in Godot output:"; grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$log" | head -20
	code=1
fi
rm -f "$log"
[ $code -eq 0 ] && echo "CHECK PASSED" || echo "CHECK FAILED"
exit $code
