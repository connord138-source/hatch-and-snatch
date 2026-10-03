#!/usr/bin/env python3
"""
make_diamond_tex.py -- "Diamond Stone" tileable PBR set for Hatch & Snatch.

A masonry wall of cut-diamond blocks, built procedurally with numpy + Pillow:

  diamond_color.png      sRGB albedo: cool white-silver, faceted, thin-film
                         iridescence and sparse sparkles baked in; max ~235
  diamond_normal.png     tangent-space normal, OpenGL / Roblox (+Y = green up)
  diamond_roughness.png  linear grayscale: facets ~0.25-0.35, grout ~0.8
  preview_tiled.png      color map tiled 3x3, downscaled to 1536 px (seam check)
  preview_wall.png       color x Lambert shading from the normal map, sun from
                         the upper left, tiled 2x2, downscaled to 1536 px

Seamless by construction: every field is a function of (x mod T, y mod T),
noise lives on periodic lattices, and sparkles use wrapped distances, so the
maps tile in both directions.

Layout (one tile = 8 studs at StudsPerTile 8, i.e. 128 px per stud):
  8 courses x 4 blocks (~2:1, widths and course heights jittered), running
  bond, 7 px pale grout. Each block face is a rectangular "radiant" brilliant:
  a small octagonal table, 8 star facets, 8 kite (bezel) facets and 16 upper
  girdle facets, stretched to the block, with a 5 px chamfer into the grout.

Usage:  python tools/textures/make_diamond_tex.py [out_dir]
        (default: assets/textures; the previews land there too, untracked)

Upload the three maps to Roblox (Studio Asset Manager) and put their ids in
src/shared/Config/Materials.luau (DiamondStone).
"""

import math
import os
import sys

import numpy as np
from PIL import Image

# --------------------------------------------------------------------------
# Parameters
# --------------------------------------------------------------------------
T = 1024  # tile size in px
SS = 4  # supersamples per axis (SS*SS per pixel) -> clean facet edges
SEED = 1617  # layout / random seed (any value gives a seamless tile)
BAND = 32  # rows evaluated per batch (memory bound)

ROWS, COLS = 8, 4  # courses per tile, blocks per course
GROUT_HALF = 3.5  # px; grout line is 7 px wide
BEVEL = 5.0  # px chamfer from the girdle down into the grout
CORNER = 4.0  # px rounding of each block's outer corners

TAN = math.tan(math.radians(22.5))
SQ = math.sqrt(0.5)

# Albedo (sRGB, 0-255)
BASE = np.array([214.0, 216.0, 221.0])  # cool white-silver facet base
GROUT = np.array([191.0, 192.0, 197.0])  # pale silver-grey grout
MAX_RGB = 235.0  # hard ceiling for any channel
KNEE = 226.0  # brighter pixels are compressed (hue kept) toward MAX_RGB
# facet types: 0 table, 1 star, 2 kite (bezel), 3 upper girdle
TYPE_BRIGHT = np.array([1.030, 1.000, 0.975, 0.945])
BR_JIT = 0.060  # +- per-facet brightness jitter
BEVEL_BRIGHT = 0.915
EDGE_GAIN = 0.030  # faint light line on polished facet junctions
EDGE_W = 0.75  # px

# Normal map (facet tilt from vertical, before the 2:1 stretch)
TYPE_TILT = np.radians([0.0, 9.0, 15.0, 21.0])
TILT_JIT = 0.20  # +- fraction
AZ_JIT = math.radians(9.0)  # +- azimuth jitter per facet
CUT_JIT = 0.020  # +- small random slope per facet (imperfect cut)
BLOCK_TILT = 0.018  # sd of a whole-block slope (hand-laid look)
STRETCH = 0.6  # 0 = ignore block aspect, 1 = true stretched-gem slopes
BEV_TILT0, BEV_TILT1 = 28.0, 50.0  # chamfer tilt (deg) at girdle -> grout
GROUT_BUMP = 1.4  # grout micro-relief strength

# Roughness (linear 0-1)
FACET_ROUGH = (0.25, 0.35)
BEVEL_ROUGH = 0.45
GROUT_ROUGH = 0.80
SPARK_ROUGH = 0.12

