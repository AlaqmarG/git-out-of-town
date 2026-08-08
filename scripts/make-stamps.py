#!/usr/bin/env python3
"""Render trek photos as perforated postage stamps for docs/hunt.md.

Frame geometry is lifted from the SummerHacks portal's own `.trek-stamp`:
a white card with 5px semicircular notches every 17px bitten out of each
edge, 10px padding, and a 4:5 photo well. Everything here is that spec
scaled by SCALE.

    python3 scripts/make-stamps.py
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SCALE = 3
CARD_W = 220 * SCALE
PAD = 10 * SCALE
NOTCH_R = 5 * SCALE
NOTCH_STEP = 17 * SCALE
PHOTO_W = CARD_W - 2 * PAD
PHOTO_H = round(PHOTO_W * 5 / 4)

ACCENT = (176, 127, 70)
INK = (42, 42, 42)
CARD = (255, 255, 255)
WELL = (255, 239, 221)
EDGE = (228, 216, 200)

TITLE_PX = 13 * SCALE
MONO_PX = 10 * SCALE
BADGE_PX = 12 * SCALE
BADGE_D = 51 * SCALE
MONO_TRACK = 0.8 * SCALE

SRC = "docs/assets/photos"
OUT = "docs/assets/photos"

# Landscape shots get letterboxed rather than cropped — a 4:5 crop cuts
# people off the edges, and every teammate has to stay in frame.
PHOTOS = [
    ("1117-milkys", "Milky's Cloud Room", "Sat Aug 8 · 11:17 AM · new spot", False),
    ("1221-fungo", "Fungo Cafe", "Sat Aug 8 · 12:21 PM · new spot", False),
    ("1324-waterworks", "Waterworks Food Hall / The Well", "Sat Aug 8 · 1:24 PM · new spot", True),
    ("1425-scadding", "Scadding Court Community Ctr", "Sat Aug 8 · 2:25 PM · new spot", False),
    ("1526-lillian", "TPL Lillian H. Smith Branch", "Sat Aug 8 · 3:26 PM · new spot", False),
    ("1631-fortyork", "TPL Fort York Branch", "Sat Aug 8 · 4:31 PM · new spot", True),
    ("1739-studio", "The Studio", "Sat Aug 8 · 5:39 PM · off-list", False),
]

PENDING = [
    ("6-39-botanic", "Botanic Coffee and Caphe", "Sat Aug 8 · 6:39 PM · closes 7 PM"),
    ("7-39-icha", "ICHA Tea / Project Seoul", "Sat Aug 8 · 7:39 PM · unlogged"),
    ("8-39-varda", "Varda", "Sat Aug 8 · 8:39 PM · unlogged"),
]


def sans(px, weight="Medium"):
    try:
        f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", px)
        f.set_variation_by_name(weight)
        return f
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", px, index=0)


def mono(px):
    return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", px, index=0)


def tracked(draw, xy, text, font, fill, track):
    """Draw text with letter-spacing, since PIL has no native tracking."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + track
    return x - track


def tracked_width(draw, text, font, track):
    return sum(draw.textlength(c, font=font) for c in text) + track * (len(text) - 1)


def stamp_mask(w, h):
    """Alpha mask: rounded card with semicircular notches bitten out of every edge."""
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=2 * SCALE, fill=255)

    def bite(cx, cy):
        d.ellipse([cx - NOTCH_R, cy - NOTCH_R, cx + NOTCH_R, cy + NOTCH_R], fill=0)

    # Centre the run of notches on each edge so corners stay symmetrical.
    def positions(span):
        n = max(1, round((span - NOTCH_STEP) / NOTCH_STEP))
        start = (span - n * NOTCH_STEP) / 2
        return [start + i * NOTCH_STEP for i in range(n + 1)]

    for x in positions(w):
        bite(x, 0)
        bite(x, h)
    for y in positions(h):
        bite(0, y)
        bite(w, y)
    return m


