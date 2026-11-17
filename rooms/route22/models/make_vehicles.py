#!/usr/bin/env python3
"""Models Route 22's other vehicles with Blender's Python module and writes vehicles.glb beside
this file: the traffic (pickup, classic sedan, semi, motorhome, tour bus, motorcycle) and the
Drive-In's parked cars (the convertible, the pickup with its tailgate down). Our own designs,
no real makes, no badges; simpler than the Cruise's woody (make_woody.py), whose tools and body
they borrow. Their shapes and proportions were worked out from photos of that time's vehicles
(1950s family sedans, 1960s farm pickups, long-nosed road tractors, old coaches): roofs and
cabs are smooth lofted shapes (canopy) with the windows pressed onto them (glass), not blocks.

    python3 rooms/route22/models/make_vehicles.py [preview folder]

Needs what make_woody.py needs (Python 3.13 with bpy, numpy, scipy, shapely). With a preview
folder it also renders a picture of each vehicle there. Run it again only to change a vehicle;
vehicles.glb is committed.

What r22_vehicles.gd relies on (change both together):
  - One object per vehicle, named by its kind: classic, convertible, pickup, semi, rv, bus,
    motorcycle; plus pickup_gate_up / pickup_gate_down (the pickup's tailgate, shut or open).
  - Blender space as in make_woody.py (X right, Y forward, Z up, ground at z = 0, the vehicle
    centred on the origin); in the game they face -Z.
  - Material names pick each surface's colour and look there (r22_vehicles.gd build_model's
    `looks` table: a new name needs a line there): paint is the vehicle's own colour; ivory a
    cream car paint (the sedan's roof, the motorhome's cab); cream the motorhome's slatted
    house; fluted the coach's bright skirt; trailer ribbed sheet metal; tyre / hub / whitewall
    are the wheels.
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
from shapely.geometry import Polygon, box as sbox

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
    "ivory": (0.82, 0.76, 0.6, 0.0, 0.5), "fluted": (0.7, 0.7, 0.72, 0.8, 0.3),
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


def loft(name: str, rings: list, material: str, levels: int = 2, sharp_rings: dict = {}, sharp_lines: dict = {}):
    """A smooth closed shape through cross-sections from front to back. rings = [(y, half
    section, bow)]: the half section is (x, z) points from the bottom middle round the right
    side to the top middle (the left side mirrors it; every ring needs the same number of
    points); bow pushes the ring's middle forward of its sides by that much (a curved
    windscreen). sharp_rings {ring number: 0..1} keeps that ring a crisp edge through the
    smoothing (a windscreen's header), sharp_lines {point number: 0..1} a line along the shape
    (a roof's gutter)."""
    bm = bmesh.new()
    made = []
    for y, half, bow in rings:
        w = max(max(abs(x) for x, _z in half), 1e-6)
        pts = half + [(-x, z) for x, z in reversed(half[1:-1])]
        made.append([bm.verts.new((x, y + bow * (1.0 - (x / w) ** 2), z)) for x, z in pts])
    n = len(made[0])
    for r0, r1 in zip(made, made[1:]):
        for i in range(n):
            bm.faces.new([r0[i], r0[(i + 1) % n], r1[(i + 1) % n], r1[i]])
    bm.faces.new(made[0])
    bm.faces.new(list(reversed(made[-1])))
    crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    for k, sharp in sharp_rings.items():
        ring = made[k]
        for i in range(n):
            bm.edges.get([ring[i], ring[(i + 1) % n]])[crease] = sharp
    for i, sharp in sharp_lines.items():
        for r0, r1 in zip(made, made[1:]):
            for j in {i, (n - i) % n}:
                bm.edges.get([r0[j], r1[j]])[crease] = sharp
    ob = W.add(name, bm, material)
    ob.modifiers.new("sub", "SUBSURF").levels = levels
    return ob


GUTTER = 3               # roof_section()'s point where the side meets the roof


def roof_section(foot: float, top: float, z0: float, z1: float, crown: float) -> list:
    """Half the cross-section of a cab or a car's roof: `foot` = half width where it stands on
    the body (height z0), `top` = half width at the gutter (the sides lean in), z1 = the roof's
    edge, crown = how much higher its middle is."""
    h = z1 - z0
    return [(0.0, z0), (foot, z0), ((foot + top) / 2 + 0.012, z0 + 0.5 * h), (top, z0 + 0.86 * h), (top * 0.84, z1),
            (top * 0.45, z1 + crown * 0.8), (0.0, z1 + crown)]


def canopy(name: str, spans: list, material: str = "paint", levels: int = 2):
    """A car's roof or a truck's cab as one smooth shape with a raked windscreen: spans =
    [(y, foot, top, z0, z1, crown, bow, sharp)] from the windscreen's foot to the back window's
    foot, each a roof_section() (the first and last are nearly flat: the feet of the glass).
    The windows are laid on afterwards with glass()."""
    rings = [(y, roof_section(foot, top, z0, z1, crown), bow) for y, foot, top, z0, z1, crown, bow, _s in spans]
    sharp = {i: s[7] for i, s in enumerate(spans) if s[7] > 0.0}
    return loft(name, rings, material, levels, sharp, {1: 1.0, GUTTER: 0.35})


def glass(name: str, on, axis: str, side: float, corners: list, round_by: float = 0.04, frame: float = 0.012, posts: tuple = (),
          start_at: float = 0.0, spacing: float = 0.07):
    """A window pressed onto a canopy / body `on`: corners = its outline as W.decal() takes it
    ((y, z) for a side window, axis "X"; (x, z) for a windscreen or back window, axis "Y"),
    its corners rounded by round_by, a bright frame `frame` wide round it (0 = none). posts =
    where upright pillars split it (positions along its width, each 0.05 wide). The glass is
    a dark skin a few millimetres proud of the paint (the game's glass is not see-through)."""
    shape = Polygon(corners).buffer(-round_by).buffer(round_by)
    panes = shape
    for u in posts:
        panes = panes.difference(sbox(u - 0.025, -99.0, u + 0.025, 99.0))
    W.decal(name, panes, "glass", on, axis, side, 0.004, 0.0, spacing, start_at)
    if frame > 0.0:
        W.decal(name + "Frame", panes.buffer(frame * 0.3).difference(panes.buffer(-frame * 0.7)), "chrome", on, axis, side, 0.004, 0.006, spacing * 0.6, start_at)


def slab_section(w: float, z0: float, z1: float, corner: float, crown: float = 0.0, tuck: float = 0.0) -> list:
    """Half the cross-section of a boxy body (a truck's hood, a coach): half width w from z0
    up to z1, its top corners rounded by `corner`, the roof's middle `crown` higher; tuck = how
    much narrower its foot is. Same number of points as roof_section()."""
    return [(0.0, z0), (w - tuck, z0), (w, (z0 + z1) / 2), (w, z1 - corner), (w - corner, z1), (w * 0.45, z1 + crown * 0.8), (0.0, z1 + crown)]


def egg(name: str, size, at, material: str, rot=(0.0, 0.0, 0.0), segs: int = 16):
    """A ball stretched to `size` (full sizes): tanks, helmets, a rider's body."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2 + 2, radius=0.5)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = W.add(name, bm, material)
    ob.location = at
    ob.rotation_euler = rot
    return ob


def guard(name: str, y: float, axle_z: float, r: float, width: float, thick: float, material: str, keep_above: float, x: float = 0.0):
    """A mudguard: the part above height keep_above of a ring of inner radius r round a wheel
    (its axle at (x, y, axle_z))."""
    h = width / 2
    ob = lathe(name, [(-h, r), (-h, r + thick), (h, r + thick), (h, r)], material, 32)
    ob.location = (x, y, axle_z)
    size = 2 * (r + thick) + 0.2
    W.cut(ob, W.box("cut_guard", (width + 0.2, size, size), (x, y, keep_above - size / 2), material, export=False), "below")
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


# ── the long, low cars: the woody's body, as a two-tone sedan or an open convertible ──
def car(kind: str, hardtop: bool):
    W.BODY_LEVELS = 2
    body = W.build_body(open_cabin=not hardtop)
    W.build_front()
    W.build_rear()
    if hardtop:
        # A tall, airy roof in the fashion of the late 1950s (worked out from photos of that
        # time's family sedans): thin pillars, a wrapped windscreen, the roof in cream over
        # the body's colour. About 1.45 m high.
        belt = 0.925
        roof = canopy("Roof", [
            (1.02, 0.85, 0.83, 0.88, belt + 0.01, 0.0, 0.10, 1.0),
            (0.50, 0.85, 0.66, 0.88, 1.41, 0.035, 0.07, 0.6),
            (-0.30, 0.85, 0.68, 0.88, 1.43, 0.045, 0.0, 0.0),
            (-1.12, 0.85, 0.66, 0.88, 1.40, 0.035, -0.05, 0.6),
            (-1.74, 0.85, 0.83, 0.88, belt + 0.01, 0.0, -0.10, 1.0)], "ivory")
        glass("Windscreen", roof, "Y", 1.0, [(-0.77, belt + 0.035), (0.77, belt + 0.035), (0.58, 1.34), (-0.58, 1.34)], 0.05)
        glass("BackWindow", roof, "Y", -1.0, [(-0.74, belt + 0.06), (0.74, belt + 0.06), (0.56, 1.32), (-0.56, 1.32)], 0.06)
        for sx in (-1.0, 1.0):
            # the side windows: front door, back door (a pillar between them), a thick last pillar
            glass("SideWindows", roof, "X", sx, [(0.86, belt + 0.03), (0.47, 1.315), (-1.02, 1.315), (-1.38, belt + 0.03)], 0.04, posts=(-0.34,))
            W.rods("MirrorStalk", [[(sx * 0.93, 0.62, 0.975), (sx * 1.02, 0.60, 1.05)]], 0.009, "chrome", 6)
            W.cyl("Mirror", 0.062, 0.055, 0.03, (sx * 1.03, 0.60, 1.07), "Y", "chrome", 16)
            # the back door's shut line and handle (the woody's body has the front door's)
            W.decal("Seam", sbox(-1.42, 0.50, -1.412, 0.925), "dark", body, "X", sx, 0.0125, 0.0, 0.03)
            W.decal("Handle", sbox(-1.36, 0.845, -1.18, 0.872).buffer(0.008), "chrome", body, "X", sx, 0.012, 0.016, 0.02)
    else:
        W.build_cabin()
    for x, y, _z in W.WHEELS:
        wheel(x, y, W.WHEEL_R, 0.21, whitewall=True)
    mark(kind, "LampFront", W.FRONT_LIGHTS)
    mark(kind, "LampTail", W.TAIL_LIGHTS)
    finish(kind, keep=0.4)


# ── the pickup ──
def pickup():
    """A plain, square-shouldered farm truck in the fashion of the late 1960s: a high flat
    hood, an upright face, a short tall cab, a long bed. 5.5 m long, 1.8 m high."""
    r = 0.40
    nose, tail = 2.70, -2.80                           # (the tail and bed stay where the built-in-code truck has them: seats)
    floor = 0.71                                       # the bed's floor (the audience sits on it)
    belt = 1.10
    # y, half width, underside, shoulder, top middle: slab sides, the hood nearly level
    stations = [(nose, 0.91, 0.60, 1.03, 1.045), (nose - 0.03, 0.945, 0.52, 1.06, 1.075), (2.40, 0.955, 0.46, 1.08, 1.10),
                (1.60, 0.955, 0.44, 1.09, 1.115), (0.95, 0.955, 0.44, belt, 1.125), (0.0, 0.955, 0.44, belt, 1.11),
                (-0.55, 0.955, 0.44, belt, 1.11), (-1.60, 0.955, 0.44, belt, 1.11), (-2.50, 0.955, 0.46, belt, 1.11),
                (tail + 0.03, 0.945, 0.50, 1.09, 1.10), (tail, 0.91, 0.56, 1.06, 1.07)]
    body = W.hull("Body", stations, 2)
    axles = (1.80, -1.55)
    for wy in axles:
        for sx in (-1.0, 1.0):
            c = W.cyl("cut_arch", r + 0.11, r + 0.11, 0.5, (sx * 0.95, wy, r + 0.03), "X", "dark", 40, export=False)
            W.cut(body, c, "arch")
    # the bed: a tub cut through the tail (the tailgate closes it), the wheel wells left in it
    tub = W.box("cut_bed", (1.70, 2.60, 0.80), (0.0, -1.85, floor + 0.40), "bed", bevel=0.02, export=False)
    W.cut(body, tub, "bed")
    for sx in (-1.0, 1.0):
        well = W.box("WheelWell", (0.22, 1.16, 0.30), (sx * 0.76, axles[1], floor + 0.13), "bed", bevel=0.04)
        hollow = W.cyl("cut_well", r + 0.11, r + 0.11, 0.5, (sx * 0.95, axles[1], r + 0.03), "X", "dark", 40, export=False)
        W.cut(well, hollow, "wheel")
    # the cab: an upright windscreen, a flat back wall with its window right behind the seat
    cab = canopy("Cab", [
        (0.98, 0.90, 0.88, 1.04, belt + 0.01, 0.0, 0.07, 1.0),
        (0.66, 0.90, 0.76, 1.04, 1.74, 0.03, 0.05, 0.7),
        (0.10, 0.90, 0.77, 1.04, 1.755, 0.04, 0.0, 0.0),
        (-0.42, 0.90, 0.76, 1.04, 1.74, 0.03, 0.0, 0.8),
        (-0.53, 0.90, 0.88, 1.04, belt + 0.01, 0.0, 0.0, 1.0)])
    glass("Windscreen", cab, "Y", 1.0, [(-0.80, belt + 0.05), (0.80, belt + 0.05), (0.68, 1.66), (-0.68, 1.66)], 0.05)
    glass("BackWindow", cab, "Y", -1.0, [(-0.62, belt + 0.16), (0.62, belt + 0.16), (0.56, 1.62), (-0.56, 1.62)], 0.06)
    for sx in (-1.0, 1.0):
        # the door glass with its little vent window at the front
        glass("SideWindow", cab, "X", sx, [(0.86, belt + 0.04), (0.64, 1.64), (-0.34, 1.64), (-0.40, belt + 0.04)], 0.04, posts=(0.50,))
    # the face: a wide dark grille in a bright frame with the lamps in its ends, the bumpers
    W.box("Grille", (1.72, 0.05, 0.30), (0.0, nose - 0.005, 0.84), "dark", bevel=0.01)
    W.rods("GrilleBars", [[(-0.62, nose + 0.02, z), (0.62, nose + 0.02, z)] for z in (0.75, 0.80, 0.84, 0.88, 0.93)], 0.008, "chrome", 6)
    W.rods("GrilleFrame", [[(-0.86, nose + 0.02, 0.69), (0.86, nose + 0.02, 0.69), (0.86, nose + 0.02, 0.99), (-0.86, nose + 0.02, 0.99), (-0.86, nose + 0.02, 0.69)]], 0.016, "chrome", 6)
    lamps("lamp_front", [(-0.74, 0.84), (0.74, 0.84)], nose - 0.005, 0.095)
    bumper(nose + 0.09, 0.53, 1.98, 0.17, 0.14)
    bumper(tail - 0.08, 0.53, 1.98, 0.15, 0.12)
    W.decal("Seam_Hood", sbox(-0.80, 1.02, 0.80, 2.62).buffer(-0.06).buffer(0.06).exterior.buffer(0.005), "dark", body, "Z", 1.0, 0.002, 0.0, 0.04)
    for sx in (-1.0, 1.0):
        W.box("TailLamp", (0.075, 0.04, 0.26), (sx * 0.905, tail + 0.005, 0.90), "lamp_tail", bevel=0.012)
        W.rods("MirrorStalk", [[(sx * 0.94, 0.80, 1.14), (sx * 1.06, 0.78, 1.24)]], 0.01, "chrome", 6)
        W.box("Mirror", (0.03, 0.12, 0.17), (sx * 1.07, 0.78, 1.27), "chrome", bevel=0.01)
        # the door's shut lines and handle, the gap between cab and bed, a bright strip along the flank
        for y in (0.93, -0.47):
            W.decal("Seam", sbox(y - 0.005, 0.50, y + 0.005, 1.08), "dark", body, "X", sx, 0.003, 0.0, 0.04)
        W.decal("BedGap", sbox(-0.575, 0.46, -0.555, 1.09), "dark", body, "X", sx, 0.003, 0.0, 0.04)
        W.decal("Handle", sbox(-0.36, 0.97, -0.20, 0.995), "chrome", body, "X", sx, 0.004, 0.014, 0.03)
        for y0, y1 in ((-2.62, -2.12), (-0.98, 1.22), (2.38, 2.62)):          # (broken by the wheel arches)
            W.decal("Strip", sbox(y0, 0.80, y1, 0.822), "chrome", body, "X", sx, 0.003, 0.008, 0.05)
    for wy in axles:
        for sx in (-1.0, 1.0):
            wheel(sx * 0.88, wy, r, 0.26)
    mark("pickup", "LampFront", [(-0.74, nose + 0.1, 0.84), (0.74, nose + 0.1, 0.84)])
    mark("pickup", "LampTail", [(-0.905, tail - 0.05, 0.90), (0.905, tail - 0.05, 0.90)])
    finish("pickup", keep=0.7)
    # the tailgate, shut and open (the Drive-In's trucks have it down, on two chains)
    W.box("Gate", (1.69, 0.07, 0.38), (0.0, tail + 0.035, floor + 0.19), "paint", bevel=0.015)
    finish("pickup_gate_up")
    W.box("Gate", (1.69, 0.38, 0.07), (0.0, tail - 0.19, floor - 0.035), "paint", bevel=0.015)
    W.rods("Chains", [[(sx * 0.84, tail + 0.02, floor + 0.34), (sx * 0.84, tail - 0.34, floor)] for sx in (-1.0, 1.0)], 0.006, "dark", 5)
    finish("pickup_gate_down")


# ── the semi: a long-nosed tractor with a sleeper, and its box trailer ──
def semi():
    r = 0.52
    W.box("Frame", (0.9, 8.4, 0.25), (0.0, 5.2, 0.85), "dark")
    # the long nose: a hood that narrows to a tall bright grille, a round mudguard over each
    # front wheel with the lamp on a pod beside it
    hood = loft("Hood", [(y, slab_section(w, 1.0, z1, 0.14, 0.05), 0.0) for y, w, z1 in
                         ((9.22, 0.60, 1.96), (9.19, 0.62, 1.99), (8.2, 0.72, 2.03), (7.2, 0.86, 2.06), (6.9, 0.90, 2.06))],
                "paint", 2, {0: 1.0}, {1: 1.0})
    W.box("Grille", (1.12, 0.06, 0.96), (0.0, 9.235, 1.50), "chrome", bevel=0.03)
    W.box("GrilleDark", (0.96, 0.05, 0.80), (0.0, 9.25, 1.50), "dark")
    W.rods("GrilleBars", [[(x, 9.28, 1.11), (x, 9.28, 1.89)] for x in (-0.36, -0.24, -0.12, 0.0, 0.12, 0.24, 0.36)], 0.012, "chrome", 6)
    for y in (8.75, 8.45, 8.15):
        W.decal("HoodVent", sbox(y, 1.35, y + 0.05, 1.75), "dark", hood, "X", 1.0, 0.003, 0.0, 0.05)
        W.decal("HoodVent", sbox(y, 1.35, y + 0.05, 1.75), "dark", hood, "X", -1.0, 0.003, 0.0, 0.05)
    for sx in (-1.0, 1.0):
        guard("Fender", 8.5, r, r + 0.07, 0.46, 0.05, "paint", r + 0.10, sx * 1.0)
        W.cyl("LampPod", 0.13, 0.11, 0.26, (sx * 0.86, 9.12, 1.30), "Y", "chrome", 20, bevel=0.03)
        W.cyl("AirCleaner", 0.17, 0.17, 0.62, (sx * 1.02, 7.25, 1.75), "Z", "chrome", 20, bevel=0.04)
        W.cyl("Tank", 0.30, 0.30, 1.3, (sx * 0.98, 6.0, 0.72), "Y", "chrome", 20, bevel=0.03)
        W.box("Step", (0.30, 0.9, 0.05), (sx * 1.05, 6.0, 1.05), "chrome", bevel=0.01)
        W.cyl("Stack", 0.075, 0.075, 2.9, (sx * 1.12, 5.22, 2.45), "Z", "chrome", 14)
        W.rods("MirrorArm", [[(sx * 1.12, 6.75, 2.2), (sx * 1.40, 6.8, 2.25), (sx * 1.40, 6.8, 2.75), (sx * 1.08, 6.75, 2.8)]], 0.014, "chrome", 6)
        W.box("Mirror", (0.05, 0.14, 0.40), (sx * 1.42, 6.8, 2.50), "chrome", bevel=0.012)
        W.box("Mudflap", (0.62, 0.03, 0.6), (sx * 0.98, 1.0, 0.72), "dark")
    W.cyl("LampFront", 0.105, 0.085, 0.03, (0.86, 9.26, 1.30), "Y", "lamp_front", 20)
    W.cyl("LampFront", 0.105, 0.085, 0.03, (-0.86, 9.26, 1.30), "Y", "lamp_front", 20)
    bumper(9.40, 0.66, 2.45, 0.34, 0.16)
    # the cab: narrow and upright, a two-piece windscreen under a peak, five marker lamps
    W.box("CabLower", (2.14, 1.62, 1.12), (0.0, 6.10, 1.51), "paint", bevel=0.06)
    cab = canopy("Cab", [
        (6.93, 1.05, 1.03, 1.90, 2.08, 0.0, 0.03, 1.0),
        (6.80, 1.05, 0.98, 1.90, 2.86, 0.03, 0.02, 0.8),
        (6.00, 1.05, 0.99, 1.90, 2.88, 0.05, 0.0, 0.0),
        (5.34, 1.05, 0.98, 1.90, 2.86, 0.03, 0.0, 0.8),
        (5.29, 1.05, 1.03, 1.90, 2.08, 0.0, 0.0, 1.0)])
    glass("Windscreen", cab, "Y", 1.0, [(-0.90, 2.14), (0.90, 2.14), (0.86, 2.74), (-0.86, 2.74)], 0.04, posts=(0.0,), start_at=8.0)
    for sx in (-1.0, 1.0):
        glass("SideWindow", cab, "X", sx, [(6.74, 2.10), (6.72, 2.74), (5.95, 2.74), (5.95, 2.10)], 0.04, posts=(6.50,), start_at=sx * 1.6)
        W.decal("DoorSeam", sbox(5.86, 1.05, 6.80, 2.06).exterior.buffer(0.006), "dark", cab, "X", sx, 0.003, 0.0, 0.05, sx * 1.6)
    W.box("Visor", (2.0, 0.26, 0.05), (0.0, 6.92, 2.84), "paint", bevel=0.015, rot=(math.radians(-12.0), 0.0, 0.0))
    for x in (-0.7, -0.35, 0.0, 0.35, 0.7):
        W.box("Marker", (0.09, 0.07, 0.05), (x, 6.70, 2.93), "amber", bevel=0.015)
    # the sleeper: a flat-topped box behind the cab, a little window in each side
    W.box("Sleeper", (2.30, 1.45, 2.30), (0.0, 4.55, 2.08), "paint", bevel=0.10)
    for sx in (-1.0, 1.0):
        W.box("SleeperWindow", (0.02, 0.42, 0.30), (sx * 1.152, 4.55, 2.70), "glass", bevel=0.005)
        W.box("SleeperTrim", (0.012, 1.30, 0.04), (sx * 1.152, 4.55, 1.55), "chrome")
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
    mark("semi", "LampFront", [(-0.86, 9.4 + shift, 1.30), (0.86, 9.4 + shift, 1.30)])
    mark("semi", "LampTail", [(-1.05, y1 - 0.1 + shift, 1.25), (1.05, y1 - 0.1 + shift, 1.25)])
    finish("semi", shift, keep=0.6)


# ── the motorhome: a house box behind a van's cab, a bunk over the windscreen ──
def rv():
    r = 0.45
    W.box("House", (2.45, 6.6, 2.5), (0.0, -1.1, 2.05), "cream", bevel=0.12)
    W.box("Bunk", (2.45, 1.6, 1.0), (0.0, 2.75, 2.85), "cream", bevel=0.16)
    # the van it is built on: a short sloping nose, the windscreen raked up to the bunk
    van = W.hull("Van", [(4.52, 0.90, 0.66, 1.16, 1.18), (4.49, 0.95, 0.58, 1.20, 1.22), (4.0, 1.0, 0.52, 1.27, 1.30),
                         (3.3, 1.02, 0.50, 1.30, 1.33), (1.8, 1.02, 0.50, 1.30, 1.33)], 2, "ivory")   # (its back end is inside the house)
    for sx in (-1.0, 1.0):
        W.cut(van, W.cyl("cut_arch", r + 0.10, r + 0.10, 0.5, (sx * 1.0, 3.3, r + 0.02), "X", "dark", 32, export=False), "arch")
    cab = canopy("Cab", [
        (4.02, 0.96, 0.94, 1.22, 1.32, 0.0, 0.08, 1.0),
        (3.50, 0.96, 0.88, 1.22, 2.40, 0.0, 0.05, 0.7),
        (1.95, 0.96, 0.88, 1.22, 2.40, 0.0, 0.0, 0.0),
        (1.85, 0.96, 0.94, 1.22, 1.32, 0.0, 0.0, 1.0)], "ivory")
    glass("Windscreen", cab, "Y", 1.0, [(-0.84, 1.42), (0.84, 1.42), (0.72, 2.24), (-0.72, 2.24)], 0.06, start_at=5.0)
    for sx in (-1.0, 1.0):
        glass("CabWindow", cab, "X", sx, [(3.80, 1.40), (3.46, 2.20), (2.42, 2.20), (2.42, 1.40)], 0.05, posts=(3.30,))
        # the cab door's shut lines (the front one stops above the wheel arch)
        W.decal("CabDoor", sbox(2.34, 0.62, 2.352, 1.27).union(sbox(3.42, 1.06, 3.432, 1.27)), "dark", van, "X", sx, 0.003, 0.0, 0.05)
    W.box("Skirt", (2.3, 6.4, 0.25), (0.0, -1.1, 0.72), "dark")
    # the stripes in the vehicle's colour, the windows, the door on the right
    W.box("Stripe", (2.47, 6.62, 0.14), (0.0, -1.1, 1.52), "paint")
    W.box("Stripe", (2.47, 6.62, 0.06), (0.0, -1.1, 1.72), "paint")
    for sx in (-1.0, 1.0):
        W.decal("StripeCab", sbox(2.2, 1.02, 4.45, 1.14), "paint", van, "X", sx, 0.003, 0.0, 0.06)
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
    W.box("Grille", (1.2, 0.05, 0.24), (0.0, 4.50, 0.93), "dark", bevel=0.01)
    W.rods("GrilleBars", [[(-0.58, 4.53, z), (0.58, 4.53, z)] for z in (0.86, 0.93, 1.0)], 0.008, "chrome", 6)
    lamps("lamp_front", [(-0.74, 0.93), (0.74, 0.93)], 4.50, 0.10)
    bumper(4.60, 0.60, 2.1, 0.18, 0.14)
    bumper(-4.46, 0.62, 2.4, 0.18, 0.12)
    for sx in (-1.0, 1.0):
        W.box("TailLamp", (0.14, 0.04, 0.30), (sx * 1.08, -4.405, 1.10), "lamp_tail", bevel=0.012)
        W.rods("MirrorStalk", [[(sx * 0.98, 3.75, 1.40), (sx * 1.28, 3.8, 1.6)]], 0.012, "chrome", 6)
        W.box("Mirror", (0.04, 0.13, 0.26), (sx * 1.29, 3.8, 1.72), "chrome", bevel=0.012)
        wheel(sx * 0.93, 3.3, r, 0.28)
        wheel(sx * 1.0, -2.6, r, 0.26, dual=True)
    mark("rv", "LampFront", [(-0.74, 4.65, 0.93), (0.74, 4.65, 0.93)])
    mark("rv", "LampTail", [(-1.08, -4.5, 1.10), (1.08, -4.5, 1.10)])
    finish("rv", keep=0.7)


# ── the tour bus ──
def bus():
    """An old long-distance coach: a rounded silver body, a raked two-piece windscreen, a long
    row of windows over a stripe in the bus's colour. 12 m long, 3.3 m high."""
    r = 0.50
    half = 6.0
    # rings from the nose back: the upright nose below the windscreen, the raked screen up to
    # the roof, the long middle, the rounded tail
    rings = [(half, slab_section(1.16, 0.50, 1.86, 0.10, 0.0, 0.03), 0.10),
             (half - 0.05, slab_section(1.22, 0.42, 1.90, 0.10, 0.0, 0.03), 0.10),
             (half - 0.62, slab_section(1.275, 0.40, 3.22, 0.30, 0.08, 0.03), 0.05),
             (half - 1.6, slab_section(1.275, 0.40, 3.26, 0.30, 0.10, 0.03), 0.0),
             (-half + 1.2, slab_section(1.275, 0.40, 3.26, 0.30, 0.10, 0.03), 0.0),
             (-half + 0.25, slab_section(1.25, 0.44, 3.20, 0.32, 0.08, 0.03), -0.05),
             (-half, slab_section(1.12, 0.60, 2.95, 0.34, 0.05, 0.03), -0.10)]
    body = loft("Body", rings, "coach", 2, {1: 0.8, 2: 0.5}, {1: 1.0})
    axles = ((4.0, False), (-3.4, True), (-4.6, False))
    for wy, _dual in axles:
        for sx in (-1.0, 1.0):
            c = W.cyl("cut_arch", r + 0.10, r + 0.10, 0.7, (sx * 1.2, wy, r), "X", "dark", 32, export=False)
            W.cut(body, c, "arch")
    glass("Windscreen", body, "Y", 1.0, [(-1.02, 2.02), (1.02, 2.02), (0.98, 3.02), (-0.98, 3.02)], 0.08, posts=(0.0,), start_at=7.0, spacing=0.10)
    glass("RearWindow", body, "Y", -1.0, [(-0.85, 2.15), (0.85, 2.15), (0.80, 2.80), (-0.80, 2.80)], 0.08, start_at=-7.0, spacing=0.10)
    W.decal("Sign", sbox(-0.55, 1.58, 0.55, 1.80).buffer(-0.03).buffer(0.03), "dark", body, "Y", 1.0, 0.004, 0.0, 0.08, 7.0)
    for sx in (-1.0, 1.0):
        # the row of windows (the door's glass at the front of the right side), the stripes
        posts = tuple(4.25 - 1.18 * i for i in range(1, 8))
        glass("Windows", body, "X", sx, [(4.25, 2.02), (4.25, 2.86), (-5.10, 2.86), (-5.10, 2.02)], 0.07, posts=posts, spacing=0.12)
        glass("FrontWindow", body, "X", sx, [(5.35, 2.02), (4.95, 2.86), (4.40, 2.86), (4.40, 2.02)], 0.07, spacing=0.10)
        W.decal("Stripe", sbox(-5.6, 1.50, 5.6, 1.82), "paint", body, "X", sx, 0.003, 0.0, 0.15)
        W.decal("StripeThin", sbox(-5.6, 1.36, 5.6, 1.43), "paint", body, "X", sx, 0.003, 0.0, 0.15)
        skirt = sbox(-5.6, 0.62, 5.6, 1.26)            # the bright fluted skirt, open round the wheel arches
        for wy, _dual in axles:
            skirt = skirt.difference(W.circle(wy, r, r + 0.14))
        W.decal("Flutes", skirt, "fluted", body, "X", sx, 0.003, 0.0, 0.15)
        for i, y in enumerate((2.6, 0.2, -1.6)):
            W.decal("LockerSeam", sbox(y, 0.66, y + 1.5, 1.22).exterior.buffer(0.006), "dark", body, "X", sx, 0.006, 0.0, 0.08)
    W.decal("Door", sbox(4.50, 0.55, 5.30, 1.98).exterior.buffer(0.007), "dark", body, "X", 1.0, 0.006, 0.0, 0.06)
    W.box("Aircon", (1.5, 2.4, 0.22), (0.0, -3.0, 3.40), "coach", bevel=0.09)
    # the lamps and bumpers, the mirrors on arms at the front corners
    for sx in (-1.0, 1.0):
        for x in (0.70, 0.94):
            W.cyl("LampRim", 0.105, 0.10, 0.06, (sx * x, half + 0.02, 1.02), "Y", "chrome", 20)
            W.cyl("Lamp", 0.088, 0.07, 0.03, (sx * x, half + 0.05, 1.02), "Y", "lamp_front", 20)
        W.box("TailLamp", (0.16, 0.06, 0.40), (sx * 0.92, -half - 0.04, 1.25), "lamp_tail", bevel=0.02)
        W.rods("MirrorArm", [[(sx * 1.22, half - 0.55, 2.60), (sx * 1.45, half - 0.35, 2.60)]], 0.016, "chrome", 6)
        W.box("Mirror", (0.05, 0.16, 0.38), (sx * 1.47, half - 0.35, 2.52), "chrome", bevel=0.02)
    bumper(half + 0.06, 0.62, 2.40, 0.22, 0.14)
    bumper(-half - 0.08, 0.72, 2.30, 0.20, 0.12)
    for wy, dual in axles:
        for sx in (-1.0, 1.0):
            wheel(sx * 1.05, wy, r, 0.30, dual=dual)
    mark("bus", "LampFront", [(-0.82, half + 0.15, 1.02), (0.82, half + 0.15, 1.02)])
    mark("bus", "LampTail", [(-0.92, -half - 0.12, 1.25), (0.92, -half - 0.12, 1.25)])
    finish("bus", keep=0.6)


# ── the motorcycle and its rider ──
def motorcycle():
    """A big touring twin of the 1960s, low and long, its rider sitting upright."""
    r = 0.33
    front, back = 0.82, -0.78
    wheel(0.0, front, r, 0.10)
    wheel(0.0, back, r, 0.13)
    guard("FrontFender", front, r, r + 0.025, 0.14, 0.012, "paint", r + 0.12)
    guard("RearFender", back, r, r + 0.03, 0.18, 0.012, "paint", r - 0.02)
    head = (0.0, 0.40, 0.98)
    W.rods("Forks", [[(sx * 0.085, front, r), (sx * 0.085, 0.45, 0.98)] for sx in (-1.0, 1.0)], 0.024, "chrome", 8)
    W.rods("Bars", [[(-0.38, 0.22, 1.12), (-0.26, 0.36, 1.10), (-0.10, 0.42, 1.02), (0.10, 0.42, 1.02), (0.26, 0.36, 1.10), (0.38, 0.22, 1.12)]], 0.013, "chrome", 6)
    W.rods("Grips", [[(sx * 0.38, 0.22, 1.12), (sx * 0.33, 0.28, 1.115)] for sx in (-1.0, 1.0)], 0.02, "seat", 6)
    W.rods("FrameTubes", [[head, (0.0, 0.22, 0.34), (0.0, -0.42, 0.30), (0.0, back, r)], [head, (0.0, -0.36, 0.78), (0.0, back, r)]], 0.022, "dark", 8)
    # the engine: a V of two finned cylinders on a round case, the pipes sweeping back
    W.cyl("Case", 0.17, 0.17, 0.30, (0.0, -0.02, 0.40), "X", "chrome", 20, bevel=0.03)
    W.cyl("Gearbox", 0.12, 0.12, 0.26, (0.0, -0.30, 0.40), "X", "chrome", 16, bevel=0.03)
    for lean, y in ((-24.0, 0.07), (24.0, -0.11)):
        c = W.cyl("Cylinder", 0.075, 0.07, 0.30, (0.0, y - math.sin(math.radians(lean)) * 0.14, 0.66), "Z", "dark", 14)
        c.rotation_euler = (math.radians(lean), 0.0, 0.0)
        h = W.cyl("Head", 0.085, 0.07, 0.06, (0.0, y - math.sin(math.radians(lean)) * 0.30, 0.80), "Z", "chrome", 14)
        h.rotation_euler = (math.radians(lean), 0.0, 0.0)
    W.cyl("AirFilter", 0.085, 0.085, 0.05, (0.17, -0.02, 0.66), "X", "chrome", 16, bevel=0.015)
    W.rods("Exhaust", [[(0.12, 0.16, 0.66), (0.17, 0.24, 0.46), (0.19, 0.0, 0.30), (0.20, -0.5, 0.30)], [(0.12, -0.2, 0.66), (0.18, -0.3, 0.42), (0.20, -0.5, 0.40)]], 0.024, "chrome", 8)
    W.rods("Mufflers", [[(0.20, -0.5, 0.30), (0.21, -1.12, 0.33)], [(0.20, -0.5, 0.40), (0.21, -1.08, 0.44)]], 0.042, "chrome", 10)
    egg("Tank", (0.34, 0.62, 0.27), (0.0, 0.10, 0.88), "paint", (math.radians(4.0), 0.0, 0.0))
    egg("Seat", (0.34, 0.62, 0.17), (0.0, -0.42, 0.80), "seat")
    egg("Pillion", (0.30, 0.34, 0.13), (0.0, -0.78, 0.78), "seat")
    for sx in (-1.0, 1.0):
        W.box("Saddlebag", (0.16, 0.50, 0.32), (sx * 0.23, -0.86, 0.56), "seat", bevel=0.05)
        W.rods("Shock", [[(sx * 0.12, back, r), (sx * 0.12, -0.52, 0.72)]], 0.02, "chrome", 6)
        W.box("Footboard", (0.12, 0.30, 0.02), (sx * 0.25, 0.12, 0.28), "dark", bevel=0.008)
    W.cyl("Headlamp", 0.10, 0.08, 0.14, (0.0, 0.60, 0.98), "Y", "chrome", 16, bevel=0.02)
    W.cyl("HeadlampLens", 0.088, 0.07, 0.02, (0.0, 0.675, 0.98), "Y", "lamp_front", 16)
    W.box("TailLamp", (0.10, 0.04, 0.06), (0.0, -1.14, 0.60), "lamp_tail", bevel=0.01)
    # the rider: jacket, jeans, boots on the footboards, gloves on the grips, a helmet in the
    # bike's colour with a dark visor
    lean_back = math.radians(-8.0)
    egg("Torso", (0.44, 0.27, 0.62), (0.0, -0.36, 1.20), "jacket", (lean_back, 0.0, 0.0))
    egg("Hips", (0.38, 0.30, 0.26), (0.0, -0.40, 0.92), "jeans")
    egg("Helmet", (0.27, 0.30, 0.28), (0.0, -0.30, 1.66), "helmet")
    W.cyl("Neck", 0.055, 0.055, 0.10, (0.0, -0.31, 1.50), "Z", "jacket", 10)
    egg("Visor", (0.22, 0.10, 0.11), (0.0, -0.185, 1.66), "dark")
    for sx in (-1.0, 1.0):
        W.rods("UpperArm", [[(sx * 0.22, -0.32, 1.42), (sx * 0.31, -0.12, 1.20)]], 0.060, "jacket", 8)
        W.rods("Forearm", [[(sx * 0.31, -0.12, 1.20), (sx * 0.36, 0.20, 1.13)]], 0.050, "jacket", 8)
        egg("Elbow", (0.13, 0.13, 0.13), (sx * 0.31, -0.12, 1.20), "jacket", segs=10)
        egg("Shoulder", (0.15, 0.15, 0.15), (sx * 0.22, -0.32, 1.42), "jacket", segs=10)
        egg("Glove", (0.10, 0.12, 0.09), (sx * 0.365, 0.22, 1.125), "seat", segs=10)
        W.rods("Thigh", [[(sx * 0.13, -0.42, 0.90), (sx * 0.24, 0.02, 0.80)]], 0.080, "jeans", 8)
        W.rods("Shin", [[(sx * 0.24, 0.02, 0.80), (sx * 0.25, 0.10, 0.36)]], 0.062, "jeans", 8)
        egg("Knee", (0.17, 0.17, 0.17), (sx * 0.24, 0.02, 0.80), "jeans", segs=10)
        W.box("Boot", (0.10, 0.27, 0.11), (sx * 0.25, 0.15, 0.34), "seat", bevel=0.035)
    mark("motorcycle", "LampFront", [(0.0, 0.80, 0.98)])
    mark("motorcycle", "LampTail", [(0.0, -1.20, 0.60)])
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
        for view, (dx, dy) in {"front": (0.75, 1.0), "rear": (-0.75, -1.0), "side": (1.35, 0.0)}.items():
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
