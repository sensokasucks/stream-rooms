"""make_hall_textures.py - paints the lecture hall's stained glass, door and exit sign textures.

    python make_hall_textures.py <out_dir>

All designs are original. Each glass picture is built as a label map (one id per piece of
glass); lead cames are drawn wherever neighbouring pieces differ, then the glass gets streaks,
seeds and a brighter middle in every piece, as real hand-made glass has.

    glass_lancet.png  512x1024  tall pointed lancet (window 1 : 2, equilateral arch top)
    glass_rondel.png  512x512   round rose window
    glass_fan.png     512x320   pointed fanlight over the exit doors (rise 0.625 of the span)
    door_leaf.png     384x1024  one leaf of the big oak doors (the other leaf is mirrored)
    exit_sign.png     256x96    EXIT, lit
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
RNG = np.random.default_rng(7)

# jewel palette (sRGB 0..255)
RUBY = (150, 18, 30)
CRIMSON = (190, 40, 38)
COBALT = (28, 52, 150)
SKY = (70, 120, 190)
EMERALD = (22, 110, 60)
LEAF = (90, 150, 60)
GOLD = (225, 165, 40)
AMBER = (205, 120, 30)
VIOLET = (100, 40, 120)
CREAM = (230, 215, 170)
PALE_G = (190, 205, 160)
PALE_A = (225, 195, 130)
WHITE = (240, 235, 215)
LEAD = (34, 31, 30)


def smooth_noise(h, w, cells_y, cells_x, seed):
    r = np.random.default_rng(seed).random((cells_y, cells_x)).astype(np.float32)
    im = Image.fromarray((r * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def render_glass(labels, colours, inside, lead_px=3):
    """labels: int map (0 = outside). colours: {label: rgb}. Returns an RGB image."""
    h, w = labels.shape
    # lead wherever a neighbour has another label
    edge = np.zeros_like(labels, bool)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = labels
        b = np.roll(np.roll(labels, dy, 0), dx, 1)
        edge |= a != b
    edge = ndimage.binary_dilation(edge, iterations=lead_px)
    edge |= ~ndimage.binary_erosion(inside, iterations=lead_px + 1)
    rgb = np.zeros((h, w, 3), np.float32)
    lut = {}
    for lab, c in colours.items():
        v = 1.0 + RNG.normal(0, 0.07)
        tint = np.array(c, np.float32) * v + RNG.normal(0, 6, 3)
        lut[lab] = np.clip(tint, 0, 255)
    for lab, c in lut.items():
        rgb[labels == lab] = c
    # brighter in the middle of each piece, darker next to the lead
    dist = ndimage.distance_transform_edt(~edge)
    glow = np.clip(dist / 14.0, 0, 1)
    shade = 0.62 + 0.45 * glow
    # streaks (hand-rolled glass) + fine seeds
    streak = smooth_noise(h, w, 10, max(4, w // 10), 11) * 0.28 + 0.86
    grain = 1.0 + RNG.normal(0, 0.035, (h, w)).astype(np.float32)
    seeds = (RNG.random((h, w)) > 0.9985)
    seeds = ndimage.binary_dilation(seeds, iterations=1)
    mul = shade * streak * grain
    rgb = rgb * mul[..., None]
    rgb[seeds] = rgb[seeds] * 1.25 + 12
    # the lead: dark with a faint highlight on its top-left side
    lead_rgb = np.array(LEAD, np.float32)
    hl = ndimage.binary_erosion(edge, iterations=1) ^ edge
    rgb[edge] = lead_rgb
    rgb[hl & edge] = lead_rgb + 22
    rgb[~inside] = (18, 16, 15)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))


def polar(x, y, cx, cy):
    dx, dy = x - cx, y - cy
    return np.hypot(dx, dy), np.arctan2(dy, dx)


class Labeler:
    def __init__(self, shape):
        self.map = np.zeros(shape, np.int32)
        self.colours = {}
        self.n = 0

    def put(self, mask, colour):
        self.n += 1
        self.map[mask] = self.n
        self.colours[self.n] = colour
        return self.n


# ─────────────────────────────── lancet ───────────────────────────────
def lancet():
    W, H = 512, 1024
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (x + 0.5) / W                  # 0..1 across
    v = (H - y - 0.5) / W              # 0..2 up, in widths
    hs = 2.0 - math.sqrt(3) / 2        # spring line
    def shape(b):
        side = (u >= b) & (u <= 1 - b) & (v >= b)
        arch = (np.hypot(u - 1, v - hs) <= 1 - b) & (np.hypot(u, v - hs) <= 1 - b)
        return side & ((v <= hs) | arch)
    outer = shape(0.0)
    inner = shape(0.075)
    L = Labeler(outer.shape)
    # background: diamond quarries in pale glass
    q = 0.145
    a = np.floor((u + v) / q)
    b = np.floor((u - v) / q)
    pale = [CREAM, PALE_G, PALE_A, (215, 205, 175)]
    for i, j in {(int(ai), int(bi)) for ai, bi in zip(a[inner].ravel()[::7], b[inner].ravel()[::7])}:
        m = inner & (a == i) & (b == j)
        L.put(m, pale[(i * 3 + j) % 4])
    # small jewels where quarry leads cross
    ja = np.round((u + v) / q) * q
    jb = np.round((u - v) / q) * q
    ju, jv = (ja + jb) / 2, (ja - jb) / 2
    jewel = inner & (np.hypot(u - ju, v - jv) < 0.028)
    L.put(jewel, CRIMSON)
    # base panel: a row of gold and ruby blocks
    for k in range(5):
        m = inner & (v < 0.2) & (u >= 0.075 + k * 0.17) & (u < 0.075 + (k + 1) * 0.17)
        L.put(m, GOLD if k % 2 == 0 else RUBY)
    # lower medallion: a quatrefoil with a four-petal flower
    cx, cy = 0.5, 0.52
    foil = np.zeros_like(inner)
    for ang in range(4):
        t = ang * math.pi / 2
        foil |= np.hypot(u - (cx + 0.13 * math.cos(t)), v - (cy + 0.13 * math.sin(t))) < 0.16
    foil &= inner
    ring = foil & ~ndimage.binary_erosion(foil, iterations=16)
    L.put(ring, GOLD)
    core = foil & ~ring
    r, th = polar(u, v, cx, cy)
    L.put(core, EMERALD)
    petal = core & (r < 0.2) & (np.cos(4 * th) > 0.15 + r * 1.2)
    petal_id = np.floor(((th + math.pi / 4) % (2 * math.pi)) / (math.pi / 2)).astype(int)
    for k in range(4):
        L.put(petal & (petal_id == k), WHITE if k % 2 == 0 else PALE_A)
    L.put(core & (r < 0.045), RUBY)
    # main medallion: ring, blue field, eight-point star with a sun at its heart
    cx, cy = 0.5, 1.12
    r, th = polar(u, v, cx, cy)
    med = inner & (r < 0.36)
    ring = med & (r > 0.31)
    seg = np.floor(((th + math.pi) / (2 * math.pi)) * 16).astype(int)
    for k in range(16):
        L.put(ring & (seg == k), RUBY if k % 2 == 0 else GOLD)
    fld = med & (r <= 0.31)
    L.put(fld, COBALT)
    star_r = 0.12 + 0.15 * (np.abs(np.cos(4 * th)) ** 3)
    star = fld & (r < star_r)
    ray = np.floor(((th + math.pi / 8) % (2 * math.pi)) / (math.pi / 4)).astype(int)
    for k in range(8):
        L.put(star & (ray == k), GOLD if k % 2 == 0 else AMBER)
    L.put(fld & (r < 0.085), CRIMSON)
    L.put(fld & (r < 0.04), WHITE)
    # four small sky roundels in the blue field between the star points
    for k in range(4):
        t = math.pi / 4 + k * math.pi / 2
        L.put(fld & (np.hypot(u - (cx + 0.225 * math.cos(t)), v - (cy + 0.225 * math.sin(t))) < 0.035), SKY)
    # trefoil in the arch point
    cx, cy = 0.5, hs + 0.42
    tre = np.zeros_like(inner)
    for k in range(3):
        t = math.pi / 2 + k * 2 * math.pi / 3
        tre |= np.hypot(u - (cx + 0.085 * math.cos(t)), v - (cy + 0.085 * math.sin(t))) < 0.1
    tre &= inner
    tr = tre & ~ndimage.binary_erosion(tre, iterations=10)
    L.put(tr, GOLD)
    r, th = polar(u, v, cx, cy)
    lobe = np.floor(((th - math.pi / 2 + math.pi / 3) % (2 * math.pi)) / (2 * math.pi / 3)).astype(int)
    for k in range(3):
        L.put(tre & ~tr & (lobe == k), [RUBY, VIOLET, COBALT][k])
    L.put(tre & (r < 0.035), WHITE)
    # border: alternating ruby / cobalt with gold pearls
    border = outer & ~inner
    p = np.where(v <= hs, v, hs + (v - hs) * 1.4)
    p = np.where(v < 0.075, 0.0 + u * 0.0 - 1.0, p)
    k = np.floor(p / 0.11).astype(int)
    for kk in np.unique(k[border]):
        m = border & (k == kk)
        L.put(m, [RUBY, GOLD, COBALT, GOLD][kk % 4] if kk >= 0 else RUBY)
    return render_glass(L.map, L.colours, outer, lead_px=2)


# ─────────────────────────────── rondel ───────────────────────────────
def rondel():
    S = 512
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    u, v = (x + 0.5) / S - 0.5, 0.5 - (y + 0.5) / S
    r, th = np.hypot(u, v), np.arctan2(v, u)
    outer = r < 0.49
    L = Labeler(outer.shape)
    # outer ring: 24 alternating pieces
    ring = outer & (r > 0.41)
    seg = np.floor(((th + math.pi) / (2 * math.pi)) * 24).astype(int)
    for k in range(24):
        L.put(ring & (seg == k), [RUBY, GOLD, COBALT, GOLD][k % 4])
    # twelve petals, each a foil ending in a round tip
    body = outer & (r <= 0.41)
    L.put(body, COBALT)
    n = 12
    sec = np.floor(((th + math.pi) / (2 * math.pi)) * n).astype(int)
    local = ((th + math.pi) % (2 * math.pi / n)) - math.pi / n     # -half..half across a petal
    width = 0.09 + 0.18 * r                                        # petals widen outward
    petal = body & (r > 0.15) & (np.abs(local) * r < width * 0.42)
    for k in range(n):
        L.put(petal & (sec == k), [CRIMSON, AMBER, VIOLET][k % 3])
    # round tips at the petal ends (foils)
    for k in range(n):
        t = -math.pi + (k + 0.5) * 2 * math.pi / n
        L.put(body & (np.hypot(u - 0.33 * math.cos(t), v - 0.33 * math.sin(t)) < 0.045), GOLD)
        t2 = t + math.pi / n
        L.put(body & (np.hypot(u - 0.37 * math.cos(t2), v - 0.37 * math.sin(t2)) < 0.022), SKY)
    # centre boss: gold ring, six-point star
    boss = outer & (r < 0.15)
    L.put(boss & (r > 0.12), GOLD)
    inner = boss & (r <= 0.12)
    L.put(inner, RUBY)
    star = inner & (r < 0.05 + 0.06 * np.abs(np.cos(3 * th)) ** 2)
    ray = np.floor(((th + math.pi / 6) % (2 * math.pi)) / (math.pi / 3)).astype(int)
    for k in range(6):
        L.put(star & (ray == k), WHITE if k % 2 == 0 else PALE_A)
    L.put(inner & (r < 0.025), GOLD)
    return render_glass(L.map, L.colours, outer, lead_px=2)


# ──────────────────────────────── fanlight ────────────────────────────
FAN_RISE = 0.625


def fan():
    W, H = 512, 320
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (x + 0.5) / W
    v = (H - y - 0.5) / W            # 0..0.625
    c = 0.25 + FAN_RISE ** 2         # arc radius (centres on the spring line)
    outer = (np.hypot(u - c, v) <= c) & (np.hypot(u - (1 - c), v) <= c) & (v >= 0)
    inner = (np.hypot(u - c, v) <= c - 0.06) & (np.hypot(u - (1 - c), v) <= c - 0.06) & (v >= 0.0)
    L = Labeler(outer.shape)
    r, th = polar(u, v, 0.5, 0.0)
    # sunburst of rays from the half-rondel at the bottom
    rays = inner & (r > 0.17)
    k = np.floor((th / math.pi) * 11).astype(int)
    band = np.floor((r - 0.17) / 0.14).astype(int)
    for kk in range(11):
        for bb in range(4):
            L.put(rays & (k == kk) & (band == bb), [AMBER, PALE_A, CRIMSON, PALE_A][(kk + bb) % 4] if bb else [GOLD, AMBER][kk % 2])
    half = inner & (r <= 0.17)
    L.put(half & (r > 0.13), GOLD)
    core = half & (r <= 0.13)
    sec = np.floor((th / math.pi) * 5).astype(int)
    for kk in range(5):
        L.put(core & (sec == kk), [COBALT, SKY][kk % 2])
    L.put(core & (r < 0.05), RUBY)
    border = outer & ~inner
    kk = np.floor((th / math.pi) * 18).astype(int)
    for q in range(19):
        L.put(border & (kk == q), [RUBY, COBALT][q % 2])
    return render_glass(L.map, L.colours, outer, lead_px=2)


# ─────────────────────────────── door leaf ────────────────────────────
def wood(h, w, seed, vertical=True):
    if vertical:
        n = smooth_noise(h, w, 5, w // 3, seed)
        fine = smooth_noise(h, w, 40, w, seed + 1)
    else:
        n = smooth_noise(h, w, h // 3, 5, seed)
        fine = smooth_noise(h, w, h, 40, seed + 1)
    base = np.array((92, 52, 26), np.float32)
    g = 0.72 + 0.38 * n + 0.12 * (fine - 0.5)
    rings = 0.5 + 0.5 * np.sin((n * 40.0))
    g *= 0.92 + 0.12 * rings
    return base[None, None, :] * g[..., None]


def door_leaf():
    W, H = 384, 1024
    img = wood(H, W, 21, vertical=True)
    rails = wood(H, W, 33, vertical=False)
    y, x = np.mgrid[0:H, 0:W]
    stile = 44
    rail_rows = [(0, 70), (430, 500), (H - 90, H)]     # top, lock, bottom rails (image rows)
    rail = np.zeros((H, W), bool)
    for a, b in rail_rows:
        rail[a:b, stile:W - stile] = True
    img[rail] = rails[rail]
    # panels: a tall upper panel with a pointed top, a lower panel
    panels = []
    up = np.zeros((H, W), bool)
    pw0, pw1 = stile + 22, W - stile - 22
    pc = (pw0 + pw1) / 2
    half = (pw1 - pw0) / 2
    spring = 200
    up[spring:430 - 22, pw0:pw1] = True
    # pointed arch over the upper panel
    rr = half * 1.4
    arch = (np.hypot(x - (pc + half - rr), y - spring) <= rr) & (np.hypot(x - (pc - half + rr), y - spring) <= rr) & (y < spring) & (x >= pw0) & (x < pw1)
    up |= arch & (y > 90)
    panels.append(up)
    lo = np.zeros((H, W), bool)
    lo[500 + 22:H - 90 - 22, pw0:pw1] = True
    panels.append(lo)
    shade = np.ones((H, W), np.float32)
    for p in panels:
        inner = ndimage.binary_erosion(p, iterations=14)
        bevel = p & ~inner
        # light from the top-left: the bevel faces up/left are lit, down/right are dark
        gy, gx = np.gradient(ndimage.gaussian_filter(p.astype(np.float32), 5))
        lit = np.clip(-(gy * 0.8 + gx * 0.6) * 18, -1, 1)
        shade[bevel] *= (1.0 + 0.35 * lit[bevel])
        shade[inner] *= 1.06
        # a shadow line all round the panel's outside edge
        rim = ndimage.binary_dilation(p, iterations=3) & ~p
        shade[rim] *= 0.45
        # linenfold ridges on the lower panel
    lf = ndimage.binary_erosion(lo, iterations=22)
    ridges = 0.86 + 0.18 * np.cos((x - pw0) / (pw1 - pw0) * 6 * math.pi * 2)
    shade[lf] *= ridges[lf]
    # carved quatrefoil in the top rail
    cx, cy = W / 2, 130
    foil = np.zeros((H, W), bool)
    for k in range(4):
        t = k * math.pi / 2
        foil |= np.hypot(x - (cx + 22 * math.cos(t)), y - (cy + 22 * math.sin(t))) < 26
    foil_rim = ndimage.binary_dilation(foil, iterations=4) & ~foil
    shade[foil] *= 0.62
    shade[foil_rim] *= 1.25
    # iron studs along the rails
    studs = np.zeros((H, W), bool)
    for a, b in rail_rows:
        cyr = (a + b) / 2
        for sx in np.linspace(stile + 30, W - stile - 30, 6):
            studs |= np.hypot(x - sx, y - cyr) < 6
    img = img * shade[..., None]
    img[studs] = (40, 36, 34)
    hl = np.zeros((H, W), bool)
    for a, b in rail_rows:
        cyr = (a + b) / 2
        for sx in np.linspace(stile + 30, W - stile - 30, 6):
            hl |= np.hypot(x - sx + 2, y - cyr + 2) < 2.2
    img[hl] = (120, 110, 100)
    # a dark gap line at the leaf's edges
    img[:, :3] *= 0.4
    img[:, -3:] *= 0.4
    img[:3] *= 0.4
    img[-3:] *= 0.4
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def exit_sign():
    W, H = 256, 96
    im = Image.new("RGB", (W, H), (26, 8, 6))
    txt = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(txt)
    font = None
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "DejaVuSans-Bold.ttf", "arialbd.ttf"):
        try:
            font = ImageFont.truetype(f, 66)
            break
        except OSError:
            pass
    font = font or ImageFont.load_default()
    bb = d.textbbox((0, 0), "EXIT", font=font)
    d.text(((W - (bb[2] - bb[0])) / 2 - bb[0], (H - (bb[3] - bb[1])) / 2 - bb[1]), "EXIT", fill=255, font=font)
    glow = txt.filter(ImageFilter.GaussianBlur(6))
    base = np.asarray(im, np.float32)
    g = np.asarray(glow, np.float32)[..., None] / 255.0
    t = np.asarray(txt, np.float32)[..., None] / 255.0
    col = np.array((255, 70, 40), np.float32)
    out = base + g * col * 0.7
    out = out * (1 - t) + t * np.array((255, 170, 130), np.float32)
    frame = np.zeros((H, W), bool)
    frame[:5] = frame[-5:] = True
    frame[:, :5] = frame[:, -5:] = True
    out[frame] = (150, 110, 50)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    lancet().save(os.path.join(OUT, "glass_lancet.png"))
    rondel().save(os.path.join(OUT, "glass_rondel.png"))
    fan().save(os.path.join(OUT, "glass_fan.png"))
    door_leaf().save(os.path.join(OUT, "door_leaf.png"))
    exit_sign().save(os.path.join(OUT, "exit_sign.png"))
    print("ok")
