"""Draws the island layout top-down from a Landmarks part dump (see run_island.sh).
Zones, plots and the plaza are drawn from the same constants as WorldService."""
import math
import sys

from PIL import Image, ImageDraw

dump, out = sys.argv[1], sys.argv[2]
ISLAND, ZONE_INNER, ZONE_OUTER, PLOT_RADIUS = 410, 205, 295, 128
SCALE, SIZE = 2, 1800
C = SIZE / 2
img = Image.new("RGB", (SIZE, SIZE), (70, 140, 200))
d = ImageDraw.Draw(img)


def px(x, z):
    return (C + x * SCALE, C + z * SCALE)


def circle(r, fill=None, outline=None, width=1):
    d.ellipse((C - r * SCALE, C - r * SCALE, C + r * SCALE, C + r * SCALE), fill=fill, outline=outline, width=width)


circle(ISLAND + 20, fill=(226, 205, 150))
circle(ISLAND, fill=(98, 150, 72))
circle(56, fill=(170, 160, 140))
circle(46, outline=(60, 60, 70), width=4)
NORTH = -math.pi / 2
GAP = math.radians(8)
span = (math.pi - GAP) / 3
colors = {"FrostShelf": (205, 232, 250), "MagmaRift": (90, 50, 40), "StormPeaks": (80, 85, 105),
          "CoralCoast": (232, 212, 165), "Mossvale": (96, 150, 70), "Moonfall": (140, 130, 170)}
for i, biome in enumerate(["FrostShelf", "MagmaRift", "StormPeaks", "CoralCoast", "Mossvale", "Moonfall"]):
    start = (NORTH + GAP / 2) if i < 3 else (NORTH + math.pi + GAP / 2)
    a0 = start + (i % 3) * span
    a1 = a0 + span
    pts = [px(math.cos(a0 + (a1 - a0) * t / 40) * ZONE_OUTER, math.sin(a0 + (a1 - a0) * t / 40) * ZONE_OUTER) for t in range(41)]
    pts += [px(math.cos(a1 - (a1 - a0) * t / 40) * ZONE_INNER, math.sin(a1 - (a1 - a0) * t / 40) * ZONE_INNER) for t in range(41)]
    d.polygon(pts, fill=colors[biome], outline=(40, 40, 45))
    mid = (a0 + a1) / 2
    d.text(px(math.cos(mid) * 250 - 20, math.sin(mid) * 250), biome, fill=(0, 0, 0))
# plots (level 5 footprint plus walls), front facing the hub
for k in range(6):
    a = k / 6 * 2 * math.pi
    cx, cz = math.cos(a) * PLOT_RADIUS, math.sin(a) * PLOT_RADIUS
    fwd = (-math.cos(a), -math.sin(a))  # toward hub = local -Z
    right = (-fwd[1], fwd[0])
    corners = []
    for lx, lz in ((-41, -25), (41, -25), (41, 49), (-41, 49)):
        wx = cx + right[0] * lx - fwd[0] * lz
        wz = cz + right[1] * lx - fwd[1] * lz
        corners.append(px(wx, wz))
    d.polygon(corners, fill=(150, 145, 135), outline=(60, 60, 60))
for line in open(dump):
    if not line.startswith("P|"):
        continue
    f = line.strip().split("|")
    size = [float(v) for v in f[3].split(",")]
    pos = [float(v) for v in f[4].split(",")]
    right = [float(v) for v in f[5].split(",")]
    up = [float(v) for v in f[6].split(",")]
    back = [float(v) for v in f[7].split(",")]
    col = tuple(int(float(v) * 255) for v in f[8].split(","))
    shape = f[2]
    # footprint: project the box's local axes onto the ground
    axes = [(right, size[0]), (up, size[1]), (back, size[2])]
    if shape == "Cylinder":
        r = size[1] / 2
        d.ellipse((*px(pos[0] - r, pos[2] - r), *px(pos[0] + r, pos[2] + r)), fill=col)
        continue
    pts = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        # use the two axes with the largest ground extent
        ground = sorted(axes, key=lambda a: -(abs(a[0][0]) + abs(a[0][2])) * a[1])[:2]
        x = pos[0] + ground[0][0][0] * ground[0][1] / 2 * sx + ground[1][0][0] * ground[1][1] / 2 * sz
        z = pos[2] + ground[0][0][2] * ground[0][1] / 2 * sx + ground[1][0][2] * ground[1][1] / 2 * sz
        pts.append(px(x, z))
    d.polygon(pts, fill=col)
d.text((20, 20), "N (-Z) is up", fill=(255, 255, 255))
img.save(out)
print("wrote", out)
