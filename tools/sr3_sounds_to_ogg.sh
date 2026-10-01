#!/usr/bin/env bash
# Convert selected Stunt Rally 3 sounds (.wav) to looping-ready .ogg under assets/audio/.
# Usage: tools/sr3_sounds_to_ogg.sh <stuntrally3 repo>
set -euo pipefail
SR3="$1"; OUT="$(dirname "$0")/../assets/audio"
mkdir -p "$OUT/engines"
for i in 1 2 3 4 5 6 7 8 9; do   # engine series "tsu" (CC-BY-4.0, CryHam)
	ffmpeg -loglevel error -y -i "$SR3/data/sounds/engines/tsu-$i.wav" -ac 1 -c:a libvorbis -q:a 4 "$OUT/engines/tsu-$i.ogg"
done
ffmpeg -loglevel error -y -i "$SR3/data/sounds/engines/turbo2.wav" -ac 1 -c:a libvorbis -q:a 4 "$OUT/boost_whoosh.ogg"  # CC0, CryHam
ls -la "$OUT" "$OUT/engines"
