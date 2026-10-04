"""Screens texture atlases for anything a moderation classifier could read as human
skin, before they go anywhere near Roblox. Exit code 1 when anything is flagged
(2 when the classifier couldn't run): upload only after a run that exits 0.

    python tools/mutations/screen_skins.py assets/skins/glb     # the packed skins Studio uploads
    python tools/mutations/screen_skins.py assets/skins         # the skin PNGs, before packing
    python tools/mutations/screen_skins.py assets/skins/glb --csv screen.csv --masks screen_masks
    python tools/mutations/screen_skins.py some.png --base assets/skins/maps --no-classifier
    python tools/mutations/screen_skins.py assets/skins --move-flagged assets/skins_flagged

Needs numpy, scipy and pillow, and for the classifier `pip install torch
transformers` (CPU is fine). Without them the color signals still run, but the run
exits 2 (not cleared) unless --no-classifier asks for a color-only check.

Why: on 2026-10-03 Roblox suspended the owner's account for 7 days ("Sexual
Content") over one uploaded mutation skin, a Chimera atlas. A UV atlas is dozens of
loose body pieces, and the old Albino, Piebald and Chimera recipes painted them pale
pink or faint cream; to an image classifier that reads as fragments of bare skin.
make_skins.py now keeps every pale tone cool (silver-blue), and this is the gate
between it and the upload.

Inputs: skin PNGs (<Model>/<Mutation>.png; eyes_debug and EyesQA are skipped, they
are never uploaded) and packed <Model>_Skins.glb files, whose mutation images are
read straight out of the GLB, so the bytes that get uploaded are the bytes that get
screened (the model's own normal and ORM maps are skipped: they went up with the
model). Every image is scored at 1024, the size pack_skins.py uploads.

The control is each creature's own color texture: <Model>.npz from bake_maps.py or
<Model>.glb, looked up in --base, then <target>/maps, <target>/../maps,
assets/skins/maps and assets/glb. Those textures were uploaded long ago without a
problem, and many are tan, brown, gold or cream (up to 78% skin tone, 32% pale), so a
skin is judged on what it adds to its creature's texture, texel for texel (same UV
layout).

Signals, per image:

  skin        texels inside both classic skin-color rules: Kovac et al. (RGB, R>95,
              G>40, B>20, max-min>15, |R-G|>15, R>G, R>B) and Chai & Ngan (YCbCr,
              77<=Cb<=127, 133<=Cr<=173). Tan and brown fur sit inside these too.
  pale        the light end those rules leave out: bright (Y>=150) with a faint
              warm cast (Cr>=128>=Cb, Cr-Cb>=3) and little chroma: cream, ivory,
              peach and pink whites. Neutral and cool whites don't count.
  added       skin or pale texels the skin has where its base texture has neither,
              after a 2-texel opening (antialiased lines along UV island edges, and
              the JPEG chroma fringe along them, are under 2 px at a classifier's
              input size)
  added_256   the same on a 256 px box-filtered copy, also opened: roughly what a
              classifier sees, where fine speckle averages into one color
  added_pale  the pale part of `added`: the exact failure that got flagged
  added_blob  the largest connected region of added texels (8-connected, opened)
  nsfw        Falconsai/nsfw_image_detection (a ViT fine-tuned for nsfw/normal),
              the highest P(nsfw) over the whole image and a 3x3 grid of
              overlapping half-size tiles (an atlas is mostly small pieces, and the
              model sees 224 px; whole images alone barely register). Trained on
              photos, it is noisy on atlases, but it reads pale pieces scattered
              among dark or tan ones as nsfw: the old Chimera and Piebald skins up
              to 0.999, and about 1 in 7 of the new cool Piebald and Chimera skins
              too, whatever their color (Nullcat, Laundrophant, Coalby, Lawnmoose,
              Mossmunk_Baby...). That is the layout Roblox flagged, so those don't
              go up either (MutationLooks falls back to the solid v1 look). A few
              creatures' own textures also score high (Halosaur_Juvenile 0.95,
              accepted by Roblox long ago), so a skin is judged against its base.
  skin, pale, risk (the two together) and blob (their largest region) are also
  reported for the whole image.

Flagged when any of these holds (constants below). Measured 2026-10-03 on all 123
models: the old recipes added 20-99% skin tone (Albino), 7-45% (Piebald), up to 49%
(Chimera) and up to 25% (Iridescent), 415 of 615 skins flagged; the current recipes
add at most 1%, and 37 of 615 are flagged (41 once JPEG-packed), all by the
classifier, all Piebald or Chimera but one.

  added, added_256 > ADDED_MAX    added_pale > ADDED_PALE_MAX    added_blob > BLOB_MAX
  nsfw > NSFW_MAX and nsfw > its base's + NSFW_OVER_BASE
  with no base texture found: pale > PALE_MAX, risk > RISK_MAX or blob > BLOB_ABS_MAX

NudeNet (pip install nudenet) was tried as a second classifier and dropped: on
atlases it scored the creatures' own textures higher than any skin (up to 0.52), so
it can't tell them apart. --csv/--json write every row, --masks writes an overlay of
each flagged image (red: the skin tone it adds; yellow: what it keeps from its base),
and --move-flagged moves flagged PNGs out of the skins folder and prints the
pack_skins.py commands that re-pack their models without them.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import pathlib
import struct
import sys
import warnings

import numpy as np
from PIL import Image
from scipy import ndimage

SIZE = 1024
MUTATIONS = ["Albino", "Melanistic", "Piebald", "Chimera", "Iridescent"]
SKIP = {"eyes_debug", "EyesQA"}

# Thresholds (percent of the image, or a classifier score), set well above the
# current recipes (at most 1% added, none of it in areas) and well below what the
# old pale recipes added (7-99%). The creatures' own textures, uploaded long ago
# without trouble, hold up to 78% skin tone and 32% pale, which is why the color
# rules count only what a skin adds to them.
ADDED_MAX = 3.0  # skin-tone texels a skin adds over its base texture
ADDED_PALE_MAX = 1.0  # of which pale pink/peach/cream (the failure that got flagged)
BLOB_MAX = 1.0  # the largest connected region of them
# Without a base texture to compare: strict absolute limits, which the skins of a
# tan or cream creature trip too (they keep their own coat), so pass --base
PALE_MAX = 2.0
RISK_MAX = 25.0
BLOB_ABS_MAX = 5.0
NSFW_MAX = 0.20
NSFW_OVER_BASE = 0.10


# --- Color signals -------------------------------------------------------------


def skin_masks(rgb: np.ndarray):
    """(skin, pale) boolean masks for an (H, W, 3) uint8 image."""
    c = rgb.astype(np.float32)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx, mn = c.max(-1), c.min(-1)
    kovac = (r > 95) & (g > 40) & (b > 20) & (mx - mn > 15) & (np.abs(r - g) > 15) & (r > g) & (r > b)
    cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
    chai = (cb >= 77) & (cb <= 127) & (cr >= 133) & (cr <= 173)
    skin = kovac & chai
    # Pale and faintly warm, the light end the classic rules leave out: bright, with
    # a measurable cast toward red/yellow (Cr at or above and Cb at or below neutral
    # 128, 3+ apart) but little chroma. Cream, ivory, peach and pink whites land here
    # (the old piebald white sat at Cr +2, Cb -3.5); neutral and cool (blue, silver,
    # lavender) whites don't.
    y = 0.299 * r + 0.587 * g + 0.114 * b
    dcr, dcb = cr - 128, cb - 128
    pale = (y >= 150) & (dcr >= 0) & (dcb <= 0) & (dcr - dcb >= 3) & (np.hypot(dcr, dcb) <= 30) & ~skin
    return skin, pale


OPEN = np.ones((3, 3), bool)
# What a skin adds is opened wider: lines up to 4 texels across (antialiased UV island
# edges, and the chroma fringe JPEG packing puts along them) are under 2 px at a
# classifier's input size
OPEN_ADDED = np.ones((5, 5), bool)


def largest_blob(mask: np.ndarray) -> float:
    """The largest 8-connected region (after a 1-texel opening) as % of the image."""
    labels, count = ndimage.label(ndimage.binary_opening(mask, structure=OPEN), structure=OPEN)
    return 100.0 * (int(np.bincount(labels.ravel())[1:].max()) if count else 0) / mask.size


def color_scores(rgb: np.ndarray, alpha: np.ndarray | None = None, base: tuple | None = None):
    """The color signals, plus the risk masks (at 1024 and at 256) to use as a
    control for other skins. With the base texture's masks, also what this image
    adds over it: same UV layout, so texel for texel. What it adds is counted after a
    2-texel opening (lines along UV island edges, thinner than 2 px at a classifier's
    input size, don't count) and again on a 256 box-filtered copy, opened by 1
    (roughly what a classifier sees: fine speckle averages into one color there,
    while a patch edge is still just a line)."""
    skin, pale = skin_masks(rgb)
    solid = np.ones(skin.shape, bool) if alpha is None else alpha > 15
    n = max(int(solid.sum()), 1)
    risk = (skin | pale) & solid
    small = np.asarray(Image.fromarray(rgb).resize((256, 256), Image.BOX))
    skin_s, pale_s = skin_masks(small)
    solid_s = (
        np.ones(skin_s.shape, bool)
        if alpha is None
        else np.asarray(Image.fromarray(alpha).resize((256, 256), Image.BOX)) > 15
    )
    risk_s = (skin_s | pale_s) & solid_s
    out = {
        "skin": 100.0 * float((skin & solid).sum()) / n,
        "pale": 100.0 * float((pale & solid).sum()) / n,
        "risk": 100.0 * float(risk.sum()) / n,
        "blob": largest_blob(risk),
    }
    if base is not None:
        base_risk, base_risk_s = base
        added = ndimage.binary_opening(risk & ~base_risk, structure=OPEN_ADDED)
        out["added"] = 100.0 * float(added.sum()) / n
        added_s = ndimage.binary_opening(risk_s & ~base_risk_s, structure=OPEN)
        out["added_256"] = 100.0 * float(added_s.sum()) / max(int(solid_s.sum()), 1)
        out["added_pale"] = 100.0 * float((added & pale).sum()) / n
        out["added_blob"] = largest_blob(risk & ~base_risk)
    return out, (risk, risk_s)


# --- Classifier (optional) ------------------------------------------------------


def views(img: Image.Image):
    """The whole image and a 3x3 grid of overlapping half-size tiles (an atlas is
    mostly small pieces, and a classifier shrinks the whole image to 224 px)."""
    w, h = img.size
    out = [img]
    for j in range(3):
        for i in range(3):
            x, y = i * w // 4, j * h // 4
            out.append(img.crop((x, y, x + w // 2, y + h // 2)))
    return out


class Falconsai:
    """Falconsai/nsfw_image_detection (a ViT fine-tuned for nsfw/normal), the highest
    P(nsfw) over the views. Needs `pip install torch transformers`; the model (~350 MB)
    downloads from Hugging Face on first use."""

    name = "falconsai"

    def __init__(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            from transformers import pipeline
            from transformers.utils import logging as hf_logging

            hf_logging.set_verbosity_error()
            hf_logging.disable_progress_bar()
            self.pipe = pipeline("image-classification", model="Falconsai/nsfw_image_detection", device="cpu")

    def score(self, img: Image.Image) -> float:
        results = self.pipe([v.convert("RGB") for v in views(img)], top_k=2)
        return max(next(r["score"] for r in res if r["label"] == "nsfw") for res in results)


def load_classifier():
    try:
        return Falconsai()
    except Exception as err:  # noqa: BLE001 - without it the color signals still run
        print(f"[screen] classifier unavailable ({type(err).__name__}: {str(err)[:160]})")
        print("[screen] pip install torch transformers  to add it; screening on color alone")
        return None


# --- Inputs ------------------------------------------------------------------------


def read_glb(path: pathlib.Path):
    """(json, binary chunk) of a GLB."""
    data = path.read_bytes()
    magic, _, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError(f"{path} is not a GLB")
    offset, doc, binary = 12, {}, b""
    while offset < length:
        size, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + size]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    return doc, binary


def glb_image(doc: dict, binary: bytes, index: int) -> Image.Image:
    view = doc["bufferViews"][doc["images"][index]["bufferView"]]
    start = view.get("byteOffset", 0)
    return Image.open(io.BytesIO(binary[start : start + view["byteLength"]]))


def glb_skins(path: pathlib.Path):
    """(name, image) for each mutation image packed in a *_Skins.glb (pack_skins.py
    names them <Model>_Skins_<Mutation>; the model's own normal and ORM maps, already
    uploaded with the model, are skipped)."""
    doc, binary = read_glb(path)
    for index, image in enumerate(doc.get("images", [])):
        name = image.get("name") or f"image{index}"
        if not name.lower().startswith(("normal", "orm")) and "bufferView" in image:
            yield name, glb_image(doc, binary, index)


def glb_base(path: pathlib.Path):
    """A creature GLB's own color texture (its first material's base color)."""
    doc, binary = read_glb(path)
    for mat in doc.get("materials", []):
        tex = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex is not None:
            return glb_image(doc, binary, doc["textures"][tex["index"]]["source"])
    return None


def collect(targets: list[str]):
    """(label, model, mutation, image, png) for every texture to screen:
    <Model>/<Mutation>.png (or .jpg) and the mutation images in <Model>_Skins.glb,
    where `png` is the skin PNG it came from (for a GLB, the one pack_skins.py read:
    <glb folder>/../<Model>/<Mutation>.png). A folder is searched for PNGs all the way
    down but for GLBs only at its top, so assets/skins screens the PNGs and
    assets/skins/glb the packed GLBs."""
    for target in targets:
        p = pathlib.Path(target)
        files = sorted(p.rglob("*")) if p.is_dir() else [p]
        for f in files:
            suffix = f.suffix.lower()
            if suffix == ".glb" and (f == p or f.parent == p):
                model = f.stem.removesuffix("_Skins")
                for name, img in glb_skins(f):
                    mutation = next((m for m in MUTATIONS if name.endswith(m)), name)
                    yield f"{f.name}:{name}", model, mutation, img, f.parent.parent / model / f"{mutation}.png"
            elif suffix in (".png", ".jpg", ".jpeg") and f.stem not in SKIP:
                with Image.open(f) as img:  # closed straight away (Windows won't move an open file)
                    yield str(f), f.parent.name, f.stem, img.copy(), f


def prepare(img: Image.Image):
    """RGB at SIZE (as uploaded) and an alpha mask, or None when it's opaque."""
    alpha = None
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        alpha = np.asarray(img.resize((SIZE, SIZE), Image.LANCZOS))[..., 3]
        if alpha.min() > 250:
            alpha = None
    return img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS), alpha


