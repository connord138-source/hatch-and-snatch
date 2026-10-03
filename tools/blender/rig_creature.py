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
  3. Finds the feet (patches of the mesh touching the ground, a front and a hind foot
     per side) and builds a quadruped skeleton: Root > Hips > Spine > Chest > Neck >
     Head, Tail1-3, and a 2-bone leg per foot (LegFL/FR/BL/BR _Upper/_Lower). Bone
     names are what CreatureAnimator drives.
  4. Skins the mesh. A smooth field along the surface decides how far each vertex
     follows a leg or the body, handing over up by the hip joints where a leg swing
     barely moves anything; within that, vertices go to their nearest bones (inverse
     distance), smoothed along the surface, and the front and hind legs (which swing
     opposite ways) never share a vertex. Max 4 influences: a dropped bone's weight goes
     to the kept bone next to it in the skeleton. More reliable on AI-generated meshes
     than Blender's bone-heat weights.
  5. Exports an FBX with embedded textures, ready for Studio's 3D Importer.

Batch: see rig_all.py. Results vary per model — always check a model in Studio.
"""

import heapq
import math
import sys

import bpy
import numpy as np  # ships with Blender
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

# ---------- mesh graph ----------
# glTF splits vertices along UV seams, so vertices at the same spot count as one
# node; otherwise the seams would tear open when the weights are smoothed.
verts = body.data.vertices
weld = {}
node_of = []
for v in verts:
    key = (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
    node_of.append(weld.setdefault(key, len(weld)))
nodes = len(weld)
members = [[] for _ in range(nodes)]
for i, n in enumerate(node_of):
    members[n].append(i)
node_pos = [body.matrix_world @ verts[m[0]].co for m in members]
links = [set() for _ in range(nodes)]
for e in body.data.edges:
    a, b = node_of[e.vertices[0]], node_of[e.vertices[1]]
    if a != b:
        links[a].add(b)
        links[b].add(a)

# ---------- find feet ----------
# Feet = patches of the mesh touching the ground. A low belly or hanging fur sits a
# little higher, so start with a thin slice and only widen it if a foot is missing.
# Each side (left/right of the body's middle) is split into a front and a hind foot
# by whole patches, never through one: the old quadrants cut at the bounding box's
# middle, which a long tail or neck moves, so a hind foot straddling it gave its toes
# to the front foot (whose column then swallowed the hind leg) and the run tore it in
# two. Toes a little apart count as one foot. A side with one foot keeps it for the
# hind leg when the other side has one too (a creature standing on two legs: the
# front legs are left empty), else for whichever end it lines up with; a leg missing
# on one side only (lifted off the ground) is mirrored from the other side.
LEG_KEYS = ("FL", "FR", "BL", "BR")
mid_x = sorted(p.x for p in node_pos)[nodes // 2]  # the body's middle, whatever the tail does
TOE_GAP = 0.05 * max(W, L)


def side_feet(low):
    """Group one side's ground nodes into feet (lists of nodes), sorted front to back."""
    low_set = set(low)
    patches, seen = [], set()
    for start in low:
        if start in seen:
            continue
        patch, stack = [], [start]
        seen.add(start)
        while stack:
            n = stack.pop()
            patch.append(n)
            for m in links[n]:
                if m in low_set and m not in seen:
                    seen.add(m)
                    stack.append(m)
        patches.append(patch)

    def gap(p, q):
        step_p, step_q = max(1, len(p) // 60), max(1, len(q) // 60)
        return min(
            ((node_pos[a].x - node_pos[b].x) ** 2 + (node_pos[a].y - node_pos[b].y) ** 2) ** 0.5
            for a in p[::step_p]
            for b in q[::step_q]
        )

    merged = True
    while merged and len(patches) > 1:
        merged = False
        for i in range(len(patches)):
            for j in range(i + 1, len(patches)):
                if gap(patches[i], patches[j]) < TOE_GAP:
                    patches[i] += patches.pop(j)
                    merged = True
                    break
            if merged:
                break
    # Specks (a fur tip, a claw) aren't feet
    biggest = max((len(p) for p in patches), default=0)
    patches = [p for p in patches if len(p) >= max(5, 0.15 * biggest)]

    def mean_y(patch):
        return sum(node_pos[n].y for n in patch) / len(patch)

    patches.sort(key=mean_y)
    if len(patches) <= 2:
        return patches
    # More than two: split front from back at the widest gap along the body
    ys = [mean_y(p) for p in patches]
    cut = max(range(1, len(patches)), key=lambda i: ys[i] - ys[i - 1])
    return [sum(patches[:cut], []), sum(patches[cut:], [])]


def find_feet(band):
    sides = {"L": [], "R": []}
    for n in range(nodes):
        if node_pos[n].z < band * H:
            sides["L" if node_pos[n].x > mid_x else "R"].append(n)
    found = {}
    per_side = {s: side_feet(low) for s, low in sides.items()}
    for s, fs in per_side.items():
        if len(fs) == 2:
            found["F" + s], found["B" + s] = fs
    for s, fs in per_side.items():
        if len(fs) != 1:
            continue
        other = "R" if s == "L" else "L"
        y = sum(node_pos[n].y for n in fs[0]) / len(fs[0])
        if "F" + other in found:
            fy = sum(node_pos[n].y for n in found["F" + other]) / len(found["F" + other])
            by = sum(node_pos[n].y for n in found["B" + other]) / len(found["B" + other])
            found[("F" if abs(y - fy) < abs(y - by) else "B") + s] = fs[0]
        else:
            found["B" + s] = fs[0]
    return found


best = {}
for band in (0.05, 0.1, 0.18):
    found = find_feet(band)
    if len(found) > len(best):
        best = found
    if len(best) == 4:
        break
feet = {}
leg_radius = {}
for key, pts in best.items():
    ps = [node_pos[n] for n in pts]
    feet[key] = Vector((sum(p.x for p in ps) / len(ps), sum(p.y for p in ps) / len(ps), 0))
    # How thick this leg is at the bottom: 80th percentile distance from its center
    dists = sorted(((p.x - feet[key].x) ** 2 + (p.y - feet[key].y) ** 2) ** 0.5 for p in ps)
    leg_radius[key] = max(dists[int(len(dists) * 0.8)], 0.04 * min(W, L))
empty_legs = set()
for key in LEG_KEYS:
    if key in feet:
        continue
    twin = key[0] + ("R" if key[1] == "L" else "L")
    if twin in best:
        # Lifted off the ground: mirror the other side's leg
        feet[key] = Vector((2 * mid_x - feet[twin].x, feet[twin].y, 0))
        leg_radius[key] = leg_radius[twin]
    else:
        # Not a leg at all (front legs of a creature standing on two): the bones still
        # exist for the animator, but no vertex follows them
        feet[key] = Vector((0.25 * W * (1 if key[1] == "L" else -1), 0.25 * L * (-1 if key[0] == "F" else 1), 0))
        leg_radius[key] = 0.08 * min(W, L)
        empty_legs.add(key)
feet = {key: feet[key] for key in LEG_KEYS}
print("[rig] feet", {k: tuple(round(c, 2) for c in v) for k, v in feet.items()}, "empty", sorted(empty_legs))

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

# ---------- skinning ----------


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def in_leg(key, p):
    """A leg's own column of vertices: below the belly line, within the leg's thickness
    of its foot and nearer its foot than any other's."""
    if key in empty_legs or p.z >= hipZ * 0.85:
        return False
    foot = feet[key]
    d = ((p.x - foot.x) ** 2 + (p.y - foot.y) ** 2) ** 0.5
    for other in LEG_KEYS:
        if other != key and other not in empty_legs:
            if ((p.x - feet[other].x) ** 2 + (p.y - feet[other].y) ** 2) ** 0.5 < d:
                return False
    # The column widens a little toward the hip, where the leg meets the body
    return d <= leg_radius[key] * (1.6 + 0.8 * (p.z / max(hipZ, 1e-6)))


def nearest(p, names):
    """Inverse-distance weights over the (up to) 4 nearest of these bones."""
    ds = sorted((seg_dist(p, *bone_segments[name]), name) for name in names)[:4]
    ws = {name: 1.0 / max(d, 1e-4) ** 4 for d, name in ds}
    total = sum(ws.values())
    return {name: w / total for name, w in ws.items()}


real_legs = [k for k in LEG_KEYS if k not in empty_legs]
column = [next((k for k in real_legs if in_leg(k, node_pos[n])), None) for n in range(nodes)]
body_bones = [name for name in bone_segments if not name.startswith("Leg")]

# How far each vertex follows the legs: u = +1 the front legs, -1 the hind legs, 0 the
# body. The feet are pinned to their legs; everything above the hip joints, and the
# head and tail, to the body; u is filled in between as smoothly as it can be (a
# harmonic fill along the surface) with every edge counted by its distance from the
# swinging hip, which is how far a unit of u moves it. So the hand-over from leg to
# body happens up by the joint, where a swing barely moves anything, not down along
# the belly and between the legs: nearest-bone weights put it there, and the bounding
# run pulled that skin into strings on short-legged, deep-bellied and baby bodies.
# The front and hind legs swing opposite ways, and u runs smoothly from one to the
# other through the body in between.
FOOT_PIN = 0.05 * hipZ  # this much of a leg's column, from its lowest point up, follows the leg fully
HEAD_TAIL_FREE = 1.0 * hipZ  # head and tail are left free this close to a foot (along the surface)
pivot_z = hipZ * 0.95  # where the upper leg bones swing from
P = np.array([tuple(p) for p in node_pos])
E = np.array(sorted({(a, b) for a in range(nodes) for b in links[a] if a < b}), dtype=np.int64).reshape(-1, 2)
pinned = np.zeros(nodes, dtype=bool)
pin = np.zeros(nodes)
sole = {k: min((node_pos[n].z for n in range(nodes) if column[n] == k), default=0.0) for k in real_legs}
for n in range(nodes):
    key = column[n]
    if key is not None and node_pos[n].z < sole[key] + FOOT_PIN:
        pinned[n], pin[n] = True, 1.0 if key[0] == "F" else -1.0
# A tail hanging by the hind legs (or a head bent down to the front feet) isn't pinned
# near the feet, or it would tear away from them instead of following a little
near_feet = {int(n): 0.0 for n in np.nonzero(pinned)[0]}
heap = [(0.0, n) for n in near_feet]
heapq.heapify(heap)
while heap:
    d, n = heapq.heappop(heap)
    if d > near_feet.get(n, math.inf) or d > HEAD_TAIL_FREE:
        continue
    for m in links[n]:
        nd = d + (node_pos[n] - node_pos[m]).length
        if nd < near_feet.get(m, math.inf):
            near_feet[m] = nd
            heapq.heappush(heap, (nd, m))
for n in range(nodes):
    p = node_pos[n]
    if pinned[n] or n in near_feet:
        continue
    if p.z >= pivot_z or min((seg_dist(p, *seg), name) for name, seg in bone_segments.items())[1] in (
        "Neck",
        "Head",
        "Tail1",
        "Tail2",
        "Tail3",
    ):
        pinned[n] = True
# A piece with nothing pinned (a floating halo, a loose plate) stays with the body
part = np.full(nodes, -1)
for start in range(nodes):
    if part[start] >= 0:
        continue
    part[start] = start
    piece, stack = [start], [start]
    while stack:
        n = stack.pop()
        for m in links[n]:
            if part[m] < 0:
                part[m] = start
                piece.append(m)
                stack.append(m)
    if not pinned[piece].any():
        pinned[piece] = True
u = pin.copy()
if len(E) and real_legs and not pinned.all():
    mid = (P[E[:, 0]] + P[E[:, 1]]) / 2
    length = np.maximum(np.linalg.norm(P[E[:, 0]] - P[E[:, 1]], axis=1), 1e-6 * max(W, L, H))
    reach = np.full(len(E), np.inf)  # distance from the nearest hip joint, side view
    for key in real_legs:
        reach = np.minimum(reach, np.hypot(mid[:, 1] - feet[key].y, mid[:, 2] - pivot_z))
    cond = np.maximum(reach, 0.1 * hipZ) ** 2 / length
    deg = np.bincount(E[:, 0], cond, nodes) + np.bincount(E[:, 1], cond, nodes)
    free = ~pinned

    def laplacian(x):
        return deg * x - np.bincount(E[:, 0], cond * x[E[:, 1]], nodes) - np.bincount(E[:, 1], cond * x[E[:, 0]], nodes)

    # Conjugate gradients on the free vertices (Jacobi preconditioned)
    x = np.zeros(nodes)
    r = np.where(free, -laplacian(np.where(pinned, pin, 0.0)), 0.0)
    inv = np.where(free & (deg > 0), 1.0 / np.maximum(deg, 1e-30), 0.0)
    z = inv * r
    step = z.copy()
    rz = r @ z
    tolerance = 1e-9 * deg.max()
    for _ in range(5000):
        if rz <= 0 or np.abs(r).max() < tolerance:
            break
        a_step = np.where(free, laplacian(step), 0.0)
        curvature = step @ a_step
        if curvature <= 0:
            break
        alpha = rz / curvature
        x += alpha * step
        r -= alpha * a_step
        z = inv * r
        rz, previous = r @ z, rz
        step = z + (rz / previous) * step
    u = np.where(pinned, pin, np.clip(x, -1.0, 1.0))

node_w = []
for n in range(nodes):
    p = node_pos[n]
    pull = abs(float(u[n]))
    pair = [k for k in real_legs if k[0] == ("F" if u[n] > 0 else "B")] if pull > 0 else []
    if not pair:
        node_w.append(nearest(p, body_bones))
        continue
    w = {name: v * (1 - pull) for name, v in nearest(p, body_bones).items()} if pull < 1 else {}
    # Left and right swing together, so the pair's pull goes to the leg whose foot is nearer
    if column[n] in pair:
        key = column[n]
    else:
        key = min(pair, key=lambda k: (p.x - feet[k].x) ** 2 + (p.y - feet[k].y) ** 2)
    for name, v in nearest(p, (f"Leg{key}_Upper", f"Leg{key}_Lower")).items():
        w[name] = w.get(name, 0.0) + v * pull
    node_w.append(w)

# Smooth the weights along the surface. Nearest-bone weights flip from one bone to
# the next within a single edge (at the knee, along the spine and tail), and an edge
# whose two ends follow different bones stretched like a string when they moved.
# Averaging with neighbors spreads each switch over a few rings of the mesh.
SMOOTH_PASSES, SMOOTH_FACTOR = 16, 0.5
for _ in range(SMOOTH_PASSES):
    smoothed = []
    for n in range(nodes):
        if not links[n]:
            smoothed.append(node_w[n])
            continue
        avg = {}
        for m in links[n]:
            for name, w in node_w[m].items():
                avg[name] = avg.get(name, 0.0) + w / len(links[n])
        mixed = {name: w * (1 - SMOOTH_FACTOR) for name, w in node_w[n].items()}
        for name, w in avg.items():
            mixed[name] = mixed.get(name, 0.0) + w * SMOOTH_FACTOR
        smoothed.append(mixed)
    node_w = smoothed

# Front legs or hind legs, never both: they swing opposite ways, so a vertex following
# both is torn between them, and smoothing can leave a little of each where u crosses
# zero. The weaker pair's weight and as much of the stronger's go to the body, so the
# hand-over still passes smoothly through body-only vertices.
for n in range(nodes):
    w = node_w[n]
    front = sum(v for k, v in w.items() if k.startswith("LegF"))
    hind = sum(v for k, v in w.items() if k.startswith("LegB"))
    if front <= 0 or hind <= 0:
        continue
    keep = "LegF" if front >= hind else "LegB"
    strong, weak = max(front, hind), min(front, hind)
    out = {k: v * (strong - weak) / strong for k, v in w.items() if k.startswith(keep)}
    body_w = {k: v for k, v in w.items() if not k.startswith("Leg")}
    body_total = sum(body_w.values())
    if body_total > 0:
        out.update({k: v * (1 + 2 * weak / body_total) for k, v in body_w.items()})
    else:
        out["Spine"] = 2 * weak
    node_w[n] = out

# Loose bits (fur tufts, mushrooms, spikes that aren't joined to the body) move as one
# piece: a tuft split between a leg and the belly would stretch just like a seam.
seen = [False] * nodes
for start in range(nodes):
    if seen[start]:
        continue
    island, stack = [], [start]
    seen[start] = True
    while stack:
        n = stack.pop()
        island.append(n)
        for m in links[n]:
            if not seen[m]:
                seen[m] = True
                stack.append(m)
    if len(island) < 0.02 * nodes:
        avg = {}
        for n in island:
            for name, w in node_w[n].items():
                avg[name] = avg.get(name, 0.0) + w / len(island)
        for n in island:
            node_w[n] = avg

# Roblox takes 4 influences. A bone that doesn't make the cut hands its weight to the
# kept bone nearest it in the skeleton (Tail3 to Tail2, Chest to Spine, a knee to its
# hip), which moves most like it. Spreading it over all four instead took a share
# from a leg on one vertex and not the next, and that edge stretched.
tree = {b.name: (b.parent.name if b.parent and b.parent.name != "Root" else None) for b in arm.data.bones}
tree.pop("Root", None)


def chain(name):
    out = []
    while name:
        out.append(name)
        name = tree[name]
    return out


def hops(a, b):
    ca, cb = chain(a), chain(b)
    common = next((x for x in ca if x in cb), None)
    return ca.index(common) + cb.index(common) if common else len(ca) + len(cb)


hop = {(a, b): hops(a, b) for a in tree for b in tree}


groups = {name: body.vertex_groups.new(name=name) for name in bone_segments}
for n in range(nodes):
    w = dict(node_w[n])
    while len(w) > 1 and (len(w) > 4 or min(w.values()) < 0.02):
        name = min(w, key=w.get)
        v = w.pop(name)
        heir = min(w, key=lambda k: (hop[name, k], -w[k]))
        w[heir] += v
    total = sum(w.values())
    for i in members[n]:
        for name, v in w.items():
            groups[name].add([i], v / total, "REPLACE")

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
