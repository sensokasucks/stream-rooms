#!/usr/bin/env python3
"""Makes the Forge Hall's close-up stone textures (the room's "Detailed" look).

The hall's own stone pictures (slab_granite.png, forge_granite.png, pillar_marble.png, made by
blender/make_forge_textures.py) are drawn from noise and look flat close up. These photo
textures sit on top of them while Room tab > Forge Hall > Stone detail is Detailed:
forge_stone.gdshader multiplies the stone's own colour by the grain picture and bends the light
with the normal picture, only near the camera. So the hall keeps its colours and gains the
photos' pits, cracks and grain.

Everything starts from CC0 (public domain) photos from Poly Haven, https://polyhaven.com.
Run it again only to change a texture; the results are committed.

    python3 rooms/forge_hall/textures/make_stone_detail.py [cache folder]

Needs Python 3 with Pillow and numpy, and the internet (api.polyhaven.com, dl.polyhaven.org).

What it writes, for each of slab (the polished granite walls, floor and seats), forge (the
forge's rough granite) and marble (the pillars):
  stone_<name>_grain.jpg   the photo in grey, divided by its own blurred self, stored so that
        mid grey (128) means "no change"; lighter = brighter grain, darker = pits and cracks
  stone_<name>_normal.jpg  the photo's normal map (OpenGL style: green = up, as Redot reads it)
"""
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"
SIZE = 1024

# name -> (Poly Haven asset, grain contrast). Picked to suit each stone: a fine, even rock for
# the polished slabs, a fractured dark rock for the forge, a veined marble rock for the pillars.
STONES = {
    "slab": ("rock_surface", 1.6),
    "forge": ("dark_rock_02", 1.3),
    "marble": ("marble_rock_01", 0.9),
}


def fetch(asset: str, kind: str, res: str = "1k") -> Image.Image:
    """One map of a Poly Haven asset (kind as their API names it: "Diffuse", "nor_gl")."""
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


def grain(name: str, asset: str, contrast: float) -> None:
    """The photo's brightness divided by a blurred copy of itself (so big light and dark
    patches cancel out and only the fine grain is left), 128 = no change."""
    img = fetch(asset, "Diffuse").convert("L").resize((SIZE, SIZE), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) + 4.0
    # blur on a 3x3 tiling so the edges blur into the opposite side (the photos tile seamlessly)
    big = Image.fromarray(np.tile(a, (3, 3)).clip(0, 255).astype(np.uint8))
    blur = np.asarray(big.filter(ImageFilter.GaussianBlur(SIZE / 24))).astype(np.float32)[SIZE:2 * SIZE, SIZE:2 * SIZE] + 4.0
    rel = a / blur
    rel = 1.0 + (rel / rel.mean() - 1.0) * contrast     # average exactly 1: no overall darkening
    out = np.clip(rel * 128.0, 0, 255).astype(np.uint8)
    Image.fromarray(out, "L").save(os.path.join(HERE, f"stone_{name}_grain.jpg"), quality=88, optimize=True)
    print("wrote", f"stone_{name}_grain.jpg", "mean", round(float(out.mean()), 1))


def normal(name: str, asset: str) -> None:
    img = fetch(asset, "nor_gl").convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(HERE, f"stone_{name}_normal.jpg"), quality=90, optimize=True)
    print("wrote", f"stone_{name}_normal.jpg")


if __name__ == "__main__":
    for key, (asset_id, k) in STONES.items():
        grain(key, asset_id, k)
        normal(key, asset_id)