def base_image(model: str, base_dirs: list[pathlib.Path]):
    """The model's own color texture: <Model>.npz (bake_maps.py) or <Model>.glb."""
    for d in base_dirs:
        if (d / f"{model}.npz").exists():
            return Image.fromarray(np.load(d / f"{model}.npz")["color"])
        if (d / f"{model}.glb").exists():
            return glb_base(d / f"{model}.glb")
    return None


def write_mask(path: pathlib.Path, rgb: Image.Image, risk: np.ndarray, base_risk: np.ndarray | None):
    """The image dimmed, with the skin tone it adds over its base in red and what it
    keeps from its base in yellow."""
    out = np.asarray(rgb, np.float32) * 0.35
    kept = risk & base_risk if base_risk is not None else np.zeros_like(risk)
    out[risk & ~kept] = (255, 30, 30)
    out[kept] = (230, 200, 40)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out.astype(np.uint8)).save(path)


# --- Main ----------------------------------------------------------------------------


def judge(row: dict) -> list[str]:
    why = []
    if row.get("added") is not None:
        if row["added"] > ADDED_MAX:
            why.append(f"adds {row['added']:.1f}% skin tone to its base texture (> {ADDED_MAX})")
        if row["added_256"] > ADDED_MAX:
            why.append(f"adds {row['added_256']:.1f}% skin tone at 256 px (> {ADDED_MAX})")
        if row["added_pale"] > ADDED_PALE_MAX:
            why.append(f"adds {row['added_pale']:.1f}% pale pink/peach/cream (> {ADDED_PALE_MAX})")
        if row["added_blob"] > BLOB_MAX:
            why.append(f"adds a {row['added_blob']:.1f}% skin-tone region (> {BLOB_MAX})")
    else:
        note = " (no base texture to compare: pass --base)"
        if row["pale"] > PALE_MAX:
            why.append(f"pale {row['pale']:.1f}% (> {PALE_MAX}){note}")
        if row["risk"] > RISK_MAX:
            why.append(f"skin tone {row['risk']:.1f}% (> {RISK_MAX}){note}")
        if row["blob"] > BLOB_ABS_MAX:
            why.append(f"a {row['blob']:.1f}% skin-tone region (> {BLOB_ABS_MAX}){note}")
    nsfw, base_nsfw = row.get("nsfw"), row.get("base_nsfw")
    if nsfw is not None and nsfw > NSFW_MAX and (base_nsfw is None or nsfw > base_nsfw + NSFW_OVER_BASE):
        why.append(
            f"classifier {nsfw:.2f} (> {NSFW_MAX}" + (f", base {base_nsfw:.2f})" if base_nsfw is not None else ")")
        )
    return why


