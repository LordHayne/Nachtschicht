#!/bin/bash
# Builds Nightforge.app. With --install it is copied to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

# The Command Line Tools ship without SwiftUI's macro plugins, so @State fails against the
# macOS 27 SDK. Without Xcode, fall back to the 26.5 SDK they still include.
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi

APP="Nightforge"
OUT="build/$APP.app"

echo "▸ Compiling (release, Apple Silicon) …"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "▸ Building app bundle …"
rm -rf "$OUT"
# The two languages Nightforge speaks: empty .lproj folders let macOS show its own menus, panels
# and text-field menus in German on a German Mac (the app's own text comes from Strings.swift).
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/en.lproj" "$OUT/Contents/Resources/de.lproj"
cp "$BIN_DIR/$APP" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
# Offline fallback for the component list; the app prefers the online copy once it's published.
cp components/manifest.json "$OUT/Contents/Resources/manifest.json"
# Same for the per-game fixes (scripts/build-profiles.py).
cp profiles/profiles.json "$OUT/Contents/Resources/profiles.json"
# Licences travel with the app: Nightforge's own (GPL-3.0) and the ones for the fixes data.
cp LICENSE "$OUT/Contents/Resources/LICENSE"
cp profiles/LICENSE-umu-protonfixes "$OUT/Contents/Resources/LICENSE-umu-protonfixes"
cp profiles/LICENSE-areweanticheatyet "$OUT/Contents/Resources/LICENSE-areweanticheatyet"
# What else is inside the app (Vulkan headers in the layer, the mingw runtime in the wrapper) and
# what Nightforge downloads, with their licences.
cp Resources/THIRD_PARTY_NOTICES.txt "$OUT/Contents/Resources/THIRD_PARTY_NOTICES.txt"
mkdir -p "$OUT/Contents/Resources/licenses"
cp wrapper/vulkan-headers/LICENSE.md "$OUT/Contents/Resources/licenses/Vulkan-Headers-LICENSE.md"
cp wrapper/vulkan-headers/Apache-2.0.txt wrapper/vulkan-headers/MIT.txt "$OUT/Contents/Resources/licenses/"

# Steam's browser needs this wrapper under Wine (see wrapper/steamwebhelper-wrapper.c).
# Rebuilt when mingw-w64 is installed, otherwise the checked-in build is used.
# (Built into the app bundle only; the checked-in binary is the one the GitHub workflow produces.)
MINGW="$(command -v x86_64-w64-mingw32-gcc || true)"
if [ -n "$MINGW" ]; then
  "$MINGW" -O2 -Wall -Wextra -municode -mwindows -static \
    -o "$OUT/Contents/Resources/steamwebhelper.exe" wrapper/steamwebhelper-wrapper.c
else
  cp wrapper/steamwebhelper.exe "$OUT/Contents/Resources/steamwebhelper.exe"
fi

# Keeps the background Steam out of the Dock (x86_64, loaded into Wine processes).
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -framework AppKit -Wall \
  -o "$OUT/Contents/Resources/hide-steam-dock.dylib" wrapper/hide-steam-dock.m

# Lets Windows games that render with Vulkan start on MoltenVK, and upscales them with MetalFX (x86_64,
# loaded by Wine's Vulkan loader).
# Its MetalFX upscaling is Objective-C (wrapper/nightforge-vulkan-metalfx.m); MetalFX is weak-linked for older Macs.
clang -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib -fvisibility=hidden -fobjc-arc -O2 -Wall \
  -I wrapper/vulkan-headers -I wrapper -framework Metal -framework QuartzCore -framework CoreGraphics -weak_framework MetalFX \
  -o "$OUT/Contents/Resources/nightforge-vulkan-layer.dylib" wrapper/nightforge-vulkan-layer.c wrapper/nightforge-vulkan-metalfx.m

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
  # `open` would only bring an already running copy to the front, so quit it first. Only when it
  # runs: AppleScript starts an app it is told to quit.
  if pgrep -qf "Applications/$APP.app/Contents/MacOS/$APP"; then
    osascript -e "tell application id \"io.github.lordhayne.nightforge\" to quit" >/dev/null 2>&1 || true
  fi
  pkill -f "$HOME/Applications/$APP.app/Contents/MacOS/$APP" 2>/dev/null || true
  rm -rf "$HOME/Applications/$APP.app"
  # Nightforge's earlier name: quit and replace it (its data moves over on first start).
  if pgrep -qf "Nachtschicht.app/Contents/MacOS/Nachtschicht"; then
    osascript -e 'tell application id "local.thomas.nachtschicht" to quit' >/dev/null 2>&1 || true
  fi
  pkill -f "$HOME/Applications/Nachtschicht.app/Contents/MacOS/Nachtschicht" 2>/dev/null || true
  rm -rf "$HOME/Applications/Nachtschicht.app"
  cp -R "$OUT" "$HOME/Applications/"
  echo "✓ Installed: ~/Applications/$APP.app"
  open "$HOME/Applications/$APP.app"
fi
