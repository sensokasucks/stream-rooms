#!/usr/bin/env python3
"""Makes the Drive-In's own photo textures (its "Detailed" set look).

Both start from CC0 (public domain) photos from Poly Haven, https://polyhaven.com. The script
downloads them, cuts them down to what the game needs and writes the files next to itself.
Run it again only to change a texture; the results are committed.

    python3 rooms/drive_in/textures/make_textures.py [cache folder]

Needs Python 3 with Pillow and numpy, and the internet (api.polyhaven.com, dl.polyhaven.org).

What it writes (drive_ground.gdshader lays them on by world position):
  ground_asphalt.jpg   the parking lot (Poly Haven "asphalt_02": worn, with tar-filled cracks)
  ground_gravel.jpg    the parking ramps the cars stand on (Poly Haven "gravel_floor", a little
                       greyer than photographed; still lighter and warmer than the asphalt, so the ramps
                       stand out from the lot as they do in the Simple look)
  detail_plaster.jpg   the snack bar's walls and roof (Poly Haven "painted_plaster_wall") and
  detail_concrete.jpg  the screen tower (Poly Haven "concrete_wall_008"): "detail" textures as
                       the campfire makes them (the photo divided by its own average, 0.5 = no
                       change), which drive_detail.gdshader multiplies onto the model's own colour
The grass, the forest floor, the planks, the cloth and the trees' pictures are the Lakeside
Campfire's (rooms/campfire/textures/, made by make_textures.py there); the Drive-In reads
them from that folder rather than keeping copies.
"""
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"


def fetch(asset: str, kind: str = "Diffuse", res: str = "1k") -> Image.Image:
    """One map of a Poly Haven asset (the same as the campfire's make_textures.py fetch)."""
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


def ground(name: str, asset: str, gain=(1.0, 1.0, 1.0), grey: float = 0.0) -> None:
    """Writes a 1024 px copy of a ground photo. gain multiplies each colour channel;
    grey (0..1) pulls the colours towards their own brightness (less saturated)."""
    a = np.asarray(fetch(asset).convert("RGB").resize((1024, 1024), Image.LANCZOS)).astype(np.float32)
    lum = a.mean(axis=2, keepdims=True)
    a = a + (lum - a) * grey
    a *= np.array(gain, dtype=np.float32)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(HERE, name), quality=86, optimize=True)
    print("wrote", name)


def detail(name: str, asset: str, size: int = 1024, keep_colour: float = 0.0, contrast: float = 1.0) -> None:
    """The photo divided by its average colour, stored so that 0.5 = no change (the same as the
    campfire's make_textures.py detail()). keep_colour: how much of the photo's own colour
    differences stay (0 = grey grain only); contrast scales the grain."""
    a = np.asarray(fetch(asset).convert("RGB").resize((size, size), Image.LANCZOS)).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    a = lum + (a - lum) * keep_colour
    rel = a / a.reshape(-1, 3).mean(axis=0)
    rel = 1.0 + (rel - 1.0) * contrast
    Image.fromarray(np.clip(rel * 127.5, 0, 255).astype(np.uint8)).save(os.path.join(HERE, name), quality=86, optimize=True)
    print("wrote", name)


if __name__ == "__main__":
    ground("ground_asphalt.jpg", "asphalt_02", (0.85, 0.85, 0.88))
    ground("ground_gravel.jpg", "gravel_floor", (1.0, 0.97, 0.92), grey=0.15)
    detail("detail_plaster.jpg", "painted_plaster_wall", contrast=0.8)
    detail("detail_concrete.jpg", "concrete_wall_008", contrast=0.9)
