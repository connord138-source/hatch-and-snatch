"""Builds the Roblox store art (icon + thumbnails) from the generated key art.

    python3 tools/marketing/compose.py

Inputs live in assets/tripo/marketing/ (gitignored; the source links are in
docs/STORE_PAGE.md): the Higgsfield drafts, and Logo.png / ThumbMoon.png from
tools/tripo_jobs_marketing.json. Outputs go to marketing/ (committed) as the
files to upload in Creator Hub:

    icon_512.png                 game icon (512x512); icon_512_alt.png is the runner-up
    thumb_1_steal.jpg ...        thumbnails (1920x1080)
    logo.png                     the logo with a transparent background

Text is set here (not by the image model) so it's crisp and spelled right.
Fonts: tools/marketing/fonts (Lilita One / Titan One, OFL; Luckiest Guy, Apache 2.0).
"""
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "tripo" / "marketing"
OUT = ROOT / "marketing"
FONTS = pathlib.Path(__file__).resolve().parent / "fonts"

W, H = 1920, 1080
NAVY = (27, 20, 64)


def src(prefix: str) -> Image.Image:
    matches = sorted(SRC.glob(f"*{prefix}*"))
    if not matches:
        raise SystemExit(f"missing source image {prefix} in {SRC}")
    return Image.open(matches[0]).convert("RGB")


def cover(im: Image.Image, w: int, h: int, focus: tuple[float, float] = (0.5, 0.5)) -> Image.Image:
    """Scales to fill w x h and crops around `focus` (0..1 of the source)."""
    scale = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    left = min(max(round(im.width * focus[0] - w / 2), 0), im.width - w)
    top = min(max(round(im.height * focus[1] - h / 2), 0), im.height - h)
    return im.crop((left, top, left + w, top + h))


def key_green(im: Image.Image) -> Image.Image:
    """Green-screen logo -> RGBA with soft edges and no green fringe."""
    r, g, b = im.convert("RGB").split()
    others = ImageChops.lighter(r, b)
    greenness = ImageChops.subtract(g, others)
    alpha = greenness.point(lambda v: 255 if v < 40 else 0 if v > 110 else round(255 * (110 - v) / 70))
    g = ImageChops.darker(g, others)  # despill
    out = Image.merge("RGBA", (r, g, b, alpha))
    return out.crop(out.getbbox())


def vibrance(im: Image.Image, amount: float = 1.12, contrast: float = 1.05) -> Image.Image:
    from PIL import ImageEnhance

    return ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(amount)).enhance(contrast)


