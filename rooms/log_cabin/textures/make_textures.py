#!/usr/bin/env python3
"""Makes the Log Cabin's photo textures (the "Detailed" look of Set detail).

Everything starts from CC0 (public domain) photos from Poly Haven, https://polyhaven.com, except
the rug, which this script draws itself (an original pattern). The script downloads the photos,
cuts them down to what the game needs and writes the files next to itself. Run it again only to
change a texture; the results are committed.

    python3 rooms/log_cabin/textures/make_textures.py [cache folder]

Needs Python 3 with Pillow and numpy, and the internet (api.polyhaven.com, dl.polyhaven.org).

What it writes (cabin_surface.gdshader reads them; cabin_builder.gd's SURFACES table says which
part of the cabin gets which):
  <name>.jpg      a "detail" texture: the photo divided by its own average colour, so mid grey
                  means "no change". The shader multiplies the mesh's own colour by it (times 2),
                  so the set keeps its colours (and its Simple look) and gains the photo's grain.
  <name>_nor.jpg  the photo's normal map (OpenGL style, green = up the picture), for the bumps.

  logs        peeled pine logs (coated_pine): honey wood, knots, grain along the log
  chinking    the light plaster between the logs (clay_plaster)
  floor       wide worn floor boards (old_wooden_floor_01)
  ceiling     knotty pine tongue-and-groove boards (plank_flooring_02), lines up the picture
  stone       the chimney's field stone (rustic_stone_wall)
  roof        wooden shakes (roof_slates_02), rows across the picture
  deck        weathered deck boards (weathered_brown_planks)
  leather     leather (brown_leather) for the sofas and armchairs
  wool        woven upholstery and cushions (poly_wool_herringbone)
  fleece      knitted throws and sheepskins (knitted_fleece)
  bark        the firewood's bark (pine_bark)
  rug         an original rug pattern drawn here (no photo, no normal map)
"""
import json
import math
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"


def fetch(asset: str, kind: str = "Diffuse", res: str = "1k") -> Image.Image:
    """One map of a Poly Haven asset (kind as their API names it: "Diffuse", "nor_gl"...)."""
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


