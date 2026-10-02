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
NIGHT = os.environ.get("NIGHT") == "1"
PROPS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../assets/tripo/props"))

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


GLB_CACHE = {}
TINTED = {}
# Theme kit pieces whose Tripo metalness map is stripped on import
# (tools/studio/organize_imports.luau): metal reflects a dark sky and turned the
# pearly shell spires navy and the gold spires near-black.
KIT_PREFIXES = ("Coral", "Fire", "Ice", "Storm", "Moss", "Moon", "Gold", "Diamond", "Void", "Snow")
ZONE_PROPS = {"CoralCluster", "IceSpire", "IceArch", "MoonMonolith"}


def strip_metal(mesh):
    for mat in mesh.materials:
        if mat is None or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                for link in list(node.inputs["Metallic"].links):
                    mat.node_tree.links.remove(link)
                node.inputs["Metallic"].default_value = 0.0


def tinted(name, mesh, tint):
    """Copies of a model's materials with the base color multiplied by `tint`
    (SurfaceAppearance.Color in game)."""
    key = (name, tint)
    if key in TINTED:
        return TINTED[key]
    out = []
    for mat in mesh.materials:
        if mat is None:
            out.append(None)
            continue
        copy = mat.copy()
        tree = copy.node_tree
        for node in list(tree.nodes):
            if node.type != "BSDF_PRINCIPLED":
                continue
            base = node.inputs["Base Color"]
            if not base.links:
                base.default_value = (*[c ** 2.2 for c in tint], 1)
                continue
            source = base.links[0].from_socket
            mult = tree.nodes.new("ShaderNodeVectorMath")
            mult.operation = "MULTIPLY"
            mult.inputs[1].default_value = tuple(c ** 2.2 for c in tint)
            tree.links.new(source, mult.inputs[0])
            tree.links.new(mult.outputs[0], base)
        out.append(copy)
    TINTED[key] = out
    return out


def glb(name):
    """Imports assets/tripo/props/<name>.glb once: (mesh data centered on its box, Roblox extents)."""
    if name in GLB_CACHE:
        return GLB_CACHE[name]
    path = os.path.join(PROPS_DIR, name + ".glb")
    if not os.path.exists(path):
        GLB_CACHE[name] = None
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = mathutils.Matrix.Identity(4)
    vs = [v.co for v in obj.data.vertices]
    mn = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    obj.data.transform(mathutils.Matrix.Translation(-(mn + mx) / 2))
    # Studio's importer turns a GLB half round (glTF -Z faces Roblox +Z: the
    # waterfall cliff poured away from the hub until it was turned), so do the same
    obj.data.transform(mathutils.Matrix.Rotation(math.pi, 4, "Z"))
    ext = mx - mn
    data = obj.data
    if name.startswith(KIT_PREFIXES) and name not in ZONE_PROPS:
        strip_metal(data)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    GLB_CACHE[name] = (data, (ext.x, ext.z, ext.y))  # Roblox X, Y (up), Z
    return GLB_CACHE[name]


def place_prop(f):
    name, mode = f[1], f[2]
    got = glb(name)
    if got is None:
        return
    data, ext = got
    pos = mathutils.Vector([float(v) for v in f[3].split(",")])
    right, up, back = (mathutils.Vector([float(v) for v in f[i].split(",")]) for i in (4, 5, 6))
    size = [float(v) for v in f[7].split(",")]
    rot = mathutils.Matrix((right, up, back)).transposed()
    if mode == "height":
        scale = size[1] / max(ext[1], 1e-4)
        centre = pos + rot @ mathutils.Vector((0, size[1] / 2, 0))
    else:
        scale = min(size[0] / max(ext[0], 1e-4), size[1] / max(ext[1], 1e-4), size[2] / max(ext[2], 1e-4))
        centre = pos
    world = (M @ rot @ M.inverted()).to_4x4()
    world.translation = M @ centre
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = world @ mathutils.Matrix.Scale(scale, 4)
    if len(f) > 9 and f[9]:
        # KitNeon: the game swaps the texture for glowing neon in this color
        color = [float(v) for v in f[9].split(",")]
        key = ("neon", tuple(round(c, 3) for c in color))
        mat = bpy.data.materials.get(str(key))
        if mat is None:
            mat = bpy.data.materials.new(str(key))
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes["Principled BSDF"]
            lin = [c ** 2.2 for c in color]
            bsdf.inputs["Base Color"].default_value = (*lin, 1)
            bsdf.inputs["Emission Color"].default_value = (*lin, 1)
            bsdf.inputs["Emission Strength"].default_value = 1.6
        for slot in obj.material_slots:
            slot.link = "OBJECT"
            slot.material = mat
    elif len(f) > 8 and f[8]:
        tint = tuple(round(float(v), 3) for v in f[8].split(","))
        for slot, mat in zip(obj.material_slots, tinted(name, data, tint)):
            slot.link = "OBJECT"
            slot.material = mat


