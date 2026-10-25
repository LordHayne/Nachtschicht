#!/bin/bash
# Checks game analysis, the self-healing launch ladder and the log parsing:
# tests/LaunchHealthTest/run.sh [Steam folder]  (with a Steam folder it also analyses installed games)
set -euo pipefail
cd "$(dirname "$0")/../.."
CLT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$CLT_SDK" ]; then
  export SDKROOT="$CLT_SDK"
fi
OUT="$(mktemp -d)/launch-health-test"
# The whole app except its entry point, plus the test driver.
SOURCES=$(ls Sources/Nightforge/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
swiftc -parse-as-library -o "$OUT" $SOURCES tests/LaunchHealthTest/main.swift
"$OUT" "$@"
