#!/bin/bash
# Installs or updates Nachtschicht from its newest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/LordHayne/Nachtschicht/main/scripts/install.sh | bash
#
# Downloaded this way the app carries no quarantine flag, so macOS opens it without the
# "can't be verified" detour (Nachtschicht is free and not registered with Apple).
# NACHTSCHICHT_ZIP (a local zip) and NACHTSCHICHT_INSTALL_DIR are for testing.
set -euo pipefail

REPO="LordHayne/Nachtschicht"
APP="Nachtschicht.app"

fail() { echo "✗ $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Nachtschicht runs on macOS only."
[ "$(uname -m)" = "arm64" ] || fail "Nachtschicht needs a Mac with Apple silicon (M1 or newer)."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Nachtschicht needs macOS 14 Sonoma or newer."

if [ -n "${NACHTSCHICHT_INSTALL_DIR:-}" ]; then
  target="$NACHTSCHICHT_INSTALL_DIR"
elif [ -w /Applications ]; then
  target="/Applications"
else
  target="$HOME/Applications"
fi
mkdir -p "$target"

work="$(mktemp -d)"
trap 'rm -rf -- "${work:?}"' EXIT

if [ -n "${NACHTSCHICHT_ZIP:-}" ]; then
  cp "$NACHTSCHICHT_ZIP" "$work/Nachtschicht.zip"
else
  echo "▸ Looking for the newest version …"
  url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*Nachtschicht-[^"]*\.zip"' | head -1 | cut -d'"' -f4)"
  [ -n "$url" ] || fail "No release found. Check your internet connection and try again."
  echo "▸ Downloading ${url##*/} …"
  curl -fL --progress-bar -o "$work/Nachtschicht.zip" "$url"
fi

ditto -x -k "$work/Nachtschicht.zip" "$work/unpacked"
[ -d "$work/unpacked/$APP" ] || fail "The download is incomplete. Please try again."

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "local.thomas.nachtschicht" to quit' >/dev/null 2>&1 || true
sleep 1

rm -rf -- "${target:?}/$APP"
ditto "$work/unpacked/$APP" "$target/$APP"
xattr -dr com.apple.quarantine "$target/$APP" 2>/dev/null || true

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
echo "✓ Nachtschicht $version installed in $target"
[ -n "${NACHTSCHICHT_NO_OPEN:-}" ] || open "$target/$APP"
