#!/bin/bash
# End-to-end check of Resources/collect.py with the real Blender on generated fixture scenes.
# Puts the "moved" texture in ~/Downloads (Spotlight indexes it) and removes it afterwards.
#   Tests/run_collect.sh [path/to/Blender]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLENDER="${1:-/Applications/Blender.app/Contents/MacOS/Blender}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/farm-collect.XXXXXX")"
TAG="$(date +%s)$RANDOM"
SPOT="$HOME/Downloads/farm-mac-fixture-$TAG"
trap 'rm -rf "$WORK" "$SPOT"' EXIT

"$BLENDER" --version | head -1
"$BLENDER" --background --factory-startup --python "$ROOT/Tests/fixtures/make_fixtures.py" -- "$WORK" "$SPOT" "$TAG" 2>&1 | grep '^FIXTURE'

echo "==> waiting for Spotlight to index $SPOT"
for _ in $(seq 60); do
  [[ "$(mdfind -name "moved_$TAG.png" 2>/dev/null | grep -c "$SPOT" || true)" -ge 2 ]] && break
  sleep 1
done
mdfind -name "moved_$TAG.png" 2>/dev/null

echo "==> collect.py"
STAGE="$WORK/staging"
"$BLENDER" --background --factory-startup --disable-autoexec "$WORK/project/scene.blend" \
  --python "$ROOT/Resources/collect.py" -- "$STAGE" > "$WORK/collect.log" 2>&1
grep '^FARM_PROGRESS' "$WORK/collect.log" | tr '\n' ' '; echo
grep '^FARM_COLLECT ' "$WORK/collect.log" | sed 's/^FARM_COLLECT //' > "$WORK/report.json"
"$BLENDER" --background --factory-startup "$STAGE/scene.blend" --python "$ROOT/Tests/fixtures/verify_staged.py" 2>&1 \
  | grep '^FARM_VERIFY ' | sed 's/^FARM_VERIFY //' > "$WORK/verify.json"
(cd "$STAGE" && find . -type f | sort)

/usr/bin/python3 - "$WORK" "$SPOT" "$TAG" <<'PY'
import json, os, sys
work, spot, tag = sys.argv[1:4]
report = json.load(open(os.path.join(work, "report.json")))
verify = {v["name"]: v for v in json.load(open(os.path.join(work, "verify.json")))}
by_name = {i["name"]: i for i in report["items"]}
for i in report["items"]:
    print("  %-10s %-8s %-28s files=%s staged=%s %s" % (i["status"], i["type"], i["name"], i.get("files"), i.get("staged"), i.get("source", "")))
def check(cond, what):
    print(("  ok    " if cond else "  FAIL  ") + what)
    if not cond: check.failed = True
check.failed = False
check(by_name["abs_tex.png"]["status"] == "collected", "absolute-path texture collected")
moved = by_name["moved_%s.png" % tag]
check(moved["status"] == "found" and moved["source"] == os.path.join(spot, "moved_%s.png" % tag), "moved texture found by Spotlight, closest copy picked")
check(by_name["udim_tex.<UDIM>.png"]["files"] == 2, "UDIM: both tiles copied")
check(by_name["frame_0001.png"]["files"] == 3, "image sequence: 3 frames copied")
check(by_name["lib.blend"]["status"] == "collected", "linked library copied")
check(by_name["gone_%s.png" % tag]["status"] == "missing", "missing file reported missing")
for name, v in verify.items():
    want = not name.startswith("gone")
    check(v["exists"] == want and (not want or v["path"].startswith("//textures/")), "staged %s: %s resolves=%s" % (name, v["path"], v["exists"]))
check(os.path.isfile(os.path.join(work, "project", "scene.blend")) and not os.path.exists(os.path.join(work, "project", "textures")), "student's project untouched")
sys.exit(1 if check.failed else 0)
PY
