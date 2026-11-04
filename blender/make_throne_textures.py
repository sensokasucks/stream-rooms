"""make_throne_textures.py - paints the Throne Hall's cloth, stone and crest textures.

    python make_throne_textures.py <out_dir> [crest.png]

The PNGs go into rooms/throne_hall/textures, where throne_hall_gen.py (tex_mat) picks them up
by these names. Needs numpy and Pillow; it runs in plain Python, not inside Blender.

    banner.png        1024x2048  one hanging banner: crimson cloth, gold edging, the crest in
                                 the upper half (the crest's dark shape is lifted off the
                                 picture given as crest.png; without one, a plain banner)
    black_marble.png  1024x1024  polished black marble with pale veins (floor, columns)
    carpet.png        512x2048   the crimson runner with a gold key border (tiles along V)
    stone_wall.png    1024x1024  dark grey panelled stone with mortar lines (walls, galleries)
    ribbed_tower.png  512x2048   the pale blue-grey ribbed cladding high on the walls (tiles)

All painted here are original; only the crest comes from the owner's picture.
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
CREST = sys.argv[2] if len(sys.argv) > 2 else ""
RNG = np.random.default_rng(11)     # fixed seed: the same textures every run

CRIMSON = (118, 16, 28)
CRIMSON_DARK = (72, 8, 18)
GOLD = (205, 160, 70)
GOLD_DARK = (120, 85, 30)
BLACK = (14, 12, 14)
MARBLE_VEIN = (120, 118, 125)
STONE = (58, 58, 64)
MORTAR = (28, 28, 32)
RIB_LIGHT = (150, 160, 178)
RIB_DARK = (62, 68, 84)


def smooth_noise(h, w, cells_y, cells_x, seed):
    """Soft random 0..1 noise of size h x w: a cells_y x cells_x grid of random values, scaled up bicubically."""
    r = np.random.default_rng(seed).random((cells_y, cells_x)).astype(np.float32)
    im = Image.fromarray((r * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def lerp_rgb(a, b, t):
    """Mix two colours per pixel: t is an h x w array 0..1."""
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    if a.ndim == 1:      # a flat colour, or an h x w x 3 picture: both work
        a = a[None, None, :]
    if b.ndim == 1:
        b = b[None, None, :]
    return a + (b - a) * t[..., None]


def save(name, arr):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name))
    print("wrote", name)


def cloth(h, w, seed):
    """Crimson cloth: a fine weave plus soft folds."""
    folds = smooth_noise(h, w, 6, 3, seed) * 0.6 + smooth_noise(h, w, 24, 12, seed + 1) * 0.4
    weave = ((np.arange(w)[None, :] % 4 < 2) ^ (np.arange(h)[:, None] % 4 < 2)).astype(np.float32) * 0.06
    t = np.clip(folds * 0.8 + weave, 0, 1)
    return lerp_rgb(CRIMSON_DARK, CRIMSON, t)


def banner():
    """One banner: cloth, a gold edge, a gold band near the top and the crest in the upper half."""
    h, w = 2048, 1024
    img = cloth(h, w, 3)
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im)
    e = 22
    for k in range(3):   # gold edging: two thin lines with a dark gap
        c = GOLD if k != 1 else GOLD_DARK
        d.rectangle([e + k * 10, e + k * 10, w - e - k * 10, h - e - k * 10], outline=c, width=5)
    d.rectangle([0, 150, w, 190], fill=GOLD)
    d.rectangle([0, 190, w, 198], fill=GOLD_DARK)
    if CREST and os.path.exists(CREST):
        crest = Image.open(CREST).convert("RGB")
        a = np.asarray(crest, np.float32)
        # the emblem is the dark shape on the owner's picture: darkness = coverage
        dark = 1.0 - (a.max(axis=2) / 255.0)
        mask = np.clip((dark - 0.6) / 0.2, 0, 1)     # the red cloth behind it stays out (dark ~0.47)
        mask_im = Image.fromarray((mask * 255).astype(np.uint8))
        target_w = int(w * 0.82)
        k = target_w / mask_im.width
        mask_im = mask_im.resize((target_w, int(mask_im.height * k)), Image.LANCZOS)
        # a soft gold halo behind the emblem so it reads from a distance
        halo = mask_im.filter(ImageFilter.GaussianBlur(14))
        base = np.asarray(im, np.float32)
        x0 = (w - mask_im.width) // 2
        y0 = 300
        ys, xs = slice(y0, y0 + mask_im.height), slice(x0, x0 + mask_im.width)
        hl = np.asarray(halo, np.float32) / 255.0 * 0.5
        base[ys, xs] = lerp_rgb(base[ys, xs], GOLD, hl)
        mk = np.asarray(mask_im, np.float32) / 255.0
        base[ys, xs] = lerp_rgb(base[ys, xs], BLACK, mk)
        im = Image.fromarray(base.astype(np.uint8))
    save("banner.png", np.asarray(im, np.float32))


def black_marble():
    """Near-black polished stone with faint pale veins (a few wandering lines, blurred)."""
    h = w = 1024
    base = lerp_rgb((10, 9, 12), (24, 22, 28), smooth_noise(h, w, 8, 8, 21))
    veins = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(veins)
    for i in range(9):
        x, y = RNG.random() * w, RNG.random() * h
        ang = RNG.random() * math.pi * 2
        pts = []
        for s in range(60):
            pts.append((x, y))
            ang += (RNG.random() - 0.5) * 0.9
            x += math.cos(ang) * 22
            y += math.sin(ang) * 22
        d.line(pts, fill=255, width=int(2 + RNG.random() * 3))
    v = np.asarray(veins.filter(ImageFilter.GaussianBlur(2.5)), np.float32) / 255.0
    v2 = np.asarray(veins.filter(ImageFilter.GaussianBlur(18)), np.float32) / 255.0 * 0.35
    out = lerp_rgb(base, MARBLE_VEIN, np.clip(v * 0.55 + v2, 0, 1))
    save("black_marble.png", out)


def carpet():
    """The runner: crimson pile with a gold key-pattern border down each side (tiles along V)."""
    h, w = 2048, 512
    img = cloth(h, w, 5)
    pile = smooth_noise(h, w, 128, 32, 6) * 18 - 9
    img = img + pile[..., None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for x0 in (26, w - 26 - 30):
        d.rectangle([x0, 0, x0 + 30, h], fill=GOLD_DARK)
        d.rectangle([x0 + 4, 0, x0 + 26, h], fill=GOLD)
        # a key (meander) pattern along the band, repeating every 64 px
        for y in range(0, h, 64):
            d.rectangle([x0 + 9, y + 8, x0 + 21, y + 12], fill=GOLD_DARK)
            d.rectangle([x0 + 9, y + 8, x0 + 13, y + 40], fill=GOLD_DARK)
            d.rectangle([x0 + 9, y + 36, x0 + 21, y + 40], fill=GOLD_DARK)
            d.rectangle([x0 + 17, y + 20, x0 + 21, y + 52], fill=GOLD_DARK)
    for x in (4, w - 8):   # a thin gold line right at the edge
        d.rectangle([x, 0, x + 4, h], fill=GOLD)
    save("carpet.png", np.asarray(im, np.float32))


def stone_wall():
    """Dark ashlar blocks with mortar lines; each block a slightly different grey."""
    h = w = 1024
    rows, bh = 8, 128
    img = np.zeros((h, w, 3), np.float32)
    grain = smooth_noise(h, w, 64, 64, 31)
    for r in range(rows):
        off = 0 if r % 2 == 0 else 128
        for c in range(-1, 5):
            x0, y0 = c * 256 + off, r * bh
            tone = 0.85 + RNG.random() * 0.3
            img[max(0, y0):y0 + bh, max(0, x0):x0 + 256] = np.asarray(STONE, np.float32) * tone
    img = img * (0.85 + grain[..., None] * 0.3)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for r in range(rows + 1):
        d.line([(0, r * bh), (w, r * bh)], fill=MORTAR, width=6)
        off = 0 if r % 2 == 0 else 128
        for c in range(-1, 5):
            d.line([(c * 256 + off, r * bh), (c * 256 + off, r * bh + bh)], fill=MORTAR, width=6)
    save("stone_wall.png", np.asarray(im, np.float32))


def ribbed_tower():
    """Pale blue-grey vertical ribs with dark grooves between them (the towering upper walls)."""
    h, w = 2048, 512
    x = np.arange(w)[None, :]
    rib = 0.5 + 0.5 * np.cos((x % 64) / 64.0 * 2 * math.pi)        # one rib per 64 px
    groove = np.clip((rib - 0.15) / 0.85, 0, 1) ** 0.6
    t = np.repeat(groove, h, axis=0) * (0.8 + smooth_noise(h, w, 32, 8, 41) * 0.3)
    bands = (np.arange(h)[:, None] % 512 < 24).astype(np.float32)   # a dark band every 512 px
    t = np.clip(t * (1.0 - bands * 0.7), 0, 1)
    save("ribbed_tower.png", lerp_rgb(RIB_DARK, RIB_LIGHT, t))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    banner()
    black_marble()
    carpet()
    stone_wall()
    ribbed_tower()
