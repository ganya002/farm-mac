#!/bin/sh
# Render Farm for Mac: one-line installer. No sudo, no Xcode.
#
#   curl -fsSL https://github.com/ganya002/farm-mac/releases/latest/download/install.sh | sh
#
# Installs Blender 5.3.0 if it's missing, then the Render Farm app, both into /Applications, and opens it.
# Every download is checked against a SHA-256 written into this file before anything is installed.
# Options (with `sh install.sh ...` or `curl ... | sh -s -- ...`): --dry-run, --no-open, --no-blender, -h
#
# The app is ad-hoc signed, not notarized. Files downloaded with curl carry no quarantine flag, so it
# opens without a Gatekeeper prompt. The flag is removed anyway, but only after the hash matches.

REPO=ganya002/farm-mac
VERSION=__VERSION__
APP_SHA256=__APP_SHA256__
BLENDER_VERSION=5.3.0
BLENDER_SHA256=2d802b54766741e612cead50b03ebbc8eb64dadc71eda932573d256b8a784720
BLENDER_URL=https://download.blender.org/release/Blender5.3/blender-5.3.0-macos-arm64.dmg
APP_NAME="Render Farm.app"

# --- looks ---------------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  ROSE=$(printf '\033[38;5;211m'); DIM=$(printf '\033[2m'); BOLD=$(printf '\033[1m')
  GREEN=$(printf '\033[38;5;114m'); RED=$(printf '\033[38;5;203m'); OFF=$(printf '\033[0m')
  TTY=1
else
  ROSE=""; DIM=""; BOLD=""; GREEN=""; RED=""; OFF=""; TTY=0
fi
STEP=0
STEPS=3