# Iridescence (thin-film tints baked into the albedo)
PALETTE = np.array(
    [
        [1.00, 0.84, 0.91],  # pale pink
        [0.90, 0.85, 1.00],  # lavender
        [0.81, 0.91, 1.00],  # sky blue
        [0.82, 1.00, 0.91],  # mint
        [1.00, 0.95, 0.79],  # pale gold
    ]
)
PALETTE = PALETTE / PALETTE.mean(axis=1, keepdims=True)  # hue only, unit luma-ish
PALETTE = PALETTE / PALETTE.mean(axis=0, keepdims=True)  # cycle averages to neutral
IRI = 0.22  # typical tint strength (fraction of the palette deviation)
FIRE_FRAC = 0.08  # share of facets that flash stronger "fire"
FIRE_MULT = 2.5
PH_FACET = 0.22  # per-facet hue offset (cycles)
PH_BLOCK = 0.15  # per-block hue offset (cycles)
PH_SLOW = 1.0  # slow drift across the tile (cycles, peak-to-peak-ish)
RAMP = 0.12  # thin-film hue ramp within a facet (cycles per 100 px)

# Sparkles
N_SPARK = 42
SPARK_MIN_DIST = 64.0


# --------------------------------------------------------------------------
# Periodic helpers
# --------------------------------------------------------------------------
def value_noise(X, Y, grid):
    """Quintic-interpolated value noise on an n x n lattice wrapping every T px."""
    n = grid.shape[0]
    fx = np.mod(X, T) * (n / T)
    fy = np.mod(Y, T) * (n / T)
    ix = np.floor(fx).astype(np.int64)
    iy = np.floor(fy).astype(np.int64)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * tx * (tx * (tx * 6 - 15) + 10)
    ty = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
    ix %= n
    iy %= n
    jx = (ix + 1) % n
    jy = (iy + 1) % n
    a = grid[iy, ix]
    b = grid[iy, jx]
    c = grid[jy, ix]
    d = grid[jy, jx]
    top = a + (b - a) * tx
    bot = c + (d - c) * tx
    return top + (bot - top) * ty


def fbm(X, Y, grids, amps):
    out = np.zeros(np.broadcast(X, Y).shape)
    for g, a in zip(grids, amps):
        out += a * value_noise(X, Y, g)
    return out / sum(amps)


def palette(phase):
    """Cyclic linear interpolation through PALETTE; phase in cycles."""
    n = len(PALETTE)
    p = np.mod(phase, 1.0) * n
    i0 = np.floor(p).astype(np.int64) % n
    i1 = (i0 + 1) % n
    f = (p - np.floor(p))[..., None]
    return PALETTE[i0] * (1 - f) + PALETTE[i1] * f


