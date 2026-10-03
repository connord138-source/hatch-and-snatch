#!/usr/bin/env python3
"""
make_gem_tex.py -- "Diamond Gem" tileable PBR set for the creatures' Diamond finish.

Owner, 2026-10-03: the Diamond finish was "far too flat and needs to resemble
diamond from Fortnite": a crystal skin of crisp facets, pale ice-white faces
against deeper blue ones, bright edges and opal glints. Built procedurally with
numpy + Pillow as a seamless Voronoi facet field:

  gem_color.png      sRGB albedo: each facet flat-shaded from a baked key light
                     (so the facets read even in flat light), pastel opal tints
                     on some, bright girdle lines and a few star glints; max ~235
  gem_normal.png     tangent-space normal, OpenGL / Roblox (+Y = green up): every
                     cell is cut like a gem's crown, a fan of 5-7 tilted facets
                     meeting at a point, ridged at the cell edges
  gem_roughness.png  linear grayscale: facets ~0.06-0.14 (glossy), edges ~0.3
  preview_gem.png    color x Lambert shading from the normal map, tiled 2x2

Seamless by construction: sites are wrapped on a torus, so every distance is
taken mod T and the maps tile in both directions.

Usage:  python tools/textures/make_gem_tex.py [out_dir]
        (default: assets/textures; the preview lands there too, untracked)

Upload the three maps to Roblox (Studio Asset Manager), put their ids in
src/shared/Config/Materials.luau (DiamondGem), run tools/studio/make_materials.luau
in Studio's Command Bar and save the place.
"""

import math
import os
import sys

import numpy as np
from PIL import Image

T = 1024  # tile size in px
SITES = 46  # facets per tile (one tile = 4 studs on a creature)
SEED = 2026
BAND = 32  # rows per batch (memory bound)
EDGE = 3.0  # px: half-width of the bright girdle line between facets
RIDGE = 7.0  # px: normals bend toward the edge within this distance
MAX_RGB = 235.0  # keeps a white gem under the bloom threshold in full sun

