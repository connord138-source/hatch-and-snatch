"""
Auto-rig a Tripo/Higgsfield creature GLB for Roblox (Blender 4.x, runs headless).

    blender --background --python tools/blender/rig_creature.py -- IN.glb OUT.fbx BODYPLAN [FRONT]

  BODYPLAN  one of the body plans in src/shared/Config/Creatures.luau (e.g. lean-predator)
  FRONT     auto | flip | +x | -x | +y | -y  — auto squares the body up and guesses which
            end is the head; flip does the same but takes the other end (for a wrong guess);
            an axis says where the head points in the GLB as imported (no squaring)

What it does
  1. Imports the GLB, joins all meshes, centers it on the ground.
  2. Squares the body up (Tripo keeps the concept's three-quarter turn, so bodies often
     come in 20-35 degrees off-axis), guesses which end is the head (override with
     FRONT), then rotates so the head points -Y (becomes -Z / "front" in Roblox).
  3. Finds the four feet from the lowest vertices and builds a quadruped skeleton:
     Root > Hips > Spine > Chest > Neck > Head, Tail1-3, and a 2-bone leg per foot
     (LegFL/FR/BL/BR _Upper/_Lower). Bone names are what CreatureAnimator drives.
  4. Skins every vertex to its nearest bones (inverse-distance, max 4 influences),
     which is more reliable on AI-generated meshes than Blender's bone-heat weights.
  5. Exports an FBX with embedded textures, ready for Studio's 3D Importer.

Batch: see rig_all.py. Results vary per model — always check a model in Studio.
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector

# ---------- args ----------
argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
if len(argv) < 3:
    print("usage: blender --background --python rig_creature.py -- IN.glb OUT.fbx BODYPLAN [FRONT]")
    sys.exit(1)
IN_PATH, OUT_PATH, BODY_PLAN = argv[0], argv[1], argv[2]
FRONT = argv[3] if len(argv) > 3 else "auto"

# Per-body-plan skeleton proportions (fractions of height H / length L)
PLANS = {
    "default": dict(hip=0.55, neck=0.78, head=0.82, tail=0.55, legs=True),
    "low-long": dict(hip=0.45, neck=0.55, head=0.55, tail=0.35, legs=True),
    "shelled": dict(hip=0.40, neck=0.45, head=0.50, tail=0.25, legs=True),
    "heavy-tank": dict(hip=0.55, neck=0.70, head=0.72, tail=0.50, legs=True),
    "small-round": dict(hip=0.45, neck=0.70, head=0.78, tail=0.40, legs=True),
    "hopper": dict(hip=0.45, neck=0.80, head=0.90, tail=0.30, legs=True),
    "upright-bandit": dict(hip=0.40, neck=0.85, head=0.92, tail=0.45, legs=True),
    "big-floppy": dict(hip=0.45, neck=0.60, head=0.65, tail=0.40, legs=True),
}
plan = {**PLANS["default"], **PLANS.get(BODY_PLAN, {})}

# ---------- import + normalize ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN_PATH)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    print("no mesh in", IN_PATH)
    sys.exit(2)

bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
body.data.transform(body.matrix_world)  # bake the import transform into the mesh
body.matrix_world = Matrix.Identity(4)
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)


def verts_world():
    return [body.matrix_world @ v.co for v in body.data.vertices]


def bounds(vs):
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


vs = verts_world()


def square_up():
    """Turn the mesh about Z so its main horizontal axis (by PCA) runs along Y."""
    n = len(vs)
    cx, cy = sum(v.x for v in vs) / n, sum(v.y for v in vs) / n
    sxx = sum((v.x - cx) ** 2 for v in vs) / n
    syy = sum((v.y - cy) ** 2 for v in vs) / n
    sxy = sum((v.x - cx) * (v.y - cy) for v in vs) / n
    spread = math.sqrt(((sxx - syy) / 2) ** 2 + sxy**2)
    major, minor = (sxx + syy) / 2 + spread, (sxx + syy) / 2 - spread
    if major < 1.15 * max(minor, 1e-9):
        return 0.0  # too round to tell; keep the bounding-box axis below
    theta = 0.5 * math.atan2(2 * sxy, sxx - syy)  # main axis angle from +X
    turn = math.pi / 2 - theta  # smallest turn that lays it along Y
    if turn > math.pi / 2:
        turn -= math.pi
    body.data.transform(Matrix.Rotation(turn, 4, "Z"))
    return turn


if FRONT in ("auto", "flip"):
    turned = square_up()
    print(f"[rig] squared up by {math.degrees(turned):.0f} degrees")
    vs = verts_world()
mn, mx = bounds(vs)
size = mx - mn
long_axis = "x" if size.x >= size.y else "y"


def head_sign_auto():
    """Head end = the end of the long axis whose outer slice has the higher average height."""
    axis = 0 if long_axis == "x" else 1
    lo, hi = mn[axis], mx[axis]
    span = hi - lo
    low_end = [v.z for v in vs if v[axis] < lo + 0.2 * span]
    high_end = [v.z for v in vs if v[axis] > hi - 0.2 * span]
    avg = lambda a: sum(a) / max(len(a), 1)
    return 1 if avg(high_end) >= avg(low_end) else -1


if FRONT in ("auto", "flip"):
    sign = head_sign_auto() * (-1 if FRONT == "flip" else 1)
    front_axis = long_axis
else:
    front_axis = FRONT[1]
    sign = 1 if FRONT[0] == "+" else -1
print(f"[rig] long axis {long_axis}, head toward {'+' if sign > 0 else '-'}{front_axis}")

# Rotate so the head points -Y
if front_axis == "x":
    angle = -math.pi / 2 if sign > 0 else math.pi / 2  # +x -> -y is -90° about Z
else:
    angle = math.pi if sign > 0 else 0.0  # +y -> -y is 180°
# Transform the mesh data directly: operators depend on selection/context state
body.data.transform(Matrix.Rotation(angle, 4, "Z"))

# Center on ground
vs = verts_world()
mn, mx = bounds(vs)
center = (mn + mx) / 2
body.data.transform(Matrix.Translation((-center.x, -center.y, -mn.z)))
body.data.update()
vs = verts_world()
mn, mx = bounds(vs)
W, L, H = mx.x - mn.x, mx.y - mn.y, mx.z - mn.z
print(f"[rig] size W={W:.2f} L={L:.2f} H={H:.2f}")

# ---------- find feet ----------
# Feet = vertices touching the ground. A low belly or hanging fur sits a little
# higher, so start with a thin slice and only widen it if a quadrant comes up empty.
quadrants = {"FL": [], "FR": [], "BL": [], "BR": []}
for band in (0.05, 0.1, 0.18):
    quadrants = {"FL": [], "FR": [], "BL": [], "BR": []}
    low = [v for v in vs if v.z < band * H]
    for v in low:
        # Facing -Y, +X is the creature's left
        quadrants[("F" if v.y < 0 else "B") + ("L" if v.x > 0 else "R")].append(v)
    if all(len(pts) >= 5 for pts in quadrants.values()):
        break
feet = {}
leg_radius = {}
for key, pts in quadrants.items():
    if len(pts) >= 5:
        feet[key] = Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), 0))
        # How thick this leg is at the bottom: 80th percentile distance from its center
        dists = sorted(((p.x - feet[key].x) ** 2 + (p.y - feet[key].y) ** 2) ** 0.5 for p in pts)
        leg_radius[key] = max(dists[int(len(dists) * 0.8)], 0.04 * min(W, L))
    else:
        fx = 0.25 * W * (1 if key[1] == "L" else -1)
        fy = 0.25 * L * (-1 if key[0] == "F" else 1)
        feet[key] = Vector((fx, fy, 0))
        leg_radius[key] = 0.08 * min(W, L)
print("[rig] feet", {k: tuple(round(c, 2) for c in v) for k, v in feet.items()})

# ---------- armature ----------
arm_data = bpy.data.armatures.new("Rig")
arm = bpy.data.objects.new("Rig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones


def bone(name, head, tail, parent=None, connect=False):
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


hipZ, neckZ, headZ, tailZ = plan["hip"] * H, plan["neck"] * H, plan["head"] * H, plan["tail"] * H
rearY = 0.22 * L
chestY = -0.18 * L
bone("Root", (0, 0, 0), (0, 0, 0.15 * H))
bone("Hips", (0, rearY, hipZ), (0, 0.02 * L, hipZ * 1.03), "Root")
bone("Spine", (0, 0.02 * L, hipZ * 1.03), (0, chestY, hipZ * 1.06), "Hips", True)
bone("Chest", (0, chestY, hipZ * 1.06), (0, -0.26 * L, (hipZ + neckZ) / 2), "Spine", True)
bone("Neck", (0, -0.26 * L, (hipZ + neckZ) / 2), (0, -0.36 * L, neckZ), "Chest", True)
bone("Head", (0, -0.36 * L, neckZ), (0, -0.5 * L, headZ), "Neck", True)
bone("Tail1", (0, rearY, tailZ), (0, 0.32 * L, tailZ * 1.02), "Hips")
bone("Tail2", (0, 0.32 * L, tailZ * 1.02), (0, 0.42 * L, tailZ * 1.05), "Tail1", True)
bone("Tail3", (0, 0.42 * L, tailZ * 1.05), (0, 0.5 * L, tailZ * 1.1), "Tail2", True)
for key, foot in feet.items():
    parent = "Chest" if key[0] == "F" else "Hips"
    top = Vector((foot.x * 0.85, foot.y, hipZ * 0.95))
    knee = Vector((foot.x, foot.y, hipZ * 0.45))
    bone(f"Leg{key}_Upper", top, knee, parent)
    bone(f"Leg{key}_Lower", knee, (foot.x, foot.y, 0.02 * H), f"Leg{key}_Upper", True)

bone_segments = {b.name: (b.head.copy(), b.tail.copy()) for b in eb if b.name != "Root"}
bpy.ops.object.mode_set(mode="OBJECT")

# ---------- skinning (nearest bones, inverse distance) ----------


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def allowed(name, p):
    """Legs only skin their own column of vertices: below the belly line and within
    the leg's thickness of its foot. Anything else (a low belly, fur or armor
    hanging between the legs) stays on the body, so a leg swing can't stretch it
    into strings or drag the head or the opposite leg along."""
    if not name.startswith("Leg"):
        return True
    key = name[3:5]
    fb, lr = key[0], key[1]
    if (p.y < 0) != (fb == "F") or (p.x > 0) != (lr == "L"):
        return False
    if p.z >= hipZ * 0.85:
        return False
    foot = feet[key]
    # The column widens a little toward the hip, where the leg meets the body
    reach = leg_radius[key] * (1.6 + 0.8 * (p.z / max(hipZ, 1e-6)))
    return ((p.x - foot.x) ** 2 + (p.y - foot.y) ** 2) ** 0.5 <= reach


groups = {name: body.vertex_groups.new(name=name) for name in bone_segments}
for i, v in enumerate(body.data.vertices):
    p = body.matrix_world @ v.co
    candidates = [(seg_dist(p, a, b), name) for name, (a, b) in bone_segments.items() if allowed(name, p)]
    dists = sorted(candidates)[:4]
    ws = [(1.0 / max(d, 1e-4) ** 4, name) for d, name in dists]
    total = sum(w for w, _ in ws)
    for w, name in ws:
        if w / total > 0.02:
            groups[name].add([i], w / total, "REPLACE")

mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
body.parent = arm

# ---------- export ----------
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.fbx(
    filepath=OUT_PATH,
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    add_leaf_bones=False,
    bake_anim=False,
    axis_forward="-Z",
    axis_up="Y",
    # Bake the Z-up -> Y-up conversion into the mesh and bones. Without it the
    # conversion is only a root transform, which Studio's importer drops for
    # skinned meshes: every creature came in rotated 90°, standing on its head.
    bake_space_transform=True,
    apply_scale_options="FBX_SCALE_ALL",
    path_mode="COPY",
    embed_textures=True,
)
print("[rig] wrote", OUT_PATH)
