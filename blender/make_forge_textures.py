"""make_forge_textures.py - paints the Forge Hall's stone, wood, metal and sign textures.

    python make_forge_textures.py <out_dir>

The PNGs go into rooms/forge_hall/textures, where forge_hall_gen.py (tex_mat) picks them up
by these names. Needs numpy and Pillow; it runs in plain Python, not inside Blender.

    slab_granite.png 1024x1024  one unbroken slab of dark polished granite: fine crystal speckle
                                and a few hairline cracks, no joints (walls, ledges, podiums; = 6 m)
    pillar_marble.png 1024x1024 the pillars: lighter grey marble with pale and dark veins (= 6 m)
    forge_granite.png 1024x1024 the forge: steelier granite with bright flakes (= 6 m)
    floor_slab.png   1024x1024  2 x 2 big polished granite floor slabs with hairline joints (= 6 m)
    standby_card.png 1280x720   the "please stand by" card shown over the screen instead of a
                                curtain (core/standby_card.gd; RoomInfo.standby_card)
    diamond_plate.png 512x512   very dark steel tread plate (the ceiling; = 1 m)
    art_1..6.png     512x640    six poster pictures for the alcove art frames (shown until the
                                owner picks their own)
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


def veins(h, w, count, seed, step=20, width=(1, 3)):
    """A 0..1 mask of a few long wandering lines (marble veins), soft-edged. Tiles badly on
    purpose: the slabs are meant to read as single big pieces of stone."""
    rng = np.random.default_rng(seed)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    for _ in range(count):
        x, y = rng.random() * w, rng.random() * h
        ang = rng.random() * math.pi * 2
        pts = []
        for _s in range(70):
            pts.append((x, y))
            ang += (rng.random() - 0.5) * 0.7
            x += math.cos(ang) * step
            y += math.sin(ang) * step
        d.line(pts, fill=255, width=int(width[0] + rng.random() * (width[1] - width[0])))
    fine = np.asarray(m.filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255.0
    wide = np.asarray(m.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255.0
    return np.clip(fine * 0.6 + wide * 0.5, 0, 1)


def granite(h, w, seed, base, grains):
    """Polished granite: a dark ground packed with small crystals. grains = [(colour, share of
    the surface 0..1, crystal size in pixels)]: each is a layer of random specks, blurred to the
    crystal size and cut off so that `share` of the surface shows it. At 1024 px for 6 m a pixel
    is about 6 mm, so sizes of 1 to 3 px read as real granite grain from across the room."""
    rng = np.random.default_rng(seed)
    cloud = smooth_noise(h, w, 5, 5, seed + 1) * 0.6 + smooth_noise(h, w, 24, 24, seed + 2) * 0.4
    img = lerp_rgb(np.asarray(base, np.float32) * 0.8, np.asarray(base, np.float32) * 1.25, cloud)
    for k, (colour, share, size) in enumerate(grains):
        speck = Image.fromarray((rng.random((h, w)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(size))
        a = np.asarray(speck, np.float32)
        cut = np.quantile(a, 1.0 - share)
        soft = max(float(a.std()) * 0.35, 1e-3)
        img = lerp_rgb(img, colour, np.clip((a - cut) / soft, 0, 1) * 0.6)
    return img


# the crystals in the hall's granite: grey and white quartz, black mica, a little warm feldspar
GRANITE_GRAINS = [((78, 80, 88), 0.3, 1.1), ((10, 10, 13), 0.22, 0.9), ((128, 128, 136), 0.09, 0.8),
                  ((190, 188, 182), 0.025, 0.6), ((104, 78, 70), 0.04, 1.0), ((58, 72, 88), 0.04, 1.5)]


def slab_granite():
    """Wall and pillar stone: one unbroken slab of dark polished granite (fine speckle, no
    joints, a few hairline cracks). One texture = 6 m."""
    img = granite(1024, 1024, 31, (34, 35, 40), GRANITE_GRAINS)
    img = cracks(img, 3, 7, 0.5)
    save("slab_granite.png", img)


def pillar_marble():
    """The pillars (round 4): a shade lighter than the granite walls and marble rather than
    speckle: a soft cloudy grey ground, pale veins wandering across it, a few thin dark ones and
    only a trace of grain. One texture = 6 m, like the slab, and a pillar's face is only
    about 220 px of it across, so the veins are packed close."""
    h = w = 1024
    cloud = smooth_noise(h, w, 4, 4, 61) * 0.55 + smooth_noise(h, w, 14, 14, 62) * 0.3 + smooth_noise(h, w, 60, 60, 63) * 0.15
    img = lerp_rgb((50, 52, 58), (88, 90, 97), cloud)
    img = lerp_rgb(img, (188, 190, 196), veins(h, w, 46, 64, step=15, width=(1, 4)) * 0.8)
    img = lerp_rgb(img, (20, 21, 25), veins(h, w, 22, 65, step=13, width=(1, 2)) * 0.6)
    rng = np.random.default_rng(66)
    img = np.clip(img + (rng.random((h, w, 1)) - 0.5) * 7.0, 0, 255)     # a trace of grain
    save("pillar_marble.png", img)


# the forge's granite: the hall's crystals plus bright steel-grey flakes that catch the light
FORGE_GRAINS = GRANITE_GRAINS + [((168, 172, 182), 0.07, 0.7), ((214, 216, 222), 0.02, 0.5)]


def forge_granite():
    """The forge body (round 4): the hall's granite with a bluer, steelier ground and extra
    bright flakes. The material is half metallic (forge_hall_gen.py, Forge_Granite), so the
    flakes glint in the fire and the inlays."""
    img = granite(1024, 1024, 71, (38, 41, 48), FORGE_GRAINS)
    img = cracks(img, 2, 73, 0.4)
    save("forge_granite.png", img)


def floor_slab():
    """Floor: 2 x 2 big slabs of the same granite, a shade darker, with hairline joints (one
    texture = 6 m, so slabs are 3 m)."""
    img = granite(1024, 1024, 41, (26, 27, 31), GRANITE_GRAINS)
    img = bevel_blocks(img, [(0, 0, 512, 512), (512, 0, 1024, 512), (0, 512, 512, 1024), (512, 512, 1024, 1024)], groove=3, hi=0.05, lo=0.08)
    img = cracks(img, 2, 11, 0.4)
    save("floor_slab.png", img)


def _font(size):
    """A bold font at `size` px: DejaVu or Arial where there is one, else PIL's built-in."""
    from PIL import ImageFont
    for name in ("DejaVuSans-Bold.ttf", "arialbd.ttf", "Arial Bold.ttf", "LiberationSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default(size)


def standby_card():
    """The "please stand by" card the hall shows over its screen instead of a curtain (an
    original design in the spirit of old TV test cards: a grid, a big circle of colour bars and
    grey steps, corner circles and a caption band). 1280 x 720, the screen's 16:9."""
    w, h = 1280, 720
    im = Image.new("RGB", (w, h), (24, 26, 32))
    d = ImageDraw.Draw(im)
    for x in range(0, w + 1, 80):
        d.line([(x, 0), (x, h)], fill=(150, 154, 160), width=2)
    for y in range(0, h + 1, 80):
        d.line([(0, y), (w, y)], fill=(150, 154, 160), width=2)
    for (cx, cy) in ((120, 120), (w - 120, 120), (120, h - 120), (w - 120, h - 120)):      # corner circles
        d.ellipse([cx - 84, cy - 84, cx + 84, cy + 84], fill=(24, 26, 32), outline=(230, 230, 225), width=5)
        for k in range(12):
            a = k * math.pi / 6
            d.line([(cx, cy), (cx + 80 * math.cos(a), cy + 80 * math.sin(a))], fill=(230, 230, 225) if k % 2 == 0 else (90, 92, 98), width=3)
    # the big circle: colour bars on top, grey steps below, cut to a disc
    r = 300
    disc = Image.new("RGB", (2 * r, 2 * r), (0, 0, 0))
    dd = ImageDraw.Draw(disc)
    bars = [(235, 235, 230), (235, 215, 40), (40, 210, 220), (50, 200, 70), (205, 60, 200), (215, 50, 45), (45, 70, 205)]
    bw = 2 * r / len(bars)
    for k, c in enumerate(bars):
        dd.rectangle([k * bw, 0, (k + 1) * bw, r * 1.1], fill=c)
    for k in range(10):
        g = int(20 + 235 * k / 9)
        dd.rectangle([k * 2 * r / 10, r * 1.5, (k + 1) * 2 * r / 10, 2 * r], fill=(g, g, g))
    for k in range(40):                                                    # fine black / white lines
        dd.rectangle([k * 2 * r / 40, r * 1.1, (k + 1) * 2 * r / 40, r * 1.26], fill=(240, 240, 240) if k % 2 else (10, 10, 10))
    mask = Image.new("L", (2 * r, 2 * r), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 2 * r - 1, 2 * r - 1], fill=255)
    im.paste(disc, (w // 2 - r, h // 2 - r), mask)
    d.ellipse([w // 2 - r, h // 2 - r, w // 2 + r, h // 2 + r], outline=(240, 240, 235), width=6)
    # the caption band across the middle of the circle
    d.rectangle([w // 2 - r - 40, h // 2 + 42, w // 2 + r + 40, h // 2 + 132], fill=(12, 12, 16), outline=(240, 240, 235), width=4)
    f = _font(58)
    text = "PLEASE STAND BY"
    tw = d.textlength(text, font=f)
    d.text((w // 2 - tw / 2, h // 2 + 52), text, fill=(245, 245, 240), font=f)
    f2 = _font(26)
    for text, y in (("FORGE HALL", 28), ("TRANSMISSION WILL RESUME SHORTLY", h - 62)):
        tw = d.textlength(text, font=f2)
        d.rectangle([w // 2 - tw / 2 - 16, y - 6, w // 2 + tw / 2 + 16, y + 38], fill=(12, 12, 16))
        d.text((w // 2 - tw / 2, y), text, fill=(120, 235, 255), font=f2)
    im.save(os.path.join(OUT, "standby_card.png"))
    print("wrote standby_card.png")


def diamond_plate():
    """Ceiling: very dark steel tread plate, the raised diamonds in a herringbone (one texture = 1 m)."""
    s = 512
    big = Image.new("L", (s * 2, s * 2), 0)
    d = ImageDraw.Draw(big)
    n = 8
    cell = s * 2 / n
    for r in range(n):
        for c in range(n):
            cx, cy = (c + 0.5) * cell, (r + 0.5) * cell
            a = math.radians(45 if (r + c) % 2 == 0 else -45)
            dx, dy = math.cos(a) * cell * 0.36, math.sin(a) * cell * 0.36
            px, py = -math.sin(a) * cell * 0.09, math.cos(a) * cell * 0.09
            d.polygon([(cx - dx, cy - dy), (cx + px, cy + py), (cx + dx, cy + dy), (cx - px, cy - py)], fill=255)
    lug = np.asarray(big.resize((s, s), Image.LANCZOS), np.float32) / 255.0
    hi = np.clip(lug - np.roll(lug, 3, axis=0), 0, 1)          # lit upper edge of each diamond
    base = lerp_rgb((14, 15, 18), (30, 32, 37), smooth_noise(s, s, 8, 8, 91))
    img = lerp_rgb(base, (52, 55, 62), lug * 0.7)
    img = lerp_rgb(img, (120, 124, 134), hi * 0.6)
    save("diamond_plate.png", img)


def _art_base(seed, top, bottom):
    """A 512 x 640 canvas with a vertical colour wash and a little paint texture."""
    h, w = 640, 512
    t = np.linspace(0, 1, h)[:, None] * np.ones((1, w))
    img = lerp_rgb(top, bottom, t.astype(np.float32))
    img *= 0.85 + smooth_noise(h, w, 40, 32, seed)[..., None] * 0.3
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def art():
    """Six pictures for the alcove frames, shown until the owner picks their own
    (art_1.png .. art_6.png, 512 x 640): simple poster designs on the room's themes."""
    # 1: a gear with a glowing hub
    im = _art_base(101, (22, 30, 44), (10, 12, 20)); d = ImageDraw.Draw(im)
    c = (256, 320)
    for k in range(12):
        a = k * math.pi / 6
        d.polygon([(c[0] + math.cos(a + s) * r, c[1] + math.sin(a + s) * r) for s, r in ((-0.11, 150), (-0.08, 200), (0.08, 200), (0.11, 150))], fill=(196, 150, 70))
    d.ellipse([c[0] - 160, c[1] - 160, c[0] + 160, c[1] + 160], fill=(196, 150, 70))
    d.ellipse([c[0] - 110, c[1] - 110, c[0] + 110, c[1] + 110], fill=(16, 20, 30))
    d.ellipse([c[0] - 46, c[1] - 46, c[0] + 46, c[1] + 46], fill=(90, 235, 255))
    im.save(os.path.join(OUT, "art_1.png"))
    # 2: an anvil under a spark
    im = _art_base(102, (60, 24, 14), (14, 8, 8)); d = ImageDraw.Draw(im)
    d.polygon([(110, 330), (402, 330), (402, 372), (330, 392), (330, 452), (392, 500), (392, 540), (120, 540), (120, 500), (182, 452), (182, 392), (110, 372)], fill=(26, 26, 32))
    d.polygon([(402, 336), (486, 348), (402, 366)], fill=(26, 26, 32))
    for k in range(9):
        a = -math.pi / 2 + (k - 4) * 0.28
        d.line([(256 + math.cos(a) * 30, 300 + math.sin(a) * 30), (256 + math.cos(a) * (120 + 40 * (k % 2)), 300 + math.sin(a) * (120 + 40 * (k % 2)))], fill=(255, 190, 80), width=6)
    d.ellipse([236, 280, 276, 320], fill=(255, 240, 190))
    im.save(os.path.join(OUT, "art_2.png"))
    # 3: a circuit sun over a horizon
    im = _art_base(103, (44, 16, 70), (8, 10, 30)); d = ImageDraw.Draw(im)
    d.ellipse([136, 150, 376, 390], fill=(255, 120, 40))
    for y in range(270, 400, 22):
        d.rectangle([120, y, 392, y + 8 + (y - 270) // 12], fill=(30, 12, 54))
    for k in range(-6, 7):
        d.line([(256 + k * 14, 420), (256 + k * 80, 640)], fill=(70, 235, 255), width=3)
    for y in (420, 440, 470, 515, 580):
        d.line([(0, y), (512, y)], fill=(70, 235, 255), width=3)
    im.save(os.path.join(OUT, "art_3.png"))
    # 4: a flame in three layers
    im = _art_base(104, (16, 18, 26), (30, 12, 8)); d = ImageDraw.Draw(im)
    for sc, colr in ((1.0, (190, 40, 16)), (0.72, (255, 130, 30)), (0.42, (255, 230, 150))):
        pts = [(256, 560), (256 - 150 * sc, 470), (256 - 120 * sc, 330), (256 - 40 * sc, 380), (256 - 20 * sc, 560 - 440 * sc),
               (256 + 70 * sc, 300), (256 + 60 * sc, 390), (256 + 140 * sc, 340), (256 + 150 * sc, 470)]
        d.polygon(pts, fill=colr)
    im.save(os.path.join(OUT, "art_4.png"))
    # 5: a hammer crossed with a wrench
    im = _art_base(105, (20, 40, 44), (8, 14, 18)); d = ImageDraw.Draw(im)
    d.line([(130, 520), (360, 170)], fill=(150, 100, 60), width=30)
    d.polygon([(300, 110), (440, 200), (410, 250), (270, 160)], fill=(170, 176, 190))
    d.line([(382, 520), (160, 180)], fill=(196, 150, 70), width=26)
    d.ellipse([110, 120, 210, 220], outline=(196, 150, 70), width=26)
    d.rectangle([120, 100, 200, 150], fill=(14, 26, 30))
    im.save(os.path.join(OUT, "art_5.png"))
    # 6: stacked towers with lit windows
    im = _art_base(106, (70, 40, 90), (16, 12, 30)); d = ImageDraw.Draw(im)
    rng = np.random.default_rng(6)
    for (x0, x1, y0) in ((40, 150, 300), (130, 260, 180), (240, 340, 260), (320, 470, 120), (430, 512, 340)):
        d.rectangle([x0, y0, x1, 640], fill=(18, 16, 30))
        for yy in range(y0 + 20, 620, 34):
            for xx in range(x0 + 14, x1 - 14, 26):
                if rng.random() < 0.45:
                    d.rectangle([xx, yy, xx + 12, yy + 18], fill=(255, 200, 110) if rng.random() < 0.7 else (90, 235, 255))
    im.save(os.path.join(OUT, "art_6.png"))
    print("wrote art_1.png .. art_6.png")


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
    slab_granite()
    pillar_marble()
    forge_granite()
    floor_slab()
    standby_card()
    diamond_plate()
    art()
    wood_panel()
    roof_planks()
    metal_plate()
    rune_sign()
    sun_patch()