step() { STEP=$((STEP + 1)); printf '\n%s%s[%d/%d]%s %s%s%s\n' "$ROSE" "$BOLD" "$STEP" "$STEPS" "$OFF" "$BOLD" "$1" "$OFF"; }
ok() { printf '      %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
note() { printf '      %s%s%s\n' "$DIM" "$1" "$OFF"; }
die() { printf '\n%s✗ %s%s\n' "$RED" "$1" "$OFF" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then note "would run: $*"; else "$@"; fi; }

mb() { awk -v b="$1" 'BEGIN { printf "%.0f MB", b / 1048576 }'; }

# One line that redraws: ▕████████░░░░░░░░▏  52%   187 MB / 360 MB
draw() {
  done_=$1; total=$2; width=28
  if [ "$total" -gt 0 ]; then pct=$((done_ * 100 / total)); [ "$pct" -gt 100 ] && pct=100; else pct=0; fi
  fill=$((pct * width / 100))
  bar=$(awk -v f="$fill" -v w="$width" 'BEGIN { s = ""; for (i = 0; i < w; i++) s = s (i < f ? "█" : "░"); print s }')
  printf '\r      %s▕%s%s%s▏%s %3d%%  %s%s / %s%s  ' "$DIM" "$OFF$ROSE" "$bar" "$OFF$DIM" "$OFF" "$pct" "$DIM" "$(mb "$done_")" "$(mb "$total")" "$OFF"
}

# download URL FILE: curl in the background, bar redrawn from the file's size.
download() {
  url=$1; out=$2
  total=$(curl -fsSLI "$url" | awk 'tolower($1) == "content-length:" { n = $2 } END { gsub(/\r/, "", n); print n + 0 }')
  if [ "$TTY" = 0 ]; then curl -fsSL -o "$out" "$url" || return 1; return 0; fi
  curl -fsSL -o "$out" "$url" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    have=$(stat -f %z "$out" 2>/dev/null || echo 0)
    draw "$have" "$total"
    sleep 0.15
  done
  wait "$pid"; status=$?
  [ "$status" = 0 ] && draw "$(stat -f %z "$out")" "$(stat -f %z "$out")"
  printf '\n'
  return "$status"
}

check_sha() {
  got=$(shasum -a 256 "$1" | awk '{ print $1 }')
  [ "$got" = "$2" ] || die "$(basename "$1") doesn't match its SHA-256 (got $got). Nothing was installed."
  ok "SHA-256 matches"
}

blender_version() {
  /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "/Applications/Blender.app/Contents/Info.plist" 2>/dev/null
}

# --- install -------------------------------------------------------------------------------------
main() {
  DRY=0; OPEN=1; BLENDER=1
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY=1 ;;
      --no-open) OPEN=0 ;;
      --no-blender) BLENDER=0 ;;
      -h|--help) sed -n '2,11p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "Unknown option: $arg" ;;
    esac
  done

  printf '\n%s%s  ✿ Render Farm for Mac%s %s%s%s\n' "$ROSE" "$BOLD" "$OFF" "$DIM" "v$VERSION" "$OFF"
  printf '  %sSends your Blender files to the school farm, textures and all.%s\n' "$DIM" "$OFF"
  [ "$DRY" = 1 ] && printf '  %sDry run: nothing will change.%s\n' "$DIM" "$OFF"

  case "$VERSION$APP_SHA256" in *__*) die "This is the unreleased install.sh. Use the one from a GitHub release." ;; esac
  [ "$(uname -m)" = arm64 ] || die "This Mac has an Intel chip. Render Farm needs Apple Silicon."
  major=$(sw_vers -productVersion | cut -d. -f1)
  [ "$major" -ge 26 ] || die "Render Farm needs macOS 26 or newer. This Mac has $(sw_vers -productVersion)."
  [ -w /Applications ] || die "You can't write to /Applications. Sign in as an administrator and run this again."

  TMP=$(mktemp -d "${TMPDIR:-/tmp}/renderfarm.XXXXXX") || die "Couldn't make a temporary folder."
  trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM

  step "Blender $BLENDER_VERSION"
  have=$(blender_version)
  if [ "$have" = "$BLENDER_VERSION" ]; then
    ok "Already installed"
  elif [ "$BLENDER" = 0 ]; then
    note "Skipped (--no-blender). Found: ${have:-none}"
  else
    [ -n "$have" ] && note "Found Blender $have. The farm uses $BLENDER_VERSION, so it gets replaced (your settings stay)."
    if [ "$DRY" = 1 ]; then
      note "would download $BLENDER_URL and install it in /Applications"
    else
      download "$BLENDER_URL" "$TMP/blender.dmg" || die "Blender didn't download. Check the Wi-Fi and run this again."
      check_sha "$TMP/blender.dmg" "$BLENDER_SHA256"
      hdiutil attach -quiet -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/blender.dmg" || die "Couldn't open the Blender disk image."
      [ -d "$TMP/mnt/Blender.app" ] || die "The Blender disk image has no Blender.app."
      pkill -x Blender 2>/dev/null && note "Closed Blender"
      rm -rf "/Applications/Blender.app"
      ditto "$TMP/mnt/Blender.app" "/Applications/Blender.app" || die "Couldn't copy Blender to /Applications."
      hdiutil detach -quiet "$TMP/mnt"
      ok "Installed Blender $(blender_version)"
    fi
  fi

  step "Render Farm app"
  zip="RenderFarm-$VERSION-arm64.zip"
  url="https://github.com/$REPO/releases/download/v$VERSION/$zip"
  if [ "$DRY" = 1 ]; then
    note "would download $url"
  else
    download "$url" "$TMP/$zip" || die "The app didn't download. Check the Wi-Fi and run this again."
    check_sha "$TMP/$zip" "$APP_SHA256"
    ditto -x -k "$TMP/$zip" "$TMP/app" || die "Couldn't unpack the app."
    [ -d "$TMP/app/$APP_NAME" ] || die "The download has no $APP_NAME."
    xattr -dr com.apple.quarantine "$TMP/app/$APP_NAME" 2>/dev/null
  fi

  step "Install"
  if [ "$DRY" = 1 ]; then
    note "would replace /Applications/$APP_NAME and open it"
  else
    pkill -x FarmMac 2>/dev/null && note "Closed the old version"
    rm -rf "/Applications/$APP_NAME"
    ditto "$TMP/app/$APP_NAME" "/Applications/$APP_NAME" || die "Couldn't copy the app to /Applications."
    ok "/Applications/$APP_NAME"
    [ "$OPEN" = 1 ] && run open "/Applications/$APP_NAME" && ok "Opened. Allow it on the local network when macOS asks."
  fi
  printf '\n%s✿ Done.%s Sign in with your farm account, pick a .blend and press %sSend to farm%s.\n\n' "$ROSE$BOLD" "$OFF" "$BOLD" "$OFF"
}

# Last line on purpose: a download cut short stops before main, so it can't install halfway.
main "$@"
