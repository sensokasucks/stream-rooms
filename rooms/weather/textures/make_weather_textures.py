"""Makes the weather module's textures (rooms/weather/): drawn here from scratch, no photos.

Run from anywhere:  python make_weather_textures.py
Needs numpy and Pillow. Writes next to this script (fixed seeds, so every run gives the same
pictures):
  drops.png    512 x 512, tiles both ways. Beads of rain sitting on glass (weather_glass.gdshader).
               R, G = which way the bead's surface leans (the bend it gives the view behind it),
               0.5 = flat; B = how thick the water is (0 = dry glass); A = each bead's own random
               number, so the shader can dry the small ones first.
  runners.png  256 x 1024, tiles both ways. Drops sliding down with the wet trail they leave.
               R, G = lean as above; B = water; A = 0 at the drop's head, rising along its trail
               (the shader fades the trail with it).
  frost.png    512 x 512, tiles both ways. Grey frost ferns and crystals (bright = thick frost);
               the shader grows it in from the bottom of each pane as it gets colder.
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def bead_layer(size, count, r_lo, r_hi, rng, out_h, out_id):
    """Paints `count` round beads (half-sphere height) into out_h, wrapping at the edges.
    out_id gets each bead's random number where it is the tallest."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    for _ in range(count):
        cx, cy = rng.uniform(0, size, 2)
        r = rng.uniform(r_lo, r_hi) * (1.0 if rng.random() > 0.15 else 1.6)
        stretch = rng.uniform(0.85, 1.25)        # a little taller than wide: gravity
        dx = (xx - cx + size / 2) % size - size / 2
        dy = ((yy - cy + size / 2) % size - size / 2) / stretch
        d2 = (dx * dx + dy * dy) / (r * r)
        h = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0)) * r
        win = h > out_h
        out_h[win] = h[win]
        out_id[win] = rng.random()


def normals_from_height(h, strength):
    gy, gx = np.gradient(h)
    nx = -gx * strength
    ny = -gy * strength
    return np.clip(nx * 0.5 + 0.5, 0, 1), np.clip(ny * 0.5 + 0.5, 0, 1)


def make_drops():
    size = 512
    rng = np.random.default_rng(1971)
    h = np.zeros((size, size), np.float32)
    ids = np.zeros((size, size), np.float32)
    bead_layer(size, 2600, 1.2, 3.2, rng, h, ids)     # fine mist of beads
    bead_layer(size, 260, 3.5, 8.0, rng, h, ids)      # bigger beads
    r, g = normals_from_height(h, 0.35)
    b = np.clip(h / 6.0, 0, 1)
    img = np.dstack([r, g, b, ids])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(HERE, "drops.png"))


def make_runners():
    w, hgt = 256, 1024
    rng = np.random.default_rng(2207)
    h = np.zeros((hgt, w), np.float32)
    trail = np.ones((hgt, w), np.float32)
    yy, xx = np.mgrid[0:hgt, 0:w].astype(np.float32)
    for _ in range(26):
        cx = rng.uniform(0, w)
        cy = rng.uniform(0, hgt)
        r = rng.uniform(3.0, 6.0)
        length = rng.uniform(120, 420)
        wobble_f = rng.uniform(0.01, 0.03)
        wobble_a = rng.uniform(1.0, 4.0)
        # the head: a fat drop at the bottom of the run
        dx = (xx - cx + w / 2) % w - w / 2
        dy = (yy - cy + hgt / 2) % hgt - hgt / 2
        d2 = (dx * dx + (dy * 0.8) ** 2) / (r * r)
        head = np.sqrt(np.clip(1.0 - d2, 0, 1)) * r
        # the trail above it (smaller y), thinning and wobbling as it goes up
        up = -dy                                   # 0 at the head, rising upwards
        along = np.clip(up / length, 0, 1)
        on = (up > 0) & (up < length)
        cxw = wobble_a * np.sin(up * wobble_f)
        tw = r * 0.45 * (1.0 - along * 0.7)
        td2 = ((dx - cxw) ** 2) / np.maximum(tw * tw, 0.01)
        tail = np.where(on, np.sqrt(np.clip(1.0 - td2, 0, 1)) * tw * 0.6, 0.0)
        hh = np.maximum(head, tail)
        win = hh > h
        h[win] = hh[win]
        trail[win] = np.where(head[win] >= tail[win], 0.0, 0.15 + 0.85 * along[win])
    r_, g_ = normals_from_height(h, 0.35)
    b = np.clip(h / 5.0, 0, 1)
    img = np.dstack([r_, g_, b, trail])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(HERE, "runners.png"))


def tile_noise(size, cells, rng):
    """Smooth value noise that tiles: random grid, cubic blend, wrapping."""
    grid = rng.random((cells, cells)).astype(np.float32)
    t = np.arange(size, dtype=np.float32) * cells / size
    i0 = np.floor(t).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    a = grid[i0][:, i0] * (1 - f)[None, :] + grid[i0][:, i1] * f[None, :]
    b = grid[i1][:, i0] * (1 - f)[None, :] + grid[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def make_frost():
    size = 512
    rng = np.random.default_rng(3141)
    n = np.zeros((size, size), np.float32)
    amp = 1.0
    for cells in (4, 8, 16, 32, 64, 128):
        n += tile_noise(size, cells, rng) * amp
        amp *= 0.55
    n /= n.max()
    # ridges: the thin bright lines of frost ferns
    ridge = 1.0 - np.abs(n * 2.0 - 1.0)
    ridge = ridge ** 6
    fine = tile_noise(size, 128, rng)
    img = np.clip(ridge * 0.8 + n * 0.35 + fine * 0.15 - 0.15, 0, 1)
    Image.fromarray((img * 255).astype(np.uint8), "L").save(os.path.join(HERE, "frost.png"))


if __name__ == "__main__":
    make_drops()
    make_runners()
    make_frost()
    print("wrote drops.png, runners.png, frost.png")
