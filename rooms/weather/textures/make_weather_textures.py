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
  frost.png    512 x 512, tiles both ways. Feathery frost crystals over a thin patchy film (bright = thick frost);
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
    # One copy covers weather_glass.gdshader's bead_size (0.8 m), so a pixel is about 1.5 mm.
    # Few, fairly big beads on purpose: thousands of tiny ones turned into grey speckle (like
    # frosted glass) once the window was a few metres from the camera.
    bead_layer(size, 700, 2.0, 4.0, rng, h, ids)      # small beads
    bead_layer(size, 150, 5.0, 10.0, rng, h, ids)     # big beads
    r, g = normals_from_height(h, 0.3)
    b = np.clip(h / 7.0, 0, 1)
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


def _frost_branch(draw, x, y, ang, length, width, depth, rng, size):
    """One ice "feather": a straight-ish stroke with smaller strokes off both sides at about 60
    degrees (how frost crystals grow), each of those with smaller ones again (depth levels).
    Drawn nine times, shifted by the picture's size, so it wraps round the edges."""
    steps = max(int(length / 4), 2)
    px, py = x, y
    for i in range(steps):
        ang += rng.normal(0, 0.06)
        nx, ny = px + np.cos(ang) * 4, py + np.sin(ang) * 4
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                draw.line((px + ox, py + oy, nx + ox, ny + oy), fill=255, width=max(int(width), 1))
        if depth > 0 and i > 0 and rng.random() < 0.35:
            side = 1 if rng.random() < 0.5 else -1
            _frost_branch(draw, nx, ny, ang + side * np.radians(rng.uniform(50, 70)),
                          length * rng.uniform(0.25, 0.45), width * 0.7, depth - 1, rng, size)
        px, py = nx, ny


def make_frost():
    from PIL import ImageDraw, ImageFilter
    size = 512
    rng = np.random.default_rng(3141)
    # the crystals: feathery strokes growing every which way (the shader decides where on the
    # pane they show; bright = frost)
    lines = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(lines)
    for _ in range(20):
        x, y = rng.uniform(0, size, 2)
        _frost_branch(draw, x, y, rng.uniform(0, 2 * np.pi), rng.uniform(120, 260), rng.uniform(1.2, 2.2), 2, rng, size)
    soft = np.asarray(lines.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    glow = np.asarray(lines.filter(ImageFilter.GaussianBlur(6)), np.float32) / 255.0
    # a thin frosty film between the crystals, patchy (smooth noise), and a fine grain
    film = np.zeros((size, size), np.float32)
    amp = 1.0
    for cells in (4, 8, 16):
        film += tile_noise(size, cells, rng) * amp
        amp *= 0.5
    film /= film.max()
    grain = tile_noise(size, 256, rng)
    img = np.clip(soft * 0.8 + glow * 0.5 + film * 0.35 + grain * 0.08 - 0.05, 0, 1)
    Image.fromarray((img * 255).astype(np.uint8), "L").save(os.path.join(HERE, "frost.png"))


if __name__ == "__main__":
    make_drops()
    make_runners()
    make_frost()
    print("wrote drops.png, runners.png, frost.png")
