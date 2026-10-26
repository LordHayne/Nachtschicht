#!/bin/bash
# Checks that every text has a German translation and that none is listed twice:
# tests/StringsTest/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I tests/StringsTest/check.py .