def add_light(f, count):
    pos = mathutils.Vector([float(v) for v in f[1].split(",")])
    color = [float(v) for v in f[2].split(",")]
    rng = float(f[3])
    ld = bpy.data.lights.new(f"KitLight{count}", "POINT")
    ld.energy = rng * rng * (5 if NIGHT else 2.5)
    ld.color = color
    ld.shadow_soft_size = 0.5
    ld.use_shadow = False  # dozens of shadowed lights take many minutes on a CPU render
    lo = bpy.data.objects.new(f"KitLight{count}", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = M @ pos


def add_bolt(f, meshes):
    """A lightning bolt for a Beam (the client flickers the real one): a jagged
    line of glowing segments between its two ends."""
    import random

    a = M @ mathutils.Vector([float(v) for v in f[1].split(",")])
    b = M @ mathutils.Vector([float(v) for v in f[2].split(",")])
    rnd = random.Random(hash(f[1]) & 0xFFFF)
    mat = bpy.data.materials.get("Bolt")
    if mat is None:
        mat = bpy.data.materials.new("Bolt")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (0.9, 0.95, 1.0, 1)
        bsdf.inputs["Emission Color"].default_value = (0.85, 0.92, 1.0, 1)
        bsdf.inputs["Emission Strength"].default_value = 12.0
    points = [a]
    for i in range(1, 9):
        t = i / 9
        jitter = mathutils.Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * 1.3
        points.append(a.lerp(b, t) + jitter)
    points.append(b)
    for p, q in zip(points, points[1:]):
        seg = q - p
        obj = bpy.data.objects.new("Bolt", meshes["Cylinder"])
        bpy.context.scene.collection.objects.link(obj)
        rot = seg.to_track_quat("X", "Z").to_matrix().to_4x4()
        rot.translation = (p + q) / 2
        obj.matrix_world = rot @ mathutils.Matrix.Diagonal((seg.length / 2, 0.12, 0.12, 1))
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = mat


def add_particles(f, meshes):
    """Stand-ins for a ParticleEmitter (smoke plumes, mist, embers, sparkles, fireflies):
    a scatter of soft blobs where its particles would be at one moment."""
    import random

    kind = f[1]
    pos = mathutils.Vector([float(v) for v in f[2].split(",")])
    box = [float(v) for v in f[3].split(",")]
    color = [float(v) for v in f[4].split(",")]
    rate, life, speed, rise, size = (float(v) for v in f[5:10])
    rnd = random.Random(hash(f[2]) & 0xFFFF)
    count = int(max(4, min(70, rate * life * 0.7)))
    key = ("particle", kind, tuple(round(c, 2) for c in color))
    mat = bpy.data.materials.get(str(key))
    if mat is None:
        mat = bpy.data.materials.new(str(key))
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        lin = [c ** 2.2 for c in color]
        bsdf.inputs["Base Color"].default_value = (*lin, 1)
        if kind == "smoke":
            bsdf.inputs["Alpha"].default_value = 0.22
        else:
            bsdf.inputs["Emission Color"].default_value = (*lin, 1)
            bsdf.inputs["Emission Strength"].default_value = 6.0 if kind == "sparkle" else 4.0
            bsdf.inputs["Alpha"].default_value = 0.85
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            mat.blend_method = "BLEND"
    for _ in range(count):
        age = rnd.random()
        offset = mathutils.Vector(
            (rnd.uniform(-box[0] / 2, box[0] / 2), rnd.uniform(-box[1] / 2, box[1] / 2), rnd.uniform(-box[2] / 2, box[2] / 2))
        )
        if kind == "smoke":
            offset.y += age * life * speed * 0.6
            d = size * (0.25 + 0.45 * age)
        else:
            offset.y += age * life * (rise * 0.3 + speed * 0.2)
            d = max(size * 0.5, 0.25)
        obj = bpy.data.objects.new("Particle", meshes["Ball"])
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = mathutils.Matrix.Translation(M @ (pos + offset)) @ mathutils.Matrix.Scale(d / 2, 4)
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = mat


def add_flame(f, meshes):
    """A Fire: a teardrop of glowing blobs, white-hot at the core."""
    pos = M @ mathutils.Vector([float(v) for v in f[1].split(",")])
    color = [float(v) for v in f[2].split(",")]
    size = float(f[3])
    for i, (lift, d, heat) in enumerate(((0.0, 0.55, 0.6), (0.35, 0.42, 0.3), (0.7, 0.26, 0.0))):
        key = ("flame", tuple(round(c, 2) for c in color), i)
        mat = bpy.data.materials.get(str(key))
        if mat is None:
            mat = bpy.data.materials.new(str(key))
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes["Principled BSDF"]
            c = [min(1.0, (v + heat * (1 - v))) ** 2.2 for v in color]
            bsdf.inputs["Base Color"].default_value = (*c, 1)
            bsdf.inputs["Emission Color"].default_value = (*c, 1)
            bsdf.inputs["Emission Strength"].default_value = 8.0
        obj = bpy.data.objects.new("Flame", meshes["Ball"])
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = mathutils.Matrix.Translation(pos + mathutils.Vector((0, 0, lift * size * 0.6))) @ mathutils.Matrix.Diagonal(
            (d * size * 0.5, d * size * 0.5, d * size * 0.8, 1)
        )
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = mat


def load(path, meshes, cache):
    # A dump with its own lights (L lines: the theme kits) doesn't need the
    # stand-in lamp over every glowing part
    lights = 12 if any(line.startswith("L|") for line in open(path)) else 0
    kit_lights = 0
    center = mathutils.Vector((0, 0, 0))
    for line in open(path):
        if line.startswith("R|"):
            place_prop(line.strip().split("|"))
            continue
        if line.startswith("F|"):
            add_flame(line.strip().split("|"), meshes)
            continue
        if line.startswith("E|"):
            add_particles(line.strip().split("|"), meshes)
            continue
        if line.startswith("B|"):
            add_bolt(line.strip().split("|"), meshes)
            continue
        if line.startswith("L|"):
            if kit_lights < 110:
                add_light(line.strip().split("|"), kit_lights)
                kit_lights += 1
            continue
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
            ld.use_shadow = False
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
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        (0.07, 0.09, 0.19, 1) if NIGHT else (0.55, 0.72, 0.95, 1)
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.7 if NIGHT else 0.9
    try:
        scene.eevee.taa_render_samples = 24
    except AttributeError:
        pass
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 1.3 if NIGHT else 3.5
    if NIGHT:  # a soft moon, like the concepts: the stone still reads and the lights carry it
        sun.color = (0.86, 0.88, 1.0)
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
    if VIEW == "front":  # the theme concepts' camera: high, square on to the gate
        target = mathutils.Vector((0, -6, 17))
        cam.location = (0, 131, 112)
    else:
        cam.location = (-78, 118, 92) if VIEW == "aerial" else (0, 110, 25)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    return scene


def bloom(path):
    """Soft glow round the bright parts (neon, flames, lit pools), like Roblox's Bloom."""
    try:
        import numpy as np
        from PIL import Image, ImageFilter
    except ImportError:
        return
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.float32) / 255
    lum = a.max(axis=2, keepdims=True)
    bright = np.clip((lum - 0.62) / 0.38, 0, 1) * a
    src = Image.fromarray((bright * 255).astype(np.uint8))
    glow = np.zeros_like(a)
    for radius, weight in ((4, 0.55), (14, 0.5), (36, 0.4)):
        glow += np.asarray(src.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255 * weight
    out = 1 - (1 - a) * (1 - np.clip(glow, 0, 1))  # screen blend
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(path)


meshes_cache = None
outputs = []
for path in sorted(glob.glob(os.path.join(DIR, "level*.txt"))):
    scene = setup_scene()
    meshes = base_meshes()
    load(path, meshes, {})
    out = path[:-4] + ".png"
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if NIGHT:
        bloom(out)
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
