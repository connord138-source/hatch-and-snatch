"""Makes every creature model's mutation skins, ready for Studio (owner's PC).

    python tools/mutations/run_all.py                     # uses `blender` on PATH
    python tools/mutations/run_all.py "C:\\...\\blender.exe"
    python tools/mutations/run_all.py --only Emberlynx Emberlynx_Baby
    python tools/mutations/run_all.py --force             # redo everything

For each GLB in assets/glb/ (python tools/fetch_assets.py downloads them):

  1. bake_maps.py (Blender)  -> assets/skins/maps/<Model>.npz
  2. make_skins.py (Python: numpy, scipy, pillow) -> assets/skins/<Model>/<Mutation>.png
     with the eyes picked in tools/mutations/eyes.json
  3. pack_skins.py (Blender) -> assets/skins/glb/<Model>_Skins.glb

Then in Studio: File > Import 3D, select every assets/skins/glb/*_Skins.glb, and
paste tools/studio/organize_skins.luau into the Command Bar. A model is skipped
when its skins GLB is newer than its GLB, eyes.json and these scripts.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/mutations"
MUTATIONS = ["Albino", "Melanistic", "Piebald", "Chimera", "Iridescent"]

args = sys.argv[1:]
force = "--force" in args
only: set[str] = set()
if "--only" in args:
    only = set(args[args.index("--only") + 1 :])
    args = args[: args.index("--only")]
args = [a for a in args if a != "--force"]
BLENDER = args[0] if args else "blender"

plans = json.loads((ROOT / "tools/blender/bodyplans.json").read_text())
glb_dir = ROOT / "assets/glb"
out_root = ROOT / "assets/skins"
inputs = [HERE / name for name in ("bake_maps.py", "make_skins.py", "pack_skins.py", "eyes.json")]
newest_input = max(p.stat().st_mtime for p in inputs)


def front_of(stem: str) -> str:
    species = stem.removesuffix("_Baby").removesuffix("_Juvenile")
    plan = plans.get(species, {})
    key = "frontBaby" if stem.endswith("_Baby") else "frontJuvenile" if stem.endswith("_Juvenile") else "front"
    return plan.get(key, "auto")


def run(cmd: list[str]) -> bool:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout[-2000:], result.stderr[-2000:])
    return result.returncode == 0


failed = []
done = 0
for glb in sorted(glb_dir.glob("*.glb")):
    name = glb.stem
    if only and name not in only:
        continue
    packed = out_root / "glb" / f"{name}_Skins.glb"
    if (
        not force
        and packed.exists()
        and packed.stat().st_mtime > max(glb.stat().st_mtime, newest_input)
    ):
        continue
    maps = out_root / "maps" / f"{name}.npz"
    skins = out_root / name
    maps.parent.mkdir(parents=True, exist_ok=True)
    print(f"[{name}] bake ({front_of(name)})")
    ok = run([BLENDER, "-b", "--python", str(HERE / "bake_maps.py"), "--", str(glb), str(maps), front_of(name)])
    ok = ok and run([sys.executable, str(HERE / "make_skins.py"), str(maps), str(skins), *MUTATIONS])
    ok = ok and run([BLENDER, "-b", "--python", str(HERE / "pack_skins.py"), "--", str(glb), str(skins), str(packed)])
    if ok:
        done += 1
    else:
        failed.append(name)
        print(f"[{name}] FAILED")

print(f"Made skins for {done} model(s)." + (f" Failed: {', '.join(failed)}" if failed else ""))
print(f"Import {out_root / 'glb'} in Studio, then run tools/studio/organize_skins.luau.")
