#!/bin/bash
# Captures the app window in every state, light and dark, into docs/screenshots/.
# Uses Demo mode with generated scenes (Tests/fixtures/make_demo_scenes.py), never your own files.
#   scripts/screenshots.sh            (after scripts/build.sh)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Render Farm.app/Contents/MacOS/FarmMac"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
OUT="$ROOT/docs/screenshots"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/farm-shots.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

"$BLENDER" --background --factory-startup --python "$ROOT/Tests/fixtures/make_demo_scenes.py" -- "$WORK/Blender projects" >/dev/null 2>&1
ages=(5 200 1300 4400 10200 20500)   # minutes ago, newest first
i=0
for f in "robot arm" "desert temple v3" "forest_scene" "headphones product" "space station final" "my room"; do
  touch -t "$(date -v-"${ages[$i]}"M +%Y%m%d%H%M)" "$WORK/Blender projects/$f.blend"; i=$((i + 1))
done
/usr/bin/swiftc -O -o "$WORK/window-id" "$ROOT/scripts/window-id.swift"
mkdir -p "$OUT"

for look in light dark; do
  for state in ${STATES:-empty picked collecting review uploading done notfound}; do
    defaults delete io.github.ganya002.farm-mac "NSWindow Frame main" 2>/dev/null || true   # open at the default size
    "$APP" --demo "$state" --demo-files "$WORK/Blender projects" --appearance "$look" >/dev/null 2>&1 &
    pid=$!
    sleep "${WAIT:-2.5}"
    id="$("$WORK/window-id" "$pid")"
    screencapture -x -o -l "$id" "$OUT/$state-$look.png"
    kill "$pid"; wait "$pid" 2>/dev/null || true
    echo "  $OUT/$state-$look.png"
  done
done
