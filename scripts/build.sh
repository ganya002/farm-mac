#!/bin/bash
# Builds the app (release) into dist/Render Farm.app.
#
# Usage: scripts/build.sh [--debug] [--identity "Signing Identity"]
#
# Signing: ad-hoc unless an identity is given (or FARM_SIGN_IDENTITY is set). A stable local
# certificate keeps the Local Network permission across rebuilds; ad-hoc builds may ask again.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=release
IDENTITY="${FARM_SIGN_IDENTITY:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG=debug ;;
    --identity) IDENTITY="$2"; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 3 ;;
  esac
  shift
done

# Use the toolchain that ships with the selected Xcode; a swift.org toolchain on PATH (swiftly, etc.)
# does not match the SDK and fails to compile Foundation.
XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SWIFT="$XCODE_TOOLCHAIN/swift"
[[ -x "$SWIFT" ]] || SWIFT=/usr/bin/swift
export PATH="$XCODE_TOOLCHAIN:$PATH"

[[ "$(uname -m)" == "arm64" ]] || echo "warning: the app targets Apple Silicon; building on $(uname -m) anyway" >&2

echo "==> swift build -c $CONFIG"
"$SWIFT" build -c "$CONFIG" --product FarmMac 2>&1 | grep -vE '^\[[0-9]+ ?/ ?[0-9]+\]' || true
BIN="$("$SWIFT" build -c "$CONFIG" --show-bin-path)"
test -x "$BIN/FarmMac" || { echo "build failed: $BIN/FarmMac missing" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="$ROOT/dist/Render Farm.app"
rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FarmMac" "$APP/Contents/MacOS/FarmMac"
cp "$ROOT/Resources/collect.py" "$APP/Contents/Resources/"
[[ -f "$ROOT/Packaging/AppIcon.icns" ]] && cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
  echo "    signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "    ad-hoc signed"
fi
codesign --verify --strict "$APP"
echo "==> done: $APP (v$VERSION, $CONFIG)"
