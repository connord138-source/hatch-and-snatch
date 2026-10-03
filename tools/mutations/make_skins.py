"""Makes the mutation skins: one recolored color texture per model and mutation.

    python tools/mutations/make_skins.py <maps.npz> <out_dir> [Mutation ...]

Needs numpy, scipy and pillow (plain Python, not Blender). The maps come from
bake_maps.py: the model's own color texture plus, for every texel, where it sits on
the body in 3D. Every recipe keeps the texture's painted detail (fur strokes, scales,
shading) by working from its brightness, and treats three kinds of texel apart:

  coat      the creature's own colors
  features  its most vivid texels: element glow, lava, crystals, coral (top ~15%)
  eyes      found in 3D: round vivid blobs with a dark pupil, a mirrored pair on the
            front of the head (eyes.json overrides a bad guess)

Mutations (owner, 2026-10-01: mutations must be "by far the most desirable yet
rarest", look professional, and not like decolored skins):

  Albino      snow-white coat with a cool silver-blue cast that keeps its detail,
              its markings ghosting through in pale blue-grey, cool lavender-grey
              in the creases, the features frosted to icy pastels, ruby-red eyes
  Melanistic  jet-black coat with its pattern still ghosting through, a cool sheen,
              and the features and eyes left blazing against the black
  Piebald     crisp cool-white patches laid out on the body in 3D (no UV seams),
              heavier on the belly, legs and face, with the eyes always in colored
              fur (a dark eye in a pale patch is a pattern nsfw classifiers pick up)
  Chimera     split down the middle: one half its normal self, the other half the
              opposite (the silver-white albino or melanistic), with odd-colored eyes
  Iridescent  a cool opal film (teal, blue, violet, mint) over the coat whose colors
              follow the body's curves (the client drifts it further in game)

No skin may look like human skin (2026-10-03): Roblox suspended the owner's account
for "Sexual Content" over an uploaded Chimera atlas. A UV atlas is dozens of loose
body pieces, and the old recipes painted them pale pinkish white (Albino's "pink
creases" covered every texel brighter than 0.16, through a smoothstep with its edges
swapped; the features went peach; the whites were warm), which reads as fragments
of bare skin. So every pale tone here is cool: whites lean silver-blue, shading
leans lavender-grey, warm feature colors fold into cool pastels (`cool_hue`), and
the opal film has no pink, peach or gold. Leucistic (a cream coat, retired
2026-10-02) is gone. Even so, an nsfw classifier still reads some creatures' Piebald
and Chimera atlases (pale pieces among dark or tan ones) as nsfw, so screen the
packed GLBs with screen_skins.py before importing them, and never upload a skin it
flags (MutationLooks falls back to the solid v1 look).

Writes <out_dir>/<Mutation>.png at the texture's full size, plus eyes_debug.png.
"""

import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ALL = ["Albino", "Melanistic", "Piebald", "Chimera", "Iridescent"]

# Cool whites (never warm: a warm white on loose atlas pieces reads as skin)
SNOW = np.array([0.91, 0.95, 1.0], np.float32)  # albino coat: snow with a silver-blue cast
PATCH = np.array([0.92, 0.955, 1.0], np.float32)  # piebald patches
CREASE = np.array([0.56, 0.58, 0.74], np.float32)  # albino pads, nose, inner ears: lavender-grey
GHOST = np.array([0.62, 0.70, 0.86], np.float32)  # albino markings ghosting through: blue-grey
GLINT = np.array([0.95, 0.97, 1.0], np.float32)  # the eyes' painted highlight


def smoothstep(a, b, x):
    # Edges in rising order only: with a > b this is a hard step up at a, not a falling
    # ramp (use 1 - smoothstep(b, a, x)). Piebald's belly, face and underside terms and
    # eye_color's highlight are written swapped and so act as steps; the approved looks
    # were made that way, so they're left as they are.
    t = np.clip((x - a) / max(b - a, 1e-6), 0, 1)
    return t * t * (3 - 2 * t)


