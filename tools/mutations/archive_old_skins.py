"""Archives the old pink mutation-skin images on Roblox through Open Cloud
(POST /assets/v1/assets/{id}:archive; undo with :restore). Creator Hub has no
Archive for Images, so this is the only way.

    $env:ROBLOX_API_KEY = Read-Host -MaskInput "Open Cloud key"   # PowerShell 7
    python tools/mutations/archive_old_skins.py --check    # read-only: what would be archived
    python tools/mutations/archive_old_skins.py --test     # archives 84739040638074 only, then checks it
    python tools/mutations/archive_old_skins.py            # the rest, about 2 a second

The key needs the Assets API with Read and Write (asset:read, asset:write) and is
read from ROBLOX_API_KEY only: it is never printed or written anywhere. Delete it in
Creator Hub (Open Cloud > API Keys) when done.

Only ids listed in old_skin_images_2026-10-03.csv are touched (the 462 images the
morning's cut-off import uploaded, 2026-10-03 07:37-07:44 EDT), and each one is
checked first: an Image named Albino, Melanistic, Piebald, Chimera or Iridescent,
created in that window by the owner. Anything else is skipped and logged. The
DiamondGem/DiamondStone maps are excluded by id as well. Any 4xx other than a 429
rate limit stops the run (the endpoint refusing Images means carrying on without
archiving). Every id and its result goes to archive_log.csv next to this file.
"""

from __future__ import annotations

import argparse
import csv
import datetime
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
IDS = HERE / "old_skin_images_2026-10-03.csv"
LOG = HERE / "archive_log.csv"
API = "https://apis.roblox.com/assets/v1/assets/"
OWNER = "10860839150"  # Dillionaire138
NAMES = {"Albino", "Melanistic", "Piebald", "Chimera", "Iridescent"}
TEST_ID = "84739040638074"  # the Chimera atlas that got the account suspended
# 2026-10-03 07:37-07:45 EDT (UTC-4)
WINDOW = (
    datetime.datetime(2026, 10, 3, 11, 37, tzinfo=datetime.timezone.utc),
    datetime.datetime(2026, 10, 3, 11, 45, tzinfo=datetime.timezone.utc),
)
NEVER = {
    "83891185187480", "122955736534217", "79115828987523",  # DiamondGem maps
    "105342885317428", "87940945454649", "98779874609985",  # DiamondStone maps
}
PAUSE = 0.5  # seconds between assets


class Stop(Exception):
    pass


def request(method: str, url: str, key: str) -> tuple[int, dict]:
    for attempt in range(6):
        req = urllib.request.Request(url, method=method, headers={"x-api-key": key, "Accept": "application/json"})
        if method == "POST":
            req.add_header("Content-Type", "application/json")
            req.data = b"{}"
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read()
                return resp.status, (json.loads(body) if body else {})
        except urllib.error.HTTPError as err:
            body = err.read()
            try:
                data = json.loads(body) if body else {}
            except ValueError:
                data = {"raw": body[:300].decode("utf-8", "replace")}
            if err.code == 429 and attempt < 5:
                wait = float(err.headers.get("Retry-After") or 5 * (attempt + 1))
                print(f"  429 rate limited, waiting {wait:.0f}s", flush=True)
                time.sleep(wait)
                continue
            return err.code, data
    return 429, {}


def created(asset: dict) -> datetime.datetime | None:
    stamp = asset.get("revisionCreateTime") or asset.get("createTime")
    if not stamp:
        return None
    stamp = stamp.rstrip("Z")[:26]  # trim to microseconds
    return datetime.datetime.fromisoformat(stamp).replace(tzinfo=datetime.timezone.utc)


def why_not(asset_id: str, asset: dict) -> str | None:
    """Why this asset must not be archived, or None when it is one of the old skins."""
    if asset_id in NEVER:
        return "excluded id"
    if str(asset.get("assetType", "")).lower() not in ("image", "asset_type_image"):
        return f"type {asset.get('assetType')}"
    if asset.get("displayName") not in NAMES:
        return f"name {asset.get('displayName')!r}"
    creator = str((asset.get("creationContext") or {}).get("creator", {}).get("userId", ""))
    if creator != OWNER:
        return f"creator {creator or '?'}"
    when = created(asset)
    if when is None or not (WINDOW[0] <= when <= WINDOW[1]):
        return f"created {asset.get('revisionCreateTime')}"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="read-only: report what would be archived")
    ap.add_argument("--test", action="store_true", help=f"archive only {TEST_ID}, then confirm it")
    args = ap.parse_args()

    key = os.environ.get("ROBLOX_API_KEY", "").strip()
    if not key:
        print("Set ROBLOX_API_KEY first (see the top of this file).")
        return 2
    ids = [row["asset_id"] for row in csv.DictReader(open(IDS, newline=""))]
    if args.test:
        ids = [TEST_ID]
    elif TEST_ID in ids:
        ids.remove(TEST_ID)
        ids.insert(0, TEST_ID)  # already archived by --test: it just logs "already"

    new_log = not LOG.exists()
    log = open(LOG, "a", newline="")
    writer = csv.writer(log)
    if new_log:
        writer.writerow(["time", "asset_id", "result", "detail"])
    counts: dict[str, int] = {}

    def record(asset_id: str, result: str, detail: str = "") -> None:
        counts[result] = counts.get(result, 0) + 1
        writer.writerow([datetime.datetime.now().isoformat(timespec="seconds"), asset_id, result, detail])
        log.flush()
        print(f"{asset_id}: {result}{' - ' + detail if detail else ''}", flush=True)

    try:
        for index, asset_id in enumerate(ids):
            if index:
                time.sleep(PAUSE)
            status, asset = request("GET", API + asset_id, key)
            if status != 200:
                record(asset_id, f"get {status}", json.dumps(asset)[:200])
                if 400 <= status < 500 and status != 404:
                    raise Stop(f"GET refused with {status}")
                continue
            reason = why_not(asset_id, asset)
            if reason:
                record(asset_id, "skipped", reason)
                continue
            if str(asset.get("state", "")).lower() == "archived":
                record(asset_id, "already archived")
                continue
            if args.check:
                record(asset_id, "would archive", f"{asset.get('displayName')} {asset.get('revisionCreateTime')}")
                continue
            status, result = request("POST", API + asset_id + ":archive", key)
            if status != 200:
                record(asset_id, f"archive {status}", json.dumps(result)[:200])
                if 400 <= status < 500:
                    raise Stop(f"archive refused with {status}")
                continue
            state = str(result.get("state", ""))
            if state.lower() != "archived":
                _, again = request("GET", API + asset_id, key)
                state = str(again.get("state", ""))
            record(asset_id, "archived" if state.lower() == "archived" else f"state {state or '?'}")
            if asset_id == TEST_ID and state.lower() != "archived":
                raise Stop("the test asset did not come back archived")
    except Stop as stop:
        print(f"STOPPED: {stop}")
        return 1
    finally:
        log.close()
        print("summary:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
