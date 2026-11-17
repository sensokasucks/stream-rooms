#!/usr/bin/env python3
"""Models Route 22's other vehicles with Blender's Python module and writes vehicles.glb beside
this file: the traffic (pickup, classic sedan, semi, motorhome, tour bus, motorcycle) and the
Drive-In's parked cars (the convertible, the pickup with its tailgate down). Our own designs,
no real makes, no badges; simpler than the Cruise's woody (make_woody.py), whose tools and body
they borrow.

    python3 rooms/route22/models/make_vehicles.py [preview folder]

Needs what make_woody.py needs (Python 3.13 with bpy, numpy, scipy, shapely). With a preview
folder it also renders a picture of each vehicle there. Run it again only to change a vehicle;
vehicles.glb is committed.

What r22_vehicles.gd relies on (change both together):
  - One object per vehicle, named by its kind: classic, convertible, pickup, semi, rv, bus,
    motorcycle; plus pickup_gate_up / pickup_gate_down (the pickup's tailgate, shut or open).
  - Blender space as in make_woody.py (X right, Y forward, Z up, ground at z = 0, the vehicle
    centred on the origin); in the game they face -Z.
  - Material names pick each surface's colour and look there (r22_vehicles.gd LOOKS): paint is
    the vehicle's own colour; tyre / hub / whitewall are the wheels (left off the wreck).
  - Empty marker nodes under each vehicle: <kind>_LampFront_n and <kind>_LampTail_n (where the
    lamps glare at night).
  - The Drive-In seats its audience at r22_vehicles.gd's own seat points (the same on the low
    and the detailed look), so the convertible's front seats and the pickup's bed floor and
    cooler must stay where the old built-in-code vehicles have them.
"""
import math
import os
import sys

import bpy  # (first: bmesh and mathutils come with it)
import bmesh
from mathutils import Matrix, Vector
from shapely.geometry import box as sbox

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_woody as W  # noqa: E402  (the shared tools: box, cyl, rods, decal, cut, hull, bake, join)

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = sys.argv[1] if len(sys.argv) > 1 else ""

# preview colours of the materials the woody does not have (the game sets its own, by name)
W.COLORS.update({
    "tyre": (0.025, 0.025, 0.025, 0.0, 0.9), "hub": (0.8, 0.8, 0.82, 1.0, 0.15), "whitewall": (0.9, 0.9, 0.88, 0.0, 0.6),
    "bed": (0.25, 0.02, 0.015, 0.3, 0.5), "cream": (0.82, 0.76, 0.6, 0.0, 0.5), "coach": (0.85, 0.85, 0.84, 0.1, 0.4),
    "trailer": (0.82, 0.82, 0.8, 0.2, 0.5), "jacket": (0.03, 0.025, 0.02, 0.0, 0.7), "jeans": (0.03, 0.04, 0.09, 0.0, 0.8),
    "helmet": (0.6, 0.1, 0.08, 0.2, 0.3), "seat": (0.03, 0.025, 0.02, 0.0, 0.6),
})

DONE: list = []          # the finished vehicles (objects) and their markers
MARKS: list = []