DEEP = np.array([122.0, 162.0, 214.0])  # facets turned away from the light
PALE = np.array([240.0, 247.0, 255.0])  # facets facing it
TINTS = np.array(
    [
        [255.0, 210.0, 236.0],  # rose
        [222.0, 210.0, 255.0],  # lilac
        [204.0, 250.0, 232.0],  # mint
        [255.0, 244.0, 204.0],  # champagne
        [200.0, 232.0, 255.0],  # sky
    ]
)
KEY = np.array([-0.45, 0.55, 0.70])  # baked key light (upper left, toward the viewer)
KEY /= np.linalg.norm(KEY)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/textures"
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(SEED)

    # Sites, jittered on a grid so the facets stay even in size
    side = math.ceil(math.sqrt(SITES))
    cell = T / side
    sites = []
    for gy in range(side):
        for gx in range(side):
            if len(sites) == SITES:
                break
            sites.append(((gx + rng.uniform(0.15, 0.85)) * cell, (gy + rng.uniform(0.15, 0.85)) * cell))
    sites = np.array(sites)
    n = len(sites)

    # Each cell is a low pyramid: a fan of `wedges` facets around its site, each
    # tilted toward its own direction, so the cell catches light like a cut stone
    wedges = rng.integers(5, 8, n)
    spin = rng.uniform(0, 2 * math.pi, n)
    slope = np.radians(rng.uniform(22, 38, n))
    lean = rng.normal(0, 0.18, (n, 2))  # the whole cell leans a little too
    tinted = rng.random(n) < 0.22
    tint_pick = TINTS[rng.integers(0, len(TINTS), n)]
    amount = rng.uniform(0.2, 0.35, n)
    facet_rough = rng.uniform(0.05, 0.12, n)

    def facet(f, theta):
        # Normal of the facet of cell f facing direction theta
        nx = np.sin(slope[f]) * np.cos(theta) + lean[f, 0]
        ny = np.sin(slope[f]) * np.sin(theta) + lean[f, 1]
        nz = np.cos(slope[f])
        v = np.stack([nx, ny, np.broadcast_to(nz, nx.shape)], axis=-1)
        return v / np.linalg.norm(v, axis=-1, keepdims=True)

    def shade_rgb(f, nrm):
        s = np.clip(nrm @ KEY, 0, 1)
        s = np.clip((s - 0.32) / 0.55, 0, 1) ** 1.1  # wide contrast between facets, mostly bright
        rgb = DEEP + (PALE - DEEP) * s[..., None]
        t = (tinted[f] * amount[f])[..., None]
        return rgb * (1 - t) + (rgb * tint_pick[f] / 255.0) * t * 1.2

    # The 9 wrapped copies of every site (torus)
    offsets = np.array([(dx, dy) for dy in (-T, 0, T) for dx in (-T, 0, T)], dtype=np.float64)
    wrapped = (sites[None, :, :] + offsets[:, None, :]).reshape(-1, 2)  # (9n, 2)
    owner = np.tile(np.arange(n), 9)

    color = np.zeros((T, T, 3))
    normal = np.zeros((T, T, 3))
    rough = np.zeros((T, T))
    xs = np.arange(T) + 0.5
    for y0 in range(0, T, BAND):
        ys = np.arange(y0, min(T, y0 + BAND)) + 0.5
        px, py = np.meshgrid(xs, ys)
        p = np.stack([px, py], axis=-1)  # (b, T, 2)
        d2 = ((p[:, :, None, :] - wrapped[None, None, :, :]) ** 2).sum(-1)  # (b, T, 9n)
        order = np.argsort(d2, axis=-1)[:, :, :2]
        i1, i2 = order[..., 0], order[..., 1]
        a = wrapped[i1]
        b = wrapped[i2]
        # Distance to the bisector between the nearest two sites = distance to the edge
        ab = b - a
        lab = np.linalg.norm(ab, axis=-1) + 1e-9
        da2 = ((p - a) ** 2).sum(-1)
        db2 = ((p - b) ** 2).sum(-1)
        edge = (db2 - da2) / (2 * lab)
        f = owner[i1]
        # Which wedge of the cell's fan the pixel is in, and how far from a wedge seam
        rel = p - a
        radius = np.linalg.norm(rel, axis=-1)
        ang = (np.arctan2(rel[..., 1], rel[..., 0]) - spin[f]) % (2 * math.pi)
        width = 2 * math.pi / wedges[f]
        w = np.floor(ang / width)
        theta = spin[f] + (w + 0.5) * width
        seam = np.minimum(ang - w * width, (w + 1) * width - ang) * radius  # px to the seam

        nrm = facet(f, theta)
        # Ridge: near the cell edge the facet steepens, so the girdle catches light
        k = np.clip(1 - edge / RIDGE, 0, 1)[..., None] * 0.35
        nrm = nrm * (1 - k) + np.stack([rel[..., 0], rel[..., 1], np.zeros_like(radius)], -1) / (
            radius[..., None] + 1e-9
        ) * k
        nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)

        rgb = shade_rgb(f, nrm)
        # Fine bright seams between a cell's facets, brighter lines at the cell edge
        seam_line = np.clip(1 - seam / 1.4, 0, 1)[..., None] * 0.45
        rgb = rgb * (1 - seam_line) + 250.0 * seam_line
        line = np.clip(1 - edge / EDGE, 0, 1)[..., None]
        rgb = rgb * (1 - line * 0.85) + np.array([246.0, 252.0, 255.0]) * line * 0.85
        rows = slice(y0, y0 + len(ys))
        color[rows] = rgb
        normal[rows] = nrm
        rough[rows] = facet_rough[f] * (1 - line[..., 0]) + 0.3 * line[..., 0]

    # Star glints at a few facet corners (wrapped distance)
    yy, xx = np.mgrid[0:T, 0:T] + 0.5
    for _ in range(14):
        cx, cy = rng.uniform(0, T, 2)
        dx = np.abs((xx - cx + T / 2) % T - T / 2)
        dy = np.abs((yy - cy + T / 2) % T - T / 2)
        r = rng.uniform(10, 22)
        star = np.clip(1 - (dx * dy) ** 0.5 / 2.2, 0, 1) * np.clip(1 - np.maximum(dx, dy) / r, 0, 1)
        dot = np.clip(1 - np.hypot(dx, dy) / 4, 0, 1)
        g = np.clip(star + dot, 0, 1)[..., None]
        color = color * (1 - g) + 250.0 * g

    # Keep under MAX_RGB, compressing the brightest values (hue kept)
    peak = color.max(-1, keepdims=True)
    over = peak > 220
    scale = np.where(over, (220 + (np.minimum(peak, 300) - 220) * (MAX_RGB - 220) / 80) / np.maximum(peak, 1), 1)
    color = np.clip(color * scale, 0, MAX_RGB)

    Image.fromarray(color.astype(np.uint8), "RGB").save(os.path.join(out, "gem_color.png"))
    nimg = ((normal * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)
    Image.fromarray(nimg, "RGB").save(os.path.join(out, "gem_normal.png"))
    Image.fromarray((rough * 255).clip(0, 255).astype(np.uint8), "L").save(os.path.join(out, "gem_roughness.png"))

    # Preview: albedo x Lambert from a light at the upper right (not the baked key)
    light = np.array([0.5, 0.45, 0.74])
    light /= np.linalg.norm(light)
    lambert = np.clip((normal @ light), 0, 1) * 0.75 + 0.35
    spec = np.clip(normal @ light, 0, 1) ** 40 * (1 - rough) * 255
    lit = np.clip(color * lambert[..., None] + spec[..., None], 0, 255).astype(np.uint8)
    tiled = np.tile(lit, (2, 2, 1))
    Image.fromarray(tiled, "RGB").resize((1024, 1024), Image.LANCZOS).save(os.path.join(out, "preview_gem.png"))
    print("wrote gem_color.png, gem_normal.png, gem_roughness.png, preview_gem.png to", out)


if __name__ == "__main__":
    main()
