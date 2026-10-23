#!/usr/bin/env python3
"""Checks components/manifest.json before it ships: the app trusts every url and sha256 in it."""

import json
import re
import sys
from pathlib import Path

MANIFEST = Path(__file__).resolve().parent.parent / "components" / "manifest.json"
KINDS = {"engine", "graphics", "tool"}
FIELDS = {"id", "kind", "version", "url", "sha256", "size", "license", "source"}


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    errors = []
    if manifest.get("schemaVersion") != 1:
        errors.append(f"unsupported schemaVersion {manifest.get('schemaVersion')}")

    seen = set()
    for c in manifest.get("components", []):
        name = c.get("id", "?")
        if missing := FIELDS - c.keys():
            errors.append(f"{name}: missing {sorted(missing)}")
            continue
        if name in seen:
            errors.append(f"{name}: duplicate id")
        seen.add(name)
        if c["kind"] not in KINDS:
            errors.append(f"{name}: unknown kind {c['kind']}")
        if not c["url"].startswith("https://"):
            errors.append(f"{name}: url must be https")
        if not re.fullmatch(r"[0-9a-f]{64}", c["sha256"]):
            errors.append(f"{name}: sha256 is not 64 hex characters")
        if not isinstance(c["size"], int) or c["size"] <= 0:
            errors.append(f"{name}: size must be a positive integer")

    if errors:
        sys.exit("\n".join(errors))
    print(f"manifest ok: {len(seen)} components")


if __name__ == "__main__":
    main()
