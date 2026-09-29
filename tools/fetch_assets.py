"""
Download every 3D model listed in tools/assets_manifest.json into assets/.

    python tools/fetch_assets.py            # skips files that already exist
    python tools/fetch_assets.py --force    # re-download everything

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

manifest = json.loads((ROOT / "tools/assets_manifest.json").read_text())
force = "--force" in sys.argv
failed = []
count = 0
for group, folder in FOLDERS.items():
    out_dir = ROOT / "assets" / folder
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, url in manifest.get(group, {}).items():
        suffix = {"babies": "_Baby", "juveniles": "_Juvenile"}.get(group, "")
        filename = f"{name}{suffix}.glb"
        out = out_dir / filename
        if out.exists() and not force:
            continue
        print(f"{group:9} {filename}")
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "hatch-and-snatch-assets"})
            with urllib.request.urlopen(request, timeout=120) as response:
                out.write_bytes(response.read())
            count += 1
        except Exception as error:  # keep going; report at the end
            print(f"  FAILED: {error}")
            failed.append(filename)

print(f"downloaded {count} file(s)." + (f" FAILED: {', '.join(failed)}" if failed else ""))
