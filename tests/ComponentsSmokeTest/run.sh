#!/bin/bash
# Compiles ComponentStore with the smoke test and runs it from the repo root (no network needed).
set -euo pipefail
cd "$(dirname "$0")/../.."

CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi

OUT="$(mktemp -d)/components-smoke"
swiftc -o "$OUT" \
  Sources/Nachtschicht/Components.swift \
  Sources/Nachtschicht/Strings.swift \
  tests/ComponentsSmokeTest/main.swift
"$OUT"
