"""
Contact sheets for checking that rigged creatures face the right way, without Studio.

    pip install bpy pillow          # bpy's wheel matches one Python version (5.0 -> 3.11)
    python tools/blender/facing_check.py assets/fbx OUT_DIR [Name,Name,...]

For every FBX from rig_all.py it draws the mesh's vertices in their texture colors, side
view above and top view below, head end expected on the LEFT (rig_creature.py turns the
head to -Y). Faces and eyes read clearly in color. It writes OUT_DIR/facing_<n>.png, 24
models per sheet. A creature whose tail is on the left needs "flip" in
tools/blender/bodyplans.json ("front", "frontBaby" or "frontJuvenile" for its stage),
and a top view that isn't lying along the sheet means it wasn't squared up.
"""

import pathlib
import sys

import bpy
from PIL import Image, ImageDraw

CELL_W, SIDE_H, TOP_H = 250, 250, 125


def texture_pixels(obj):
    for slot in obj.material_slots:
        material = slot.material
        if material and material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image and node.image.size[0] > 0:
                    return node.image.size[0], node.image.size[1], node.image.pixels[:]
    return None


def colored_points(fbx: pathlib.Path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    points = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        tex = texture_pixels(obj)
        uv = obj.data.uv_layers.active.data if obj.data.uv_layers.active else None
        seen = set()
        for poly in obj.data.polygons:
            for loop in poly.loop_indices:
                index = obj.data.loops[loop].vertex_index
                if index in seen:
                    continue
                seen.add(index)
                co = obj.matrix_world @ obj.data.vertices[index].co
                color = (60, 60, 60)
                if tex and uv:
                    w, h, px = tex
                    u, v = uv[loop].uv
                    k = (int((v % 1) * (h - 1)) * w + int((u % 1) * (w - 1))) * 4
                    color = tuple(int(max(0.0, min(1.0, c)) ** (1 / 2.2) * 255) for c in px[k : k + 3])
                points.append((co.y, co.z, co.x, color))
    return points


def draw(points, label: str) -> Image.Image:
    img = Image.new("RGB", (CELL_W, SIDE_H + TOP_H), (235, 235, 235))
    d = ImageDraw.Draw(img)
    if points:
        ys, zs, xs = [p[0] for p in points], [p[1] for p in points], [p[2] for p in points]
        span = max(max(ys) - min(ys), max(zs) - min(zs), max(xs) - min(xs), 1e-6)
        mid_x = (min(xs) + max(xs)) / 2
        for y, z, x, c in sorted(points, key=lambda p: -p[2]):
            px, pz = 5 + (y - min(ys)) / span * 240, SIDE_H - 5 - (z - min(zs)) / span * 235
            d.rectangle((px, pz, px + 1, pz + 1), fill=c)
        for y, z, x, c in sorted(points, key=lambda p: p[1]):
            px, pz = 5 + (y - min(ys)) / span * 240, SIDE_H + TOP_H / 2 + (x - mid_x) / span * 120
            d.rectangle((px, pz, px + 1, pz + 1), fill=c)
    d.line((0, SIDE_H, CELL_W, SIDE_H), fill=(150, 150, 200))
    d.text((3, 3), f"{label}  (head LEFT)", fill=(200, 0, 0))
    return img


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    fbx_dir, out_dir = pathlib.Path(args[0]), pathlib.Path(args[1])
    only = set(args[2].split(",")) if len(args) > 2 else None
    out_dir.mkdir(parents=True, exist_ok=True)
    files = [f for f in sorted(fbx_dir.glob("*.fbx")) if only is None or f.stem in only]
    cells = [draw(colored_points(f), f.stem) for f in files]
    for start in range(0, len(cells), 24):
        chunk = cells[start : start + 24]
        sheet = Image.new("RGB", (CELL_W * 6, (SIDE_H + TOP_H) * ((len(chunk) + 5) // 6)), "white")
        for i, cell in enumerate(chunk):
            sheet.paste(cell, ((i % 6) * CELL_W, (i // 6) * (SIDE_H + TOP_H)))
        sheet.save(out_dir / f"facing_{start // 24}.png")
    print(f"{len(cells)} model(s) -> {out_dir}")


main()
