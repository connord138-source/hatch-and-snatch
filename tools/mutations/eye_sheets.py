"""Contact sheets for picking eyes by hand (eyes.json), from bake_maps.py's face renders.

    python3 tools/mutations/eye_sheets.py <maps_dir> <out_dir> [--per 4] [--qa eyes.json]

Each sheet shows six models: the front view large and the two 75-degree views
beside it, with a coordinate grid (labels in the renders' own 512 px coordinates,
a fine line every 32) so a pick is [view, x, y, radius]. Dark coats are lifted so
the eyes show. With --qa, the picks already in
eyes.json are drawn as circles instead, to check them.
"""

import argparse
import json
import pathlib

import numpy as np
from PIL import Image, ImageDraw

VIEWS = (0, 3, 4)  # front, turned 75 degrees each way
BIG, SMALL = 400, 200  # the front view large, the side views beside it
COLS = 2


def render(face: np.ndarray) -> Image.Image:
    rgb = np.clip(face[..., :3], 0, 1)
    mask = face[..., 5] > 0.5
    bg = np.array([0.16, 0.17, 0.2])
    rgb = np.where(mask[..., None], rgb, bg)
    # Lift the dark coats so the eyes show (picking only; the skins use the texture)
    rgb = np.where(mask[..., None], rgb ** 0.6, rgb)
    return Image.fromarray((rgb * 255).astype(np.uint8))


def gridded(im: Image.Image, size: int, picks, view: int, qa: bool) -> Image.Image:
    scale = size / 512
    im = im.resize((size, size))
    d = ImageDraw.Draw(im)
    if qa:
        for v, x, y, r in picks:
            if v == view:
                d.ellipse(((x - r) * scale, (y - r) * scale, (x + r) * scale, (y + r) * scale), outline=(255, 40, 40), width=2)
    else:
        step = 32 if size >= 400 else 64
        for g in range(step, 512, step):
            major = g % 64 == 0
            color = (90, 200, 255) if major else (60, 110, 150)
            d.line(((g * scale, 0), (g * scale, size)), fill=color, width=1)
            d.line(((0, g * scale), (size, g * scale)), fill=color, width=1)
            if major:
                d.text((g * scale + 2, 2), str(g), fill=(150, 240, 255))
                d.text((2, g * scale + 2), str(g), fill=(150, 240, 255))
    d.text((size - 22, size - 13), f"v{view}", fill=(255, 255, 255))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("maps")
    ap.add_argument("out")
    ap.add_argument("--per", type=int, default=6)
    ap.add_argument("--qa")
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    picks = json.load(open(args.qa)) if args.qa else {}
    names = sorted(p.stem for p in pathlib.Path(args.maps).glob("*.npz"))
    if args.only:
        names = [n for n in names if n in args.only]
    global BIG, SMALL, COLS
    if args.qa:  # smaller cells, more per sheet: only the circles need checking
        BIG, SMALL, COLS = 240, 120, 4
        args.per = 16
    cell_w, cell_h = BIG + SMALL, BIG + 16
    for start in range(0, len(names), args.per):
        batch = names[start : start + args.per]
        rows = (len(batch) + COLS - 1) // COLS
        sheet = Image.new("RGB", (cell_w * COLS, cell_h * rows), (20, 20, 24))
        draw = ImageDraw.Draw(sheet)
        for k, name in enumerate(batch):
            x0, y0 = (k % COLS) * cell_w, (k // COLS) * cell_h
            faces = np.load(pathlib.Path(args.maps) / f"{name}.npz")["faces"]
            these = picks.get(name, {}).get("picks", [])
            draw.text((x0 + 4, y0 + 2), name, fill=(255, 230, 120))
            sheet.paste(gridded(render(faces[0]), BIG, these, 0, bool(args.qa)), (x0, y0 + 16))
            sheet.paste(gridded(render(faces[3]), SMALL, these, 3, bool(args.qa)), (x0 + BIG, y0 + 16))
            sheet.paste(gridded(render(faces[4]), SMALL, these, 4, bool(args.qa)), (x0 + BIG, y0 + 16 + SMALL))
            if args.qa and not these:
                draw.text((x0 + 4, y0 + 20), "no eyes picked", fill=(255, 120, 120))
        path = out / f"{'qa' if args.qa else 'eyes'}_{start // args.per:02d}.png"
        sheet.save(path)
        print("wrote", path, ", ".join(batch))


if __name__ == "__main__":
    main()
