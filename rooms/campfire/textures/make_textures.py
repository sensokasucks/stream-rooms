#!/usr/bin/env python3
"""Makes the Lakeside Campfire's photo textures (the "Detailed set" look).

Everything here starts from CC0 (public domain) pictures from Poly Haven, https://polyhaven.com.
The script downloads them, cuts them down to what the game needs and writes the files next to
itself. Run it again only to change a texture; the results are committed.

    python3 rooms/campfire/textures/make_textures.py [cache folder]

Needs Python 3 with Pillow and numpy, and the internet (api.polyhaven.com, dl.polyhaven.org).

What it writes:
  ground_grass / ground_forest / ground_dirt / ground_sand .jpg   the four kinds of ground
        (camp_ground.gdshader mixes them by the ground mesh's vertex colour)
  detail_bark_pine / detail_bark_oak / detail_bark_birch / detail_rock / detail_planks /
  detail_fabric .jpg   "detail" textures: the photo divided by its own average colour, so
        mid grey means "no change". camp_prop.gdshader multiplies an object's own colour by
        one of them (times 2), which keeps the set's colours and adds the photo's grain.
  card_fir / card_pine / card_grass / card_fern .png   see-through pictures of a fir bough, a
        pine tuft, a grass tuft and a fern frond, put together here from single photographed twigs;
  water_normal.png   the lake's ripples (a normal map) for camp_water.gdshader
  sky_noise.png      cloud shapes for camp_sky.gdshader (three noise fields in r, g, b)
        Both are made from noise by this script: no photo, no download.
  card_oak / card_maple / card_birch .png   sprays of oak, maple and birch leaves. These leaves
        are not photos: this script draws them (leaf_outline, drawn_leaf), one shape per species; the trees are built out of flat cards showing them
        (campfire_trees.gd, camp_foliage.gdshader). The stem end of each is at the bottom middle.
"""
import json
import math
import os
import random
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"


def fetch(asset: str, kind: str, res: str = "1k") -> Image.Image:
    """One map of a Poly Haven asset (kind as their API names it: "Diffuse", "twig_alpha"...)."""
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, f"{asset}__{kind}__{res}.jpg")
    if not os.path.exists(out):
        req = urllib.request.Request(API + asset, headers={"User-Agent": "texture-bake-script"})
        files = json.load(urllib.request.urlopen(req, timeout=60))
        url = files[kind][res]["jpg"]["url"]
        req = urllib.request.Request(url, headers={"User-Agent": "texture-bake-script"})
        with open(out, "wb") as f:
            f.write(urllib.request.urlopen(req, timeout=180).read())
    return Image.open(out)


def save_jpg(img: Image.Image, name: str, quality: int = 86) -> None:
    img.convert("RGB").save(os.path.join(HERE, name), quality=quality, optimize=True)
    print("wrote", name)


# ── ground ───────────────────────────────────────────────────
def ground(name: str, asset: str, gain=(1.0, 1.0, 1.0)) -> None:
    a = np.asarray(fetch(asset, "Diffuse").convert("RGB").resize((1024, 1024), Image.LANCZOS)).astype(np.float32)
    a *= np.array(gain, dtype=np.float32)
    save_jpg(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), name)


# ── detail textures ──────────────────────────────────────────
def detail(name: str, asset: str, size: int = 1024, keep_colour: float = 0.6, contrast: float = 1.0, rotate: bool = False) -> None:
    """photo / its average colour, stored so that 0.5 = no change. keep_colour: how much of the
    photo's own colour differences stay (0 = grey grain only)."""
    img = fetch(asset, "Diffuse").convert("RGB").resize((size, size), Image.LANCZOS)
    if rotate:
        img = img.rotate(90)
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    a = lum + (a - lum) * keep_colour
    rel = a / a.reshape(-1, 3).mean(axis=0)
    rel = 1.0 + (rel - 1.0) * contrast
    save_jpg(Image.fromarray(np.clip(rel * 127.5, 0, 255).astype(np.uint8)), name)


