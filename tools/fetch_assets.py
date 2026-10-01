"""
Download every 3D model listed in tools/assets_manifest.json into assets/.

    python tools/fetch_assets.py            # downloads what's new or whose link changed
    python tools/fetch_assets.py --force    # re-download everything

Each file's link is remembered in assets/.sources.json, so a model that was
replaced in the manifest (a new link) is downloaded again. A file with no record yet
(an older checkout) is compared by size with the server, so a replaced model is
caught there too.

Layout it creates (all gitignored):
    assets/glb/<SpeciesId>.glb, _Baby.glb, _Juvenile.glb           -> rig with tools/blender/rig_all.py
    assets/eggs/<BiomeId>.glb   (and Egg.glb, the tinted fallback) -> ReplicatedStorage.EggModels
    assets/props/<PropName>.glb                                    -> ReplicatedStorage.WorldProps
"""

import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
FOLDERS = {"creatures": "glb", "babies": "glb", "juveniles": "glb", "eggs": "eggs", "props": "props"}

def remote_size(url: str) -> int | None:
    """The file's size on the server (Content-Length), or None if it can't be read."""
    try:
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "hatch-and-snatch-assets"})
        with urllib.request.urlopen(request, timeout=30) as response:
            length = response.headers.get("Content-Length")
            return int(length) if length else None
    except Exception:
        return None


manifest = json.loads((ROOT / "tools/assets_manifest.json").read_text())
force = "--force" in sys.argv
SOURCES = ROOT / "assets" / ".sources.json"
sources = json.loads(SOURCES.read_text()) if SOURCES.exists() else {}
failed = []
count = 0
for group, folder in FOLDERS.items():
    out_dir = ROOT / "assets" / folder
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, url in manifest.get(group, {}).items():
        suffix = {"babies": "_Baby", "juveniles": "_Juvenile"}.get(group, "")
        filename = f"{name}{suffix}.glb"
        out = out_dir / filename
        key = f"{folder}/{filename}"
        if out.exists() and not force:
            known = sources.get(key)
            if known == url:
                continue
            # No record yet: current if it's the same size as the file behind the link
            if known is None and remote_size(url) in (None, out.stat().st_size):
                sources[key] = url
                continue
        print(f"{group:9} {filename}")
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "hatch-and-snatch-assets"})
            with urllib.request.urlopen(request, timeout=120) as response:
                out.write_bytes(response.read())
            sources[key] = url
            count += 1
        except Exception as error:  # keep going; report at the end
            print(f"  FAILED: {error}")
            failed.append(filename)

SOURCES.write_text(json.dumps(sources, indent=1, sort_keys=True))
print(f"downloaded {count} file(s)." + (f" FAILED: {', '.join(failed)}" if failed else ""))
