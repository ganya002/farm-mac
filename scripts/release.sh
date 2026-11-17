#!/bin/bash
# Build the app, zip it, and write dist/install.sh with this version and the zip's SHA-256 baked in.
# Publishing is separate (and needs a yes): gh release create "v$(cat VERSION)" dist/RenderFarm-*.zip dist/install.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
scripts/build.sh
VERSION="$(tr -d '[:space:]' < VERSION)"
ZIP="dist/RenderFarm-$VERSION-arm64.zip"
(cd dist && ditto -c -k --keepParent "Render Farm.app" "RenderFarm-$VERSION-arm64.zip")
SHA="$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
sed -e "s/__VERSION__/$VERSION/" -e "s/__APP_SHA256__/$SHA/" install.sh > dist/install.sh
grep -qE '__(VERSION|APP_SHA256)__' dist/install.sh && { echo "placeholders left in dist/install.sh" >&2; exit 1; }
sh -n dist/install.sh
echo "==> $ZIP  $SHA"
echo "==> dist/install.sh (v$VERSION)"
