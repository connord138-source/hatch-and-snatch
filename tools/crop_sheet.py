"""Cuts the separate props out of a prop sheet (a plain light background with a few
props on it) into their own images, for Tripo image_to_model.

    python3 tools/crop_sheet.py <sheet.png> <out_dir> Name1 Name2 ...

Props are found as connected regions that differ from the background, left to
right then top to bottom, and each is saved as <out_dir>/<Name>.png: a square
crop with a margin, on the sheet's own background.
"""

import sys
from collections import deque

import numpy as np
from PIL import Image


def regions(mask: np.ndarray, min_area: int):
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    for y0 in range(0, h, 2):
        for x0 in range(0, w, 2):
            if not mask[y0, x0] or seen[y0, x0]:
                continue
            queue = deque([(y0, x0)])
            seen[y0, x0] = True
            xs, ys = [], []
            while queue:
                y, x = queue.popleft()
                xs.append(x)
                ys.append(y)
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if len(xs) >= min_area:
                found.append((min(xs), min(ys), max(xs), max(ys), len(xs)))
    return found


def main():
    sheet, out_dir, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    im = Image.open(sheet).convert("RGB")
    small = im.resize((im.width // 2, im.height // 2))
    a = np.asarray(small).astype(np.float32)
    # The background is a soft gradient: compare each pixel with the sheet's
    # border color on its row
    bg_rows = np.stack([np.median(np.concatenate([a[y, :8], a[y, -8:]]), axis=0) for y in range(a.shape[0])])
    diff = np.abs(a - bg_rows[:, None, :]).max(axis=2)
    mask = diff > 18
    # Close small gaps (thin branches, glows) so a prop is one region
    from PIL import ImageFilter

    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))
    mask = np.asarray(m) > 0
    found = regions(mask, min_area=600)
    found.sort(key=lambda r: -r[4])
    found = found[: len(names)]
    # Reading order: rows first (props whose middles sit within a quarter of the
    # sheet's height share a row), then left to right
    found.sort(key=lambda r: (r[1] + r[3]) / 2)
    rows, row_of = [], {}
    for r in found:
        middle = (r[1] + r[3]) / 2
        if not rows or middle - rows[-1] > mask.shape[0] / 4:
            rows.append(middle)
        row_of[r] = len(rows)
    found.sort(key=lambda r: (row_of[r], r[0]))
    if len(found) < len(names):
        raise SystemExit(f"found {len(found)} props, expected {len(names)}")
    for name, (x0, y0, x1, y1, _) in zip(names, found):
        x0, y0, x1, y1 = (v * 2 for v in (x0, y0, x1, y1))
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        side = max(x1 - x0, y1 - y0) * 1.25 + 24
        box = (int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2))
        crop = Image.new("RGB", (box[2] - box[0], box[3] - box[1]), tuple(int(c) for c in bg_rows[int(cy / 2)]))
        # Only the part inside the sheet (a crop past the edge would come out black)
        inside = (max(box[0], 0), max(box[1], 0), min(box[2], im.width), min(box[3], im.height))
        crop.paste(im.crop(inside), (inside[0] - box[0], inside[1] - box[1]))
        crop = crop.resize((768, 768), Image.LANCZOS)
        crop.save(f"{out_dir}/{name}.png")
        print("cropped", name, box)


if __name__ == "__main__":
    main()