def fit_4x5(path, w, h, contain=False):
    """Centre-crop to 4:5, or letterbox when cropping would cut people out."""
    im = Image.open(path).convert("RGB")
    sw, sh = im.size
    if contain:
        s = min(w / sw, h / sh)
        im = im.resize((round(sw * s), round(sh * s)), Image.LANCZOS)
        well = Image.new("RGB", (w, h), WELL)
        well.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
        return well
    if sw / sh > w / h:
        nw = round(sh * w / h)
        box = ((sw - nw) // 2, 0, (sw - nw) // 2 + nw, sh)
    else:
        nh = round(sw * h / w)
        box = (0, (sh - nh) // 2, sw, (sh - nh) // 2 + nh)
    return im.resize((w, h), Image.LANCZOS, box=box)


def badge(text):
    """Circular dashed '+N pts' chip, drawn 4x and downsampled for clean curves."""
    s, d_ = 4, BADGE_D
    img = Image.new("RGBA", (d_ * s, d_ * s), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    r = d_ * s / 2
    dr.ellipse([0, 0, d_ * s - 1, d_ * s - 1], fill=(255, 255, 255, 217))
    # Dashed ring: 2px stroke, ~10 dashes round the circle.
    seg = 360 / 22
    for i in range(22):
        if i % 2:
            continue
        dr.arc([s, s, d_ * s - s, d_ * s - s], i * seg, (i + 1) * seg,
               fill=ACCENT + (255,), width=2 * SCALE * s)
    img = img.resize((d_, d_), Image.LANCZOS)
    dr = ImageDraw.Draw(img)
    f = sans(BADGE_PX, "Semibold")
    tw = dr.textlength(text, font=f)
    dr.text(((d_ - tw) / 2, d_ / 2 - BADGE_PX * 0.62), text, font=f, fill=ACCENT + (255,))
    return img


def caption_block(draw, y, title, meta, ink, accent):
    f = sans(TITLE_PX, "Medium")
    while draw.textlength(title, font=f) > PHOTO_W and f.size > 8 * SCALE:
        f = sans(f.size - SCALE, "Medium")
    draw.text((PAD, y), title, font=f, fill=ink)

    fm = mono(MONO_PX)
    up = meta.upper()
    while tracked_width(draw, up, fm, MONO_TRACK) > PHOTO_W and fm.size > 6 * SCALE:
        fm = mono(fm.size - 1)
    tracked(draw, (PAD, y + TITLE_PX + 5 * SCALE), up, fm, accent, MONO_TRACK)


CAPTION_H = TITLE_PX + 5 * SCALE + MONO_PX + 6 * SCALE
CARD_H = PAD + PHOTO_H + 9 * SCALE + CAPTION_H + PAD


def build(slug, title, meta, photo=None, contain=False):
    card = Image.new("RGBA", (CARD_W, CARD_H), CARD + (255,))
    d = ImageDraw.Draw(card)

    well = Image.new("RGB", (PHOTO_W, PHOTO_H), WELL)
    if photo:
        well = fit_4x5(photo, PHOTO_W, PHOTO_H, contain)
    card.paste(well, (PAD, PAD))

    if not photo:
        d.rounded_rectangle([PAD, PAD, PAD + PHOTO_W - 1, PAD + PHOTO_H - 1],
                            radius=2 * SCALE, outline=(232, 208, 178), width=SCALE)
        f = mono(11 * SCALE)
        t = "NOT YET"
        d.text(((CARD_W - d.textlength(t, font=f)) / 2, PAD + PHOTO_H / 2 - 8 * SCALE),
               t, font=f, fill=(214, 180, 141))

    ink = INK if photo else (150, 150, 150)
    accent = ACCENT if photo else (196, 176, 152)
    caption_block(d, PAD + PHOTO_H + 9 * SCALE, title, meta, ink, accent)

    if photo:
        b = badge("+2 pts" if "new spot" in meta else "+1 pt")
        card.alpha_composite(b, (CARD_W - PAD - BADGE_D + 6 * SCALE, PAD - 6 * SCALE))

    mask = stamp_mask(CARD_W, CARD_H)
    # Hairline along the scalloped silhouette so the white card still reads
    # against GitHub's light theme.
    ring = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    card.paste(Image.new("RGBA", card.size, EDGE + (255,)), (0, 0), ring)

    card.putalpha(mask)
    out = f"{OUT}/{slug}-stamp.png"
    # The notch alpha is hard-edged, so a palette PNG keeps the cut-outs
    # intact and drops each stamp from ~830 KB to ~180 KB.
    card.quantize(colors=255, method=Image.FASTOCTREE,
                  dither=Image.FLOYDSTEINBERG).save(out, optimize=True)
    return out


if __name__ == "__main__":
    for slug, title, meta, contain in PHOTOS:
        print(build(slug, title, meta, photo=f"{SRC}/{slug}.jpg", contain=contain))
    for slug, title, meta in PENDING:
        print(build(slug, title, meta))
    print(f"card {CARD_W}x{CARD_H}  photo {PHOTO_W}x{PHOTO_H}")