def text_layer(
    text: str,
    font_name: str,
    size: int,
    top=(255, 236, 110),
    bottom=(255, 150, 30),
    stroke: int | None = None,
    angle: float = 0,
) -> Image.Image:
    """Chunky game-style text: gradient fill, thick navy outline, drop shadow."""
    font = ImageFont.truetype(str(FONTS / font_name), size)
    stroke = stroke if stroke is not None else max(4, size // 9)
    lines = text.split("\n")
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    boxes = [probe.textbbox((0, 0), line, font=font, stroke_width=stroke) for line in lines]
    line_h = max(b[3] - b[1] for b in boxes)
    width = max(b[2] - b[0] for b in boxes)
    pad = stroke * 3
    height = line_h * len(lines) + pad * 2
    mask_fill = Image.new("L", (width + pad * 2, height), 0)
    mask_all = Image.new("L", mask_fill.size, 0)
    d_fill, d_all = ImageDraw.Draw(mask_fill), ImageDraw.Draw(mask_all)
    for i, (line, box) in enumerate(zip(lines, boxes)):
        x = pad + (width - (box[2] - box[0])) // 2 - box[0]
        y = pad + i * line_h - box[1]
        d_all.text((x, y), line, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
        d_fill.text((x, y), line, font=font, fill=255)
    gradient = Image.new("RGB", mask_fill.size)
    gd = ImageDraw.Draw(gradient)
    for y in range(gradient.height):
        t = y / max(1, gradient.height - 1)
        gd.line([(0, y), (gradient.width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    layer = Image.new("RGBA", mask_fill.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", mask_fill.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 170), (0, 0), mask_all)
    shadow = shadow.filter(ImageFilter.GaussianBlur(stroke * 0.8))
    layer.alpha_composite(shadow, (stroke // 2, stroke))
    layer.paste(NAVY + (255,), (0, 0), mask_all)
    layer.paste(gradient, (0, 0), mask_fill)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    return layer


def place(canvas: Image.Image, layer: Image.Image, x: int, y: int, anchor: str = "lt"):
    if anchor[0] == "m":
        x -= layer.width // 2
    elif anchor[0] == "r":
        x -= layer.width
    if anchor[1] == "m":
        y -= layer.height // 2
    elif anchor[1] == "b":
        y -= layer.height
    canvas.alpha_composite(layer, (x, y))


def logo_at(width: int, logo: Image.Image, glow: bool = True) -> Image.Image:
    scaled = logo.resize((width, round(logo.height * width / logo.width)), Image.LANCZOS)
    if not glow:
        return scaled
    halo = Image.new("RGBA", (scaled.width + 80, scaled.height + 80), (0, 0, 0, 0))
    alpha = Image.new("L", halo.size, 0)
    alpha.paste(scaled.getchannel("A"), (40, 40))
    halo.paste((0, 0, 0, 150), (0, 0), alpha.filter(ImageFilter.GaussianBlur(18)))
    halo.alpha_composite(scaled, (40, 40))
    return halo


def vignette(canvas: Image.Image, strength: int = 120):
    mask = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-canvas.width * 0.15, -canvas.height * 0.25, canvas.width * 1.15, canvas.height * 1.25), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(160))
    dark = Image.new("RGBA", canvas.size, (0, 0, 0, strength))
    dark.putalpha(ImageChops.invert(mask).point(lambda v: v * strength // 255))
    canvas.alpha_composite(dark)


def main():
    OUT.mkdir(exist_ok=True)
    logo = key_green(src("Logo"))
    logo.save(OUT / "logo.png")

    # Icon: the snatch moment, straight from the draft, a touch punchier
    # Realistic eyes (owner's art direction): B is the snarling young Emberlynx
    # from its model sheet; A is the first draft's composition with the eyes fixed
    vibrance(src("IconRealEyesB")).resize((512, 512), Image.LANCZOS).save(OUT / "icon_512.png")
    vibrance(src("IconRealEyesA")).resize((512, 512), Image.LANCZOS).save(OUT / "icon_512_alt.png")

    # 1. The steal (lead thumbnail): big logo, one line of hype
    c = vibrance(cover(src("c826ccbe"), W, H, (0.5, 0.45))).convert("RGBA")
    vignette(c, 90)
    place(c, logo_at(700, logo), 10, 0)
    place(c, text_layer("STEAL THEIR\nRAREST!", "LuckiestGuy-Regular.ttf", 120, angle=-4), 60, H - 40, "lb")
    c.convert("RGB").save(OUT / "thumb_1_steal.jpg", quality=92)

    # 2. The hatch
    c = vibrance(cover(src("a95a62f6"), W, H, (0.5, 0.5))).convert("RGBA")
    vignette(c, 90)
    place(c, logo_at(430, logo), 10, 0)
    place(
        c,
        text_layer("HATCH A\n1 IN 10,000!", "LuckiestGuy-Regular.ttf", 118, angle=4),
        W - 50,
        H - 40,
        "rb",
    )
    c.convert("RGB").save(OUT / "thumb_2_hatch.jpg", quality=92)

    # 3. The collection
    c = vibrance(cover(src("1ccbf410"), W, H, (0.5, 0.5))).convert("RGBA")
    vignette(c, 80)
    place(c, logo_at(430, logo), 10, 0)
    place(c, text_layer("COLLECT 41 CREATURES", "LuckiestGuy-Regular.ttf", 104, angle=-2), W // 2, H - 30, "mb")
    place(
        c,
        text_layer("7 SHINY FINISHES", "LuckiestGuy-Regular.ttf", 64, (230, 250, 255), (120, 200, 255)),
        W - 40,
        40,
        "rt",
    )
    c.convert("RGB").save(OUT / "thumb_3_collect.jpg", quality=92)

    # 4. Moon events: the square art on the right, a panel of the same scene on the left
    art = vibrance(src("ThumbMoon")).resize((H, H), Image.LANCZOS)
    panel = W - H + 320  # the left panel runs under the art's faded edge
    c = Image.new("RGBA", (W, H))
    back = art.crop((0, 0, H // 3, H)).resize((panel, H), Image.LANCZOS)
    back = back.filter(ImageFilter.GaussianBlur(22)).convert("RGBA")
    shade = Image.new("L", (panel, H))
    for x in range(panel):  # darker on the left for the text, clear toward the art
        ImageDraw.Draw(shade).line([(x, 0), (x, H)], fill=round(130 * (1 - x / panel)))
    back.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (panel, H), (20, 0, 10)).split(), shade)))
    c.alpha_composite(back, (0, 0))
    fade = Image.new("L", (H, H), 255)
    for x in range(320):
        ImageDraw.Draw(fade).line([(x, 0), (x, H)], fill=round(255 * (x / 320) ** 1.5))
    art_rgba = art.convert("RGBA")
    art_rgba.putalpha(fade)
    c.alpha_composite(art_rgba, (W - H, 0))
    middle = (W - H) // 2 + 40
    place(c, logo_at(560, logo), middle, 20, "mt")
    place(
        c,
        text_layer("MOON EVENTS!", "LuckiestGuy-Regular.ttf", 120, (255, 225, 225), (255, 60, 60), angle=-3),
        middle,
        H - 170,
        "mb",
    )
    place(
        c,
        text_layer("BLOOD · GOLD · VOID · PRISM", "LilitaOne-Regular.ttf", 54, (255, 255, 255), (255, 210, 210)),
        middle,
        H - 70,
        "mb",
    )
    c.convert("RGB").save(OUT / "thumb_4_moon.jpg", quality=92)
    print("wrote", ", ".join(sorted(p.name for p in OUT.iterdir())))


if __name__ == "__main__":
    main()
