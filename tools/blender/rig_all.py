"""
Rig every creature GLB in assets/glb/ (<SpeciesId>.glb, <SpeciesId>_Baby.glb, <SpeciesId>_Juvenile.glb)
into assets/fbx/ with the same name.

    python tools/blender/rig_all.py            # uses `blender` on PATH
    python tools/blender/rig_all.py "C:\\Program Files\\Blender Foundation\\Blender 4.2\\blender.exe"

Body plans and head-direction overrides come from tools/blender/bodyplans.json: "front"
for the adult, "frontBaby" and "frontJuvenile" for the other stages (each GLB has its own
orientation). "auto" squares the body up and guesses the head end; "flip" takes the other
end when that guess is wrong (a raised tail club or tuft fools it). Rerun after a change.
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
    species = glb.stem.removesuffix("_Baby").removesuffix("_Juvenile")
    if species not in plans:
        print(f"skip {glb.name}: not a species id in bodyplans.json")
        continue
    entry = plans[species]
    stage = "Baby" if glb.stem.endswith("_Baby") else "Juvenile" if glb.stem.endswith("_Juvenile") else ""
    front = entry.get(f"front{stage}", "auto")  # "front" (adult), "frontBaby", "frontJuvenile"
    out = fbx_dir / f"{glb.stem}.fbx"
    cmd = [BLENDER, "--background", "--python", str(ROOT / "tools/blender/rig_creature.py"), "--",
           str(glb), str(out), entry["bodyPlan"], front]
    print(">>", glb.stem)
    if subprocess.run(cmd).returncode != 0 or not out.exists():
        failed.append(glb.stem)

print("done." + (f" FAILED: {', '.join(failed)}" if failed else " all rigged."))