def rgb_to_hsv(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx = c.max(-1)
    mn = c.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m & (mx == r), ((g - b) / np.where(m, d, 1)) % 6, 0)
    gc = np.where(m & (mx == g) & (mx != r), (b - r) / np.where(m, d, 1) + 2, 0)
    bc = np.where(m & (mx == b) & (mx != r) & (mx != g), (r - g) / np.where(m, d, 1) + 4, 0)
    h = (rc + gc + bc) / 6.0
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return np.stack([h % 1.0, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0] * 6, hsv[..., 1], hsv[..., 2]
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,))
    for k, (r, g, b) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[sel] = np.stack([r[sel], g[sel], b[sel]], -1)
    return out


def value_noise(p, freq, seed):
    """Smooth 3D value noise at points p (N,3), roughly in [0, 1]."""
    rng = np.random.default_rng(seed)
    lattice = rng.random((32, 32, 32))
    q = p * freq + 7.3
    i0 = np.floor(q).astype(int)
    f = q - i0
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * lattice[(i0[:, 0] + dx) % 32, (i0[:, 1] + dy) % 32, (i0[:, 2] + dz) % 32]
    return out


class Model:
    def __init__(self, path):
        d = np.load(path)
        self.color = d["color"].astype(np.float32) / 255.0
        self.size = self.color.shape[0]
        k = self.size // d["position"].shape[0]
        # Smooth (bilinear) upsampling, so patch and split edges don't stair-step
        smooth = lambda a: ndimage.zoom(a, (k, k, 1), order=1)  # noqa: E731
        self.pos = smooth(d["position"].astype(np.float32))
        self.nrm = smooth(d["normal"].astype(np.float32))
        self.cov = np.repeat(np.repeat(d["covered"], k, 0), k, 1)
        self.mn, self.mx = d["bounds"]
        self.length = float(d["length"])
        self.faces = d["faces"] if "faces" in d.files else None
        self.pn = (self.pos - self.mn) / np.maximum(self.mx - self.mn, 1e-6)  # 0..1 per axis
        # Height against the top of the torso (ears, horns and crests stretch pn z)
        mid = self.cov & (self.pn[..., 1] > 0.3) & (self.pn[..., 1] < 0.7)
        top = float(np.percentile(self.pn[..., 2][mid], 92)) if mid.any() else 1.0
        self.zb = self.pn[..., 2] / max(top, 1e-3)
        self.hsv = rgb_to_hsv(self.color)
        self.lum = self.color @ np.array([0.299, 0.587, 0.114], np.float32)
        self.vivid = self.hsv[..., 1] * self.hsv[..., 2]
        c = self.cov
        lumc = self.lum[c]
        self.lum_hi = float(np.percentile(lumc, 97))
        self.coat_lum = float(np.median(lumc))
        cut = max(0.33, float(np.percentile(self.vivid[c], 85)))
        self.feature = smoothstep(cut, cut + 0.15, self.vivid) * c
        self.eyes = np.zeros(self.color.shape[:2], bool)
        self.eye_centres = []
        self.lum_split = None
        self.eye_scores = []


def disk(r):
    y, x = np.mgrid[-r : r + 1, -r : r + 1]
    return (x * x + y * y <= r * r).astype(np.float32)


def eyes_from_picks(m: Model, picks):
    """Eyes marked by hand on the face renders (eyes.json): the texels under each
    pick, grown to a sphere on the body so the sides the camera missed are covered."""
    h, w = m.color.shape[:2]
    mask = np.zeros((h, w), bool)
    yy, xx = np.mgrid[0 : m.faces.shape[1], 0 : m.faces.shape[2]]
    centres = []
    for view, px, py, radius in picks:
        face = m.faces[view]
        sel = ((xx - px) ** 2 + (yy - py) ** 2 <= radius * radius) & (face[..., 5] > 0.5)
        u, v = face[..., 3][sel], face[..., 4][sel]
        tx = np.clip((u % 1.0) * w, 0, w - 1).astype(int)
        ty = np.clip((1 - v % 1.0) * h, 0, h - 1).astype(int)
        hit = np.zeros((h, w), bool)
        hit[ty, tx] = True
        hit = ndimage.binary_closing(hit, iterations=3) & m.cov
        if not hit.any():
            continue
        pts = m.pos[hit]
        centre = np.median(pts, 0)
        r3 = float(np.percentile(np.linalg.norm(pts - centre, axis=-1), 90))
        sphere = (np.linalg.norm(m.pos - centre, axis=-1) < r3 * 1.05) & m.cov
        mask |= hit | sphere
        centres.append(((centre - m.mn) / (m.mx - m.mn)).round(4).tolist())
    m.eye_centres = centres
    m.eye_scores = ["picked"] * len(centres)
    return ndimage.binary_closing(mask, iterations=2)


