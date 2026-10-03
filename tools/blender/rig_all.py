"""
Rig every creature GLB in assets/glb/ (<SpeciesId>.glb, <SpeciesId>_Baby.glb, <SpeciesId>_Juvenile.glb)
into assets/fbx/ with the same name.

    python tools/blender/rig_all.py            # uses `blender` on PATH
    python tools/blender/rig_all.py "C:\\Program Files\\Blender Foundation\\Blender 4.2\\blender.exe"

Body plans and head-direction overrides come from tools/blender/bodyplans.json: "front"
for the adult, "frontBaby" and "frontJuvenile" for the other stages (each GLB has its own
orientation). "auto" squares the body up and guesses the head end; "flip" takes the other
end when that guess is wrong (a raised tail club or tuft fools it). Rerun after a change.

Only models that changed are rigged again: a new GLB, a different body plan or front
for that stage, or a new RIG_VERSION (remembered in assets/fbx/.rigged.json). --all
rigs everything.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
# Bump when rig_creature.py's output changes, so every model is rigged again.
# 2: weights smoothed along the surface (no more stringing at legs and tails).
# 3: feet found as ground patches, leg/body hand-over up by the hip, smarter 4-bone cap (no leg strings).
RIG_VERSION = 3
RIG_SCRIPT = ROOT / "tools/blender/rig_creature.py"
args = [a for a in sys.argv[1:] if a != "--all"]
BLENDER = args[0] if args else "blender"
EVERYTHING = "--all" in sys.argv
plans = json.loads((ROOT / "tools/blender/bodyplans.json").read_text())
glb_dir, fbx_dir = ROOT / "assets/glb", ROOT / "assets/fbx"
fbx_dir.mkdir(parents=True, exist_ok=True)
RIGGED = fbx_dir / ".rigged.json"
rigged = json.loads(RIGGED.read_text()) if RIGGED.exists() else {}

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
    signature = f"v{RIG_VERSION}|{entry['bodyPlan']}|{front}|{glb.stat().st_size}|{int(glb.stat().st_mtime)}"
    if not EVERYTHING and out.exists():
        # No record yet (rigged before .rigged.json existed): current if the FBX is newer
        # than both its GLB and the rig script
        known = rigged.get(glb.stem)
        newest = max(glb.stat().st_mtime, RIG_SCRIPT.stat().st_mtime)
        if known == signature or (known is None and out.stat().st_mtime >= newest):
            rigged[glb.stem] = signature
            continue
    cmd = [BLENDER, "--background", "--python", str(RIG_SCRIPT), "--",
           str(glb), str(out), entry["bodyPlan"], front]
    print(">>", glb.stem)
    if subprocess.run(cmd).returncode != 0 or not out.exists():
        failed.append(glb.stem)
    else:
        rigged[glb.stem] = signature
        RIGGED.write_text(json.dumps(rigged, indent=1, sort_keys=True))

RIGGED.write_text(json.dumps(rigged, indent=1, sort_keys=True))
print("done." + (f" FAILED: {', '.join(failed)}" if failed else " all rigged."))