# ── cards ────────────────────────────────────────────────────
def sprites(asset: str, diff: str, alpha: str, min_share: float = 0.004, res: str = "2k") -> list:
    """Cuts an atlas into its separate pieces (each twig / leaf): a list of RGBA pictures,
    biggest first. Pieces are found as joined-up patches of the alpha map."""
    rgb = fetch(asset, diff, res).convert("RGB")
    mask = fetch(asset, alpha, res).convert("L").resize(rgb.size)
    small = np.asarray(mask.resize((256, 256), Image.BILINEAR)) > 100
    seen = np.zeros_like(small)
    boxes = []
    for y in range(256):
        for x in range(256):
            if small[y, x] and not seen[y, x]:
                stack = [(y, x)]
                seen[y, x] = True
                x0 = x1 = x
                y0 = y1 = y
                count = 0
                while stack:
                    cy, cx = stack.pop()
                    count += 1
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < 256 and 0 <= nx < 256 and small[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
                boxes.append((count, x0, y0, x1 + 1, y1 + 1))
    out = []
    k = rgb.width / 256.0
    for count, x0, y0, x1, y1 in sorted(boxes, reverse=True):
        box_area = (x1 - x0) * (y1 - y0)
        # skip specks, and the atlas's solid filler blocks (a twig or leaf never fills its box)
        if count < min_share * 256 * 256 or count > 0.8 * box_area and box_area > 0.02 * 65536:
            continue
        box = (int(x0 * k), int(y0 * k), int(x1 * k), int(y1 * k))
        piece = rgb.crop(box).convert("RGBA")
        piece.putalpha(mask.crop(box))
        out.append(piece)
    return out


def bleed(img: Image.Image) -> Image.Image:
    """Fills the see-through pixels' colour with the picture's average leaf colour, so the
    smaller copies the graphics card makes (mipmaps) don't get dark edges."""
    a = np.asarray(img).astype(np.float32)
    w = a[..., 3:4] / 255.0
    avg = (a[..., :3] * w).sum(axis=(0, 1)) / max(w.sum(), 1.0)
    a[..., :3] = a[..., :3] * w + avg * (1.0 - w)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def stamp(canvas: Image.Image, piece: Image.Image, at, length: float, turn_deg: float, shade: float = 1.0, anchor=(0.5, 1.0)) -> None:
    """Pastes a piece so that its anchor point (share of its width / height; the default is the
    bottom middle, a twig's stem end) lands on `at`, scaled so it is `length` pixels tall and
    turned turn_deg clockwise from pointing straight up."""
    k = length / piece.height
    p = piece.resize((max(1, int(piece.width * k)), max(1, int(piece.height * k))), Image.LANCZOS)
    if shade != 1.0:
        r, g, b, al = p.split()
        rgbp = Image.merge("RGB", (r, g, b)).point(lambda v: min(255, int(v * shade)))
        p = Image.merge("RGBA", (*rgbp.split(), al))
    # put the anchor in the middle of a bigger square, so turning keeps it in place
    side = int(2.2 * max(p.size)) + 4
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(p, (side // 2 - int(p.width * anchor[0]), side // 2 - int(p.height * anchor[1])))
    sq = sq.rotate(-turn_deg, resample=Image.BICUBIC)
    canvas.alpha_composite(sq, (int(at[0]) - side // 2, int(at[1]) - side // 2))


def upright(piece: Image.Image) -> Image.Image:
    """Turns a piece so its stem end is at the bottom (the end where it is narrowest)."""
    a = np.asarray(piece)[..., 3] > 100
    h = a.shape[0]
    top = a[: h // 6].sum()
    bottom = a[-(h // 6):].sum()
    return piece.rotate(180) if top < bottom else piece


def only_green(piece: Image.Image) -> Image.Image:
    """Clears the pixels that aren't needle-coloured (grey scraps of the atlas's filler that
    touch a twig and so were cut out with it)."""
    a = np.asarray(piece).copy()
    grey = a[..., 2].astype(np.float32) > 0.8 * a[..., 1].astype(np.float32)
    a[..., 3] = np.where(grey, 0, a[..., 3])
    return Image.fromarray(a, "RGBA")


def card_fir(size: int = 512) -> None:
    rnd = random.Random(3)
    # pieces 1-4 and 6 of the atlas are the green twigs (0 and 5 are bark and a bare stick)
    found = sprites("fir_tree_01", "twig_diff", "twig_alpha")
    twigs = [upright(found[i]) for i in (1, 2, 3, 4, 6)]
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    d.line([(size / 2, size), (size / 2, size * 0.12)], fill=(58, 44, 30, 255), width=7)
    steps = 13
    for i in range(steps):
        t = i / (steps - 1)
        y = size * (0.97 - 0.82 * t)
        length = size * (0.42 - 0.2 * t) * rnd.uniform(0.9, 1.1)
        for side in (-1, 1):
            stamp(c, rnd.choice(twigs), (size / 2, y), length, side * rnd.uniform(48, 68), rnd.uniform(0.75, 1.05))
    stamp(c, twigs[0], (size / 2, size * 0.2), size * 0.2, 0.0)
    bleed(c).save(os.path.join(HERE, "card_fir.png"))
    print("wrote card_fir.png")


def card_pine(size: int = 512) -> None:
    rnd = random.Random(5)
    # pieces 1 and 2 of the atlas are the needle tufts; 2 lies on its side, stem end to the left
    found = sprites("pine_tree_01", "twig_diff", "twig_alpha", 0.0015)
    tufts = [only_green(upright(found[1])), only_green(found[2].rotate(90, expand=True))]
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    d.line([(size / 2, size), (size / 2, size * 0.5)], fill=(70, 52, 36, 255), width=8)
    for i in range(16):
        ang = rnd.uniform(-80, 80)
        y = size * rnd.uniform(0.45, 0.8)
        stamp(c, rnd.choice(tufts), (size / 2 + rnd.uniform(-20, 20), y), size * rnd.uniform(0.36, 0.5), ang, rnd.uniform(0.75, 1.1))
    bleed(c).save(os.path.join(HERE, "card_pine.png"))
    print("wrote card_pine.png")


def leaf_outline(kind: str) -> list:
    """The outline of one leaf, drawn by us (no photo): points (x, y) with the stem end at
    (0, 0), the tip at (0, 1) and x the half-width, for the right half then mirrored.
    oak: rounded lobes (a white oak); maple: five points; birch: a small toothed egg shape."""
    right = []
    if kind == "oak":
        for i in range(0, 121):
            t = i / 120.0
            body = 0.36 * math.sin(math.pi * min(1.0, t * 1.08) ** 0.75) ** 0.8      # widest above the middle
            lobes = 0.45 + 0.55 * math.cos(t * math.pi * 3.5) ** 2 if 0.06 < t < 0.93 else 1.0
            right.append((max(0.012, body * lobes), t))
    elif kind == "maple":
        # hand-placed corners of the right half: stem notch, two lower points, the big side
        # point, the notch under the top point, the top point
        right = [(0.02, 0.0), (0.05, 0.16), (0.3, 0.1), (0.24, 0.2), (0.5, 0.22), (0.4, 0.34), (0.56, 0.5), (0.4, 0.5), (0.5, 0.66),
                 (0.3, 0.6), (0.2, 0.56), (0.13, 0.64), (0.2, 0.8), (0.1, 0.78), (0.0, 1.0)]
    else:
        for i in range(0, 81):
            t = i / 80.0
            body = 0.33 * math.sin(math.pi * t ** 0.62) * (1.0 - 0.25 * t)
            teeth = 1.0 + 0.07 * math.sin(t * 60.0)
            right.append((max(0.012, body * teeth), t))
    return right + [(-x, y) for x, y in reversed(right)]


def drawn_leaf(kind: str, colour, rnd: random.Random, px: int = 220) -> Image.Image:
    """One leaf as an upright RGBA picture, px tall, stem end at the bottom middle: the
    outline filled with `colour` (a little lighter towards the edge, as a leaf held to the
    light is), with a pale midrib and side veins. Drawn four times too big and shrunk, so its
    edge is smooth."""
    k = 4
    w = int(px * (1.2 if kind == "maple" else 0.8)) * k
    h = px * k
    stalk = int(h * (0.16 if kind == "maple" else 0.08))             # the leaf's own little stalk
    pts = [(w / 2 + x * (h - stalk), h - stalk - y * (h - stalk) * 0.98) for x, y in leaf_outline(kind)]
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.polygon(pts, fill=255)
    md.line([(w / 2, h), (w / 2, h - stalk)], fill=255, width=3 * k)
    # colour: darker in the middle, lighter and yellower at the edge, plus fine noise
    edge = np.asarray(mask.filter(ImageFilter.GaussianBlur(h * 0.05))).astype(np.float32) / 255.0
    noise = np.asarray(Image.effect_noise((w, h), 26).filter(ImageFilter.GaussianBlur(k))).astype(np.float32) / 255.0
    shade = (0.78 + 0.3 * (1.0 - edge) + 0.5 * (noise - 0.5)) * rnd.uniform(0.9, 1.1)
    warm = np.stack([1.0 + 0.25 * (1.0 - edge), np.ones_like(edge), 1.0 - 0.2 * (1.0 - edge)], axis=-1)
    rgb = np.clip(np.array(colour, dtype=np.float32)[None, None, :] * shade[..., None] * warm, 0, 255)
    img = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    pale = tuple(min(255, int(c * 1.5 + 30)) for c in colour) + (255,)
    top = h - stalk
    d.line([(w / 2, h), (w / 2, top - (h - stalk) * 0.9)], fill=pale, width=2 * k)
    if kind == "maple":
        for x, y in ((0.5, 0.22), (0.56, 0.5), (0.3, 0.1)):          # a vein to each side point
            for sx in (-1, 1):
                d.line([(w / 2, top - (h - stalk) * 0.12), (w / 2 + sx * x * (h - stalk) * 0.9, top - y * (h - stalk) * 0.96)], fill=pale, width=k)
    else:
        n = 6 if kind == "oak" else 7
        for i in range(n):
            t = 0.12 + 0.75 * i / n
            reach = 0.2 * math.sin(math.pi * t) + 0.04
            for sx in (-1, 1):
                d.line([(w / 2, top - t * (h - stalk)), (w / 2 + sx * reach * (h - stalk), top - (t + 0.1) * (h - stalk))], fill=pale, width=k)
    img.putalpha(mask)
    return img.resize((w // k, h // k), Image.LANCZOS)


def card_broadleaf(kind: str, size: int = 512) -> None:
    """card_oak / card_maple / card_birch .png: a spray of our own drawn leaves on twigs that
    fan up from the bottom middle (the card's stem end). Each species has its own leaf shape,
    leaf size, colour and habit, so the trees can be told apart:
      oak    big lobed leaves in bunches at the twig ends, dark green
      maple  broad five-pointed leaves in pairs on long stalks, lighter green
      birch  many small toothed leaves along thin twigs, yellow-green"""
    rnd = random.Random({"oak": 21, "maple": 22, "birch": 23}[kind])
    colour = {"oak": (52, 92, 34), "maple": (78, 122, 36), "birch": (104, 138, 44)}[kind]
    leaves = [drawn_leaf(kind, colour, rnd) for _ in range(6)]
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    twigs = {"oak": 6, "maple": 5, "birch": 8}[kind]
    for tw in range(twigs):
        spread = 104.0 if kind != "birch" else 100.0
        ang = math.radians(-spread / 2 + spread * tw / (twigs - 1) + rnd.uniform(-5, 5))
        # (short enough that no leaf is cut off at the card's edge)
        length = size * (rnd.uniform(0.42, 0.56) if kind != "birch" else rnd.uniform(0.5, 0.72))
        x1 = size / 2 + math.sin(ang) * length
        y1 = size - math.cos(ang) * length
        d.line([(size / 2, size), (x1, y1)], fill=(70, 54, 38, 255) if kind != "birch" else (60, 44, 36, 255), width=4 if kind != "birch" else 3)
        if kind == "oak":
            # bunches: a few leaves along the twig, a rosette of five at its end
            for t in (0.45, 0.7):
                at = (size / 2 + (x1 - size / 2) * t, size + (y1 - size) * t)
                for side in (-1, 1):
                    stamp(c, rnd.choice(leaves), at, size * rnd.uniform(0.17, 0.21), math.degrees(ang) + side * rnd.uniform(40, 70), rnd.uniform(0.75, 1.0))
            for i in range(5):
                stamp(c, rnd.choice(leaves), (x1, y1), size * rnd.uniform(0.19, 0.24), math.degrees(ang) - 80 + 40 * i + rnd.uniform(-10, 10), rnd.uniform(0.85, 1.12))
        elif kind == "maple":
            # pairs opposite each other, the leaves hanging a little flat and wide, one at the end
            for t in (0.4, 0.62, 0.84):
                at = (size / 2 + (x1 - size / 2) * t, size + (y1 - size) * t)
                for side in (-1, 1):
                    stamp(c, rnd.choice(leaves), at, size * rnd.uniform(0.18, 0.22), math.degrees(ang) + side * rnd.uniform(45, 65), rnd.uniform(0.78, 1.08))
            stamp(c, rnd.choice(leaves), (x1, y1), size * rnd.uniform(0.2, 0.24), math.degrees(ang) + rnd.uniform(-12, 12), rnd.uniform(0.95, 1.15))
        else:
            n = 11
            for i in range(n):
                t = 0.25 + 0.75 * (i + 1.0) / n
                at = (size / 2 + (x1 - size / 2) * t, size + (y1 - size) * t)
                side = -1 if i % 2 else 1
                stamp(c, rnd.choice(leaves), at, size * rnd.uniform(0.1, 0.13), math.degrees(ang) + side * rnd.uniform(35, 70), rnd.uniform(0.8, 1.12))
    bleed(c).save(os.path.join(HERE, "card_%s.png" % kind))
    print("wrote card_%s.png" % kind)


def card_grass(size: int = 256) -> None:
    rnd = random.Random(7)
    # pieces 2 to 5 of the atlas are its ready-made tufts
    found = sprites("grass_medium_01", "Diffuse", "Alpha", 0.001)
    tufts = [found[i] for i in (2, 3, 4, 5)]
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for i in range(5):
        t = rnd.choice(tufts)
        # kept small enough that no blade is cut off at the picture's sides
        stamp(c, t, (size * rnd.uniform(0.44, 0.56), size), size * rnd.uniform(0.5, 0.62), rnd.uniform(-8, 8), rnd.uniform(0.85, 1.15))
    bleed(c).save(os.path.join(HERE, "card_grass.png"))
    print("wrote card_grass.png")


def card_fern() -> None:
    frond = upright(max(sprites("fern_02", "Diffuse", "Alpha"), key=lambda p: p.height))
    c = Image.new("RGBA", (128, 512), (0, 0, 0, 0))
    stamp(c, frond, (64, 512), 508, 0.0)
    bleed(c).save(os.path.join(HERE, "card_fern.png"))
    print("wrote card_fern.png")


def bark_birch() -> None:
    """There is no birch on Poly Haven: a cherry bark (it has the same sideways streaks) turned
    pale, with birch's dark marks drawn over it by us: many short sideways dashes (lenticels)
    and a few black arched scars where branches were. Mid grey = no change, as with the
    other detail textures; the trunk's own off-white colour comes from the mesh."""
    a = np.asarray(fetch("sakura_bark", "Diffuse").convert("L").resize((1024, 1024), Image.LANCZOS)).astype(np.float32) / 255.0
    a = (a - a.mean()) / a.std()
    rel = np.clip(1.0 + 0.12 * a, 0.0, 2.0)
    rel = np.where(a < -1.5, 0.45, rel)             # the photo's darkest streaks
    marks = Image.new("L", (1024, 1024), 255)
    d = ImageDraw.Draw(marks)
    rnd = random.Random(5)
    for _ in range(260):                            # lenticels: thin dashes, 2 to 9 cm wide on the tree
        x, y = rnd.uniform(0, 1024), rnd.uniform(0, 1024)
        w, h = rnd.uniform(18, 90), rnd.uniform(3, 8)
        d.ellipse([x - w / 2, y - h / 2, x + w / 2, y + h / 2], fill=rnd.randint(60, 130))
    for _ in range(5):                              # branch scars: a dark arch
        x, y = rnd.uniform(80, 944), rnd.uniform(80, 944)
        w = rnd.uniform(40, 80)
        d.arc([x - w, y - w * 0.35, x + w, y + w * 0.9], 200, 340, fill=30, width=int(w * 0.16))
    m = np.asarray(marks.filter(ImageFilter.GaussianBlur(1.6))).astype(np.float32) / 255.0
    img = Image.fromarray(np.clip(rel * m * 127.5, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    save_jpg(img.convert("RGB"), "detail_bark_birch.jpg")


def tile_noise(size: int, slope: float, seed: int, stretch=(1.0, 1.0)) -> np.ndarray:
    """Noise that repeats without a seam (made in frequency space): values with mean 0 and
    spread 1. slope = how fast the fine detail falls away (2 = soft billows, 1 = rough);
    stretch pulls the features out along x or y."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(size)[:, None] * size * stretch[1]
    fx = np.fft.fftfreq(size)[None, :] * size * stretch[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / f ** slope
    amp[0, 0] = 0.0
    amp[f < 1.5] *= 0.35                      # no single huge blob across the whole tile
    spec = amp * np.exp(2j * np.pi * rng.random((size, size)))
    n = np.fft.ifft2(spec).real
    return (n - n.mean()) / n.std()


def water_normal(size: int = 256) -> None:
    """water_normal.png: the lake's ripples as a seamless normal map (red = slope along x,
    green = slope along z, 0.5 = flat). camp_water.gdshader slides three copies of it across
    each other. Ours: made from noise here, no photo."""
    # smooth swells, with ridged noise taken off so crests are sharper than troughs
    # (Kept small and fairly rough on purpose: the file has 256 steps of slope, and a big
    # smooth picture changes by less than one step from pixel to pixel, which shows as
    # terraces in the reflection. The shader blends between pixels and layers three copies.)
    h = tile_noise(size, 2.1, 3) + 0.45 * tile_noise(size, 1.7, 4) - 0.5 * np.abs(tile_noise(size, 1.9, 5))
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    k = 0.5 / (3.0 * max(dx.std(), dy.std()))          # three spreads fill the range; rarer slopes are clipped
    img = np.zeros((size, size, 3), dtype=np.uint8)
    img[..., 0] = np.clip((0.5 + dx * k) * 255.0, 0, 255)
    img[..., 1] = np.clip((0.5 + dy * k) * 255.0, 0, 255)
    img[..., 2] = 255
    Image.fromarray(img, "RGB").save(os.path.join(HERE, "water_normal.png"))
    print("wrote water_normal.png")


def tile_puffs(size: int, cells: int, seed: int) -> np.ndarray:
    """Round bumps that repeat without a seam, 0..1: one random point in each square of a
    cells x cells grid, and every pixel is as bright as it is close to its nearest point
    (the "cauliflower" look of a heap cloud; plain noise only gives wisps)."""
    rng = np.random.default_rng(seed)
    pts = (np.indices((cells, cells)).transpose(1, 2, 0)[..., ::-1] + rng.random((cells, cells, 2)))  # x, y in cells
    ys, xs = np.mgrid[0:size, 0:size] * (cells / size)
    cx, cy = np.floor(xs).astype(int), np.floor(ys).astype(int)
    best = np.full((size, size), 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            q = pts[(cy + oy) % cells, (cx + ox) % cells]           # the neighbour square's point, wrapped
            dx = q[..., 0] + (cx + ox - (cx + ox) % cells) - xs
            dy = q[..., 1] + (cy + oy - (cy + oy) % cells) - ys
            best = np.minimum(best, dx * dx + dy * dy)
    return np.clip(1.0 - np.sqrt(best), 0.0, 1.0)


def sky_noise(size: int = 512) -> None:
    """sky_noise.png: three seamless noise fields for camp_sky.gdshader's clouds, one per
    colour channel (0..1). red = big billows built from round bumps (a heap cloud's body),
    green = small round bumps (eat the edges into puffs), blue = long streaks (the high
    thin cloud). Ours: made from noise here, no photo."""
    def unit(n: np.ndarray) -> np.ndarray:
        lo, hi = np.percentile(n, 0.5), np.percentile(n, 99.5)
        return np.clip((n - lo) / (hi - lo), 0.0, 1.0)
    # where the clouds are (soft noise), then heaped up out of round bumps of three sizes
    where = unit(tile_noise(size, 2.3, 11))
    body = where * 0.55 + tile_puffs(size, 5, 21) * 0.25 + tile_puffs(size, 11, 22) * 0.14 + tile_puffs(size, 23, 23) * 0.06
    fine = tile_puffs(size, 20, 24) * 0.55 + tile_puffs(size, 41, 25) * 0.3 + 0.15 * unit(tile_noise(size, 1.0, 14))
    streak = tile_noise(size, 1.6, 15, stretch=(1.0, 5.0))
    img = np.stack([unit(body), unit(fine), unit(streak)], axis=-1)
    Image.fromarray((img * 255.0).astype(np.uint8), "RGB").save(os.path.join(HERE, "sky_noise.png"))
    print("wrote sky_noise.png")


if __name__ == "__main__":
    ground("ground_grass.jpg", "forrest_ground_01")
    ground("ground_forest.jpg", "forest_leaves_04", (0.62, 0.6, 0.62))
    ground("ground_dirt.jpg", "forest_ground_04")
    ground("ground_sand.jpg", "coast_sand_01")
    detail("detail_bark_pine.jpg", "pine_bark")
    detail("detail_bark_oak.jpg", "bark_brown_02", keep_colour=0.5)
    bark_birch()
    detail("detail_rock.jpg", "rock_boulder_dry", keep_colour=0.4, contrast=1.3)
    detail("detail_planks.jpg", "weathered_planks", keep_colour=0.5)
    detail("detail_fabric.jpg", "denim_fabric_03", size=512, keep_colour=0.0, contrast=2.0)
    card_fir()
    card_pine()
    for leaf_kind in ("oak", "maple", "birch"):
        card_broadleaf(leaf_kind)
    card_grass()
    card_fern()
    water_normal()
    sky_noise()