def detail_from(img: Image.Image, name: str, size: int, keep_colour: float, contrast: float) -> None:
    """photo / its average colour, stored so that 0.5 = no change. keep_colour: how much of the
    photo's own colour differences stay (0 = grey grain only, 1 = all of them)."""
    img = img.convert("RGB").resize((size, size), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    a = lum + (a - lum) * keep_colour
    rel = a / a.reshape(-1, 3).mean(axis=0)
    rel = 1.0 + (rel - 1.0) * contrast
    save_jpg(Image.fromarray(np.clip(rel * 127.5, 0, 255).astype(np.uint8)), name)


def detail(name: str, asset: str, size: int = 1024, keep_colour: float = 0.5, contrast: float = 1.0, rotate: bool = False) -> None:
    img = fetch(asset)
    if rotate:
        img = img.rotate(90)
    detail_from(img, name + ".jpg", size, keep_colour, contrast)


def normal(name: str, asset: str, size: int = 1024, strength: float = 1.0, rotate: bool = False) -> None:
    """The asset's normal map, its bumps scaled by `strength` (1 = as photographed). Turning it
    a quarter round (to match a turned photo) also turns the bumps' directions."""
    img = fetch(asset, "nor_gl").convert("RGB").resize((size, size), Image.LANCZOS)
    n = np.asarray(img).astype(np.float32) / 127.5 - 1.0
    if rotate:
        n = np.rot90(n, 1).copy()
        # rot90 counter-clockwise: the picture's old +x (right) is now up, old up (+y) now left
        x, y = n[..., 0].copy(), n[..., 1].copy()
        n[..., 0] = -y
        n[..., 1] = x
    n[..., 0:2] *= strength
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    save_jpg(Image.fromarray(np.clip((n + 1.0) * 127.5, 0, 255).astype(np.uint8)), name + "_nor.jpg", quality=92)


def rug(size: int = 1024) -> None:
    """An original woven rug: a border of stepped diamonds round a field of stripes and a large
    central medallion, in brick red, mustard, cream and forest green, with a little weave
    texture and wear. One copy of the picture is the whole rug (the shader lays it once)."""
    red, mustard, cream, green, brown = (150, 52, 36), (196, 150, 62), (222, 206, 172), (52, 82, 58), (84, 50, 34)
    img = Image.new("RGB", (size, size), red)
    d = ImageDraw.Draw(img)
    b = size // 12
    d.rectangle([0, 0, size - 1, size - 1], outline=brown, width=b // 3)
    d.rectangle([b // 3, b // 3, size - 1 - b // 3, size - 1 - b // 3], fill=cream)
    d.rectangle([b, b, size - 1 - b, size - 1 - b], fill=red)
    # stepped diamonds along the border band
    step = b * 0.9
    for side in range(4):
        n = int((size - 2 * b) / step)
        for i in range(n):
            t = b + (i + 0.5) * step
            c = (t, b * 0.66) if side == 0 else (t, size - b * 0.66) if side == 1 else (b * 0.66, t) if side == 2 else (size - b * 0.66, t)
            r = step * 0.38
            col = green if i % 2 == 0 else mustard
            d.polygon([(c[0], c[1] - r), (c[0] + r, c[1]), (c[0], c[1] + r), (c[0] - r, c[1])], fill=col)
    # bands across the field
    for k, col in enumerate([mustard, cream, green, cream, mustard]):
        y = b * 1.6 + k * b * 0.18
        d.rectangle([b * 1.3, y, size - b * 1.3, y + b * 0.1], fill=col)
        d.rectangle([b * 1.3, size - y - b * 0.1, size - b * 1.3, size - y], fill=col)
    # the medallion: nested stepped diamonds
    cx = cy = size / 2
    for r, col in [(size * 0.3, brown), (size * 0.27, mustard), (size * 0.22, green), (size * 0.16, cream), (size * 0.1, red), (size * 0.05, mustard)]:
        pts = []
        steps = 6
        for q in range(4):
            for s in range(steps):
                a = (q + s / steps) * math.pi / 2
                dx, dy = math.cos(a), math.sin(a)
                k = r / (abs(dx) + abs(dy))
                pts.append((cx + round(dx * k / (r / steps)) * (r / steps), cy + round(dy * k / (r / steps)) * (r / steps)))
        d.polygon(pts, fill=col)
    # weave: fine rows and a little wear
    a = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:size, 0:size]
    weave = 0.92 + 0.08 * (np.sin(yy * math.pi / 2.0) * 0.5 + 0.5) * (np.sin(xx * math.pi / 3.0) * 0.3 + 0.7)
    rng = np.random.default_rng(11)
    noise = Image.fromarray((rng.random((size // 8, size // 8)) * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(6))
    wear = 0.9 + 0.2 * np.asarray(noise).astype(np.float32) / 255.0
    a = a * weave[..., None] * wear[..., None]
    detail_from(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), "rug.jpg", size, 1.0, 1.0)


if __name__ == "__main__":
    detail("logs", "coated_pine", keep_colour=0.45, contrast=0.9)
    normal("logs", "coated_pine", strength=1.4)
    detail("chinking", "clay_plaster", size=512, keep_colour=0.2, contrast=1.3)
    normal("chinking", "clay_plaster", size=512)
    detail("floor", "old_wooden_floor_01", keep_colour=0.5)
    normal("floor", "old_wooden_floor_01")
    detail("ceiling", "plank_flooring_02", keep_colour=0.4, contrast=0.8)
    normal("ceiling", "plank_flooring_02")
    detail("stone", "rustic_stone_wall", keep_colour=0.7, contrast=1.1)
    normal("stone", "rustic_stone_wall", strength=1.3)
    detail("roof", "roof_slates_02", keep_colour=0.3)
    normal("roof", "roof_slates_02", strength=1.2)
    detail("deck", "weathered_brown_planks", keep_colour=0.4)
    normal("deck", "weathered_brown_planks")
    detail("leather", "brown_leather", size=512, keep_colour=0.4, contrast=2.2)
    normal("leather", "brown_leather", size=512, strength=2.0)
    detail("wool", "poly_wool_herringbone", size=512, keep_colour=0.0, contrast=1.6)
    normal("wool", "poly_wool_herringbone", size=512, strength=1.5)
    detail("fleece", "knitted_fleece", size=512, keep_colour=0.0, contrast=1.5)
    normal("fleece", "knitted_fleece", size=512, strength=1.5)
    detail("bark", "pine_bark", size=512, keep_colour=0.5)
    normal("bark", "pine_bark", size=512)
    rug()