# ── shared parts ──
def lathe(name: str, profile: list, material: str, segs: int = 24):
    """A closed ring-shaped solid: `profile` is a closed outline of (distance along the axle,
    radius) points, spun round the X axis."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        rings.append([bm.verts.new((x, math.cos(a) * rad, math.sin(a) * rad)) for x, rad in profile])
    k = len(profile)
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % segs]
        for j in range(k):
            if profile[j][1] < 1e-6 and profile[(j + 1) % k][1] < 1e-6:
                continue                              # (both ends on the axle: no face)
            bm.faces.new([r0[j], r0[(j + 1) % k], r1[(j + 1) % k], r1[j]])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return W.add(name, bm, material)


def wheel(x: float, y: float, r: float, width: float, whitewall: bool = False, dual: bool = False):
    """A wheel standing on the ground at (x, y), its axle across the car, its dished hub facing
    outwards (the side x is on; x = 0: a motorcycle's, the same both sides). dual: a second
    tyre inboard of it (trucks' rear axles)."""
    out = 1.0 if x >= 0.0 else -1.0
    h = width / 2
    s = r * 0.045                                      # the rounding of the tyre's shoulders
    tyre = [(-h, r * 0.60), (-h, r - 3 * s), (-h + 2 * s, r), (h - 2 * s, r), (h, r - 3 * s), (h, r * 0.60)]
    parts = [lathe("Tyre", tyre, "tyre")]
    if dual:
        parts.append(lathe("TyreInner", [(px - width * 1.12, pr) for px, pr in tyre], "tyre"))
        parts.append(lathe("HubInner", [(-width * 1.5, 0.0), (-width * 1.5, r * 0.62), (-h, r * 0.62), (-h, 0.0)], "seat"))
    if x == 0.0:
        hub = [(-h * 0.7, 0.0), (-h * 0.7, r * 0.3), (-h * 0.4, r * 0.62), (h * 0.4, r * 0.62), (h * 0.7, r * 0.3), (h * 0.7, 0.0)]
    else:
        # dished: a rim, a step in, a domed cap; flat and dark on the inside
        hub = [(-h * 0.9, 0.0), (-h * 0.9, r * 0.62), (h * 0.95, r * 0.62), (h * 0.80, r * 0.50), (h * 0.80, r * 0.36), (h * 1.05, r * 0.30),
               (h * 1.18, r * 0.12), (h * 1.2, 0.0)]
    parts.append(lathe("Hub", hub, "hub"))
    if whitewall:
        parts.append(lathe("Whitewall", [(h * 0.98, r * 0.63), (h + 0.004, r * 0.65), (h + 0.004, r * 0.80), (h * 0.98, r * 0.82)], "whitewall"))
    for ob in parts:
        ob.matrix_world = Matrix.Translation((x, y, r)) @ Matrix.Scale(out, 4, (1.0, 0.0, 0.0))
    return parts


def greenhouse(name: str, base, top, z0: float, z1: float, panes: str = "FBLR", side_panes: int = 1, material: str = "paint",
               bevel: float = 0.05, margin: float = 0.07):
    """A cab / roof: a tapering block from `base` to `top`, each (y front, y back, half width),
    between heights z0 and z1, with glass let into its Front, Back, Left and Right faces (the
    letters in `panes`); side_panes = how many windows a side has. The glass is a dark skin a
    few millimetres proud of the face (the game's glass is not see-through)."""
    (yf0, yb0, w0), (yf1, yb1, w1) = base, top
    corners = {}                                       # (side, end, level) -> point
    for lvl, (yf, yb, w, z) in enumerate(((yf0, yb0, w0, z0), (yf1, yb1, w1, z1))):
        for sx in (-1, 1):
            corners[(sx, "F", lvl)] = Vector((sx * w, yf, z))
            corners[(sx, "B", lvl)] = Vector((sx * w, yb, z))
    bm = bmesh.new()
    vs = {k: bm.verts.new(p) for k, p in corners.items()}
    quads = {"F": [(-1, "F", 0), (1, "F", 0), (1, "F", 1), (-1, "F", 1)], "B": [(1, "B", 0), (-1, "B", 0), (-1, "B", 1), (1, "B", 1)],
             "R": [(1, "F", 0), (1, "B", 0), (1, "B", 1), (1, "F", 1)], "L": [(-1, "B", 0), (-1, "F", 0), (-1, "F", 1), (-1, "B", 1)]}
    for q in quads.values():
        bm.faces.new([vs[k] for k in q])
    bm.faces.new([vs[(-1, "F", 1)], vs[(1, "F", 1)], vs[(1, "B", 1)], vs[(-1, "B", 1)]])
    bm.faces.new([vs[(-1, "B", 0)], vs[(1, "B", 0)], vs[(1, "F", 0)], vs[(-1, "F", 0)]])
    ob = W.add(name, bm, material)
    bv = ob.modifiers.new("bevel", "BEVEL")
    bv.width = bevel
    bv.segments = 3
    # the glass
    gm = bmesh.new()
    for side in panes:
        a, b, c, d = [corners[k] for k in quads[side]]         # bottom left, bottom right, top right, top left
        n = (d - a).cross(b - a).normalized()            # out of the cab
        count = side_panes if side in "LR" else 1
        for i in range(count):
            width = (b - a).length
            mu = margin / width
            u0 = mu + (1.0 - 2 * mu) * i / count + (mu * 0.5 if i else 0.0)
            u1 = mu + (1.0 - 2 * mu) * (i + 1) / count - (mu * 0.5 if i < count - 1 else 0.0)
            mv = margin / (d - a).length
            def at(u, v):
                return a.lerp(b, u).lerp(d.lerp(c, u), v) + n * 0.006
            gm.faces.new([gm.verts.new(at(u, v)) for u, v in ((u0, mv * 1.6), (u1, mv * 1.6), (u1, 1.0 - mv), (u0, 1.0 - mv))])
    if panes:
        W.add(name + "Glass", gm, "glass")
    return ob


def bumper(y: float, z: float, wide: float, tall: float = 0.15, deep: float = 0.12, material: str = "chrome"):
    W.box("Bumper", (wide, deep, tall), (0.0, y, z), material, bevel=min(tall, deep) * 0.3)


def lamps(kind: str, pts: list, y: float, r: float = 0.09, facing: float = 1.0):
    """Round lamps on a face at y: front (facing +1) or tail (-1) lamps at each (x, z)."""
    for x, z in pts:
        W.cyl("LampRim", r * 1.18, r * 1.1, 0.06, (x, y, z), "Y", "chrome", 20)
        W.cyl("Lamp", r, r * 0.8, 0.03, (x, y + facing * 0.035, z), "Y", kind, 20)


def mark(kind: str, group: str, pts: list):
    """Marker empties for r22_vehicles.gd (see the top of the file)."""
    for i, p in enumerate(pts):
        MARKS.append((kind, "%s_%s_%d" % (kind, group, i + 1), p))


def finish(kind: str, shift_y: float = 0.0, keep: float = 1.0):
    """Bakes and joins everything built since the last finish() into the object `kind`.
    keep < 1: thins its triangles to that share (the woody's parts are finer than a car seen in
    passing needs)."""
    for ob in list(W.EXPORT):
        W.bake(ob)
    for ob in W.CUTTERS:
        bpy.data.objects.remove(ob)
    ob = W.join(list(W.EXPORT), kind)
    # (the joined object keeps its first part's place: move the mesh so the object itself sits
    # at the origin, as r22_vehicles.gd reads the mesh alone)
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    if keep < 1.0:
        ob.modifiers.new("thin", "DECIMATE").ratio = keep
        W.bake(ob)
    if shift_y:
        ob.data.transform(Matrix.Translation((0.0, shift_y, 0.0)))
    W.EXPORT.clear()
    W.CUTTERS.clear()
    DONE.append(ob)
    print("%-18s %6d triangles" % (kind, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    return ob


# ── the long, low cars: the woody's body, as a hardtop sedan or an open convertible ──
def car(kind: str, hardtop: bool):
    W.BODY_LEVELS = 2
    W.build_body()
    W.build_front()
    W.build_rear()
    if hardtop:
        # a roof with a wrap of windows where the woody has its open cabin
        greenhouse("Roof", (0.94, -1.86, 0.875), (0.42, -1.32, 0.76), 0.92, 1.40, side_panes=2, bevel=0.07)
        for sx in (-1.0, 1.0):
            W.rods("MirrorStalk", [[(sx * 0.93, 0.62, 0.975), (sx * 1.02, 0.60, 1.05)]], 0.009, "chrome", 6)
            W.cyl("Mirror", 0.062, 0.055, 0.03, (sx * 1.03, 0.60, 1.07), "Y", "chrome", 16)
    else:
        W.build_cabin()
    for x, y, _z in W.WHEELS:
        wheel(x, y, W.WHEEL_R, 0.21, whitewall=True)
    mark(kind, "LampFront", W.FRONT_LIGHTS)
    mark(kind, "LampTail", W.TAIL_LIGHTS)
    finish(kind, keep=0.4)


# ── the pickup ──
def pickup():
    r = 0.414
    half = 2.80
    floor = 0.71                                       # the bed's floor (the audience sits on it)
    stations = [(half, 0.86, 0.62, 0.98, 1.00), (half - 0.03, 0.92, 0.56, 1.03, 1.05), (2.45, 0.95, 0.48, 1.06, 1.09),
                (1.60, 0.955, 0.44, 1.08, 1.115), (0.95, 0.955, 0.44, 1.09, 1.12), (0.0, 0.955, 0.44, 1.09, 1.10),
                (-0.55, 0.955, 0.44, 1.09, 1.10), (-1.60, 0.955, 0.44, 1.09, 1.10), (-2.50, 0.955, 0.46, 1.09, 1.10),
                (-half + 0.03, 0.94, 0.50, 1.08, 1.09), (-half, 0.90, 0.56, 1.05, 1.06)]
    body = W.hull("Body", stations, 2)
    axles = (1.75, -1.55)
    for wy in axles:
        for sx in (-1.0, 1.0):
            c = W.cyl("cut_arch", r + 0.10, r + 0.10, 0.5, (sx * 0.95, wy, r + 0.02), "X", "dark", 40, export=False)
            W.cut(body, c, "arch")
    # the bed: a tub cut through the tail (the tailgate closes it), the wheel wells left in it
    tub = W.box("cut_bed", (1.70, 2.60, 0.80), (0.0, -1.85, floor + 0.40), "bed", bevel=0.02, export=False)
    W.cut(body, tub, "bed")
    for sx in (-1.0, 1.0):
        well = W.box("WheelWell", (0.22, 1.16, 0.30), (sx * 0.76, axles[1], floor + 0.13), "bed", bevel=0.04)
        hollow = W.cyl("cut_well", r + 0.10, r + 0.10, 0.5, (sx * 0.95, axles[1], r + 0.02), "X", "dark", 40, export=False)
        W.cut(well, hollow, "wheel")
    greenhouse("Cab", (0.98, -0.52, 0.93), (0.50, -0.44, 0.80), 1.05, 1.80, bevel=0.07)
    # the face: a dark grille in a bright frame, two round lamps, the bumpers
    W.box("Grille", (1.16, 0.05, 0.30), (0.0, half - 0.005, 0.86), "dark", bevel=0.01)
    W.rods("GrilleBars", [[(-0.56, half + 0.02, z), (0.56, half + 0.02, z)] for z in (0.76, 0.81, 0.86, 0.91, 0.96)], 0.008, "chrome", 6)
    W.rods("GrilleFrame", [[(-0.60, half + 0.02, 0.71), (0.60, half + 0.02, 0.71), (0.60, half + 0.02, 1.01), (-0.60, half + 0.02, 1.01), (-0.60, half + 0.02, 0.71)]], 0.014, "chrome", 6)
    lamps("lamp_front", [(-0.74, 0.86), (0.74, 0.86)], half - 0.005, 0.095)
    bumper(half + 0.09, 0.53, 1.98, 0.17, 0.14)
    bumper(-half - 0.08, 0.53, 1.98, 0.15, 0.12)
    for sx in (-1.0, 1.0):
        W.box("TailLamp", (0.075, 0.04, 0.26), (sx * 0.905, -half + 0.005, 0.90), "lamp_tail", bevel=0.012)
        W.rods("MirrorStalk", [[(sx * 0.94, 0.80, 1.12), (sx * 1.06, 0.78, 1.22)]], 0.01, "chrome", 6)
        W.box("Mirror", (0.03, 0.12, 0.17), (sx * 1.07, 0.78, 1.25), "chrome", bevel=0.01)
        # the door's shut lines and handle, a bright strip along the flank
        for y in (0.93, -0.47):
            W.decal("Seam", sbox(y - 0.005, 0.50, y + 0.005, 1.07), "dark", body, "X", sx, 0.003, 0.0, 0.04)
        W.decal("Handle", sbox(-0.36, 0.95, -0.20, 0.975), "chrome", body, "X", sx, 0.004, 0.014, 0.03)
        W.decal("Strip", sbox(-1.0, 0.80, 1.2, 0.822), "chrome", body, "X", sx, 0.003, 0.008, 0.05)
    for wy in axles:
        for sx in (-1.0, 1.0):
            wheel(sx * 0.88, wy, r, 0.26)
    mark("pickup", "LampFront", [(-0.74, half + 0.1, 0.86), (0.74, half + 0.1, 0.86)])
    mark("pickup", "LampTail", [(-0.905, -half - 0.05, 0.90), (0.905, -half - 0.05, 0.90)])
    finish("pickup")
    # the tailgate, shut and open (the Drive-In's trucks have it down, on two chains)
    W.box("Gate", (1.69, 0.07, 0.38), (0.0, -half + 0.035, floor + 0.19), "paint", bevel=0.015)
    finish("pickup_gate_up")
    W.box("Gate", (1.69, 0.38, 0.07), (0.0, -half - 0.19, floor - 0.035), "paint", bevel=0.015)
    W.rods("Chains", [[(sx * 0.84, -half + 0.02, floor + 0.34), (sx * 0.84, -half - 0.34, floor)] for sx in (-1.0, 1.0)], 0.006, "dark", 5)
    finish("pickup_gate_down")


# ── the semi: a long-nosed tractor with a sleeper, and its box trailer ──
def semi():
    r = 0.52
    W.box("Frame", (0.9, 8.4, 0.25), (0.0, 5.2, 0.85), "dark")
    W.box("Hood", (1.75, 2.2, 1.0), (0.0, 8.1, 1.55), "paint", bevel=0.15)
    W.box("Grille", (1.25, 0.06, 0.95), (0.0, 9.21, 1.55), "chrome", bevel=0.03)
    W.box("GrilleDark", (1.08, 0.05, 0.80), (0.0, 9.225, 1.55), "dark")
    W.rods("GrilleBars", [[(x, 9.255, 1.16), (x, 9.255, 1.94)] for x in (-0.4, -0.2, 0.0, 0.2, 0.4)], 0.012, "chrome", 6)
    for sx in (-1.0, 1.0):
        W.box("Fender", (0.55, 1.5, 0.36), (sx * 1.0, 8.5, 1.14), "paint", bevel=0.13)
        W.cyl("Tank", 0.30, 0.30, 1.3, (sx * 0.98, 6.0, 0.72), "Y", "chrome", 20, bevel=0.03)
        W.cyl("Stack", 0.075, 0.075, 2.7, (sx * 1.05, 3.70, 2.55), "Z", "chrome", 14)
        W.rods("MirrorArm", [[(sx * 1.17, 6.9, 2.25), (sx * 1.45, 6.95, 2.3), (sx * 1.45, 6.95, 2.75), (sx * 1.17, 6.9, 2.8)]], 0.014, "chrome", 6)
        W.box("Mirror", (0.05, 0.14, 0.36), (sx * 1.47, 6.95, 2.52), "chrome", bevel=0.012)
        W.box("Mudflap", (0.62, 0.03, 0.6), (sx * 0.98, 1.0, 0.72), "dark")
    lamps("lamp_front", [(-1.0, 1.14), (1.0, 1.14)], 9.25, 0.11)
    bumper(9.36, 0.62, 2.45, 0.32, 0.16)
    W.box("CabLower", (2.3, 1.7, 1.15), (0.0, 6.15, 1.5), "paint", bevel=0.06)
    greenhouse("Cab", (7.0, 5.3, 1.15), (6.72, 5.3, 1.08), 2.03, 2.95, panes="FLR", bevel=0.06)
    W.box("Visor", (2.2, 0.28, 0.06), (0.0, 6.86, 2.97), "paint", bevel=0.02)
    for x in (-0.7, -0.35, 0.0, 0.35, 0.7):
        W.box("Marker", (0.09, 0.07, 0.05), (x, 6.74, 3.02), "amber", bevel=0.015)
    W.box("Sleeper", (2.4, 1.5, 2.35), (0.0, 4.55, 2.1), "paint", bevel=0.10)
    W.box("Fairing", (2.3, 1.9, 0.5), (0.0, 4.72, 3.52), "paint", bevel=0.12, rot=(math.radians(-18.0), 0.0, 0.0))
    W.cyl("FifthWheel", 0.5, 0.5, 0.12, (0.0, 2.3, 1.12), "Z", "dark", 20)
    for sx in (-1.0, 1.0):
        wheel(sx * 1.0, 8.5, r, 0.30)
        for wy in (2.9, 1.65):
            wheel(sx * 1.0, wy, r, 0.28, dual=True)
    # the trailer: a ribbed box on a frame, two doors with their lock rods at the back
    y0, y1 = 3.1, -10.1
    mid, length = (y0 + y1) / 2, y0 - y1
    W.box("Trailer", (2.55, length, 2.8), (0.0, mid, 2.75), "trailer", bevel=0.04)
    for z in (1.39, 4.11):
        W.box("Rail", (2.59, length + 0.02, 0.12), (0.0, mid, z), "chrome", bevel=0.01)
    n = 12
    for i in range(1, n):
        W.box("Rib", (2.575, 0.04, 2.66), (0.0, y0 - length * i / n, 2.75), "trailer")
    W.box("DoorSeam", (0.02, 0.02, 2.6), (0.0, y1 - 0.005, 2.75), "dark")
    W.rods("LockRods", [[(x, y1 - 0.025, 1.45), (x, y1 - 0.025, 4.05)] for x in (-0.95, -0.35, 0.35, 0.95)], 0.016, "chrome", 6)
    W.box("Sill", (2.5, 0.10, 0.25), (0.0, y1 + 0.05, 1.25), "dark")
    W.box("Underride", (2.3, 0.08, 0.10), (0.0, y1 + 0.05, 0.62), "dark")
    W.box("Chassis", (1.0, length - 0.8, 0.2), (0.0, mid - 0.3, 1.25), "dark")
    for sx in (-1.0, 1.0):
        W.box("UnderrideLeg", (0.08, 0.08, 0.6), (sx * 0.8, y1 + 0.05, 0.9), "dark")
        W.box("TailLamp", (0.22, 0.04, 0.13), (sx * 1.05, y1 - 0.005, 1.25), "lamp_tail", bevel=0.01)
        W.box("TailLamp", (0.10, 0.04, 0.13), (sx * 0.80, y1 - 0.005, 1.25), "lamp_tail", bevel=0.01)
        W.rods("LandingGear", [[(sx * 0.8, 0.6, 1.3), (sx * 0.8, 0.6, 0.2)]], 0.05, "dark", 8)
        W.box("LandingPad", (0.25, 0.25, 0.04), (sx * 0.8, 0.6, 0.17), "dark")
        W.box("Mudflap", (0.62, 0.03, 0.6), (sx * 0.98, -9.85, 0.72), "dark")
        for wy in (-7.9, -9.15):
            wheel(sx * 1.0, wy, r, 0.28, dual=True)
    shift = 0.35                                       # (centres its 19.5 m on the origin)
    mark("semi", "LampFront", [(-1.0, 9.4 + shift, 1.14), (1.0, 9.4 + shift, 1.14)])
    mark("semi", "LampTail", [(-1.05, y1 - 0.1 + shift, 1.25), (1.05, y1 - 0.1 + shift, 1.25)])
    finish("semi", shift)


# ── the motorhome: a house box behind a van's cab, a bunk over the windscreen ──
def rv():
    r = 0.45
    W.box("House", (2.45, 6.6, 2.5), (0.0, -1.1, 2.05), "cream", bevel=0.12)
    W.box("Bunk", (2.45, 1.6, 1.0), (0.0, 2.75, 2.85), "cream", bevel=0.16)
    W.box("CabLower", (2.1, 1.9, 1.0), (0.0, 3.1, 1.25), "cream", bevel=0.12)
    W.box("Hood", (2.0, 0.95, 0.55), (0.0, 4.03, 1.02), "cream", bevel=0.15)
    greenhouse("Cab", (4.0, 2.2, 1.03), (3.45, 2.2, 0.98), 1.30, 2.40, panes="FLR", material="cream", bevel=0.06)
    W.box("Skirt", (2.3, 6.4, 0.25), (0.0, -1.1, 0.72), "dark")
    # the stripes in the vehicle's colour, the windows, the door on the right
    W.box("Stripe", (2.47, 6.62, 0.14), (0.0, -1.1, 1.52), "paint")
    W.box("Stripe", (2.47, 6.62, 0.06), (0.0, -1.1, 1.72), "paint")
    W.box("StripeCab", (2.12, 1.92, 0.14), (0.0, 3.1, 1.12), "paint")
    for y, wide in ((0.9, 1.2), (-1.1, 1.2), (-3.1, 0.9)):
        W.box("Window", (2.47, wide, 0.62), (0.0, y, 2.45), "glass", bevel=0.01)
    W.box("BunkWindow", (2.47, 0.9, 0.32), (0.0, 2.75, 2.92), "glass", bevel=0.01)
    W.box("Door", (0.03, 0.66, 1.85), (1.225, -0.1, 1.86), "cream", bevel=0.01)
    W.box("DoorWindow", (0.035, 0.4, 0.45), (1.228, -0.1, 2.38), "glass")
    W.box("DoorHandle", (0.04, 0.08, 0.03), (1.24, -0.36, 1.75), "chrome")
    # on the roof: the air conditioner and a vent; the rolled awning; the ladder and spare
    W.box("Aircon", (0.9, 1.0, 0.26), (0.0, -1.5, 3.40), "white", bevel=0.08)
    W.box("Vent", (0.45, 0.45, 0.12), (0.0, -3.3, 3.34), "white", bevel=0.04)
    W.cyl("Awning", 0.075, 0.075, 4.2, (1.27, -1.4, 3.15), "Y", "white", 12)
    W.rods("Ladder", [[(x, -4.43, 0.9), (x, -4.43, 3.3), (x, -4.2, 3.34)] for x in (-0.85, -0.5)]
           + [[(-0.85, -4.43, z), (-0.5, -4.43, z)] for z in (1.3, 1.7, 2.1, 2.5, 2.9)], 0.014, "chrome", 6)
    W.cyl("Spare", 0.38, 0.38, 0.2, (0.35, -4.47, 1.6), "Y", "white", 24, bevel=0.03)
    W.box("Grille", (1.3, 0.05, 0.22), (0.0, 4.49, 1.0), "dark", bevel=0.01)
    lamps("lamp_front", [(-0.82, 1.02), (0.82, 1.02)], 4.49, 0.10)
    bumper(4.56, 0.62, 2.2, 0.20, 0.14)
    bumper(-4.46, 0.62, 2.4, 0.18, 0.12)
    for sx in (-1.0, 1.0):
        W.box("TailLamp", (0.14, 0.04, 0.30), (sx * 1.08, -4.405, 1.10), "lamp_tail", bevel=0.012)
        W.rods("MirrorStalk", [[(sx * 1.04, 3.75, 1.45), (sx * 1.28, 3.8, 1.6)]], 0.012, "chrome", 6)
        W.box("Mirror", (0.04, 0.13, 0.26), (sx * 1.29, 3.8, 1.72), "chrome", bevel=0.012)
        wheel(sx * 0.93, 3.3, r, 0.28)
        wheel(sx * 1.0, -2.6, r, 0.26, dual=True)
    mark("rv", "LampFront", [(-0.82, 4.65, 1.02), (0.82, 4.65, 1.02)])
    mark("rv", "LampTail", [(-1.08, -4.5, 1.10), (1.08, -4.5, 1.10)])
    finish("rv")


# ── the tour bus ──
def bus():
    r = 0.50
    half = 6.0
    body = W.box("Body", (2.55, 2 * half, 2.75), (0.0, 0.0, 2.0), "coach", bevel=0.18)
    axles = ((4.2, False), (-3.4, True), (-4.6, False))
    for wy, _dual in axles:
        for sx in (-1.0, 1.0):
            c = W.cyl("cut_arch", r + 0.10, r + 0.10, 0.7, (sx * 1.2, wy, r), "X", "dark", 32, export=False)
            W.cut(body, c, "arch")
    # the stripe in the vehicle's colour, the band of dark windows with its pillars
    W.box("Stripe", (2.57, 2 * half - 0.5, 0.32), (0.0, 0.0, 1.18), "paint")
    W.box("StripeThin", (2.57, 2 * half - 0.5, 0.07), (0.0, 0.0, 1.46), "paint")
    W.box("Windows", (2.575, 10.4, 0.95), (0.0, -0.35, 2.38), "glass")
    for i in range(1, 8):
        W.box("Pillar", (2.585, 0.07, 0.97), (0.0, 4.85 - 10.4 * i / 8, 2.38), "coach")
    W.box("Windscreen", (2.16, 0.05, 1.45), (0.0, half - 0.01, 2.22), "glass", bevel=0.02)
    W.box("ScreenPost", (0.05, 0.06, 1.45), (0.0, half - 0.008, 2.22), "coach")
    W.box("RearWindow", (1.8, 0.05, 0.7), (0.0, -half + 0.01, 2.5), "glass", bevel=0.02)
    W.box("Door", (0.03, 0.9, 1.95), (1.277, 5.0, 1.78), "glass", bevel=0.01)
    W.box("Aircon", (1.6, 2.6, 0.24), (0.0, -3.0, 3.42), "coach", bevel=0.1)
    # the lamps and bumpers, the mirrors hanging like ears from the front corners
    for sx in (-1.0, 1.0):
        W.box("LampRim", (0.40, 0.04, 0.20), (sx * 0.92, half - 0.01, 0.95), "chrome", bevel=0.02)
        W.box("Lamp", (0.34, 0.05, 0.15), (sx * 0.92, half - 0.005, 0.95), "lamp_front", bevel=0.02)
        W.box("TailLamp", (0.20, 0.05, 0.42), (sx * 1.08, -half + 0.005, 1.05), "lamp_tail", bevel=0.02)
        W.rods("MirrorArm", [[(sx * 1.18, half - 0.2, 3.2), (sx * 1.42, half + 0.2, 3.0), (sx * 1.42, half + 0.2, 2.55)]], 0.018, "dark", 6)
        W.box("Mirror", (0.06, 0.16, 0.36), (sx * 1.42, half + 0.2, 2.42), "dark", bevel=0.02)
    bumper(half + 0.01, 0.72, 2.5, 0.22, 0.10, "dark")
    bumper(-half - 0.01, 0.72, 2.5, 0.22, 0.10, "dark")
    for wy, dual in axles:
        for sx in (-1.0, 1.0):
            wheel(sx * 1.05, wy, r, 0.30, dual=dual)
    mark("bus", "LampFront", [(-0.92, half + 0.12, 0.95), (0.92, half + 0.12, 0.95)])
    mark("bus", "LampTail", [(-1.08, -half - 0.08, 1.05), (1.08, -half - 0.08, 1.05)])
    finish("bus")


# ── the motorcycle and its rider ──
def motorcycle():
    r = 0.34
    front, back = 0.75, -0.80
    wheel(0.0, front, r, 0.11)
    wheel(0.0, back, r, 0.14)
    head = (0.0, 0.42, 1.0)
    W.rods("Forks", [[(sx * 0.075, front, r), (sx * 0.075, 0.47, 0.98)] for sx in (-1.0, 1.0)], 0.022, "chrome", 8)
    W.rods("Bars", [[(-0.36, 0.36, 1.10), (-0.16, 0.44, 1.06), (0.16, 0.44, 1.06), (0.36, 0.36, 1.10)]], 0.014, "chrome", 6)
    W.rods("Grips", [[(sx * 0.36, 0.36, 1.10), (sx * 0.30, 0.385, 1.088)] for sx in (-1.0, 1.0)], 0.02, "seat", 6)
    W.rods("FrameTubes", [[head, (0.0, -0.05, 0.42), (0.0, back, r)], [head, (0.0, -0.5, 0.80), (0.0, back, r)], [(0.0, -0.5, 0.80), (0.0, -0.95, 0.78)]], 0.022, "dark", 8)
    W.box("Engine", (0.30, 0.42, 0.34), (0.0, 0.02, 0.50), "chrome", bevel=0.05)
    for sx in (-1.0, 1.0):
        W.cyl("Cylinder", 0.075, 0.07, 0.24, (sx * 0.02, 0.02 + sx * 0.11, 0.72), "Z", "chrome", 12).rotation_euler = (math.radians(-sx * 22.0), 0.0, 0.0)
    W.rods("Exhaust", [[(0.13, 0.16, 0.48), (0.16, -0.2, 0.36), (0.17, -1.0, 0.42)]], 0.035, "chrome", 8)
    W.box("Tank", (0.30, 0.56, 0.24), (0.0, 0.14, 0.88), "paint", bevel=0.10)
    W.box("Seat", (0.30, 0.62, 0.10), (0.0, -0.46, 0.84), "seat", bevel=0.04)
    W.box("RearFender", (0.17, 0.52, 0.04), (0.0, -0.84, 0.73), "paint", bevel=0.015, rot=(math.radians(8.0), 0.0, 0.0))
    W.box("FrontFender", (0.14, 0.40, 0.035), (0.0, front, 0.71), "paint", bevel=0.012)
    W.cyl("Headlamp", 0.085, 0.07, 0.10, (0.0, 0.60, 0.98), "Y", "chrome", 16)
    W.cyl("HeadlampLens", 0.075, 0.06, 0.02, (0.0, 0.655, 0.98), "Y", "lamp_front", 16)
    W.box("TailLamp", (0.10, 0.04, 0.06), (0.0, -1.10, 0.76), "lamp_tail", bevel=0.01)
    # the rider: jacket, jeans, boots, gloves on the grips, a helmet in the bike's colour
    W.box("Torso", (0.40, 0.25, 0.58), (0.0, -0.30, 1.22), "jacket", bevel=0.10, rot=(math.radians(-16.0), 0.0, 0.0))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.145)
    W.add("Helmet", bm, "helmet").location = (0.0, -0.16, 1.66)
    W.box("Visor", (0.20, 0.03, 0.08), (0.0, -0.03, 1.67), "dark", bevel=0.012)
    for sx in (-1.0, 1.0):
        W.rods("Arm", [[(sx * 0.21, -0.20, 1.42), (sx * 0.31, 0.10, 1.24), (sx * 0.33, 0.34, 1.11)]], 0.055, "jacket", 8)
        W.rods("Leg", [[(sx * 0.13, -0.42, 0.94), (sx * 0.22, 0.02, 0.86), (sx * 0.21, -0.06, 0.44)]], 0.07, "jeans", 8)
        W.box("Boot", (0.10, 0.26, 0.10), (sx * 0.21, 0.0, 0.40), "seat", bevel=0.03)
    mark("motorcycle", "LampFront", [(0.0, 0.80, 0.98)])
    mark("motorcycle", "LampTail", [(0.0, -1.16, 0.76)])
    finish("motorcycle")


def render(folder: str):
    """A picture of each vehicle (not part of the game)."""
    os.makedirs(folder, exist_ok=True)
    glass = W.mat("glass").node_tree.nodes["Principled BSDF"]      # dark, as the game draws it
    glass.inputs["Alpha"].default_value = 1.0
    glass.inputs["Base Color"].default_value = (0.03, 0.04, 0.05, 1.0)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 32
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 1100, 620
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.82, 0.95, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = world
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=200.0)
    ground = bpy.data.objects.new("ground", bpy.data.meshes.new("ground"))
    bm.to_mesh(ground.data)
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.36, 0.26, 1.0)
    ground.data.materials.append(gm)
    sc.collection.objects.link(ground)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(3.0)
    sun.rotation_euler = (math.radians(55.0), 0.0, math.radians(40.0))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50.0
    sc.collection.objects.link(cam)
    sc.camera = cam
    gates = {o.name: o for o in DONE if o.name.startswith("pickup_gate")}
    for ob in DONE:
        ob.hide_render = True
    for ob in DONE:
        if ob.name.startswith("pickup_gate"):
            continue
        ob.hide_render = False
        if ob.name == "pickup":
            gates["pickup_gate_down"].hide_render = False
        size = max(ob.dimensions.y, 3.0)
        for view, (dx, dy) in {"front": (0.75, 1.0), "rear": (-0.75, -1.0)}.items():
            cam.location = (dx * (2.5 + size * 0.75), dy * (2.5 + size * 0.75), 1.6 + size * 0.22)
            look = Vector((0.0, 0.0, ob.dimensions.z * 0.4))
            cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(folder, "%s_%s.png" % (ob.name, view))
            bpy.ops.render.render(write_still=True)
        ob.hide_render = True
        for g in gates.values():
            g.hide_render = True


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    car("classic", True)
    car("convertible", False)
    pickup()
    semi()
    rv()
    bus()
    motorcycle()
    bpy.ops.object.select_all(action="DESELECT")
    by_name = {o.name: o for o in DONE}
    for ob in DONE:
        ob.select_set(True)
    for kind, name, p in MARKS:
        e = bpy.data.objects.new(name, None)
        e.location = p
        bpy.context.scene.collection.objects.link(e)
        e.parent = by_name[kind]
        e.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, "vehicles.glb"), use_selection=True, export_apply=True, export_yup=True,
                              export_tangents=False, export_materials="EXPORT")
    print("wrote vehicles.glb")
    if PREVIEW:
        render(PREVIEW)
