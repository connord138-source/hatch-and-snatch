"""Bakes a creature GLB's texture-space maps for the mutation skins (make_skins.py).

    <blender python> tools/mutations/bake_maps.py -- <creature.glb> <out.npz> [front] [size]

For every texel of the model's color texture this records where it sits on the body:
its 3D position and surface normal in a squared-up body frame (head toward -Y, up +Z,
the creature's left/right along X), normalized so the body spans 0..1 on its long axis.
The color texture itself comes along, and three flat renders of the face (front and
each side of the front) with a UV pass, for finding the eyes. That lets the skins put patches, splits and
eye colors on the body in 3D, so nothing breaks at the texture's UV seams.

`front` matches bodyplans.json (auto | flip | +x | -x | +y | -y), as in rig_creature.py.
"""

import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = argv[0], argv[1]
FRONT = argv[2] if len(argv) > 2 else "auto"
SIZE = int(argv[3]) if len(argv) > 3 else 1024

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

# The color texture (Tripo: one material, one base-color image)
color_image = None
for slot in body.material_slots:
    for node in slot.material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image and node.image.name.lower().startswith("color"):
            color_image = node.image
if color_image is None:
    for slot in body.material_slots:
        bsdf = next(n for n in slot.material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        link = bsdf.inputs["Base Color"].links
        if link and link[0].from_node.type == "TEX_IMAGE":
            color_image = link[0].from_node.image
assert color_image is not None, "no color texture"

# Square the body up like the rig does: long axis along Y, head toward -Y
vs = np.array([v.co[:] for v in body.data.vertices])


def square_up():
    c = vs[:, :2] - vs[:, :2].mean(0)
    sxx, syy, sxy = (c[:, 0] ** 2).mean(), (c[:, 1] ** 2).mean(), (c[:, 0] * c[:, 1]).mean()
    spread = math.sqrt(((sxx - syy) / 2) ** 2 + sxy**2)
    major, minor = (sxx + syy) / 2 + spread, (sxx + syy) / 2 - spread
    if major < 1.15 * max(minor, 1e-9):
        return 0.0
    theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
    turn = math.pi / 2 - theta
    if turn > math.pi / 2:
        turn -= math.pi
    return turn


rot = Matrix.Identity(4)
if FRONT in ("auto", "flip"):
    rot = Matrix.Rotation(square_up(), 4, "Z")
    body.data.transform(rot)
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
# Rotate so the head points -Y
if front_axis == 0:
    angle = -math.pi / 2 if sign > 0 else math.pi / 2
else:
    angle = math.pi if sign > 0 else 0.0
body.data.transform(Matrix.Rotation(angle, 4, "Z"))
vs = np.array([v.co[:] for v in body.data.vertices])
mn, mx = vs.min(0), vs.max(0)
length = float(mx[1] - mn[1])

# Bake position and normal as emission into float images
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 1
scene.cycles.device = "CPU"
scene.render.bake.margin = 6

mat = body.material_slots[0].material
nodes, links = mat.node_tree.nodes, mat.node_tree.links
out_node = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
orig_surface = out_node.inputs["Surface"].links[0].from_socket
geo = nodes.new("ShaderNodeNewGeometry")
emit = nodes.new("ShaderNodeEmission")
target = nodes.new("ShaderNodeTexImage")
mapping = nodes.new("ShaderNodeVectorMath")  # (p - mn) / extent
mapping.operation = "MULTIPLY_ADD"
extent = np.maximum(mx - mn, 1e-6)
mapping.inputs[1].default_value = tuple(1.0 / extent)
mapping.inputs[2].default_value = tuple(-mn / extent)


def bake(name, socket, transform=True):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=True, float_buffer=True)
    img.generated_color = (0, 0, 0, 0)
    target.image = img
    nodes.active = target
    for link in list(emit.inputs["Color"].links):
        links.remove(link)
    if transform:
        links.new(socket, mapping.inputs[0])
        links.new(mapping.outputs[0], emit.inputs["Color"])
    else:
        links.new(socket, emit.inputs["Color"])
    links.new(emit.outputs[0], out_node.inputs["Surface"])
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type="EMIT")
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
    return arr[::-1]  # top row first, like the PNG


position = bake("pos", geo.outputs["Position"])
normal = bake("nrm", geo.outputs["Normal"], transform=False)

# Face views for finding the eyes: the head from the front and from each side of
# the front, rendered flat (unlit texture color) and as a UV pass, so an eye found
# in the picture maps straight back to its texels.
FACE = 512
scene.render.resolution_x = FACE
scene.render.resolution_y = FACE
scene.render.image_settings.file_format = "OPEN_EXR"
scene.render.image_settings.color_depth = "32"
scene.view_settings.view_transform = "Raw"
scene.cycles.samples = 4
scene.cycles.use_denoising = False
scene.render.film_transparent = True
uvmap = nodes.new("ShaderNodeUVMap")
tex_color = next(n for n in nodes if n.type == "TEX_IMAGE" and n.image == color_image)
front = vs[vs[:, 1] < mn[1] + 0.10 * (mx[1] - mn[1])]
upper = front[front[:, 2] > np.percentile(front[:, 2], 45)]
face_c = Vector(upper.mean(0))
face_c.z = float(np.percentile(upper[:, 2], 55))
face_r = float(max(np.percentile(upper[:, 0], 95) - np.percentile(upper[:, 0], 5), np.ptp(upper[:, 2]) * 0.8, 1e-3))
cam_data = bpy.data.cameras.new("FaceCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = face_r * 1.25
cam = bpy.data.objects.new("FaceCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
tmp = pathlib.Path(OUT).with_suffix(".face.exr")


def render_pass(socket):
    for link in list(emit.inputs["Color"].links):
        links.remove(link)
    links.new(socket, emit.inputs["Color"])
    links.new(emit.outputs[0], out_node.inputs["Surface"])
    scene.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(tmp))
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(FACE, FACE, 4)[::-1]
    bpy.data.images.remove(img)
    return arr


faces = []
for yaw in (0.0, 35.0, -35.0, 75.0, -75.0):
    direction = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0.15)).normalized()
    cam.location = face_c + direction * (length * 2)
    cam.rotation_euler = (face_c - cam.location).to_track_quat("-Z", "Y").to_euler()
    flat = render_pass(tex_color.outputs["Color"])
    uv = render_pass(uvmap.outputs["UV"])
    faces.append(np.concatenate([flat[..., :3], uv[..., :2], flat[..., 3:4]], -1))
tmp.unlink(missing_ok=True)
links.new(orig_surface, out_node.inputs["Surface"])

w, h = color_image.size
color = np.array(color_image.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]

np.savez_compressed(
    OUT,
    color=(np.clip(color, 0, 1) * 255).astype(np.uint8),
    position=(position[:, :, :3] * extent + mn).astype(np.float16),  # body frame, model units
    normal=normal[:, :, :3].astype(np.float16),
    covered=position[:, :, :3].sum(-1) > 1e-5,  # unbaked texels stay black
    bounds=np.stack([mn, mx]),
    length=length,
    faces=np.stack(faces).astype(np.float32),  # (view, y, x, [r, g, b, u, v, alpha])
)
print(f"[bake] {SRC}: texture {w}x{h}, maps {SIZE}, length {length:.3f}")
