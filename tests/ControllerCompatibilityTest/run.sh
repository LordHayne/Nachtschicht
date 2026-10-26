#!/bin/bash
# Checks which Mac games get macOS's synthetic Xbox 360 pad: tests/ControllerCompatibilityTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
WORK="$(mktemp -d)"
# Two stand-in games: an old one reading HID itself (universal, like most ports) and a modern one.
echo 'int main(void) { return 0; }' > "$WORK/game.c"
clang -arch x86_64 -arch arm64 -o "$WORK/old" "$WORK/game.c" -framework IOKit
clang -arch arm64 -o "$WORK/modern" "$WORK/game.c" -framework GameController
clang -arch x86_64 -dynamiclib -o "$WORK/libSDL2.dylib" "$WORK/game.c" -framework GameController
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$WORK/test" $SOURCES tests/ControllerCompatibilityTest/main.swift
"$WORK/test" "$WORK"
