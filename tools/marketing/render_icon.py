"""Renders the store icon's 3D layer in Blender from the game's own models.

    EGL_PLATFORM=surfaceless <bpy python> tools/marketing/render_icon.py -- <creature.glb> <out.png> [variant]

A baby creature sits in a cracked, glowing egg while a blocky gloved thief's hand
reaches in from the corner (the hatch and the snatch). Rendered with a transparent
background; tools/marketing/compose.py adds the burst background, glow and sparkle.
Built from real game assets (the creature GLB) rather than an image model, so the
icon matches what players see in game. Variants: "snatch" (with the hand), "hatch"
(no hand, closer).
"""

import math
import sys

import bpy  # first: the bpy module provides bmesh and mathutils
import bmesh
import mathutils

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = argv[0], argv[1]
VARIANT = argv[2] if len(argv) > 2 else "snatch"
SIZE = int(__import__("os").environ.get("ICON_SIZE", "1024"))


def material(name, color, roughness=0.5, emission=None, strength=0.0, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def glow(name, color, strength):
    """Pure light (no shading), so scene lights can't wash it out."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.remove(nodes["Principled BSDF"])
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*color, 1)
    emit.inputs["Strength"].default_value = strength
    links.new(emit.outputs["Emission"], nodes["Material Output"].inputs["Surface"])
    return mat


def speckled_shell(name):
    """Warm cream eggshell with darker gold speckles."""
    mat = material(name, (1.0, 0.6, 0.16), roughness=0.28)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.5  # glossy, like a fresh egg
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 22
    noise.inputs["Detail"].default_value = 2
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.62
    ramp.color_ramp.elements[0].color = (1.0, 0.58, 0.14, 1)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (0.55, 0.16, 0.04, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    try:
        scene.eevee.taa_render_samples = 64
    except AttributeError:
        pass
    scene.view_settings.exposure = -0.2
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    except TypeError:
        pass
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.18, 0.14, 0.35, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    return scene


def import_creature(path):
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    points = [o.matrix_world @ mathutils.Vector(c) for o in meshes for c in o.bound_box]
    low = mathutils.Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = mathutils.Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    # Normalize: 0.8 tall, feet at z = -0.4, centered (the models face +Y)
    scale = 0.8 / (high.z - low.z)
    center = (low + high) / 2
    roots = [o for o in bpy.context.scene.objects if o.parent is None]
    for obj in roots:
        obj.location = (obj.location - center) * scale
        obj.scale = obj.scale * scale
    bpy.context.view_layer.update()
    return meshes


def egg_shell(radius=0.5, cut=-0.02, teeth=9, amplitude=0.09):
    """An egg's bottom part with a jagged crack line, thick shell, glowing inside."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=teeth * 16, v_segments=64, radius=1.0)
    for v in bm.verts:
        z = v.co.z
        narrow = 1.0 - 0.16 * z  # wider at the bottom, like an egg
        v.co.x *= radius * narrow
        v.co.y *= radius * narrow
        v.co.z = z * radius * 1.3 - 0.12

    def crack(angle):
        tri = abs(((angle * teeth / (2 * math.pi)) % 1.0) * 2 - 1)  # 0..1 sawtooth
        return cut + amplitude * (tri - 0.5) * 2

    doomed = [f for f in bm.faces if f.calc_center_median().z > crack(math.atan2(f.calc_center_median().y, f.calc_center_median().x))]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    # Snap the rim onto the crack line so the teeth are crisp
    for v in bm.verts:
        if v.is_boundary:
            v.co.z = crack(math.atan2(v.co.y, v.co.x))
    mesh = bpy.data.meshes.new("Egg")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    egg = bpy.data.objects.new("Egg", mesh)
    bpy.context.scene.collection.objects.link(egg)
    egg.data.materials.append(speckled_shell("Shell"))
    solid = egg.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.035
    # The inside glows like magma: a slightly smaller copy facing inward
    inner = bpy.data.objects.new("EggInside", mesh.copy())
    bpy.context.scene.collection.objects.link(inner)
    inner.scale = (0.9, 0.9, 1.0)
    inner.data.materials.clear()
    inner.data.materials.append(glow("Inside", (1.0, 0.33, 0.04), 1.0))
    return egg


def cube(name, size, location, mat, parent=None, bevel=0.018):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bevel_mod = obj.modifiers.new("Bevel", "BEVEL")
    bevel_mod.width = bevel
    bevel_mod.segments = 4
    bevel_mod.affect = "EDGES"
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if parent:
        obj.parent = parent
    return obj


def thief_hand():
    """A blocky Roblox-style gloved hand reaching forward (+X), fingers curled to grab."""
    glove = material("Glove", (0.05, 0.03, 0.09), 0.32)
    cuff = material("Cuff", (0.42, 0.12, 0.95), 0.35)
    sleeve = material("Sleeve", (0.1, 0.09, 0.16), 0.8)
    root = bpy.data.objects.new("Hand", None)
    bpy.context.scene.collection.objects.link(root)
    cube("Sleeve", (0.5, 0.21, 0.21), (-0.41, 0, 0), sleeve, root, 0.03)
    cube("Cuff", (0.07, 0.23, 0.23), (-0.14, 0, 0), cuff, root, 0.02)
    # A chunky mitten like a Roblox avatar's hand: palm, one finger block, thumb
    cube("Palm", (0.2, 0.19, 0.085), (0.0, 0, 0), glove, root, 0.025)
    fingers = cube("Fingers", (0.13, 0.19, 0.075), (0.15, 0, -0.03), glove, root, 0.025)
    fingers.rotation_euler = (0, math.radians(55), 0)  # curled to grab
    thumb = cube("Thumb", (0.1, 0.06, 0.065), (0.05, 0.12, -0.035), glove, root, 0.02)
    thumb.rotation_euler = (math.radians(-25), math.radians(20), math.radians(40))
    return root


def light(name, kind, location, target, energy, color, size=1.0):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    direction = mathutils.Vector(target) - mathutils.Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def place_hand(hand, cam):
    """Puts the hand in the top-left of the frame, reaching for the creature's head."""
    view = cam.matrix_world.to_3x3()
    right, up, back = view.col[0], view.col[1], view.col[2]
    head = mathutils.Vector((0.0, 0.08, 0.32))
    hand.location = head - right * 0.24 + up * 0.2 + back * 0.3
    hand.scale = (0.95, 0.95, 0.95)
    reach = (head - hand.location).normalized()
    top = (up - reach * up.dot(reach)).normalized()  # back of the hand faces up-screen
    side = top.cross(reach)
    hand.rotation_euler = mathutils.Matrix((reach, side, top)).transposed().to_euler()


def main():
    scene = reset()
    import_creature(SRC)
    egg_shell(radius=0.47)

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 85
    target = mathutils.Vector((0.0, 0.05, 0.12 if VARIANT == "snatch" else 0.1))
    cam.location = (0.75, 2.6, 0.75) if VARIANT == "snatch" else (0.6, 2.4, 0.55)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    if VARIANT == "snatch":
        place_hand(thief_hand(), cam)

    light("Key", "AREA", (1.6, 2.2, 1.8), (0, 0, 0.2), 130, (1.0, 0.92, 0.82), 1.4)
    light("Fill", "AREA", (-1.8, 1.6, 0.6), (0, 0, 0.2), 45, (0.6, 0.7, 1.0), 2.0)
    light("Rim", "AREA", (-0.6, -1.6, 1.4), (0, 0, 0.3), 520, (0.65, 0.45, 1.0), 1.2)
    light("RimWarm", "AREA", (1.2, -1.4, 0.4), (0, 0, 0.1), 260, (1.0, 0.55, 0.2), 1.0)
    light("Magma", "POINT", (0, 0.1, -0.1), (0, 0, 0), 30, (1.0, 0.45, 0.1))

    scene.render.filepath = OUT
    bpy.ops.render.render(write_still=True)


main()
