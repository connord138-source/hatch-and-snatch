"""Renders a creature GLB wearing each of its mutation skins (preview and QA sheet).

    <blender python> tools/mutations/render_skins.py -- <creature.glb> <skins_dir> <out_dir> [front] [Skin ...]

For each skin PNG in <skins_dir> (plus "Normal", the model's own texture) writes
<out_dir>/<Skin>_body.png (front three-quarter) and <Skin>_head.png (a close-up of
the face, to check the eyes). `front` matches bodyplans.json, as in bake_maps.py.
"""

import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, SKINS, OUT = argv[0], pathlib.Path(argv[1]), pathlib.Path(argv[2])
FRONT = argv[3] if len(argv) > 3 else "auto"
NAMES = argv[4:] or ["Normal"] + sorted(p.stem for p in SKINS.glob("*.png") if p.stem != "eyes_debug")
SIZE = 640
OUT.mkdir(parents=True, exist_ok=True)


def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.data.transform(body.matrix_world)
    body.matrix_world = Matrix.Identity(4)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    # Same squaring as bake_maps.py: head toward -Y
    vs = np.array([v.co[:] for v in body.data.vertices])
    if FRONT in ("auto", "flip"):
        c = vs[:, :2] - vs[:, :2].mean(0)
        sxx, syy, sxy = (c[:, 0] ** 2).mean(), (c[:, 1] ** 2).mean(), (c[:, 0] * c[:, 1]).mean()
        spread = math.sqrt(((sxx - syy) / 2) ** 2 + sxy**2)
        major, minor = (sxx + syy) / 2 + spread, (sxx + syy) / 2 - spread
        if major >= 1.15 * max(minor, 1e-9):
            theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
            turn = math.pi / 2 - theta
            if turn > math.pi / 2:
                turn -= math.pi
            body.data.transform(Matrix.Rotation(turn, 4, "Z"))
            vs = np.array([v.co[:] for v in body.data.vertices])
    mn, mx = vs.min(0), vs.max(0)
    size = mx - mn
    long_axis = 0 if size[0] >= size[1] else 1
    if FRONT in ("auto", "flip"):
        lo, hi = mn[long_axis], mx[long_axis]
        span = hi - lo
        low_end = vs[vs[:, long_axis] < lo + 0.2 * span][:, 2].mean()
        high_end = vs[vs[:, long_axis] > hi - 0.2 * span][:, 2].mean()
        sign = 1 if high_end >= low_end else -1
        if FRONT == "flip":
            sign = -sign
        front_axis = long_axis
    else:
        front_axis = 0 if FRONT[1] == "x" else 1
        sign = 1 if FRONT[0] == "+" else -1
    angle = (-math.pi / 2 if sign > 0 else math.pi / 2) if front_axis == 0 else (math.pi if sign > 0 else 0.0)
    body.data.transform(Matrix.Rotation(angle, 4, "Z"))
    vs = np.array([v.co[:] for v in body.data.vertices])
    mn, mx = vs.min(0), vs.max(0)
    body.data.transform(Matrix.Translation(Vector((-(mn[0] + mx[0]) / 2, -(mn[1] + mx[1]) / 2, -mn[2]))))
    vs = np.array([v.co[:] for v in body.data.vertices])
    mn, mx = vs.min(0), vs.max(0)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (lin(40), lin(44), lin(58), 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.5
    for name, energy, rot in (("Key", 3.0, (50, 10, -35)), ("Fill", 1.1, (65, 0, 140))):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = energy
        obj = bpy.data.objects.new(name, light)
        obj.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(obj)
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 50
    co = bpy.data.objects.new("Cam", cam)
    scene.collection.objects.link(co)
    scene.camera = co
    # The model's color image node
    mat = body.material_slots[0].material
    node = next(
        n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and n.image.name.lower().startswith("color")
    )
    return body, node, co, mn, mx, vs


body, node, cam, mn, mx, vs = setup()
original = node.image
size = mx - mn
# The face: the front 10% of the body, its upper half
head = vs[vs[:, 1] < mn[1] + 0.10 * size[1]]
head = head[head[:, 2] > np.percentile(head[:, 2], 40)]
head_c = Vector(head.mean(0))
head_r = float(max(size) * 0.16)


def shoot(target, dist, direction, path):
    cam.location = target + direction.normalized() * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


for name in NAMES:
    bsdf = next(n for n in node.id_data.nodes if n.type == "BSDF_PRINCIPLED")
    if name == "Normal":
        node.image = original
    else:
        node.image = bpy.data.images.load(str(SKINS / f"{name}.png"), check_existing=True)
        # The skins ship without the model's metalness map (a metallic Tripo map
        # turned the albino Quasarfox grey), so preview them as plain surfaces
        for link in list(bsdf.inputs["Metallic"].links):
            node.id_data.links.remove(link)
        bsdf.inputs["Metallic"].default_value = 0.0
    body_target = Vector((0, 0, size[2] * 0.48))
    shoot(body_target, max(size) * 1.55, Vector((-0.78, -0.95, 0.42)), OUT / f"{name}_body.png")
    shoot(head_c, head_r * 2.4, Vector((-0.45, -1.0, 0.12)), OUT / f"{name}_head.png")
    print("[render]", name)