def srgb_to_lin(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


# --------------------------------------------------------------------------
# Layout and per-block / per-facet random data
# --------------------------------------------------------------------------
class Layout:
    """Running-bond courses on the torus; joints in adjacent courses stay apart."""

    def __init__(self, rng):
        avg = T / COLS
        for _ in range(200000):
            rh = rng.uniform(0.93, 1.07, ROWS)
            rh = rh / rh.sum() * T
            w = rng.uniform(0.82, 1.18, (ROWS, COLS))
            w = w / w.sum(axis=1, keepdims=True) * T
            off = (np.arange(ROWS) % 2) * 0.5 * avg + rng.uniform(-0.12, 0.12, ROWS) * avg
            start = np.concatenate([np.zeros((ROWS, 1)), np.cumsum(w, axis=1)[:, :-1]], axis=1)
            joints = np.mod(start + off[:, None], T)
            ok = True
            for r in range(ROWS):  # includes the wrap pair (ROWS-1, 0)
                a, b = joints[r], joints[(r + 1) % ROWS]
                d = np.abs(np.mod(a[:, None] - b[None, :] + T / 2, T) - T / 2)
                if d.min() < 0.30 * avg:
                    ok = False
                    break
            if ok:
                break
        else:
            raise RuntimeError("no valid layout found")
        self.row_h = rh
        self.row_y0 = np.concatenate([[0.0], np.cumsum(rh)[:-1]])
        self.w = w
        self.start = start
        self.off = off

    def block_center(self, r, i):
        cx = np.mod(self.off[r] + self.start[r, i] + 0.5 * self.w[r, i], T)
        cy = self.row_y0[r] + 0.5 * self.row_h[r]
        gx = 0.5 * self.w[r, i] - GROUT_HALF - BEVEL
        gy = 0.5 * self.row_h[r] - GROUT_HALF - BEVEL
        return cx, cy, gx, gy


class Params:
    def __init__(self, rng, nb):
        self.rt = rng.uniform(0.25, 0.32, nb)  # table radius (girdle = 1)
        self.rs0 = rng.uniform(0.56, 0.64, nb)  # star apex toward the edge midpoints
        self.rs1 = rng.uniform(0.60, 0.70, nb)  # star apex toward the corners
        self.btx = rng.normal(0, BLOCK_TILT, nb)
        self.bty = rng.normal(0, BLOCK_TILT, nb)
        self.bbright = 1 + rng.uniform(-0.018, 0.018, nb)
        self.bphase = rng.uniform(0, 1, nb)
        # per facet: 0 tilt, 1 azimuth, 2 brightness, 3 hue, 4 fire, 5 iri amount,
        #            6 roughness, 7/8 cut jitter
        self.fr = rng.random((nb, 33, 9))


# --------------------------------------------------------------------------
# Core field evaluation at arbitrary sample points
# --------------------------------------------------------------------------
def evaluate(L, P, X, Y, noise):
    x = np.mod(X, T)
    y = np.mod(Y, T)
    r = np.clip(np.searchsorted(L.row_y0, y, side="right") - 1, 0, ROWS - 1)
    xl = np.mod(x - L.off[r], T)
    i = np.zeros(x.shape, np.int64)
    for k in range(1, COLS):
        i += xl >= L.start[r, k]
    w = L.w[r, i]
    h = L.row_h[r]
    dx = xl - (L.start[r, i] + 0.5 * w)
    dy = y - (L.row_y0[r] + 0.5 * h)  # image coords: +y is down
    b = r * COLS + i

    # rounded-rectangle SDF of the block's top face (negative inside)
    hx = 0.5 * w - GROUT_HALF
    hy = 0.5 * h - GROUT_HALF
    qx = np.abs(dx) - (hx - CORNER)
    qy = np.abs(dy) - (hy - CORNER)
    sdf = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - CORNER
    face = sdf < -BEVEL
    bevel = (sdf >= -BEVEL) & (sdf < 0)

    # facet pattern in girdle space [-1,1]^2, folded into the wedge 0 <= V <= U
    gx = hx - BEVEL
    gy = hy - BEVEL
    u = dx / gx
    v = dy / gy
    au, av = np.abs(u), np.abs(v)
    swap = av > au
    U = np.maximum(au, av)
    V = np.minimum(au, av)
    rt, rs0, rs1 = P.rt[b], P.rs0[b], P.rs1[b]
    t0x, t0y = rt, rt * TAN  # table vertex T0;  S0=(rs0,0)  S1=(rs1,rs1)  B0=(1,TAN)
    s_t0s0 = (rs0 - t0x) * (V - t0y) + t0y * (U - t0x)
    s_t0s1 = (rs1 - t0x) * (V - t0y) - (rs1 - t0y) * (U - t0x)
    s_s0b0 = (1.0 - rs0) * V - TAN * (U - rs0)
    s_s1b0 = (1.0 - rs1) * (V - rs1) - (TAN - rs1) * (U - rs1)
    in_table = (U <= rt) & (U + V <= rt * (1 + TAN))
    reg = np.full(U.shape, 4, np.int64)  # 4 kite
    reg[s_s1b0 > 0] = 6  # upper girdle by the corner
    reg[s_s0b0 <= 0] = 5  # upper girdle by the edge midpoint
    reg[s_t0s1 > 0] = 3  # star pointing at the corner
    reg[s_t0s0 < 0] = 2  # star pointing at the edge midpoint
    reg[in_table] = 1  # table

    ftype = np.select([reg == 1, reg <= 3, reg == 4], [0, 1, 2], 3)
    # representative outward direction of each facet (apex or centroid), folded
    kcx = (rt + rs0 + 1.0 + rs1) / 4
    kcy = (t0y + TAN + rs1) / 4
    conds = [reg == 2, reg == 3, reg == 4, reg == 5, reg == 6]
    dU = np.select(conds, [1.0, SQ, kcx, (rs0 + 2.0) / 3, (rs1 + 2.0) / 3], 0.0)
    dV = np.select(conds, [0.0, SQ, kcy, TAN / 3, (rs1 + TAN + 1.0) / 3], 0.0)
    pu = (u >= 0).astype(np.int64)
    pv = (v >= 0).astype(np.int64)
    sw = swap.astype(np.int64)
    su = 2.0 * pu - 1
    sv = 2.0 * pv - 1
    du = np.where(swap, dV, dU) * su  # unfold
    dv = np.where(swap, dU, dV) * sv
    octant = pu * 4 + pv * 2 + sw
    fid = np.select(
        [reg == 1, reg == 2, reg == 3, reg == 4, reg == 5],
        [0 * octant, 1 + np.where(swap, 2 + pv, pu), 5 + 2 * pu + pv, 9 + octant, 17 + octant],
        25 + octant,
    )
    fr = P.fr[b, fid]

    # distance (physical px) to the facet's own edges -> polished junction lines
    scU = np.where(swap, gy, gx)  # px per folded-uv unit along U and V
    scV = np.where(swap, gx, gy)
    diag = np.sqrt(scU**-2.0 + scV**-2.0)

    def line_dist(s, ax_, ay_, bx_, by_):  # s = side value of line A->B
        cu = (by_ - ay_) / scU
        cv = (bx_ - ax_) / scV
        return np.abs(s) / np.sqrt(cu * cu + cv * cv)

    d_tab1 = np.abs(U - rt) * scU
    d_tab2 = np.abs(U + V - rt * (1 + TAN)) / diag
    d_a = line_dist(s_t0s0, t0x, t0y, rs0, 0.0)
    d_b = line_dist(s_t0s1, t0x, t0y, rs1, rs1)
    d_c = line_dist(s_s0b0, rs0, 0.0, 1.0, TAN)
    d_d = line_dist(s_s1b0, rs1, rs1, 1.0, TAN)
    d_axis = V * scV  # ug0 meets its mirror on the fold line
    d_diag = np.abs(U - V) / diag  # ug1 meets its mirror on the diagonal
    edge = np.select(
        [reg == 1, reg == 2, reg == 3, reg == 4, reg == 5],
        [
            np.minimum(d_tab1, d_tab2),
            np.minimum(d_tab1, d_a),
            np.minimum(d_tab2, d_b),
            np.minimum(np.minimum(d_a, d_b), np.minimum(d_c, d_d)),
            np.minimum(d_c, d_axis),
        ],
        np.minimum(d_d, d_diag),
    )
    edge = np.minimum(edge, np.abs(sdf + BEVEL))  # girdle crease
    eline = np.exp(-((edge / EDGE_W) ** 2)) * (face | bevel)

    # facet normals (image coords, z up): tilt toward the facet's outward side,
    # slopes stretched with the block's aspect like a stretched gem
    geo = np.sqrt(gx * gy)
    sx = (gx / geo) ** STRETCH
    sy = (gy / geo) ** STRETCH
    pxd = du / sx
    pyd = dv / sy
    nuv = np.hypot(du, dv)
    m = np.where(nuv > 1e-9, np.hypot(pxd, pyd) / np.maximum(nuv, 1e-9), 1.0)
    tilt = TYPE_TILT[ftype] * (1 + TILT_JIT * (2 * fr[:, 0] - 1))
    slope = np.tan(tilt) * m
    phi = np.arctan2(pyd, pxd) + AZ_JIT * (2 * fr[:, 1] - 1)
    fnx = slope * np.cos(phi) + P.btx[b] + CUT_JIT * (2 * fr[:, 7] - 1)
    fny = slope * np.sin(phi) + P.bty[b] + CUT_JIT * (2 * fr[:, 8] - 1)

    # chamfer normals: outward along the SDF gradient, steepening toward the grout
    corner = (qx > 0) & (qy > 0)
    ex = np.where(corner, np.maximum(qx, 0), (qx >= qy).astype(np.float64))
    ey = np.where(corner, np.maximum(qy, 0), (qx < qy).astype(np.float64))
    en = np.hypot(ex, ey) + 1e-12
    ex = ex / en * np.where(dx >= 0, 1.0, -1.0)
    ey = ey / en * np.where(dy >= 0, 1.0, -1.0)
    tb = np.clip((sdf + BEVEL) / BEVEL, 0, 1)
    bslope = np.tan(np.radians(BEV_TILT0 + (BEV_TILT1 - BEV_TILT0) * tb))

    nx = np.where(face, fnx, np.where(bevel, bslope * ex, 0.0))
    ny = np.where(face, fny, np.where(bevel, bslope * ey, 0.0))
    nn = np.sqrt(nx * nx + ny * ny + 1.0)
    normal = np.stack([nx / nn, ny / nn, 1.0 / nn], axis=-1)

    # albedo: facet brightness x thin-film tint
    slow_ph, slow_amt = noise
    phase = (
        PH_SLOW * slow_ph
        + PH_FACET * fr[:, 3]
        + PH_BLOCK * P.bphase[b]
        + RAMP * (dx * np.cos(phi) + dy * np.sin(phi)) / 100.0
    )
    fire = (fr[:, 4] > 1 - FIRE_FRAC) & (ftype > 0)  # never the table: it would
    amt = IRI * (0.50 + 1.00 * fr[:, 5]) * np.where(fire, FIRE_MULT, 1.0)  # repeat as a hotspot
    amt = amt * (0.75 + 0.50 * slow_amt)
    bright = TYPE_BRIGHT[ftype] * (1 + BR_JIT * (2 * fr[:, 2] - 1)) * P.bbright[b]
    face_rgb = BASE * bright[:, None] * (1 + amt[:, None] * (palette(phase) - 1))
    bev_ph = PH_SLOW * slow_ph + PH_BLOCK * P.bphase[b] + 0.5
    bev_rgb = BASE * (BEVEL_BRIGHT * P.bbright[b])[:, None] * (1 + 0.6 * IRI * (palette(bev_ph) - 1))
    grout_rgb = GROUT * (1 + 0.3 * IRI * (palette(PH_SLOW * slow_ph + 0.3) - 1))
    rgb = np.where(face[:, None], face_rgb, np.where(bevel[:, None], bev_rgb, grout_rgb))
    rgb = rgb * (1 + EDGE_GAIN * eline)[:, None]

    rough = np.where(
        face,
        FACET_ROUGH[0] + (FACET_ROUGH[1] - FACET_ROUGH[0]) * fr[:, 6],
        np.where(bevel, BEVEL_ROUGH, GROUT_ROUGH),
    )
    return rgb, normal, rough, (sdf >= 0).astype(np.float64)


# --------------------------------------------------------------------------
# Sparkles (final resolution, wrapped)
# --------------------------------------------------------------------------
def sparkle_sites(L, P, rng):
    sites = []
    tries = 0
    while len(sites) < N_SPARK and tries < 20000:
        tries += 1
        r = int(rng.integers(ROWS))
        i = int(rng.integers(COLS))
        b = r * COLS + i
        cx, cy, gx, gy = L.block_center(r, i)
        kind = rng.random()
        sgn = rng.choice([-1.0, 1.0], 2)
        if kind < 0.40:  # star apex
            if rng.random() < 0.5:
                uv = (P.rs0[b], 0.0) if rng.random() < 0.5 else (0.0, P.rs0[b])
            else:
                uv = (P.rs1[b], P.rs1[b])
        elif kind < 0.70:  # table corner
            uv = (P.rt[b], P.rt[b] * TAN) if rng.random() < 0.5 else (P.rt[b] * TAN, P.rt[b])
        elif kind < 0.85:  # kite tip on the girdle
            uv = (0.97, TAN) if rng.random() < 0.5 else (TAN, 0.97)
        else:  # somewhere on a facet
            uv = tuple(rng.uniform(0.15, 0.85, 2))
        px = np.mod(cx + sgn[0] * uv[0] * gx, T)
        py = np.mod(cy + sgn[1] * uv[1] * gy, T)
        ok = True
        for q in sites:
            ddx = abs(((px - q[0]) + T / 2) % T - T / 2)
            ddy = abs(((py - q[1]) + T / 2) % T - T / 2)
            if math.hypot(ddx, ddy) < SPARK_MIN_DIST:
                ok = False
                break
        if not ok:
            continue
        inten = float(np.clip(rng.lognormal(math.log(0.65), 0.35), 0.35, 1.0))
        arm = inten > 0.72 or rng.random() < 0.15
        sites.append((px, py, inten, arm))
    return sites


def render_sparkles(sites):
    spark = np.zeros((T, T))
    spec = np.zeros((T, T, 3))  # faint spectral fringe on the star arms
    R = 14
    idx = np.arange(-R, R + 1)
    for px, py, inten, arm in sites:
        ix, iy = int(math.floor(px)), int(math.floor(py))
        xs = (ix + idx) % T
        ys = (iy + idx) % T
        DX = (ix + idx + 0.5)[None, :] - px
        DY = (iy + idx + 0.5)[:, None] - py
        r2 = DX * DX + DY * DY
        core = np.exp(-r2 / (2 * 1.3**2))
        halo = 0.45 * np.exp(-r2 / (2 * 3.2**2))
        prof = np.maximum(core, halo)
        tint = np.zeros(prof.shape + (3,))
        if arm:
            alen = 3.0 + 5.0 * inten
            ax_ = np.exp(-DY * DY / (2 * 0.6**2)) * np.exp(-np.abs(DX) / alen)
            ay_ = np.exp(-DX * DX / (2 * 0.6**2)) * np.exp(-np.abs(DY) / alen)
            arms = 0.85 * np.maximum(ax_, ay_)
            prof = np.maximum(prof, arms)
            # rainbow fringe: warm on the horizontal arm, cool on the vertical
            tint += ax_[..., None] * np.array([0.03, 0.0, -0.03])
            tint += ay_[..., None] * np.array([-0.03, 0.0, 0.03])
        prof = inten * prof
        sub = np.ix_(ys, xs)
        spark[sub] = np.maximum(spark[sub], prof)
        spec[sub] += inten * tint
    return spark, spec


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------
def soft_ceiling(c):
    """Compress the brightest channel smoothly into [KNEE, MAX_RGB - 0.6]; scale the
    pixel's three channels together so its hue survives."""
    m = c.max(axis=-1, keepdims=True)
    span = MAX_RGB - 0.6 - KNEE
    m2 = np.where(m > KNEE, KNEE + span * (1 - np.exp(-(m - KNEE) / span)), m)
    return c * (m2 / np.maximum(m, 1e-6))


def build(out_dir):
    rng = np.random.default_rng(SEED)
    L = Layout(rng)
    P = Params(rng, ROWS * COLS)
    g_ph = [rng.random((n, n)) for n in (3, 6)]
    g_amt = [rng.random((n, n)) for n in (4, 8)]
    g_grout = [rng.random((n, n)) for n in (128, 256)]
    g_bump = [rng.random((n, n)) for n in (256, 512)]

    color = np.zeros((T, T, 3))
    normal = np.zeros((T, T, 3))
    rough = np.zeros((T, T))
    gcov = np.zeros((T, T))

    offs = (np.arange(SS) + 0.5) / SS
    oy, ox = np.meshgrid(offs, offs, indexing="ij")
    oy = oy.reshape(-1)[:, None, None]
    ox = ox.reshape(-1)[:, None, None]
    xs = np.arange(T, dtype=np.float64)[None, None, :]
    for y0 in range(0, T, BAND):
        ys = np.arange(y0, y0 + BAND, dtype=np.float64)[None, :, None]
        Y, X = np.broadcast_arrays(ys + oy, xs + ox)  # (SS*SS, BAND, T)
        Xf = X.reshape(-1)
        Yf = Y.reshape(-1)
        noise = (
            fbm(Xf, Yf, g_ph, [1.0, 0.45]) - 0.5,
            fbm(Xf, Yf, g_amt, [1.0, 0.5]),
        )
        rgb, nrm, rgh, grt = evaluate(L, P, Xf, Yf, noise)
        shp = (SS * SS, BAND, T)
        color[y0 : y0 + BAND] = rgb.reshape(shp + (3,)).mean(axis=0)
        normal[y0 : y0 + BAND] = nrm.reshape(shp + (3,)).mean(axis=0)
        rough[y0 : y0 + BAND] = rgh.reshape(shp).mean(axis=0)
        gcov[y0 : y0 + BAND] = grt.reshape(shp).mean(axis=0)

    # grout: mottled albedo/roughness and a fine relief in the normal map
    PY, PX = np.mgrid[0:T, 0:T].astype(np.float64) + 0.5
    gn = 2 * (fbm(PX, PY, g_grout, [1.0, 0.6]) - 0.5)
    color *= (1 + 0.04 * gn * gcov)[..., None]
    rough += 0.06 * gn * gcov
    hgt = fbm(PX, PY, g_bump, [1.0, 0.7])
    dhdx = 0.5 * (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1))
    dhdy = 0.5 * (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0))
    normal[..., 0] -= GROUT_BUMP * dhdx * gcov
    normal[..., 1] -= GROUT_BUMP * dhdy * gcov
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)

    # ceiling first, then sparkles push toward it (cores reach ~235), glossier
    color = soft_ceiling(color)
    sites = sparkle_sites(L, P, rng)
    spark, spec = render_sparkles(sites)
    target = np.array([MAX_RGB - 1.5, MAX_RGB - 0.8, MAX_RGB])
    color = color + (target - color) * spark[..., None] + spec * 255.0 * 0.5
    rough = rough + (SPARK_ROUGH - rough) * spark

    # dither, quantize
    color = color + rng.uniform(-0.5, 0.5, color.shape)
    col8 = np.clip(np.round(color), 0, MAX_RGB).astype(np.uint8)
    gl = np.stack([normal[..., 0], -normal[..., 1], normal[..., 2]], axis=-1)  # +Y up
    nrm8 = np.clip(np.round((gl * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8)
    rgh8 = np.clip(np.round(rough * 255), 0, 255).astype(np.uint8)

    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray(col8, "RGB").save(os.path.join(out_dir, "diamond_color.png"), optimize=True)
    Image.fromarray(nrm8, "RGB").save(os.path.join(out_dir, "diamond_normal.png"), optimize=True)
    Image.fromarray(rgh8, "L").save(os.path.join(out_dir, "diamond_roughness.png"), optimize=True)

    # previews
    tiled = np.tile(col8, (3, 3, 1))
    Image.fromarray(tiled, "RGB").resize((1536, 1536), Image.LANCZOS).save(
        os.path.join(out_dir, "preview_tiled.png"), optimize=True
    )
    n = nrm8.astype(np.float64) / 255 * 2 - 1  # decode what was saved
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    light = np.array([-1.0, 1.0, 1.25])  # from the upper left (GL: +y is up)
    light /= np.linalg.norm(light)
    ndl = np.clip(n @ light, 0, None)
    flat = light[2]
    shade = 0.35 + 0.65 * ndl / flat  # flat surface -> 1.0
    lit = lin_to_srgb(srgb_to_lin(col8 / 255.0) * shade[..., None])
    wall = np.round(np.tile(lit, (2, 2, 1)) * 255).astype(np.uint8)
    Image.fromarray(wall, "RGB").resize((1536, 1536), Image.LANCZOS).save(
        os.path.join(out_dir, "preview_wall.png"), optimize=True
    )

    report(col8, nrm8, rgh8, gcov, len(sites))


def report(col8, nrm8, rgh8, gcov, nspark):
    c = col8.astype(np.float64)
    print("color   mean RGB", np.round(c.reshape(-1, 3).mean(0), 1), " max RGB", c.reshape(-1, 3).max(0))
    print("        p1/p50/p99 luma", np.round(np.percentile(c.mean(-1), [1, 50, 99]), 1))
    n = nrm8.astype(np.float64) / 127.5 - 1
    tilt = np.degrees(np.arccos(np.clip(n[..., 2] / np.linalg.norm(n, axis=-1), -1, 1)))
    print("normal  mean RGB", np.round(nrm8.reshape(-1, 3).mean(0), 1), " tilt deg p50/p90/p99/max",
          np.round(np.percentile(tilt, [50, 90, 99, 100]), 1))
    r = rgh8.astype(np.float64) / 255
    g = gcov > 0.99
    f = gcov < 0.01
    print("rough   mean %.3f  non-grout median %.3f  grout mean %.3f" % (r.mean(), np.median(r[f]), r[g].mean()))
    print("grout coverage %.1f%%  sparkles %d" % (100 * gcov.mean(), nspark))
    # Seam check: mean |difference| across the wrap edge vs between neighbouring
    # interior lines. x: all column pairs. y: the tile's top/bottom edge lies on a
    # horizontal grout joint, so compare with row pairs inside interior joints.
    grout_rows = np.where(gcov.mean(axis=1) > 0.9)[0]
    pairs = [y for y in grout_rows if y + 1 in set(grout_rows) and y + 1 < T]
    for name, a in (("color", c), ("normal", nrm8.astype(np.float64)), ("rough", r * 255)):
        a2 = a if a.ndim == 3 else a[..., None]
        inner_x = np.abs(np.diff(a2, axis=1)).mean()
        wrap_x = np.abs(a2[:, 0] - a2[:, -1]).mean()
        inner_y = np.mean([np.abs(a2[y + 1] - a2[y]).mean() for y in pairs])
        wrap_y = np.abs(a2[0] - a2[-1]).mean()
        print("seam %-6s  wrap vs interior  x %.2f vs %.2f   y %.2f vs %.2f" % (name, wrap_x, inner_x, wrap_y, inner_y))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "assets", "textures")
    build(out)
