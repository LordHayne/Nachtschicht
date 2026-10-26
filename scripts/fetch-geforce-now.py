#!/usr/bin/env python3
"""Fetches the GeForce Now game catalog for build-profiles.py --geforcenow.

GeForce Now's deep links (https://github.com/NVIDIAGameWorks/GeForceNOW-SDK, doc/GfnSdk-Deep-Linking.md)
need a game's id, a UUID. NVIDIA's public game list only has numeric ids, so this reads the catalog
GeForce Now's own web app uses, which has both the UUID and the Steam app ID of every game.

Usage: fetch-geforce-now.py <out.json> [--region NP-AMS-08]
"""

import argparse
import json
import pathlib
import sys
import urllib.request

URL = "https://games.geforce.com/graphql"
QUERY = """query($vpcId: String!, $after: String) {
  apps(vpcId: $vpcId, first: 1000, after: $after) {
    pageInfo { hasNextPage endCursor }
    items { id title variants { appStore storeId } }
  }
}"""


def fetch(region):
    games, after = [], None
    while True:
        body = json.dumps({"query": QUERY, "variables": {"vpcId": region, "after": after}}).encode()
        request = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            result = json.load(response)
        if result.get("errors"):
            raise RuntimeError(result["errors"])
        page = result["data"]["apps"]
        games += page["items"]
        if not page["pageInfo"]["hasNextPage"]:
            return games
        after = page["pageInfo"]["endCursor"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=pathlib.Path)
    # A European data centre; the catalog differs little between regions.
    parser.add_argument("--region", default="NP-AMS-08")
    options = parser.parse_args()
    games = fetch(options.region)
    options.out.write_text(json.dumps(games, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(games)} GeForce Now games → {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
