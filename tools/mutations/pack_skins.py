"""Packs a model's mutation skins into one small GLB for Studio's 3D importer.

    <blender python> tools/mutations/pack_skins.py -- <creature.glb> <skins_dir> <out.glb> [size]

The GLB holds one tiny quad per skin, named for its mutation (Albino, Melanistic,
...), whose material is the skin as its color map plus the model's own normal and
roughness maps (non-metallic: a metallic Tripo map turned the albino Quasarfox
grey). Importing it uploads the textures and makes a SurfaceAppearance on each
quad; tools/studio/organize_skins.luau then files them under
ReplicatedStorage.MutationSkins.<Model>.<Mutation>, where MutationLooks wears them
in place of the model's own SurfaceAppearance. Textures are scaled to `size`
(default 1024, Roblox's largest).
"""

import pathlib
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, SKINS, OUT = argv[0], pathlib.Path(argv[1]), pathlib.Path(argv[2])
SIZE = int(argv[3]) if len(argv) > 3 else 1024
MUTATIONS = ["Albino", "Melanistic", "Piebald", "Chimera", "Iridescent"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)


def find_image(prefix: str):
    for image in bpy.data.images:
        if image.name.lower().startswith(prefix) and image.size[0] > 0:
            return image
    return None


def fit(image):
    if image is not None and max(image.size) > SIZE:
        image.scale(SIZE, SIZE)
    return image


normal = fit(find_image("normal"))
orm = fit(find_image("orm"))
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)

made = 0
for index, mutation in enumerate(MUTATIONS):
    path = SKINS / f"{mutation}.png"
    if not path.exists():
        continue
    skin = fit(bpy.data.images.load(str(path)))
    skin.name = f"{OUT.stem}_{mutation}"
    mat = bpy.data.materials.new(mutation)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    color = nodes.new("ShaderNodeTexImage")
    color.image = skin
    links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    if normal is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = normal
        tex.image.colorspace_settings.name = "Non-Color"
        node = nodes.new("ShaderNodeNormalMap")
        links.new(tex.outputs["Color"], node.inputs["Color"])
        links.new(node.outputs["Normal"], bsdf.inputs["Normal"])
    if orm is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = orm
        tex.image.colorspace_settings.name = "Non-Color"
        split = nodes.new("ShaderNodeSeparateColor")
        links.new(tex.outputs["Color"], split.inputs["Color"])
        links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    bpy.ops.mesh.primitive_plane_add(size=0.2, location=(index * 0.3, 0, 0))
    quad = bpy.context.active_object
    quad.name = mutation
    quad.data.name = mutation
    quad.data.materials.append(mat)
    made += 1

if made == 0:
    raise SystemExit(f"no skins in {SKINS}")
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUT), export_format="GLB", export_image_format="JPEG", export_jpeg_quality=92
)
print(f"[pack] {OUT.name}: {made} skins")
