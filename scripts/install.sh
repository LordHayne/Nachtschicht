#!/bin/bash
# Installs or updates Nightforge from its newest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/LordHayne/Nightforge/main/scripts/install.sh | bash
#
# Downloaded this way the app carries no quarantine flag, so macOS opens it without the
# "can't be verified" detour (Nightforge is free and not registered with Apple).
# NIGHTFORGE_ZIP (a local zip) and NIGHTFORGE_INSTALL_DIR are for testing.
set -euo pipefail

REPO="LordHayne/Nightforge"
APP="Nightforge.app"

fail() { echo "✗ $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Nightforge runs on macOS only."
[ "$(uname -m)" = "arm64" ] || fail "Nightforge needs a Mac with Apple silicon (M1 or newer)."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Nightforge needs macOS 14 Sonoma or newer."

if [ -n "${NIGHTFORGE_INSTALL_DIR:-}" ]; then
  target="$NIGHTFORGE_INSTALL_DIR"
elif [ -w /Applications ]; then
  target="/Applications"
else
  target="$HOME/Applications"
fi
mkdir -p "$target"

work="$(mktemp -d)"
trap 'rm -rf -- "${work:?}"' EXIT

if [ -n "${NIGHTFORGE_ZIP:-}" ]; then
  cp "$NIGHTFORGE_ZIP" "$work/Nightforge.zip"
else
  echo "▸ Looking for the newest version …"
  url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*Nightforge-[^"]*\.zip"' | head -1 | cut -d'"' -f4)"
  [ -n "$url" ] || fail "No release found. Check your internet connection and try again."
  echo "▸ Downloading ${url##*/} …"
  curl -fL --progress-bar -o "$work/Nightforge.zip" "$url"
fi

ditto -x -k "$work/Nightforge.zip" "$work/unpacked"
[ -d "$work/unpacked/$APP" ] || fail "The download is incomplete. Please try again."

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "io.github.lordhayne.nightforge" to quit' >/dev/null 2>&1 || true
# Nightforge's earlier name: replaced by this install (its data moves over on first start).
osascript -e 'tell application id "local.thomas.nachtschicht" to quit' >/dev/null 2>&1 || true
sleep 1

rm -rf -- "${target:?}/$APP" "${target:?}/Nachtschicht.app"
ditto "$work/unpacked/$APP" "$target/$APP"
xattr -dr com.apple.quarantine "$target/$APP" 2>/dev/null || true

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
echo "✓ Nightforge $version installed in $target"
[ -n "${NIGHTFORGE_NO_OPEN:-}" ] || open "$target/$APP"