def find_eyes(m: Model, override=None):
    """The eyes, found as a dark pupil inside a vivid iris ring, on the front of the
    head, as a mirrored pair in 3D. Works on a 1024 copy of the maps."""
    step = max(1, m.size // 1024)
    pn = m.pn[::step, ::step]
    cov = m.cov[::step, ::step]
    pos = m.pos[::step, ::step]
    v = m.hsv[::step, ::step, 2]
    vivid = m.vivid[::step, ::step]

    def grow(centres, radius):
        mask = np.zeros(cov.shape, bool)
        for c in centres:
            dist = np.linalg.norm(pos - c, axis=-1) / m.length
            mask |= (dist < radius) & cov
        return np.kron(mask, np.ones((step, step), bool)).astype(bool)

    if override and m.faces is not None:
        return eyes_from_picks(m, override["picks"])

    head = cov & (pn[..., 1] < 0.2)
    if head.sum() < 50:
        return np.zeros(m.color.shape[:2], bool)
    hz = pn[..., 2][head]
    z_lo, z_hi = np.percentile(hz, 5), np.percentile(hz, 99)
    zrel = (pn[..., 2] - z_lo) / max(z_hi - z_lo, 1e-6)
    # Tripo keeps the concept's turned head, so the face's own midline, not the body's
    face = head & (pn[..., 1] < 0.1)
    xc = float(np.median(pn[..., 0][face])) if face.any() else 0.5
    prior = (
        head
        & (zrel > 0.35)
        & (np.abs(pn[..., 0] - xc) > 0.03)
    ).astype(np.float32) * (1 - np.clip(pn[..., 1] / 0.2, 0, 1) * 0.5)
    best = np.zeros(cov.shape, np.float32)
    scale = np.zeros(cov.shape, np.float32)
    for r_in, r_out in ((2, 5), (3, 8), (5, 12), (7, 16)):
        inner = disk(r_in)
        outer = disk(r_out)
        ring = outer.copy()
        ring[r_out - r_in : r_out + r_in + 1, r_out - r_in : r_out + r_in + 1] -= inner
        ring = np.clip(ring, 0, 1)
        centre_v = ndimage.convolve(v, inner / inner.sum(), mode="constant")
        ring_v = ndimage.convolve(v, ring / ring.sum(), mode="constant")
        ring_viv = ndimage.convolve(vivid, ring / ring.sum(), mode="constant")
        score = ring_viv * np.clip(ring_v - centre_v, 0, 1) * prior
        better = score > best
        best[better] = score[better]
        scale[better] = r_out
    peaks = (best == ndimage.maximum_filter(best, size=9)) & (best > 0.02)
    ys, xs = np.nonzero(peaks)
    order = np.argsort(-best[ys, xs])[:30]
    nrm = m.nrm[::step, ::step]
    cands = [
        (float(best[ys[i], xs[i]]), pos[ys[i], xs[i]], pn[ys[i], xs[i]], nrm[ys[i], xs[i]])
        for i in order
    ]
    pair = None
    for i in range(len(cands)):
        for j in range(i + 1, len(cands)):
            a, b = cands[i], cands[j]
            if (
                abs((a[2][0] - xc) + (b[2][0] - xc)) < 0.09
                and 0.06 < abs(a[2][0] - b[2][0]) < 0.5
                and abs(a[2][1] - b[2][1]) < 0.05
                and abs(a[2][2] - b[2][2]) < 0.07
                and a[3][0] * b[3][0] < 0.05  # facing opposite sides
            ):
                total = a[0] + b[0]
                if pair is None or total > pair[0]:
                    pair = (total, [a, b])
    chosen = pair[1] if pair else cands[:1]
    if not chosen:
        return np.zeros(m.color.shape[:2], bool)
    # Eye radius in body lengths from the ring scale (texels) and the local texel size
    radius = 0.009
    m.eye_centres = [((c[1] - m.mn) / (m.mx - m.mn)).round(4).tolist() for c in chosen]
    m.eye_scores = [round(c[0], 3) for c in chosen]
    mask = grow([c[1] for c in chosen], radius)
    # Keep only the painted eye inside that sphere: the iris and pupil, not the fur round it
    keep = (m.vivid > 0.25) | (m.hsv[..., 2] < np.percentile(m.hsv[..., 2][mask], 40) if mask.any() else False)
    mask &= keep
    return ndimage.binary_closing(mask, iterations=2)


def shade(m: Model, lo, hi, gamma=1.0):
    """The texture's own detail as a brightness ramp from lo to hi."""
    t = np.clip(m.lum / max(m.lum_hi, 1e-3), 0, 1) ** gamma
    return (lo + (hi - lo) * t)[..., None]


def detail(m: Model, base, fine, broad):
    """A new coat brightness that keeps the painted detail but not the old pattern:
    `base` plus the fine strokes and creases (`fine`) and a trace of the broad
    markings (`broad`), so a dark-patched creature doesn't turn out grey-patched."""
    if m.lum_split is None:
        t = np.clip(m.lum / max(m.lum_hi, 1e-3), 0, 1.2)
        low = ndimage.gaussian_filter(t, sigma=m.size / 256)
        m.lum_split = (t - low, low - float(np.median(low[m.cov])))
    high, low = m.lum_split
    return np.clip(base + fine * high + broad * low, 0, 1.2)[..., None]


def cool_hue(h):
    """Folds the warm half of the hue wheel (red, orange, yellow, pink) onto the cool
    half, so a pale tint can't come out peach or pink. Continuous: cool hues stay
    roughly put, and every result lands between teal-green and violet (153-279 deg)."""
    rel = (h - 0.6 + 0.5) % 1.0 - 0.5
    rel = np.where(np.abs(rel) > 0.25, np.sign(rel) * (0.5 - np.abs(rel)), rel)
    return (0.6 + 0.7 * rel) % 1.0


def cool_pastel(m: Model, sat, val):
    """The texels' own colors as pale cool tints: hue folded cool, saturation scaled
    by `sat`, brightness lifted toward 1 from `val`."""
    hsv = m.hsv.copy()
    hsv[..., 0] = cool_hue(hsv[..., 0])
    hsv[..., 1] *= sat
    hsv[..., 2] = val + (1 - val) * hsv[..., 2]
    return hsv_to_rgb(np.clip(hsv, 0, 1))


def eye_color(m: Model, rgb, keep_highlight=True):
    """Recolor the eyes: a deep pupil, a colored iris that keeps its painted rings,
    and the painted highlight (and any white of the eye) kept."""
    t = np.clip(m.lum / max(m.lum_hi, 1e-3), 0, 1)[..., None]
    iris = np.array(rgb, np.float32) * (0.22 + 0.95 * t)
    if keep_highlight:
        white = (smoothstep(0.78, 0.92, m.lum) * smoothstep(0.35, 0.15, m.hsv[..., 1]))[..., None]
        iris = iris * (1 - white) + GLINT * white
    return iris


def albino(m: Model):
    # A dark coat's painted strokes are faint against its bright features, so they
    # get a boost: the fur detail is what keeps a white coat from looking like skin
    gain = float(np.clip(0.55 / max(m.coat_lum / max(m.lum_hi, 1e-3), 0.1), 1.0, 2.2))
    fur = detail(m, 0.95, gain, 0.04)
    out = SNOW * fur
    # The markings ghost through in pale blue-grey (like an albino tiger's faint
    # stripes), which also keeps big pieces from reading as flat skin
    _, low = m.lum_split
    ghost = (np.clip(-low * 0.9, 0, 0.32) * m.cov)[..., None]
    out = out * (1 - ghost) + GHOST * fur * ghost
    # Lavender-grey in the deepest creases (pads, nose, inner ears), measured against
    # the creature's own coat, so a dark-coated one isn't shaded all over
    # (smoothstep needs its edges in rising order: with them swapped it's a hard step
    # the wrong way round, which is how the old recipe's pink "crease" covered every
    # texel brighter than 0.16)
    rel = m.lum / max(m.coat_lum, 0.05)
    crease = ((1 - smoothstep(0.12, 0.42, rel)) * 0.45)[..., None]
    out = out * (1 - crease) + CREASE * crease
    f = m.feature[..., None]
    out = out * (1 - f) + cool_pastel(m, 0.30, 0.78) * f
    e = m.eyes[..., None]
    return out * (1 - e) + eye_color(m, (0.86, 0.06, 0.16)) * e


def melanistic(m: Model):
    sheen = np.array([0.86, 0.88, 1.0], np.float32)
    out = sheen * detail(m, 0.09, 0.55, 0.12)
    # The features glow vivid (more saturated as well as brighter), so where they fade
    # into the black they pass through deep ember, not brown
    f = m.feature[..., None]
    hsv = m.hsv.copy()
    hsv[..., 1] = 1 - (1 - hsv[..., 1]) * 0.15
    hsv[..., 2] = np.clip(hsv[..., 2] * 1.12, 0, 1)
    glow = hsv_to_rgb(hsv)
    out = out * (1 - f) + glow * f
    e = m.eyes[..., None]
    eyes = hsv_to_rgb(np.clip(m.hsv * [1, 1.15, 0] + [0, 0, 1], 0, 1))  # its own eye color at full brightness
    eyes = eyes * (0.3 + 0.8 * np.clip(m.lum / max(m.lum_hi, 1e-3), 0, 1))[..., None]
    return out * (1 - e) + eyes * e


def piebald(m: Model, seed=3):
    p = m.pos.reshape(-1, 3) / m.length
    n = value_noise(p, 8.0, seed) * 0.6 + value_noise(p, 17.0, seed + 1) * 0.4
    n = n.reshape(m.cov.shape)
    n = (n - n[m.cov].mean()) / max(float(n[m.cov].std()), 1e-6)
    pn, nz = m.pn, m.nrm[..., 2]
    # Like real piebalds: white on the face, chest, belly and legs, the back and
    # spine keep their color
    bias = (
        1.4 * smoothstep(0.6, 0.2, m.zb)  # belly, chest and legs
        + 1.2 * smoothstep(0.14, 0.03, pn[..., 1]) * smoothstep(0.5, 0.8, m.zb)  # muzzle and face
        + 0.8 * smoothstep(0.1, -0.6, nz)  # undersides
        - 1.8 * smoothstep(0.7, 0.92, m.zb) * smoothstep(0.1, 0.6, nz) * (pn[..., 1] > 0.12)  # spine and back
    )
    field = n + bias
    cut = np.percentile(field[m.cov], 60)
    # The eyes sit in colored fur, like a piebald dog's eye patches: a dark eye in a
    # pale patch is a pattern an nsfw classifier picks up on
    for c in m.eye_centres:
        centre = m.mn + np.array(c) * (m.mx - m.mn)
        dist = np.linalg.norm(m.pos - centre.astype(np.float32), axis=-1) / m.length
        field = field - 4.0 * (1 - smoothstep(0.045, 0.075, dist))
    patch = smoothstep(cut - 0.02, cut + 0.02, field)[..., None] * (1 - m.eyes[..., None])
    white = PATCH * detail(m, 0.92, 1.0, 0.08)
    white_f = cool_pastel(m, 0.30, 0.8)
    f = m.feature[..., None]
    white = white * (1 - f) + white_f * f
    out = m.color * (1 - patch) + white * patch
    # Halfway between a warm coat and the white the mix goes cream, so the patch
    # edges pass through a cool grey-white instead
    mid = 4 * patch * (1 - patch) * 0.9
    return out * (1 - mid) + out.mean(-1, keepdims=True) * PATCH * mid


def chimera(m: Model, seed=5):
    p = m.pos.reshape(-1, 3) / m.length
    wobble = (value_noise(p, 2.5, seed).reshape(m.cov.shape) - 0.5) * 0.06
    # The split runs down the body's middle, and down the face's own middle on a
    # turned head (Tripo keeps the concept's head turn)
    face = m.cov & (m.pn[..., 1] < 0.1) & (m.pn[..., 2] > 0.5)
    face_x = float(np.median(m.pn[..., 0][face])) if face.any() else 0.5
    if m.eye_centres and len(m.eye_centres) == 2:
        face_x = (m.eye_centres[0][0] + m.eye_centres[1][0]) / 2
    mid = face_x + (0.5 - face_x) * smoothstep(0.08, 0.3, m.pn[..., 1])
    side = smoothstep(-0.006, 0.006, (m.pn[..., 0] - mid) + wobble)[..., None]
    other = albino(m) if m.coat_lum < 0.42 else melanistic(m)
    out = m.color * (1 - side) + other * side
    # Odd eyes: the changed side's eye turns ice blue (gold on an albino-coated split)
    e = (m.eyes[..., None]) * side
    odd = eye_color(m, (0.40, 0.78, 1.0) if m.coat_lum < 0.42 else (1.0, 0.72, 0.15))
    return out * (1 - e) + odd * e


# A cool opal film: no magenta, peach or gold, which turn pinkish over a warm coat
FILM = np.array(
    [
        (0.20, 0.85, 0.80),  # teal
        (0.30, 0.62, 1.00),  # azure
        (0.52, 0.46, 1.00),  # periwinkle
        (0.40, 0.80, 1.00),  # sky
        (0.38, 0.95, 0.66),  # mint
        (0.20, 0.85, 0.80),
    ],
    np.float32,
)


def iridescent(m: Model):
    nrm, pn = m.nrm, m.pn
    phase = 0.55 * nrm[..., 2] + 0.35 * nrm[..., 0] + 1.1 * pn[..., 1] + 0.4 * pn[..., 2]
    phase = (phase * 0.8) % 1.0
    x = phase * (len(FILM) - 1)
    i = np.floor(x).astype(int)
    f = (x - i)[..., None]
    film = FILM[i] * (1 - f) + FILM[np.minimum(i + 1, len(FILM) - 1)] * f
    body = film * detail(m, 0.62, 1.0, 0.35)
    sheen = smoothstep(0.3, 0.9, nrm[..., 2])[..., None] * 0.12
    # The coat's own colors stay readable under the film, folded into cool hues
    # (a warm coat half-mixed with a cool film comes out tan, salmon or mauve)
    hsv = m.hsv.copy()
    hsv[..., 0] = cool_hue(hsv[..., 0])
    own = hsv_to_rgb(hsv)
    coat = np.clip(own * 0.45 + body * 0.55 + sheen * GLINT, 0, 1)
    # The features keep their own color under a light film (orange lava under a
    # violet film went salmon pink)
    fe = smoothstep(0.3, 0.7, m.feature)[..., None]  # a short edge: cool into warm mixes salmon
    feat = np.clip(m.color * 1.05 + film * 0.15, 0, 1)
    out = coat * (1 - fe) + feat * fe
    e = m.eyes[..., None]
    return out * (1 - e) + m.color * e


RECIPES = {
    "Albino": albino,
    "Melanistic": melanistic,
    "Piebald": piebald,
    "Chimera": chimera,
    "Iridescent": iridescent,
}


def main():
    src, out_dir = sys.argv[1], pathlib.Path(sys.argv[2])
    which = sys.argv[3:] or ALL
    out_dir.mkdir(parents=True, exist_ok=True)
    m = Model(src)
    overrides = {}
    eyes_file = pathlib.Path(__file__).with_name("eyes.json")
    if eyes_file.exists():
        overrides = json.loads(eyes_file.read_text())
    m.eyes = find_eyes(m, overrides.get(pathlib.Path(src).stem))
    debug = (m.color * 0.35).copy()
    debug[m.eyes] = (0.1, 1.0, 0.2)
    debug[(m.feature > 0.5) & ~m.eyes] = m.color[(m.feature > 0.5) & ~m.eyes]
    Image.fromarray((debug * 255).astype(np.uint8)).resize((1024, 1024)).save(out_dir / "eyes_debug.png")
    qa = m.color.copy()
    qa[m.eyes] = (0.1, 1.0, 0.2)
    Image.fromarray((qa * 255).astype(np.uint8)).save(out_dir / "EyesQA.png")
    for name in which:
        img = np.clip(RECIPES[name](m), 0, 1)
        Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(out_dir / f"{name}.png", optimize=True)
        print(f"[skins] {out_dir.name}/{name}.png")
    print(f"[skins] eyes at {m.eye_centres} (scores {m.eye_scores}), {int(m.eyes.sum())} texels; coat {m.coat_lum:.2f}")


if __name__ == "__main__":
    main()
