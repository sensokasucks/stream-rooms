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
  card_fir / card_pine / card_leaves / card_grass / card_fern .png   see-through pictures of a
        fir bough, a pine tuft, a spray of leaves, a grass tuft and a fern frond, put together
        here from single twigs and leaves; the trees are built out of flat cards showing them
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


def card_leaves(size: int = 512) -> None:
    rnd = random.Random(11)
    leaves = [upright(t) for t in sprites("island_tree_02", "leaves_diff", "leaves_alpha", 0.006)[:8]]
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    # a few twigs fanning up from the bottom middle, leaves all along them
    for tw in range(7):
        ang = math.radians(-66 + 22 * tw + rnd.uniform(-6, 6))
        length = size * rnd.uniform(0.62, 0.86)
        x1 = size / 2 + math.sin(ang) * length
        y1 = size - math.cos(ang) * length
        d.line([(size / 2, size), (x1, y1)], fill=(64, 50, 34, 255), width=4)
        n = 9
        for i in range(n):
            t = (i + 1.0) / n
            at = (size / 2 + (x1 - size / 2) * t, size + (y1 - size) * t)
            for side in (-1, 1):
                stamp(c, rnd.choice(leaves), at, size * rnd.uniform(0.13, 0.19), math.degrees(ang) + side * rnd.uniform(35, 75), rnd.uniform(0.7, 1.1))
    bleed(c).save(os.path.join(HERE, "card_leaves.png"))
    print("wrote card_leaves.png")


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
    white with dark marks."""
    a = np.asarray(fetch("sakura_bark", "Diffuse").convert("L").resize((1024, 1024), Image.LANCZOS)).astype(np.float32) / 255.0
    a = (a - a.mean()) / a.std()
    rel = np.clip(1.0 + 0.1 * a, 0.0, 2.0)
    rel = np.where(a < -1.5, 0.35, rel)             # the darkest streaks become birch's black marks
    img = Image.fromarray(np.clip(rel * 127.5, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    save_jpg(img.convert("RGB"), "detail_bark_birch.jpg")


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
    card_leaves()
    card_grass()
    card_fern()
