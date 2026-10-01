"""Renders part dumps from the luau world builders (see run_fortress.sh) in Blender.

    EGL_PLATFORM=surfaceless <bpy python> render_parts.py -- <dir with level*.txt> [camera]

Each level<N>.txt becomes level<N>.png, and sheet.png puts them side by side. A rough
look only (Roblox materials become flat colors), for checking shapes, proportions
and layout before a Studio playtest.
"""
import glob
import math
import os
import sys

import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1 :]
DIR = os.path.abspath(argv[0])
VIEW = argv[1] if len(argv) > 1 else "aerial"

M = mathutils.Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox (x, y, z) -> Blender (x, -z, y)


def material(cache, color, mat_name, transparency, glow):
    key = (round(color[0], 2), round(color[1], 2), round(color[2], 2), mat_name, round(transparency, 2))
    if key in cache:
        return cache[key]
    mat = bpy.data.materials.new(str(key))
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[c ** 2.2 for c in color], 1)
    bsdf.inputs["Roughness"].default_value = 0.75
    if mat_name in ("Foil", "Metal", "DiamondPlate"):
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.35
    if mat_name == "Neon" or glow:
        bsdf.inputs["Emission Color"].default_value = (*[c ** 2.2 for c in color], 1)
        bsdf.inputs["Emission Strength"].default_value = 3.0 if mat_name == "Neon" else 0.0
    if transparency > 0 or mat_name == "Glass":
        alpha = 1 - max(transparency, 0.5 if mat_name == "Glass" else 0)
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            mat.blend_method = "BLEND"
    cache[key] = mat
    return mat


def base_meshes():
    made = []
    bpy.ops.mesh.primitive_cube_add(size=2)
    made.append(bpy.context.active_object)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1, depth=2)
    made.append(bpy.context.active_object)
    made[1].data.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, "Y"))  # axis along X like Roblox
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=16, ring_count=8)
    made.append(bpy.context.active_object)
    meshes = {"Block": made[0].data, "Cylinder": made[1].data, "Ball": made[2].data}
    placeholder = bpy.data.materials.new("slot")
    for mesh in meshes.values():
        mesh.materials.append(placeholder)
    for o in made:
        bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def load(path, meshes, cache):
    lights = 0
    center = mathutils.Vector((0, 0, 0))
    for line in open(path):
        if not line.startswith("P|"):
            continue
        f = line.strip().split("|")
        name, shape = f[1], f[2]
        size = [float(v) for v in f[3].split(",")]
        pos = mathutils.Vector([float(v) for v in f[4].split(",")])
        right, up, back = (mathutils.Vector([float(v) for v in f[i].split(",")]) for i in (5, 6, 7))
        color = [float(v) for v in f[8].split(",")]
        mat_name, transparency, glow = f[9], float(f[10]), f[11] == "1"
        rot = mathutils.Matrix((right, up, back)).transposed()  # columns
        world = M @ rot
        mw = world.to_4x4()
        mw.translation = M @ pos
        mesh = meshes.get(shape, meshes["Block"])
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        scale = mathutils.Matrix.Diagonal((size[0] / 2, size[1] / 2, size[2] / 2, 1))
        obj.matrix_world = mw @ scale
        slot_mat = material(cache, color, mat_name, transparency, glow)
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = slot_mat
        if glow and lights < 12:
            lights += 1
            ld = bpy.data.lights.new(name + "L", "POINT")
            ld.energy = 600
            ld.color = (1.0, 0.6, 0.3)
            lo = bpy.data.objects.new(name + "L", ld)
            bpy.context.scene.collection.objects.link(lo)
            lo.location = M @ pos + mathutils.Vector((0, 0, 1.5))


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1100, 760
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.72, 0.95, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("Sun", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    # Grass
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, -20, -0.01))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("grass")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.1, 0.25, 0.06, 1)
    g.data.materials.append(gm)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 35
    target = mathutils.Vector((0, -14, 12))
    cam.location = (-78, 118, 92) if VIEW == "aerial" else (0, 110, 25)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    return scene


meshes_cache = None
outputs = []
for path in sorted(glob.glob(os.path.join(DIR, "level*.txt"))):
    scene = setup_scene()
    meshes = base_meshes()
    load(path, meshes, {})
    out = path[:-4] + ".png"
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    outputs.append(out)
    print("wrote", out)

try:
    from PIL import Image

    ims = [Image.open(p) for p in outputs]
    if ims:
        w, h = ims[0].size
        cols = 3
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (w * cols, h * rows), (30, 30, 30))
        for i, im in enumerate(ims):
            sheet.paste(im.convert("RGB"), ((i % cols) * w, (i // cols) * h))
        sheet.save(os.path.join(DIR, "sheet.png"))
        print("wrote", os.path.join(DIR, "sheet.png"))
except ImportError:
    pass
