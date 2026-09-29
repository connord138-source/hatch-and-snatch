"""
Rig every creature GLB in assets/glb/ (named <SpeciesId>.glb or <SpeciesId>_Baby.glb)
into assets/fbx/ with the same name.

    python tools/blender/rig_all.py            # uses `blender` on PATH
    python tools/blender/rig_all.py "C:\\Program Files\\Blender Foundation\\Blender 4.2\\blender.exe"

Body plans and head-direction overrides come from tools/blender/bodyplans.json.
If a creature comes out facing backwards, set its "front" there (+x, -x, +y, -y) and rerun.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BLENDER = sys.argv[1] if len(sys.argv) > 1 else "blender"
plans = json.loads((ROOT / "tools/blender/bodyplans.json").read_text())
glb_dir, fbx_dir = ROOT / "assets/glb", ROOT / "assets/fbx"
fbx_dir.mkdir(parents=True, exist_ok=True)

failed = []
for glb in sorted(glb_dir.glob("*.glb")):
    species = glb.stem.removesuffix("_Baby")
    if species not in plans:
        print(f"skip {glb.name}: not a species id in bodyplans.json")
        continue
    entry = plans[species]
    out = fbx_dir / f"{glb.stem}.fbx"
    cmd = [BLENDER, "--background", "--python", str(ROOT / "tools/blender/rig_creature.py"), "--",
           str(glb), str(out), entry["bodyPlan"], entry.get("front", "auto")]
    print(">>", glb.stem)
    if subprocess.run(cmd).returncode != 0 or not out.exists():
        failed.append(glb.stem)

print("done." + (f" FAILED: {', '.join(failed)}" if failed else " all rigged."))
