#!/usr/bin/env python3
"""Makes the Lecture Hall's "Detailed" textures (Room tab > Set detail).

The hall's own textures (rooms/lecture_hall/textures, painted by a script) give the woods,
walls and carpet their colours and patterns: the gothic arches carved in the panels, the plank
joints of the stage, the door's panels. Here each of them gets the grain of a real photo
on top, plus a normal map (the small bumps light catches: the carved lines, the wood's
figure, the plaster's trowel marks, the carpet's pile) and, for the woods and leather, a
roughness map (where the varnish is worn duller). The Simple look keeps the old textures.

Every photo is CC0 (public domain) from Poly Haven, https://polyhaven.com:
  oak_veneer_01           the oak's figure (desks, rails, carved panels, doors, stage)
  black_walnut_veneer_01  its normal map, for the dark oak (pew backs, risers, ribs)
  leather_red_02          the pew cushions' bumps and sheen
  grey_plaster            the painted plaster walls and ceiling
  dirty_carpet            the carpet's pile

    python3 rooms/lecture_hall/detail/make_detail_textures.py [cache folder]

Needs Python 3 with Pillow, numpy and scipy, and the internet (api.polyhaven.com,
dl.polyhaven.org). The results are committed; run it again only to change a texture.

What it writes next to itself (names = the hall's material names in lower case; the room
script, lecture_hall_room.gd _detail_material(), loads them by those names):
  <name>.jpg      colour (albedo); 1024 px
  <name>_n.jpg    normal map, OpenGL style (green = up), as Godot wants
  <name>_r.jpg    roughness (only for the woods and the leather)
  sky_noise.png   not a photo and not part of the Detailed look: three layers of soft, seamless
                  noise (r, g, b) that window_sky.gdshaderinc turns into the clouds seen through
                  the windows. Made from random numbers here; no download. A texture rather than
                  noise worked out in the shader, because sin()-based shader noise turns blocky
                  on real graphics cards far from the origin (found in the Lakeside Campfire).

How big one repeat of each texture is in the hall (it must match the UVs that
blender/lecture_hall_gen.py gives the material, or the grain comes out the wrong size):
  Oak 1 m, Oak_Gothic 1.8 m, Stage_Floor 3 m, Door_Leaf one leaf (1 x 3 m), Oak_Dark 1 m,
  Leather 1 m, Carpet 2 m, Red_Wall 2 m, Ochre_Panel and Ceiling_Panel one whole panel (~4 m).
"""
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
HALL_TEX = os.path.join(HERE, "..", "textures")
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"
SIZE = 1024


def fetch(asset: str, kind: str, res: str = "2k") -> np.ndarray:
    """One map of a Poly Haven asset as a float array 0..1 (kind as their API names it:
    "Diffuse", "nor_gl", "Rough"...). Downloads are kept in CACHE."""
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, f"{asset}__{kind}__{res}.jpg")
    if not os.path.exists(out):
        req = urllib.request.Request(API + asset, headers={"User-Agent": "texture-bake-script"})
        files = json.load(urllib.request.urlopen(req, timeout=60))
        url = files[kind][res]["jpg"]["url"]
        req = urllib.request.Request(url, headers={"User-Agent": "texture-bake-script"})
        with open(out, "wb") as f:
            f.write(urllib.request.urlopen(req, timeout=180).read())
    return np.asarray(Image.open(out).convert("RGB"), np.float32) / 255.0


def hall(name: str) -> np.ndarray:
    """One of the hall's own painted textures, 0..1 RGB, scaled to SIZE x SIZE."""
    im = Image.open(os.path.join(HALL_TEX, name)).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0


