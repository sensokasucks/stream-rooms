"""make_forge_textures.py - paints the Forge Hall's stone, wood, metal and sign textures.

    python make_forge_textures.py <out_dir>

The PNGs go into rooms/forge_hall/textures, where forge_hall_gen.py (tex_mat) picks them up
by these names. Needs numpy and Pillow; it runs in plain Python, not inside Blender.

    stone_slab.png   1024x1024  big warm-grey stone slabs with bevelled edges and a few cracks
                                (walls, pillars, chimney; one texture = 4 m)
    floor_tiles.png  1024x1024  2 x 2 worn floor flags (one texture = 3 m, so tiles are 1.5 m)
    wood_panel.png   1024x512   dark wood wainscot: two framed panels with rounded corners
                                (one texture = 2.4 m wide, 1.2 m tall)
    roof_planks.png  512x512    dark roof boards (one texture = 2 m)
    metal_plate.png  512x512    gunmetal plating with seams and rivets (trim bands, the forge)
    rune_sign.png    256x256    a round cyan sign (our own glyph: two hooked arrows chasing
                                each other) on a dark plate; glows
    sun_patch.png    256x512    the soft patch of sunlight a barred skylight throws on the
                                floor (white on black; the room script draws it additively)

Everything here is an original design.
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
RNG = np.random.default_rng(23)     # fixed seed: the same textures every run

STONE_DARK = (58, 52, 50)
STONE_LIGHT = (112, 102, 94)
GROOVE = (22, 19, 20)
WOOD_DARK = (38, 26, 20)
WOOD_LIGHT = (84, 58, 40)
METAL_DARK = (30, 32, 38)
METAL_LIGHT = (70, 74, 84)
CYAN = (70, 235, 255)


def smooth_noise(h, w, cells_y, cells_x, seed):
    """Soft random 0..1 noise of size h x w: a cells_y x cells_x grid of random values, scaled up bicubically."""
    r = np.random.default_rng(seed).random((cells_y, cells_x)).astype(np.float32)
    im = Image.fromarray((r * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def lerp_rgb(a, b, t):
    """Mix two colours per pixel: t is an h x w array 0..1."""
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    if a.ndim == 1:
        a = a[None, None, :]
    if b.ndim == 1:
        b = b[None, None, :]
    return a + (b - a) * t[..., None]


def save(name, arr, mode=None):
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode)
    im.save(os.path.join(OUT, name))
    print("wrote", name)


def painted(h, w, seed, dark, light):
    """A hand-painted looking surface: big soft blotches, medium dabs and a fine grain."""
    t = (smooth_noise(h, w, 5, 5, seed) * 0.5 + smooth_noise(h, w, 18, 18, seed + 1) * 0.3
         + smooth_noise(h, w, 96, 96, seed + 2) * 0.2)
    return lerp_rgb(dark, light, np.clip((t - 0.2) / 0.6, 0, 1))


def bevel_blocks(img, rects, groove=7, hi=0.22, lo=0.3):
    """Cuts img into blocks: each rect (x0, y0, x1, y1) gets its own tone, a light top / left
    edge and a dark bottom / right edge, with a dark groove between blocks."""
    h, w = img.shape[:2]
    shade = np.ones((h, w), np.float32)
    gmask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(gmask)
    for (x0, y0, x1, y1) in rects:
        tone = 0.86 + RNG.random() * 0.28
        shade[y0:y1, x0:x1] *= tone
        b = groove + 10
        shade[y0:y0 + b, x0:x1] *= 1.0 + hi          # lit top edge
        shade[y0:y1, x0:x0 + b // 2] *= 1.0 + hi * 0.5
        shade[y1 - b:y1, x0:x1] *= 1.0 - lo          # shaded bottom edge
        shade[y0:y1, x1 - b // 2:x1] *= 1.0 - lo * 0.6
        d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=255, width=groove // 2 + 1)
    shade = np.asarray(Image.fromarray(np.clip(shade * 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)), np.float32) / 128.0
    g = np.asarray(gmask.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    out = img * shade[..., None]
    return lerp_rgb(out, GROOVE, np.clip(g * 1.2, 0, 1))


def cracks(img, count, seed, strength=0.6):
    """A few wandering dark cracks with a thin light lip."""
    h, w = img.shape[:2]
    rng = np.random.default_rng(seed)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    for _ in range(count):
        x, y = rng.random() * w, rng.random() * h
        ang = rng.random() * math.pi * 2
        pts = []
        for _s in range(int(10 + rng.random() * 14)):
            pts.append((x, y))
            ang += (rng.random() - 0.5) * 1.2
            x += math.cos(ang) * 14
            y += math.sin(ang) * 14
        d.line(pts, fill=255, width=2)
    c = np.asarray(m.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
    lip = np.roll(c, 2, axis=0)
    out = img * (1.0 + lip[..., None] * 0.25)
    return lerp_rgb(out, GROOVE, np.clip(c * strength, 0, 1))


def stone_slab():
    """Wall stone: a row of tall slabs over a row of wide ones (tiles both ways)."""
    h = w = 1024
    img = painted(h, w, 31, STONE_DARK, STONE_LIGHT)
    rects = [(0, 0, 512, 512), (512, 0, 1024, 512),
             (0, 512, 256, 1024), (256, 512, 768, 1024), (768, 512, 1024, 1024)]
    img = bevel_blocks(img, rects)
    img = cracks(img, 9, 5)
    save("stone_slab.png", img)


def floor_tiles():
    """Floor flags: 2 x 2 big tiles, worn lighter in the middle, darker in the joints."""
    h = w = 1024
    img = painted(h, w, 41, (50, 46, 46), (104, 98, 92))
    rects = [(0, 0, 512, 512), (512, 0, 1024, 512), (0, 512, 512, 1024), (512, 512, 1024, 1024)]
    img = bevel_blocks(img, rects, groove=6, hi=0.12, lo=0.2)
    img = cracks(img, 6, 9, 0.45)
    save("floor_tiles.png", img)


def wood_panel():
    """Wainscot: dark boards with two inset panels, each framed with a rounded moulding."""
    h, w = 512, 1024
    grain = smooth_noise(h, w, 4, 160, 51) * 0.6 + smooth_noise(h, w, 24, 6, 52) * 0.4
    img = lerp_rgb(WOOD_DARK, WOOD_LIGHT, np.clip(grain, 0, 1) * 0.75)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for k in range(2):
        x0, x1 = k * 512 + 56, k * 512 + 456
        y0, y1 = 70, 440
        d.rounded_rectangle([x0, y0, x1, y1], radius=46, outline=(20, 13, 10), width=14)
        d.rounded_rectangle([x0 + 12, y0 + 12, x1 - 12, y1 - 12], radius=36, outline=(104, 74, 50), width=4)
        d.line([(k * 512, 0), (k * 512, h)], fill=(18, 12, 9), width=6)
    d.rectangle([0, 0, w, 22], fill=(64, 44, 30))          # the cap rail (top of the texture = V 1)
    d.rectangle([0, 22, w, 28], fill=(18, 12, 9))
    d.rectangle([0, h - 30, w, h], fill=(26, 18, 14))      # the skirting
    img = np.asarray(im.filter(ImageFilter.GaussianBlur(0.7)), np.float32)
    img *= (0.9 + smooth_noise(h, w, 12, 24, 53)[..., None] * 0.2)
    save("wood_panel.png", img)


def roof_planks():
    """Roof boards: eight dark planks with grain along them."""
    h = w = 512
    grain = smooth_noise(h, w, 200, 5, 61) * 0.7 + smooth_noise(h, w, 8, 8, 62) * 0.3
    img = lerp_rgb((24, 17, 14), (66, 46, 33), np.clip(grain, 0, 1))
    for k in range(8):
        img[:, k * 64:(k + 1) * 64] *= 0.85 + RNG.random() * 0.3
        img[:, k * 64:k * 64 + 3] *= 0.35
    save("roof_planks.png", img)


def metal_plate():
    """Gunmetal plating: brushed panels with seams and a rivet in every corner."""
    h = w = 512
    brushed = smooth_noise(h, w, 256, 6, 71) * 0.5 + smooth_noise(h, w, 6, 6, 72) * 0.5
    img = lerp_rgb(METAL_DARK, METAL_LIGHT, np.clip(brushed, 0, 1))
    img = bevel_blocks(img, [(0, 0, 256, 256), (256, 0, 512, 256), (0, 256, 512, 512)], groove=5, hi=0.25, lo=0.25)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for (x, y) in [(22, 22), (234, 22), (22, 234), (234, 234), (278, 22), (490, 22), (278, 234), (490, 234),
                   (22, 278), (490, 278), (22, 490), (490, 490), (256, 278), (256, 490)]:
        d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(18, 19, 23))
        d.ellipse([x - 5, y - 6, x + 4, y + 3], fill=(96, 100, 112))
    save("metal_plate.png", np.asarray(im, np.float32))


def rune_sign():
    """The round cyan sign: a ring with two hooked arrows chasing each other, on a dark plate."""
    s = 256
    big = Image.new("L", (s * 4, s * 4), 0)       # drawn 4x and scaled down for smooth edges
    d = ImageDraw.Draw(big)
    c, R = s * 2, s * 2 - 90
    d.ellipse([c - R, c - R, c + R, c + R], outline=255, width=44)
    r = R - 190
    for a0 in (20, 200):                          # two arcs, each ending in a hook
        d.arc([c - r, c - r, c + r, c + r], a0, a0 + 130, fill=255, width=56)
        a = math.radians(a0 + 130)
        tip = (c + r * math.cos(a), c + r * math.sin(a))
        inward = (c + (r - 150) * math.cos(a - 0.5), c + (r - 150) * math.sin(a - 0.5))
        d.line([tip, inward], fill=255, width=56)
    glyph = np.asarray(big.resize((s, s), Image.LANCZOS), np.float32) / 255.0
    halo = np.asarray(Image.fromarray((glyph * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(8)), np.float32) / 255.0
    img = lerp_rgb((6, 14, 18), CYAN, np.clip(glyph + halo * 0.5, 0, 1))
    save("rune_sign.png", img)


def sun_patch():
    """Sunlight through a barred skylight, as it lands on the floor: 2 x 4 soft bright panes."""
    h, w = 512, 256
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    for r in range(4):
        for c in range(2):
            x0, y0 = 28 + c * 104, 30 + r * 116
            d.rectangle([x0, y0, x0 + 92, y0 + 104], fill=255)
    soft = np.asarray(m.filter(ImageFilter.GaussianBlur(9)), np.float32)
    soft *= 0.75 + smooth_noise(h, w, 8, 4, 81) * 0.25
    save("sun_patch.png", np.repeat(soft[..., None], 3, axis=2))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    stone_slab()
    floor_tiles()
    wood_panel()
    roof_planks()
    metal_plate()
    rune_sign()
    sun_patch()
