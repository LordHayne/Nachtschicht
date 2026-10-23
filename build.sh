#!/bin/bash
# Builds Nachtschicht.app. With --install it is copied to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

# The Command Line Tools ship without SwiftUI's macro plugins, so @State fails against the
# macOS 27 SDK. Without Xcode, fall back to the 26.5 SDK they still include.
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi

APP="Nachtschicht"
OUT="build/$APP.app"

echo "▸ Compiling (release, Apple Silicon) …"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "▸ Building app bundle …"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/$APP" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
# Offline fallback for the component list; the app prefers the online copy once it's published.
cp components/manifest.json "$OUT/Contents/Resources/manifest.json"

# Steam's browser needs this wrapper under Wine (see wrapper/steamwebhelper-wrapper.c).
# Rebuilt when mingw-w64 is installed, otherwise the checked-in build is used.
MINGW="$(command -v x86_64-w64-mingw32-gcc || true)"
if [ -n "$MINGW" ]; then
  "$MINGW" -O2 -Wall -Wextra -municode -mwindows -static \
    -o wrapper/steamwebhelper.exe wrapper/steamwebhelper-wrapper.c
fi
cp wrapper/steamwebhelper.exe "$OUT/Contents/Resources/steamwebhelper.exe"

# Keeps the background Steam out of the Dock (x86_64, loaded into Wine processes).
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -framework AppKit -Wall \
  -o "$OUT/Contents/Resources/hide-steam-dock.dylib" wrapper/hide-steam-dock.m

if [ -f Resources/AppIcon.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# Local ad-hoc signature so macOS launches the app without a developer account
codesign --force --deep --sign - "$OUT" >/dev/null
echo "✓ Done: $OUT"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$APP.app"
  cp -R "$OUT" "$HOME/Applications/"
  echo "✓ Installed: ~/Applications/$APP.app"
  open "$HOME/Applications/$APP.app"
fi