def move_flagged(flagged: list[dict], dest: pathlib.Path):
    """Moves each flagged skin's PNG (for a GLB image, the PNG it was packed from) out
    of the skins folder and prints how to re-pack those models without them (a packed
    GLB holds all of a model's skins, so a flagged one means re-packing the rest)."""
    repack: dict[str, pathlib.Path] = {}
    for r in flagged:
        src = pathlib.Path(r["png"])
        if not src.is_file():
            print(f"[screen] {r['file']}: no {src} to move; re-make {r['model']} without it")
            continue
        target = dest / r["model"] / src.name
        target.parent.mkdir(parents=True, exist_ok=True)
        src.replace(target)
        repack[r["model"]] = src.parent.parent
        print(f"[screen] moved {src} -> {target}")
    if repack:
        print("\n[screen] Re-pack those models without the moved skins, then screen the GLBs again:")
        for model, skins in sorted(repack.items()):
            packed = skins / "glb" / f"{model}_Skins.glb"
            if not any((skins / model / f"{m}.png").exists() for m in MUTATIONS):
                print(f"  (no skins left for {model}: delete {packed})")
                continue
            print(
                f"  blender -b --python-exit-code 1 --python tools/mutations/pack_skins.py -- assets/glb/{model}.glb {skins / model} {packed}"
            )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("targets", nargs="+", help="skin PNGs, folders of <Model>/<Mutation>.png, or *_Skins.glb")
    ap.add_argument("--base", action="append", default=[], help="folder of <Model>.npz or <Model>.glb (repeatable)")
    ap.add_argument("--controls", action="store_true", help="also list each model's own texture as a row")
    ap.add_argument("--no-classifier", action="store_true", help="color signals only (fast)")
    ap.add_argument("--csv", help="write every row here")
    ap.add_argument("--json", help="write every row here")
    ap.add_argument("--masks", help="write an overlay of each flagged image here (red: skin tone it adds)")
    ap.add_argument(
        "--move-flagged",
        metavar="DIR",
        help="move each flagged skin's PNG to DIR/<Model>/<Mutation>.png (pack_skins.py skips a missing skin)",
    )
    ap.add_argument("--quiet", action="store_true", help="print only the summary and the flagged files")
    args = ap.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parents[2]
    base_dirs = [pathlib.Path(b) for b in args.base]
    for t in args.targets:
        base_dirs += [pathlib.Path(t) / "maps", pathlib.Path(t).parent / "maps"]
    base_dirs += [root / "assets/skins/maps", root / "assets/glb"]
    base_dirs = [d for d in dict.fromkeys(base_dirs) if d.is_dir()]

    classifier = None if args.no_classifier else load_classifier()
    bases: dict[str, tuple[dict, tuple] | None] = {}
    rows = []

    def score(label, model, mutation, img, base_masks=None):
        rgb, alpha = prepare(img)
        row = {"file": label, "model": model, "mutation": mutation}
        scores, masks = color_scores(np.asarray(rgb), alpha, base_masks)
        row.update({k: round(v, 3) for k, v in scores.items()})
        if classifier is not None:
            row["nsfw"] = round(classifier.score(rgb), 4)
        return row, masks, rgb

    for label, model, mutation, img, png in collect(args.targets):
        if model not in bases:
            base = base_image(model, base_dirs)
            bases[model] = None
            if base is not None:
                row, masks, _ = score(f"{model}:Base", model, "Base", base)
                bases[model] = (row, masks)
                if args.controls:
                    rows.append(dict(row, flags=""))
        control = bases[model]
        row, masks, rgb = score(label, model, mutation, img, control[1] if control else None)
        row["base_risk"] = control[0]["risk"] if control else None
        row["base_nsfw"] = control[0].get("nsfw") if control else None
        row["png"] = str(png)
        why = judge(row)
        row["flags"] = "; ".join(why)
        rows.append(row)
        if why and args.masks:
            write_mask(
                pathlib.Path(args.masks) / f"{model}_{mutation}.png", rgb, masks[0], control[1][0] if control else None
            )
        if not args.quiet:
            added = f", adds {row['added']:.1f}% ({row['added_256']:.1f}% at 256)" if "added" in row else ", no base"
            nsfw = f", classifier {row['nsfw']:.3f}" if "nsfw" in row else ""
            print(
                f"[{'FLAG' if why else 'ok'}] {label}: skin {row['skin']:.1f}% pale {row['pale']:.1f}%"
                f"{added}{nsfw}" + (f"  <- {row['flags']}" if why else ""),
                flush=True,
            )

    if not rows:
        print("[screen] nothing to screen")
        return 0
    keys = list(dict.fromkeys(k for r in rows for k in r))
    if args.csv:
        with open(args.csv, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=keys)
            writer.writeheader()
            writer.writerows(rows)
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(rows, indent=1))

    # Summary per mutation: mean / max of each signal
    metrics = [
        k
        for k in ("skin", "pale", "risk", "blob", "added", "added_256", "added_pale", "added_blob", "nsfw")
        if k in keys
    ]
    print()
    print(f"{'':<12}{'n':>4}{'flagged':>8} " + "".join(f"{m:>14}" for m in metrics))
    print(f"{'':<24} " + "".join(f"{'mean / max':>14}" for _ in metrics))
    groups: dict[str, list[dict]] = {}
    for r in rows:
        groups.setdefault(r["mutation"], []).append(r)
    order = MUTATIONS + ["Base"]
    for name in sorted(groups, key=lambda g: (order.index(g) if g in order else len(order), g)):
        group = groups[name]
        cells = []
        for m in metrics:
            vals = [r[m] for r in group if r.get(m) is not None]
            fmt = ".2f" if m == "nsfw" else ".1f"
            cells.append(f"{np.mean(vals):{fmt}} / {np.max(vals):{fmt}}" if vals else "-")
        flagged = sum(1 for r in group if r.get("flags"))
        print(f"{name:<12}{len(group):>4}{flagged:>8} " + "".join(f"{c:>14}" for c in cells))
    print()
    missing = classifier is None and not args.no_classifier
    if missing:
        print("[screen] NOTE: no classifier ran (see above); the color signals alone decided")
    flagged = [r for r in rows if r.get("flags")]
    if flagged:
        print(f"[screen] {len(flagged)} of {len(rows)} FLAGGED. Do not upload these:")
        for r in flagged:
            print(f"  {r['file']}: {r['flags']}")
        if args.move_flagged:
            move_flagged(flagged, pathlib.Path(args.move_flagged))
        return 1
    if missing:
        # The classifier catches what color can't (pale pieces among dark ones), so a
        # color-only pass doesn't clear an upload unless asked for with --no-classifier
        print(f"[screen] {len(rows)} screened, none flagged on color, but NOT CLEARED without the classifier.")
        return 2
    print(f"[screen] {len(rows)} screened, none flagged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