def tile(photo: np.ndarray, photo_m: float, tex_m: tuple, flip: bool = False, shift: float = 0.0) -> np.ndarray:
    """The part of a seamless photo (photo_m metres square) that covers tex_m = (width, height)
    metres, repeated as needed, resampled to SIZE x SIZE. Repeats only join up seamlessly when
    tex_m is a whole number of photo repeats or less than one; small seams at the texture's
    own edge don't show on the hall's woods. shift moves the crop (0..1 of the photo) so two
    materials don't show the same knot in the same place."""
    h, w = photo.shape[:2]
    pw = max(1, int(round(w * tex_m[0] / photo_m)))
    ph = max(1, int(round(h * tex_m[1] / photo_m)))
    p = np.roll(photo, int(shift * w), axis=1)
    reps = (int(np.ceil(ph / h)), int(np.ceil(pw / w)), 1)
    big = np.tile(p, reps)[:ph, :pw]
    im = Image.fromarray(np.clip(big * 255, 0, 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)
    a = np.asarray(im, np.float32) / 255.0
    return a[:, ::-1] if flip else a


def grain(photo: np.ndarray, keep_colour: float = 0.35, contrast: float = 1.0) -> np.ndarray:
    """The photo divided by its own average colour: 1.0 = no change. keep_colour: how much of
    the photo's own colour differences stay (0 = grey grain only)."""
    lum = photo.mean(axis=2, keepdims=True)
    a = lum + (photo - lum) * keep_colour
    rel = a / a.reshape(-1, 3).mean(axis=0)
    return 1.0 + (rel - 1.0) * contrast


def soften(base: np.ndarray, sigma: float) -> np.ndarray:
    """Blurs the painted texture's fake stripes away, keeping its bigger shapes (panels, joints)."""
    return np.stack([ndimage.gaussian_filter(base[..., c], sigma, mode="wrap") for c in range(3)], axis=2)


def height_normal(base: np.ndarray, strength: float, sigma: float = 1.2) -> np.ndarray:
    """A normal map (OpenGL, 0..1) from the painted texture's dark lines: dark = cut in, so the
    carved arches, plank joints and door panels catch the light. strength: how deep."""
    lum = ndimage.gaussian_filter(base.mean(axis=2), sigma, mode="wrap")
    gy, gx = np.gradient(lum)
    n = np.stack([-gx * strength, gy * strength, np.ones_like(lum)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def blend_normals(a: np.ndarray, b: np.ndarray, b_amount: float = 1.0) -> np.ndarray:
    """Two normal maps on top of each other ("whiteout" blend); b_amount flattens b first."""
    na = a * 2.0 - 1.0
    nb = b * 2.0 - 1.0
    nb[..., :2] *= b_amount
    n = np.stack([na[..., 0] + nb[..., 0], na[..., 1] + nb[..., 1], na[..., 2] * nb[..., 2]], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def flat_normal(n: np.ndarray, amount: float) -> np.ndarray:
    """A photo's normal map made shallower (amount 0 = flat, 1 = as photographed)."""
    v = n * 2.0 - 1.0
    v[..., :2] *= amount
    v /= np.linalg.norm(v, axis=2, keepdims=True)
    return v * 0.5 + 0.5


def save(a: np.ndarray, name: str, quality: int = 88, grey: bool = False) -> None:
    img = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))
    if grey:
        img = img.convert("L")
    img.save(os.path.join(HERE, name), quality=quality, optimize=True)
    print("wrote", name)


def rough_map(photo_rough: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """The photo's roughness squeezed into lo..hi (the material's own roughness range)."""
    r = photo_rough.mean(axis=2)
    r = (r - r.min()) / max(1e-4, r.max() - r.min())
    return np.repeat((lo + (hi - lo) * r)[..., None], 3, axis=2)


def sky_noise(size: int = 256) -> None:
    """Seamless cloud noise: each channel a sum of random waves on a whole number of cycles
    across the picture, so it repeats without a seam. r = big cloud shapes, g = middle
    detail, b = fine wisps."""
    rng = np.random.default_rng(31)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size * 2.0 * np.pi
    chans = []
    for lo, hi, waves in ((1, 4, 24), (3, 9, 40), (7, 20, 60)):
        a = np.zeros((size, size), np.float32)
        for _ in range(waves):
            fx, fy = rng.integers(-hi, hi + 1, 2)
            if max(abs(fx), abs(fy)) < lo:
                continue
            a += np.cos(fx * x + fy * y + rng.random() * 6.2832) / np.hypot(fx, fy)
        a = (a - a.min()) / (a.max() - a.min())
        chans.append(a)
    img = np.stack(chans, axis=2)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(os.path.join(HERE, "sky_noise.png"))
    print("wrote sky_noise.png")


def main() -> None:
    sky_noise()
    OAK = "oak_veneer_01"          # 1.83 m square, grain running up the picture
    oak_c = fetch(OAK, "Diffuse")
    oak_n = fetch(OAK, "nor_gl")
    oak_r = fetch(OAK, "Rough")

    # Oak (1 m): the photo itself, in the painted oak's colour
    base = hall("oak.png")
    g = grain(tile(oak_c, 1.83, (1.0, 1.0)), keep_colour=0.3, contrast=1.25)
    mean = soften(base, 40.0)
    save(mean * g, "oak.jpg")
    save(flat_normal(tile(oak_n, 1.83, (1.0, 1.0)), 0.8), "oak_n.jpg", 92)
    save(rough_map(tile(oak_r, 1.83, (1.0, 1.0)), 0.3, 0.6), "oak_r.jpg", 85, grey=True)

    # Oak_Gothic (1.8 m): the carved arch panels keep their shapes, the grain is the photo's
    base = hall("gothic_panel.png")
    g = grain(tile(oak_c, 1.83, (1.8, 1.8), shift=0.37), keep_colour=0.3, contrast=1.1)
    save(soften(base, 2.0) * g, "oak_gothic.jpg")
    nrm = blend_normals(height_normal(base, 9.0), flat_normal(tile(oak_n, 1.83, (1.8, 1.8), shift=0.37), 0.7))
    save(nrm, "oak_gothic_n.jpg", 92)
    save(rough_map(tile(oak_r, 1.83, (1.8, 1.8), shift=0.37), 0.35, 0.65), "oak_gothic_r.jpg", 85, grey=True)

    # Stage_Floor (3 m): the painted planks and their joints, the photo's grain in each
    base = hall("wood_light.png")
    g = grain(tile(oak_c, 1.83, (3.0, 3.0), flip=True, shift=0.6), keep_colour=0.25, contrast=1.0)
    save(soften(base, 2.5) * g, "stage_floor.jpg")
    nrm = blend_normals(height_normal(base, 6.0), flat_normal(tile(oak_n, 1.83, (3.0, 3.0), flip=True, shift=0.6), 0.6))
    save(nrm, "stage_floor_n.jpg", 92)
    save(rough_map(tile(oak_r, 1.83, (3.0, 3.0), flip=True, shift=0.6), 0.25, 0.5), "stage_floor_r.jpg", 85, grey=True)

    # Door_Leaf (one leaf, 1 m wide and 3 m tall): panels and studs from the painting
    base = np.asarray(Image.open(os.path.join(HALL_TEX, "door_leaf.png")).convert("RGB").resize((SIZE // 2, SIZE), Image.LANCZOS), np.float32) / 255.0
    base = np.asarray(Image.fromarray((base * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255.0
    g = grain(tile(oak_c, 1.83, (1.0, 3.0), shift=0.15), keep_colour=0.3, contrast=1.1)
    save(soften(base, 1.5) * g, "door_leaf.jpg")
    save(blend_normals(height_normal(base, 7.0), flat_normal(tile(oak_n, 1.83, (1.0, 3.0), shift=0.15), 0.7)), "door_leaf_n.jpg", 92)
    save(rough_map(tile(oak_r, 1.83, (1.0, 3.0), shift=0.15), 0.35, 0.6), "door_leaf_r.jpg", 85, grey=True)

    # Oak_Dark (1 m; a plain colour in the Simple look): the oak photo darkened to its colour.
    # The colour is the material's own (0.16, 0.08, 0.035) in linear, about (112, 80, 52) in sRGB.
    g = grain(tile(oak_c, 1.83, (1.0, 1.0), flip=True, shift=0.8), keep_colour=0.2, contrast=1.4)
    dark = np.array([112, 80, 52], np.float32) / 255.0
    save(dark * g, "oak_dark.jpg")
    wal_n = fetch("black_walnut_veneer_01", "nor_gl")
    save(flat_normal(tile(wal_n, 1.0, (1.0, 1.0)), 0.8), "oak_dark_n.jpg", 92)
    save(rough_map(tile(oak_r, 1.83, (1.0, 1.0), flip=True, shift=0.8), 0.3, 0.6), "oak_dark_r.jpg", 85, grey=True)

    # Leather (1 m; plain colour in the Simple look): the cushions' crinkles and sheen. The
    # colour stays the material's own red (0.30, 0.07, 0.05) linear = (149, 74, 63) sRGB,
    # with the photo's shading for depth.
    lea_n = fetch("leather_red_02", "nor_gl")
    lea_ao = fetch("leather_red_02", "AO")
    lea_r = fetch("leather_red_02", "Rough")
    red = np.array([149, 74, 63], np.float32) / 255.0
    ao = tile(lea_ao, 0.6, (1.2, 1.2))
    save(red * grain(ao, 0.0, 1.5), "leather.jpg")
    save(flat_normal(tile(lea_n, 0.6, (1.2, 1.2)), 1.0), "leather_n.jpg", 92)
    save(rough_map(tile(lea_r, 0.6, (1.2, 1.2)), 0.4, 0.7), "leather_r.jpg", 85, grey=True)

    # Carpet (2 m): the pile, very shallow, and a faint shading from the photo
    car_c = fetch("dirty_carpet", "Diffuse")
    car_n = fetch("dirty_carpet", "nor_gl")
    base = hall("carpet.png")
    save(base * grain(tile(car_c, 0.6, (2.4, 2.4)), 0.0, 0.5), "carpet.jpg")
    save(flat_normal(tile(car_n, 0.6, (2.4, 2.4)), 0.6), "carpet_n.jpg", 92)

    # the painted plaster: Red_Wall (2 m), Ochre_Panel and Ceiling_Panel (one panel, ~4 m)
    pl_c = fetch("grey_plaster", "Diffuse")
    pl_n = fetch("grey_plaster", "nor_gl")
    for name, src, metres in (("red_wall", "red_wall.png", 2.0), ("ochre_panel", "ochre_panel.png", 4.0), ("ceiling_panel", "ceiling_panel.png", 4.0)):
        base = hall(src)
        save(base * grain(tile(pl_c, 1.0, (metres, metres)), 0.0, 0.45), name + ".jpg")
        save(flat_normal(tile(pl_n, 1.0, (metres, metres)), 0.6), name + "_n.jpg", 92)


if __name__ == "__main__":
    main()
