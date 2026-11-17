#!/usr/bin/env python3
"""Makes the Route 22 rooms' textures (rooms/route22 = the drive-in, rooms/route22_cruise = the
endless desert road). Run it again only to change a texture; the results are committed.

    python3 rooms/route22/textures/make_textures.py [cache folder]

Needs Python 3 with Pillow and numpy, and the internet for the photos (api.polyhaven.com,
dl.polyhaven.org). Every photo is CC0 (public domain) from Poly Haven, https://polyhaven.com.

What it writes (all seamless, so they tile):
  detail_sandstone.jpg  a "detail" texture from Poly Haven's cliff_side photo: the photo divided
        by its own average colour, so mid grey = no change. r22_rock.gdshader multiplies the
        rock bands' colour by it (times 2): the colour comes from the strata, the grain from the photo.
  ground_desert.jpg     red desert ground (Poly Haven cracked_red_ground), used as it is by
        r22_ground.gdshader, mixed with the sand below by the ground's vertex colour.
  ground_sand.jpg       loose sand and pebbles (Poly Haven aerial_sand).
  road_asphalt.jpg      worn, dry asphalt (Poly Haven asphalt_04) for r22_road.gdshader.
  *_nor.jpg             the matching normal maps (OpenGL style, green = up the picture) of
        detail_sandstone, ground_desert, ground_sand and road_asphalt, softened a little; the
        rock, ground and road shaders bend their lighting with them on the Detailed look.
  detail_planks_weathered.jpg  weathered wood planks (Poly Haven weathered_planks) as a "detail"
        texture like the sandstone: r22_prop.gdshader's wood (fences, signs, sheds, the stage).
  prop_rust.jpg         rusty painted metal (Poly Haven rusty_metal_02): r22_prop.gdshader's rust
        blotches take this photo's colour on the Detailed look.
  rock_noise.png        made here from noise, no photo: r = honeycomb cells (the rows of little
        holes wind carves in sandstone, "tafoni"), g = long vertical streaks (desert varnish
        running down cliffs), b = soft lumpy noise (warps the rock bands so they aren't ruler-straight),
        a = small speckle. r22_rock.gdshader reads it.
"""
import json
import math
import os
import sys
import urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"


def fetch(asset: str, kind: str = "Diffuse", res: str = "1k") -> Image.Image:
    """One map of a Poly Haven asset (kind as their API names it), cached in CACHE."""
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


def photo(name: str, asset: str, size: int = 1024, gain=(1.0, 1.0, 1.0)) -> None:
    """A photo as it is (scaled, colour gain per channel)."""
    img = fetch(asset).convert("RGB").resize((size, size), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) * np.array(gain, dtype=np.float32)
    save_jpg(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), name)


def detail(name: str, asset: str, size: int = 1024, contrast: float = 1.2) -> None:
    """photo / its average colour, grey only, stored so that 0.5 = no change."""
    img = fetch(asset).convert("RGB").resize((size, size), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True).repeat(3, axis=2)
    rel = lum / lum.reshape(-1, 3).mean(axis=0)
    rel = 1.0 + (rel - 1.0) * contrast
    save_jpg(Image.fromarray(np.clip(rel * 127.5, 0, 255).astype(np.uint8)), name)


def normal(name: str, asset: str, size: int = 1024, strength: float = 0.8) -> None:
    """A Poly Haven normal map (nor_gl), its bumps scaled by `strength` (1 = as photographed)."""
    img = fetch(asset, "nor_gl").convert("RGB").resize((size, size), Image.LANCZOS)
    n = np.asarray(img).astype(np.float32) / 127.5 - 1.0
    n[..., 0:2] *= strength
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    save_jpg(Image.fromarray(np.clip((n + 1.0) * 127.5, 0, 255).astype(np.uint8)), name, quality=92)


def tile_noise(size: int, slope: float, seed: int, stretch=(1.0, 1.0)) -> np.ndarray:
    """Seamless noise from random frequencies (1/f^slope), 0..1. stretch squashes it along x / y."""
    rng = np.random.default_rng(seed)
    fx = np.fft.fftfreq(size)[None, :] * stretch[0]
    fy = np.fft.fftfreq(size)[:, None] * stretch[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = (rng.normal(size=(size, size)) + 1j * rng.normal(size=(size, size))) / np.power(f, slope)
    spec[0, 0] = 0.0
    n = np.real(np.fft.ifft2(spec))
    n = (n - n.min()) / (n.max() - n.min())
    return n


def worley(size: int, cells: int, seed: int) -> np.ndarray:
    """Seamless cell noise: distance to the nearest of `cells`^2 jittered points, 0 at a point.
    Inverted and sharpened it makes round pits in rows, like honeycomb weathering."""
    rng = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1).reshape(-1, 2) + rng.random((cells * cells, 2))) / cells
    yy, xx = np.mgrid[0:size, 0:size] / size
    best = np.full((size, size), 9.0)
    for px, py in pts:
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, 1.0 - dx)                 # wrap round: seamless
        dy = np.minimum(dy, 1.0 - dy)
        best = np.minimum(best, np.sqrt(dx * dx + dy * dy))
    return best * cells


def rock_noise(size: int = 512) -> None:
    pits = worley(size, 22, 7)
    pits = np.clip(1.0 - pits / 0.55, 0.0, 1.0) ** 1.6           # 1 in a pit's middle, 0 between pits
    clump = tile_noise(size, 1.6, 11)                           # pits come in patches, not everywhere
    r = pits * np.clip((clump - 0.42) * 3.0, 0.0, 1.0)
    g = tile_noise(size, 1.3, 23, stretch=(1.0, 0.06))          # long vertical streaks
    b = tile_noise(size, 2.0, 37)
    a = tile_noise(size, 0.6, 41)
    img = np.stack([r, g, b, a], -1)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(HERE, "rock_noise.png"))
    print("wrote rock_noise.png")


if __name__ == "__main__":
    detail("detail_sandstone.jpg", "cliff_side")
    photo("ground_desert.jpg", "cracked_red_ground")
    photo("ground_sand.jpg", "aerial_sand", gain=(1.05, 0.92, 0.82))
    photo("road_asphalt.jpg", "asphalt_04", gain=(0.95, 0.95, 0.97))
    normal("detail_sandstone_nor.jpg", "cliff_side")
    normal("ground_desert_nor.jpg", "cracked_red_ground")
    normal("ground_sand_nor.jpg", "aerial_sand", strength=0.6)
    normal("road_asphalt_nor.jpg", "asphalt_04", strength=0.6)
    detail("detail_planks_weathered.jpg", "weathered_planks", size=512)
    photo("prop_rust.jpg", "rusty_metal_02", size=512)
    rock_noise()
