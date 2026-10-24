#!/usr/bin/env python3
"""Rebuilds components/manifest.json from the newest GitHub releases listed in components/sources.json.

Runs nightly in CI. Uses the sha256 digest GitHub publishes for release assets; files without one
(e.g. a script taken from a tag) are downloaded once and hashed. Set GITHUB_TOKEN to avoid rate limits.
"""

import hashlib
import json
import os
import re
import sys
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "components" / "sources.json"
MANIFEST = ROOT / "components" / "manifest.json"
SCHEMA_VERSION = 1


def request(url: str) -> urllib.request.Request:
    headers = {"User-Agent": "nightforge-components", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def get_json(url: str):
    with urllib.request.urlopen(request(url), timeout=30) as response:
        return json.load(response)


def hash_url(url: str) -> tuple[str, int]:
    digest, size = hashlib.sha256(), 0
    with urllib.request.urlopen(request(url), timeout=120) as response:
        while chunk := response.read(1 << 20):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def latest_release(repo: str, tag_prefix: str = "") -> dict:
    releases = get_json(f"https://api.github.com/repos/{repo}/releases?per_page=30")
    for release in releases:
        if not release["draft"] and not release["prerelease"] and release["tag_name"].startswith(tag_prefix):
            return release
    sys.exit(f"{repo}: no stable release found")


def build(source: dict) -> dict:
    repo = source["repo"]
    if "tag" in source:
        release = get_json(f"https://api.github.com/repos/{repo}/releases/tags/{source['tag']}")
    else:
        release = latest_release(repo, source.get("tagPrefix", ""))
    license_id = source.get("license") or (get_json(f"https://api.github.com/repos/{repo}").get("license") or {}).get("spdx_id") or "NOASSERTION"
    version = release["tag_name"].removeprefix(source.get("tagPrefix", "")).lstrip("v")

    if "file" in source:
        url = f"https://raw.githubusercontent.com/{repo}/{release['tag_name']}/{source['file']}"
        sha256, size = hash_url(url)
    else:
        pattern = re.compile(source["asset"])
        assets = [a for a in release["assets"] if pattern.search(a["name"])]
        if len(assets) != 1:
            sys.exit(f"{repo} {release['tag_name']}: expected one asset matching {source['asset']}, found {len(assets)}")
        asset = assets[0]
        url, size = asset["browser_download_url"], asset["size"]
        digest = asset.get("digest") or ""
        sha256 = digest.removeprefix("sha256:") if digest.startswith("sha256:") else hash_url(url)[0]

    return {
        "id": source["id"],
        "kind": source["kind"],
        "version": version,
        "url": url,
        "sha256": sha256,
        "size": size,
        "license": license_id,
        "source": f"https://github.com/{repo}",
    }


def main() -> None:
    sources = json.loads(SOURCES.read_text())["sources"]
    components = [build(s) for s in sources]

    previous = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    if previous.get("components") == components and previous.get("schemaVersion") == SCHEMA_VERSION:
        print("manifest unchanged")
        return

    manifest = {"schemaVersion": SCHEMA_VERSION, "generated": date.today().isoformat(), "components": components}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    for c in components:
        print(f"{c['id']:<12} {c['version']:<28} {c['size'] / 1048576:7.1f} MB  {c['license']}")


if __name__ == "__main__":
    main()
