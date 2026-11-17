#!/usr/bin/env python3
"""Models the Route 22 Cruise's car, the red woody convertible, with Blender's Python module and
writes woody.glb beside this file. Our own design after the style of Sen's reference sheet (a
long, low 1960s American convertible with wood-panelled sides); no real make, no badges.

    python3 rooms/route22/models/make_woody.py [preview folder]

Needs Python 3.13 with `bpy` (Blender as a module: pip install bpy), numpy, scipy and shapely.
With a preview folder it also renders a few pictures there (Cycles on the CPU, a minute or so).
Run it again only to change the car; woody.glb is committed.

What r22_car.gd relies on (change both together):
  - Blender space here: X = the car's right, Y = forward, Z = up, metres, ground at z = 0, the
    car centred on the origin. The glTF export turns that into Godot's (x, z up -> y, forward
    -> -z), so in the game the car faces -Z like every Route 22 vehicle.
  - Material names pick the look in the game (r22_car.gd _materials): paint, wood, trim, chrome,
    glass, leather, pad, carpet, dark, rubber, white, lamp_front, lamp_tail, amber, plate.
  - Object "Wheel" is ONE wheel at the origin, its axle along X, its outer face towards +X;
    r22_car.gd puts a copy on each of WHEELS and spins it. Everything else is the body.
  - Empty marker nodes tell r22_car.gd where things go: Wheel_1..4 (the wheel centres),
    Seat_1..4 (where the four guests sit: front left, front right, back left, back right),
    LampFront_1..4 and LampTail_1..2 (where the lamps glare), PlateWords (the plate's text).
"""
import math
import os
import sys

import bpy  # (first: bmesh and mathutils come with it)
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from scipy.spatial import Delaunay
from shapely.geometry import Point, Polygon, box as sbox

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = sys.argv[1] if len(sys.argv) > 1 else ""

# ── the car's main sizes (metres) ──
HALF_L = 2.69            # half its length (5.38 m, the sheet's 212 in)
WHEEL_R = 0.36
WHEEL_Y = 1.60           # axles this far ahead of / behind the middle (3.2 m wheelbase)
TRACK = 0.84             # wheel centres this far from the middle line
BELT = 0.93              # height of the body's shoulder line
ARCH_R = 0.46            # wheel arch radius

# Blender-space points that r22_car.gd needs (exported as empty marker nodes)
WHEELS = [(sx * TRACK, sy * WHEEL_Y, WHEEL_R) for sy in (1, -1) for sx in (-1, 1)]
SEATS = [(-0.42, 0.20, 0.66), (0.42, 0.20, 0.66), (-0.42, -1.18, 0.69), (0.42, -1.18, 0.69)]
FRONT_LIGHTS = [(x, HALF_L + 0.12, 0.70) for x in (-0.80, -0.61, 0.61, 0.80)]
TAIL_LIGHTS = [(x, -HALF_L - 0.08, 0.72) for x in (-0.86, 0.86)]

# preview colours (the game sets its own materials by these names)
COLORS = {
    "paint": (0.50, 0.03, 0.025, 0.35, 0.3), "wood": (0.36, 0.17, 0.06, 0.0, 0.4), "trim": (0.72, 0.55, 0.30, 0.0, 0.4),
    "chrome": (0.8, 0.8, 0.82, 1.0, 0.12), "glass": (0.6, 0.72, 0.78, 0.0, 0.05), "leather": (0.42, 0.03, 0.03, 0.0, 0.45),
    "pad": (0.03, 0.028, 0.028, 0.0, 0.6), "carpet": (0.05, 0.045, 0.045, 0.0, 0.95),
    "dark": (0.02, 0.02, 0.02, 0.0, 0.8), "rubber": (0.025, 0.025, 0.025, 0.0, 0.9), "white": (0.9, 0.9, 0.88, 0.0, 0.6),
    "lamp_front": (1.0, 0.95, 0.85, 0.0, 0.2), "lamp_tail": (0.7, 0.02, 0.02, 0.0, 0.2), "amber": (1.0, 0.42, 0.04, 0.0, 0.25),
    "plate": (0.9, 0.72, 0.15, 0.0, 0.5),
}
MATS: dict = {}


def mat(name: str) -> bpy.types.Material:
    """The material of that name (name, base colour, metal, roughness from COLORS)."""
    if name not in MATS:
        m = bpy.data.materials.new(name)
        r, g, b, metal, rough = COLORS[name]
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if name == "glass":
            bsdf.inputs["Alpha"].default_value = 0.25
        MATS[name] = m
    return MATS[name]


EXPORT: list = []        # the objects that go into the .glb
CUTTERS: list = []       # boolean cutters (deleted before the export)


def add(name: str, bm: bmesh.types.BMesh, material: str, export: bool = True) -> bpy.types.Object:
    """A new object from a bmesh, with one material, smooth shaded."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(material))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    (EXPORT if export else CUTTERS).append(ob)
    return ob


def box(name: str, size, at, material: str, bevel: float = 0.0, rot=(0.0, 0.0, 0.0), export: bool = True, subsurf: int = 0):
    """A box (full sizes) centred at `at`, turned by rot (radians, XYZ), its edges rounded by `bevel`."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = add(name, bm, material, export)
    ob.location = at
    ob.rotation_euler = rot
    if bevel > 0.0:
        bv = ob.modifiers.new("bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 4
    if subsurf:
        ob.modifiers.new("sub", "SUBSURF").levels = subsurf
    return ob


def cyl(name: str, r0: float, r1: float, depth: float, at, axis: str, material: str, segs: int = 32, export: bool = True, bevel: float = 0.0):
    """A cylinder / cone (r0 at its start, r1 at its end) centred at `at`, along axis 'X', 'Y' or 'Z'."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=depth)
    turn = {"Z": Matrix.Identity(4), "X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(-math.pi / 2, 4, "X")}[axis]
    bmesh.ops.transform(bm, matrix=turn, verts=bm.verts)
    ob = add(name, bm, material, export)
    ob.location = at
    if bevel > 0.0:
        bv = ob.modifiers.new("bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        bv.limit_method = "ANGLE"
    return ob


def rods(name: str, paths: list, radius: float, material: str, segs: int = 10):
    """Round bars along polylines (each a list of points), with a ball at every joint."""
    bm = bmesh.new()
    for pts in paths:
        for i, p in enumerate(pts):
            p = Vector(p)
            bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=6, radius=radius, matrix=Matrix.Translation(p))
            if i == 0:
                continue
            a = Vector(pts[i - 1])
            d = p - a
            m = Matrix.Translation((a + p) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
            bmesh.ops.create_cone(bm, cap_ends=False, segments=segs, radius1=radius, radius2=radius, depth=d.length, matrix=m)
    return add(name, bm, material)


def torus(name: str, major: float, minor: float, at, material: str, rot=(0.0, 0.0, 0.0), arc: float = 2 * math.pi):
    """A ring (or part of one) lying in its own XY plane."""
    bm = bmesh.new()
    n, k = 40, 8
    steps = n if arc >= 2 * math.pi - 1e-6 else int(n * arc / (2 * math.pi)) + 1
    rings = []
    for i in range(steps):
        a = arc * i / (steps if arc >= 2 * math.pi - 1e-6 else steps - 1)
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0.0))
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rings.append([bm.verts.new(c + out * math.cos(b) * minor + Vector((0, 0, math.sin(b) * minor))) for b in [2 * math.pi * j / k for j in range(k)]])
    closed = arc >= 2 * math.pi - 1e-6
    for i in range(steps if closed else steps - 1):
        r0, r1 = rings[i], rings[(i + 1) % steps]
        for j in range(k):
            bm.faces.new([r0[j], r0[(j + 1) % k], r1[(j + 1) % k], r1[j]])
    ob = add(name, bm, material)
    ob.location = at
    ob.rotation_euler = rot
    return ob


# ── the body shell ──
def section(w: float, zb: float, belt: float, top: float) -> list:
    """Half a body cross-section (x, z) from the bottom middle round the right side to the top
    middle: w = half width, zb = underside, belt = shoulder line, top = the middle of the top.
    Point RIDGE is the crease along the flank, point SHOULDER the edge where the side meets the
    top (body_shell keeps both crisp)."""
    h = belt - zb
    return [(0.0, zb), (w * 0.80, zb), (w * 0.972, zb + 0.11 * h), (w * 0.988, zb + 0.42 * h), (w * 1.0, zb + 0.60 * h),
            (w * 0.984, zb + 0.87 * h), (w * 0.957, belt - 0.004), (w * 0.86, belt + 0.012), (w * 0.45, top), (0.0, top)]


RIDGE, SHOULDER = 4, 6   # indexes into section()


BODY_LEVELS = 3          # how finely the hull is smoothed (make_vehicles.py lowers it for the lot's cars)


def hull(name: str, stations: list, levels: int, material: str = "paint"):
    """A smooth hull through cross-sections: stations = [(y, half width, underside, shoulder,
    top middle)] from nose to tail, each made into a section()."""
    bm = bmesh.new()
    rings = []
    for y, w, zb, belt, top in stations:
        half = section(w, zb, belt, top)
        pts = half + [(-x, z) for x, z in reversed(half[1:-1])]
        rings.append([bm.verts.new((x, y, z)) for x, z in pts])
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new([a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]])
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    # the flank's ridge and the shoulder stay crisp lines through the smoothing (both sides:
    # point i on the right is point n - i on the left)
    crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    for a, b in zip(rings, rings[1:]):
        for i, sharp in ((RIDGE, 0.55), (SHOULDER, 0.7)):
            for j in (i, n - i):
                bm.edges.get([a[j], b[j]])[crease] = sharp
    ob = add(name, bm, material)
    ob.modifiers.new("sub", "SUBSURF").levels = levels
    return ob


def body_shell():
    """The car's lower body: one smooth hull from nose to tail (hood, fenders, doors, deck)."""
    # y, half width, underside, shoulder, top middle (the hood and the deck crown slightly)
    stations = [(HALF_L, 0.90, 0.46, 0.80, 0.83), (HALF_L - 0.03, 0.955, 0.40, 0.855, 0.885), (2.50, 0.985, 0.34, 0.895, 0.93),
                (1.95, 0.995, 0.30, 0.915, 0.955), (1.00, 1.0, 0.29, BELT, 0.985), (0.0, 1.0, 0.29, BELT, 0.955),
                (-1.20, 1.0, 0.29, BELT + 0.005, 0.96), (-2.10, 0.99, 0.31, 0.92, 0.945), (-2.55, 0.975, 0.35, 0.90, 0.92),
                (HALF_L * -1 + 0.03, 0.95, 0.40, 0.87, 0.89), (-HALF_L, 0.90, 0.45, 0.82, 0.84)]
    return hull("Body", stations, BODY_LEVELS)


def cut(body, cutter, name: str):
    """Cuts `cutter` out of the body; the cut faces keep the cutter's material."""
    md = body.modifiers.new(name, "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.object = cutter
    md.solver = "EXACT"
    md.material_mode = "TRANSFER"


# ── flat pieces laid onto the body (wood panels, trim, seams, arch lips) ──
def decal(name: str, poly, material: str, body, axis: str, side: float, offset: float, thick: float = 0.0, spacing: float = 0.05):
    """A flat shape pressed onto the body's surface. poly = its outline (shapely, may have
    holes) in (y, z) for a side panel (axis 'X'), (x, z) for one on the tail / nose (axis 'Y') or
    (x, y) for one on the hood / deck (axis 'Z', side +1 = pressed down from above).
    side = +1 / -1: which side of the car it lies on. offset = how far it stands off the paint,
    thick = its own thickness (0 = a skin)."""
    if poly.is_empty:
        return None
    polys = list(poly.geoms) if hasattr(poly, "geoms") else [poly]
    bm = bmesh.new()
    # texture coordinates in metres, U along the grain and V across it (the wood photos' grain
    # runs along their width), so the grain runs along the car on the sides and the deck and
    # across it on the tail (r22_car.gd scales them)
    uv = bm.loops.layers.uv.new("UVMap")
    grain = {"X": lambda u, v: (u, v), "Y": lambda u, v: (u, v), "Z": lambda u, v: (v, u)}[axis]
    for pg in polys:
        pg = pg.segmentize(spacing)
        pts = [c for ring in [pg.exterior] + list(pg.interiors) for c in ring.coords[:-1]]
        x0, y0, x1, y1 = pg.bounds
        inner = pg.buffer(-spacing * 0.6)
        for gx in np.arange(x0, x1, spacing):
            for gy in np.arange(y0, y1, spacing):
                if inner.contains(Point(gx, gy)):
                    pts.append((gx, gy))
        pts = np.array(pts)
        if len(pts) < 3:
            continue
        tri = Delaunay(pts)
        start = {"X": lambda u, v: (side * 1.4, u, v), "Y": lambda u, v: (u, side * 3.2, v), "Z": lambda u, v: (u, v, side * 2.0)}[axis]
        verts = [bm.verts.new(start(u, v)) for u, v in pts]
        for a, b, c in tri.simplices:
            if pg.contains(Point(*(pts[[a, b, c]].mean(axis=0)))):
                face = bm.faces.new([verts[a], verts[b], verts[c]])
                for loop, i in zip(face.loops, (a, b, c)):
                    loop[uv].uv = grain(*pts[i])
    ob = add(name, bm, material)
    sw = ob.modifiers.new("wrap", "SHRINKWRAP")
    sw.target = body
    sw.wrap_method = "PROJECT"
    sw.use_project_x = axis == "X"
    sw.use_project_y = axis == "Y"
    sw.use_project_z = axis == "Z"
    sw.use_negative_direction = side > 0
    sw.use_positive_direction = side < 0
    sw.offset = offset
    if thick > 0.0:
        so = ob.modifiers.new("thick", "SOLIDIFY")
        so.thickness = thick
        so.offset = 1.0
    return ob


def circle(cx: float, cy: float, r: float):
    return Point(cx, cy).buffer(r, resolution=24)


def build_body():
    body = body_shell()
    # the wheel arches (their insides dark) and the open cabin (its walls in the seats' vinyl)
    for sx, sy, _z in [(w[0], w[1], 0) for w in WHEELS]:
        c = cyl("cut_arch", ARCH_R, ARCH_R, 0.9, (math.copysign(0.95, sx), sy, WHEEL_R + 0.02), "X", "dark", 48, export=False)
        cut(body, c, "arch")
    # The rear wheels reach in under the back seat, so each gets a housing: a vinyl-covered hump
    # that shows in the cabin as the block either side of the back seat, hollowed out round the
    # wheel (dark inside, seen through the arch).
    for sx in (-1.0, 1.0):
        hump = box("WheelHump", (0.285, 0.98, 0.47), (sx * 0.7175, -WHEEL_Y, 0.645), "leather", bevel=0.05)
        hollow = cyl("cut_hump", ARCH_R, ARCH_R, 0.6, (sx * 0.90, -WHEEL_Y, WHEEL_R + 0.02), "X", "dark", 48, export=False)
        cut(hump, hollow, "wheel")
    tub = box("cut_cabin", (1.70, 2.56, 1.2), (0.0, -0.44, 1.02), "leather", bevel=0.09, export=False)
    cut(body, tub, "cabin")
    grille = box("cut_grille", (1.78, 0.16, 0.24), (0.0, HALF_L, 0.70), "dark", bevel=0.02, export=False)
    cut(body, grille, "grille")

    # ── the wood: one long panel a side, kicked up over the rear wheel, framed in pale trim ──
    side = Polygon([(1.05, 0.41), (1.05, 0.80), (-0.42, 0.80), (-0.86, 0.905), (-2.52, 0.895), (-2.60, 0.47), (-2.20, 0.41)])
    side = side.difference(circle(-WHEEL_Y, WHEEL_R + 0.02, ARCH_R + 0.075))
    seam_z = (0.33, 0.925)
    for sx, tag in ((1.0, "R"), (-1.0, "L")):
        decal("Wood_" + tag, side.buffer(-0.02), "wood", body, "X", sx, 0.003)
        decal("Trim_" + tag, side.difference(side.buffer(-0.045)), "trim", body, "X", sx, 0.004, 0.007, 0.03)
        # the door's shut lines, the chrome lips round the arches and along the sill, the handle
        for y in (0.98, -0.34):
            decal("Seam_" + tag, sbox(y - 0.004, seam_z[0], y + 0.004, seam_z[1]), "dark", body, "X", sx, 0.0125, 0.0, 0.03)
        for wy in (WHEEL_Y, -WHEEL_Y):
            lip = circle(wy, WHEEL_R + 0.02, ARCH_R + 0.035).difference(circle(wy, WHEEL_R + 0.02, ARCH_R + 0.002)).intersection(sbox(-9, 0.375, 9, 2))
            decal("ArchLip_" + tag, lip, "chrome", body, "X", sx, 0.002, 0.012, 0.025)
        decal("Sill_" + tag, sbox(-WHEEL_Y + ARCH_R + 0.06, 0.34, WHEEL_Y - ARCH_R - 0.06, 0.375), "chrome", body, "X", sx, 0.002, 0.012, 0.04)
        decal("Handle_" + tag, sbox(-0.26, 0.845, -0.08, 0.872).buffer(0.008), "chrome", body, "X", sx, 0.012, 0.016, 0.02)
        # the bright moulding along the top of the door and rear quarter, the door's lock
        decal("BeltBead_" + tag, sbox(sx * 0.874 - 0.012, -1.52, sx * 0.874 + 0.012, 0.86), "chrome", body, "Z", 1.0, 0.001, 0.011, 0.04)
        decal("Lock_" + tag, circle(-0.03, 0.858, 0.013), "chrome", body, "X", sx, 0.012, 0.006, 0.01)
    # the tailgate panel, a plain lozenge emblem in its middle (our own, no make's badge)
    tail = sbox(-0.76, 0.55, 0.76, 0.865)
    decal("Wood_Tail", tail.buffer(-0.02), "wood", body, "Y", -1.0, 0.003)
    decal("Trim_Tail", tail.difference(tail.buffer(-0.045)), "trim", body, "Y", -1.0, 0.004, 0.007, 0.03)
    decal("Emblem", Polygon([(-0.085, 0.715), (0.0, 0.745), (0.085, 0.715), (0.0, 0.685)]), "chrome", body, "Y", -1.0, 0.006, 0.008, 0.02)
    # from above: the hood's shut line and the cowl's vent slots; the deck lid's wood (two panels
    # with a rail between them, as on the sheet's top view) and its shut line
    def outline(x0, y0, x1, y1, wide=0.009):
        shape = sbox(x0, y0, x1, y1).buffer(-0.06).buffer(0.06)
        return shape.difference(shape.buffer(-wide))
    decal("Seam_Hood", outline(-0.80, 1.06, 0.80, 2.60), "dark", body, "Z", 1.0, 0.002, 0.0, 0.03)
    for y in (0.972, 0.990, 1.008, 1.026):
        decal("CowlVent", sbox(-0.62, y, 0.62, y + 0.008), "dark", body, "Z", 1.0, 0.002, 0.0, 0.03)
    deck = sbox(-0.74, -2.56, 0.74, -1.99)
    decal("Wood_Deck", deck.buffer(-0.02), "wood", body, "Z", 1.0, 0.003)
    decal("Trim_Deck", deck.difference(deck.buffer(-0.045)).union(sbox(-0.022, -2.56, 0.022, -1.99)), "trim", body, "Z", 1.0, 0.004, 0.007, 0.03)
    decal("Seam_Deck", outline(-0.81, -2.615, 0.81, -1.945), "dark", body, "Z", 1.0, 0.002, 0.0, 0.03)
    return body


def build_front():
    y = HALF_L
    # the grille: thin bright bars in the dark opening, a brighter frame round it
    bars = []
    for i in range(10):
        z = 0.60 + 0.20 * i / 9.0
        bars.append([(-0.50, y - 0.035, z), (0.50, y - 0.035, z)])
    rods("GrilleBars", bars, 0.005, "chrome", 6)
    box("GrilleCentre", (0.035, 0.03, 0.225), (0.0, y - 0.02, 0.70), "chrome", bevel=0.01)
    rods("GrilleUprights", [[(x, y - 0.03, 0.595), (x, y - 0.03, 0.805)] for x in np.linspace(-0.5, 0.5, 21)], 0.004, "chrome", 5)
    rods("GrilleFrame", [[(-0.885, y + 0.004, 0.585), (0.885, y + 0.004, 0.585), (0.885, y + 0.004, 0.815), (-0.885, y + 0.004, 0.815), (-0.885, y + 0.004, 0.585)]], 0.014, "chrome", 8)
    # four round headlights in chrome rims
    for x in (-0.80, -0.61, 0.61, 0.80):
        cyl("LampRim", 0.092, 0.086, 0.09, (x, y - 0.005, 0.70), "Y", "chrome", 32, bevel=0.006)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=10, radius=0.074)
        bmesh.ops.scale(bm, vec=Vector((1.0, 0.35, 1.0)), verts=bm.verts)
        add("LampLens", bm, "lamp_front").location = (x, y + 0.03, 0.70)
    bumper(y + 0.10, 1.0)
    # the hood's centre crease and a small ornament, the cowl's wiper grille
    rods("HoodSpear", [[(0.0, 2.55, 0.936), (0.0, 1.9, 0.962), (0.0, 1.15, 0.99)]], 0.006, "chrome", 6)
    box("HoodOrnament", (0.014, 0.17, 0.034), (0.0, 2.50, 0.956), "chrome", bevel=0.006, rot=(math.radians(-3.0), 0.0, 0.0))
    for sx in (-1.0, 1.0):
        # amber turn lamps under the headlights, little bright fins on the fender tops
        box("SignalRim", (0.21, 0.02, 0.07), (sx * 0.66, y + 0.0, 0.525), "chrome", bevel=0.008)
        box("Signal", (0.18, 0.03, 0.045), (sx * 0.66, y + 0.008, 0.525), "amber", bevel=0.01)
        box("FenderFin", (0.012, 0.13, 0.026), (sx * 0.86, 2.32, 0.915), "chrome", bevel=0.005)
    # the radio aerial on the right front fender
    cyl("AerialBase", 0.016, 0.01, 0.03, (0.82, 1.30, 0.945), "Z", "chrome", 12)
    rods("Aerial", [[(0.82, 1.30, 0.95), (0.82, 1.27, 1.78)]], 0.0035, "chrome", 5)


def bumper(y: float, facing: float):
    """A chrome bumper across the car at y (its middle), wrapping round the corners, with two guards."""
    box("Bumper", (2.0, 0.11, 0.13), (0.0, y, 0.40), "chrome", bevel=0.035)
    for sx in (-1.0, 1.0):
        box("BumperEnd", (0.09, 0.34, 0.13), (sx * 0.975, y - facing * 0.15, 0.40), "chrome", bevel=0.035)
        box("BumperGuard", (0.07, 0.07, 0.22), (sx * 0.36, y + facing * 0.045, 0.42), "chrome", bevel=0.025)


def build_rear():
    y = -HALF_L
    for sx in (-1.0, 1.0):
        box("TailRim", (0.115, 0.05, 0.30), (sx * 0.86, y + 0.012, 0.72), "chrome", bevel=0.02)
        box("TailLens", (0.075, 0.05, 0.25), (sx * 0.86, y - 0.006, 0.72), "lamp_tail", bevel=0.018)
    bumper(y - 0.10, -1.0)
    box("Plate", (0.34, 0.012, 0.17), (0.0, y - 0.165, 0.40), "plate", bevel=0.004)
    box("PlateFrame", (0.37, 0.012, 0.20), (0.0, y - 0.158, 0.40), "chrome", bevel=0.004)
    # white reversing lamps let into the bumper, the tail pipe under its right end
    for sx in (-1.0, 1.0):
        cyl("ReverseRim", 0.046, 0.046, 0.012, (sx * 0.66, y - 0.156, 0.40), "Y", "chrome", 20)
        cyl("ReverseLens", 0.036, 0.03, 0.02, (sx * 0.66, y - 0.162, 0.40), "Y", "white", 20)
    cyl("TailPipe", 0.032, 0.032, 0.34, (0.56, y + 0.04, 0.275), "Y", "chrome", 16, bevel=0.004)
    cyl("TailPipeHole", 0.024, 0.024, 0.01, (0.56, y - 0.131, 0.275), "Y", "dark", 16)


def build_cabin():
    # the floor's carpet, the dash with its pad, two dials and the glovebox line
    box("Carpet", (1.66, 2.5, 0.02), (0.0, -0.44, 0.435), "carpet")
    box("Dash", (1.68, 0.26, 0.20), (0.0, 0.74, 0.86), "paint", bevel=0.05)
    box("DashPad", (1.68, 0.20, 0.05), (0.0, 0.76, 0.975), "pad", bevel=0.02)
    box("Cluster", (0.46, 0.02, 0.12), (-0.42, 0.605, 0.87), "dark", bevel=0.008)
    for dx in (-0.10, 0.10):
        torus("Dial", 0.05, 0.007, (-0.42 + dx, 0.594, 0.87), "chrome", rot=(math.pi / 2, 0.0, 0.0))
        cyl("DialFace", 0.046, 0.046, 0.004, (-0.42 + dx, 0.596, 0.87), "Y", "white", 20)
    box("Radio", (0.22, 0.02, 0.07), (0.05, 0.605, 0.86), "chrome", bevel=0.006)
    box("RadioDial", (0.13, 0.02, 0.035), (0.05, 0.601, 0.862), "dark", bevel=0.004)
    for x in (-0.085, 0.185, 0.0, 0.05, 0.10, -0.62):       # radio knobs, heater knobs, the light switch
        z = 0.86 if x in (-0.085, 0.185) else 0.805
        cyl("Knob", 0.015, 0.012, 0.03, (x, 0.598, z), "Y", "chrome", 12)
    box("DashStrip", (1.64, 0.012, 0.016), (0.0, 0.607, 0.775), "chrome", bevel=0.004)
    rods("Glovebox", [[(0.36, 0.607, 0.815), (0.74, 0.607, 0.815), (0.74, 0.607, 0.925), (0.36, 0.607, 0.925), (0.36, 0.607, 0.815)]], 0.004, "chrome", 5)
    cyl("GloveboxKnob", 0.012, 0.01, 0.02, (0.55, 0.600, 0.905), "Y", "chrome", 10)
    # the gear selector and the turn stalk on the column, the pedals, the tunnel down the floor
    rods("Selector", [[(-0.42, 0.52, 0.945), (-0.29, 0.50, 0.995)], [(-0.42, 0.54, 0.935), (-0.54, 0.53, 0.955)]], 0.006, "chrome", 6)
    rods("SelectorKnob", [[(-0.285, 0.50, 0.998)], [(-0.545, 0.53, 0.957)]], 0.015, "white", 10)
    box("PedalGas", (0.07, 0.02, 0.15), (-0.27, 0.77, 0.52), "dark", bevel=0.006, rot=(math.radians(-25.0), 0.0, 0.0))
    box("PedalBrake", (0.14, 0.02, 0.08), (-0.47, 0.75, 0.56), "dark", bevel=0.006, rot=(math.radians(-25.0), 0.0, 0.0))
    box("Tunnel", (0.24, 2.3, 0.10), (0.0, -0.36, 0.45), "carpet", bevel=0.045)
    # inside the doors and the rear quarters: armrests, a bright strip, window winders, handles
    for sx in (-1.0, 1.0):
        box("DoorStrip", (0.012, 2.2, 0.018), (sx * 0.843, -0.42, 0.815), "chrome", bevel=0.004)
        box("DoorArmrest", (0.085, 0.44, 0.06), (sx * 0.805, 0.16, 0.715), "leather", bevel=0.024)
        box("DoorPull", (0.02, 0.11, 0.024), (sx * 0.838, 0.42, 0.765), "chrome", bevel=0.008)
        cyl("WinderBoss", 0.022, 0.018, 0.02, (sx * 0.838, 0.55, 0.66), "X", "chrome", 14)
        rods("Winder", [[(sx * 0.826, 0.55, 0.66), (sx * 0.818, 0.60, 0.615)]], 0.006, "chrome", 6)
        rods("WinderKnob", [[(sx * 0.812, 0.60, 0.615)]], 0.013, "white", 8)
    # the steering wheel: a thin ivory rim on a raked column, two spokes and a chrome horn ring
    hub = Vector((-0.42, 0.44, 0.985))
    tilt = math.radians(62.0)                    # the rim's plane leans this far back from flat
    rods("Column", [[(-0.42, 0.66, 0.88), tuple(hub)]], 0.022, "dark")
    torus("WheelRim", 0.185, 0.013, hub, "white", rot=(tilt, 0.0, 0.0))
    torus("HornRing", 0.10, 0.006, hub + Vector((0.0, -0.004, 0.002)), "chrome", rot=(tilt, 0.0, 0.0), arc=math.pi)
    rim_x = Vector((1.0, 0.0, 0.0))
    rods("Spokes", [[tuple(hub - rim_x * 0.18), tuple(hub), tuple(hub + rim_x * 0.18)]], 0.009, "chrome", 6)
    cyl("HubCap", 0.035, 0.03, 0.03, hub, "Y", "paint", 16).rotation_euler = (tilt - math.pi / 2, 0.0, 0.0)
    # seats: two front seats and a rear bench in red vinyl, soft-edged, each with a pleated look
    lean = math.radians(-14.0)
    for sx in (-1.0, 1.0):
        box("SeatFront", (0.74, 0.60, 0.20), (sx * 0.405, 0.20, 0.555), "leather", bevel=0.07)
        box("BackFront", (0.74, 0.15, 0.58), (sx * 0.405, -0.13, 0.88), "leather", bevel=0.065, rot=(lean, 0.0, 0.0))
        # the back of the seat: a stitched panel under a bright strip
        box("SeatBackPanel", (0.60, 0.02, 0.40), (sx * 0.405, -0.209, 0.885), "leather", bevel=0.009, rot=(lean, 0.0, 0.0))
        box("SeatBackStrip", (0.62, 0.014, 0.016), (sx * 0.405, -0.268, 1.10), "chrome", bevel=0.005, rot=(lean, 0.0, 0.0))
        for i in range(5):                          # pleats: slim raised ribs down the back and across the cushion
            x = sx * 0.405 + (i - 2) * 0.125
            box("Pleat", (0.10, 0.03, 0.46), (x, -0.048, 0.89), "leather", bevel=0.014, rot=(lean, 0.0, 0.0))
            box("Pleat", (0.10, 0.44, 0.03), (x, 0.22, 0.668), "leather", bevel=0.014)
    # (the back seat fits between the wheel humps, see build_body)
    box("SeatRear", (1.15, 0.62, 0.22), (0.0, -1.18, 0.575), "leather", bevel=0.075)
    box("BackRear", (1.15, 0.16, 0.60), (0.0, -1.53, 0.90), "leather", bevel=0.07, rot=(lean, 0.0, 0.0))
    for i in range(7):
        x = (i - 3) * 0.14
        box("Pleat", (0.115, 0.03, 0.48), (x, -1.444, 0.91), "leather", bevel=0.014, rot=(lean, 0.0, 0.0))
        box("Pleat", (0.115, 0.46, 0.03), (x, -1.16, 0.70), "leather", bevel=0.014)
    box("Armrest", (0.16, 0.5, 0.10), (0.0, 0.16, 0.66), "leather", bevel=0.04)
    # the folded top under its boot behind the back seat
    box("TopBoot", (1.74, 0.36, 0.13), (0.0, -1.72, 0.995), "pad", bevel=0.06)
    rods("BootSnaps", [[(x, -1.538, 0.985)] for x in np.linspace(-0.74, 0.74, 9)] + [[(x, -1.902, 0.985)] for x in np.linspace(-0.74, 0.74, 9)], 0.011, "chrome", 8)
    # the windscreen: chrome frame, glass, the quarter windows and the mirrors
    bl, br = Vector((-0.865, 0.90, 0.975)), Vector((0.865, 0.90, 0.975))
    tl, tr = Vector((-0.80, 0.50, 1.43)), Vector((0.80, 0.50, 1.43))
    top_mid = Vector((0.0, 0.53, 1.445))
    rods("ScreenFrame", [[tuple(bl), tuple(tl), tuple(top_mid), tuple(tr), tuple(br)]], 0.024, "chrome")
    rods("ScreenBase", [[tuple(bl), (0.0, 0.94, 0.992), tuple(br)]], 0.014, "chrome")
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in (bl, (0.0, 0.94, 0.992), br, tr, top_mid, tl)]
    bm.faces.new(vs)
    add("Screen", bm, "glass")
    for sx in (-1.0, 1.0):
        a = Vector((sx * 0.865, 0.90, 0.975))
        t = Vector((sx * 0.80, 0.50, 1.43))
        post = Vector((sx * 0.885, 0.38, 0.975))
        post_top = Vector((sx * 0.84, 0.38, 1.37))
        rods("VentFrame", [[tuple(post), tuple(post_top), tuple(a.lerp(t, 0.88))]], 0.011, "chrome", 8)
        bm = bmesh.new()
        bm.faces.new([bm.verts.new(p) for p in (a, post, post_top, a.lerp(t, 0.88))])
        add("VentGlass", bm, "glass")
        # door mirrors on short stalks
        rods("MirrorStalk", [[(sx * 0.93, 0.62, 0.975), (sx * 1.02, 0.60, 1.05)]], 0.009, "chrome", 6)
        cyl("Mirror", 0.062, 0.055, 0.03, (sx * 1.03, 0.60, 1.07), "Y", "chrome", 20, bevel=0.008)
    # the sun visors folded up along the top of the glass, the wipers parked along its foot
    for sx in (-1.0, 1.0):
        box("Visor", (0.40, 0.018, 0.11), (sx * 0.42, 0.522, 1.368), "leather", bevel=0.007, rot=(math.radians(41.0), 0.0, 0.0))
    rods("Wipers", [[(-0.50, 0.928, 0.996), (-0.12, 0.812, 1.128)], [(0.15, 0.944, 1.004), (0.53, 0.812, 1.128)]], 0.005, "dark", 5)
    rods("WiperPivots", [[(-0.50, 0.930, 0.994)], [(0.15, 0.946, 1.002)]], 0.012, "chrome", 8)
    rods("InsideMirrorArm", [[(0.0, 0.535, 1.43), (0.0, 0.50, 1.385)]], 0.006, "chrome", 6)
    box("InsideMirror", (0.22, 0.015, 0.06), (0.0, 0.495, 1.37), "chrome", bevel=0.006)


def build_wheel():
    """One wheel at the origin: axle along X, the outside face towards +X."""
    r, half = WHEEL_R, 0.105
    # the tyre's cross-section, spun round the axle: (distance along the axle, radius)
    prof = [(-half, r - 0.135), (-half, r - 0.05), (-half + 0.02, r - 0.012), (-half + 0.05, r)]
    for gx in (-0.03, 0.0, 0.03):                 # three grooves round the tread
        prof += [(gx - 0.005, r), (gx - 0.003, r - 0.009), (gx + 0.003, r - 0.009), (gx + 0.005, r)]
    prof += [(half - 0.05, r), (half - 0.02, r - 0.012), (half, r - 0.05), (half, r - 0.135)]
    def spin(name, profile, material, segs=48):
        bm = bmesh.new()
        rings = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            rings.append([bm.verts.new((x, math.cos(a) * rad, math.sin(a) * rad)) for x, rad in profile])
        for i in range(segs):
            r0, r1 = rings[i], rings[(i + 1) % segs]
            for j in range(len(profile) - 1):
                bm.faces.new([r0[j], r0[j + 1], r1[j + 1], r1[j]])
        return add(name, bm, material)
    parts = [spin("Tyre", prof, "rubber")]
    # the whitewall: a band on the outer sidewall; the steel wheel behind it; the chrome cap
    parts.append(spin("Whitewall", [(half + 0.003, r - 0.125), (half + 0.004, r - 0.075)], "white"))
    parts.append(spin("Steel", [(-half, r - 0.135), (-half + 0.03, 0.0)], "dark"))
    parts.append(spin("Rim", [(half + 0.001, r - 0.135), (half - 0.03, r - 0.14), (half - 0.035, r - 0.18)], "chrome"))
    # the hubcap: a bright outer dish, a ring painted the body's red let into it, a domed centre
    parts.append(spin("Cap", [(half - 0.035, r - 0.18), (half + 0.010, 0.165), (half + 0.016, 0.135), (half + 0.004, 0.128)], "chrome"))
    parts.append(spin("CapRing", [(half + 0.004, 0.128), (half + 0.004, 0.092)], "paint"))
    parts.append(spin("CapDome", [(half + 0.004, 0.092), (half + 0.022, 0.086), (half + 0.040, 0.05), (half + 0.046, 0.0)], "chrome"))
    for ob in parts:
        EXPORT.remove(ob)
    return parts


# ── putting it together ──
def bake(ob):
    """Applies an object's modifiers and marks its sharp edges (so the cut and bevelled edges
    stay crisp and the curved faces shade smooth)."""
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps))
    ob.modifiers.clear()
    ob.data = me
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.set_sharp_from_angle(angle=math.radians(38.0))


def join(objs: list, name: str):
    """Joins objects into one (their materials become its surfaces)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def render(folder: str):
    """A few preview pictures (not part of the game)."""
    os.makedirs(folder, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.82, 0.95, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = world
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60.0)
    ground = bpy.data.objects.new("ground", bpy.data.meshes.new("ground"))
    bm.to_mesh(ground.data)
    gm = bpy.data.materials.new("ground")
    gm.diffuse_color = (0.55, 0.36, 0.26, 1.0)
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
    views = {"front_quarter": ((4.6, 6.2, 2.1), (0.0, 0.3, 0.6)), "side": ((8.5, 0.0, 1.3), (0.0, 0.0, 0.7)),
             "rear_quarter": ((-4.4, -6.4, 2.3), (0.0, -0.3, 0.6)), "cabin": ((1.6, -3.4, 3.0), (0.0, 0.0, 0.8)),
             "front": ((0.0, 8.0, 1.2), (0.0, 0.0, 0.7))}
    for name, (at, look) in views.items():
        cam.location = at
        cam.rotation_euler = (Vector(look) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, "woody_" + name + ".png")
        bpy.ops.render.render(write_still=True)


def markers() -> list:
    """The empty nodes r22_car.gd reads (see the top of the file)."""
    out = []
    groups = {"Wheel": WHEELS, "Seat": SEATS, "LampFront": FRONT_LIGHTS, "LampTail": TAIL_LIGHTS, "PlateWords": [(0.0, -HALF_L - 0.175, 0.40)]}
    for name, pts in groups.items():
        for i, p in enumerate(pts):
            e = bpy.data.objects.new(name + ("_%d" % (i + 1) if len(pts) > 1 else ""), None)
            e.location = p
            bpy.context.scene.collection.objects.link(e)
            out.append(e)
    return out


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = build_body()
    build_front()
    build_rear()
    build_cabin()
    for ob in list(EXPORT):
        bake(ob)
    for ob in CUTTERS:
        bpy.data.objects.remove(ob)
    car = join(list(EXPORT), "Woody")
    wheel_parts = build_wheel()
    for ob in wheel_parts:
        bake(ob)
    wheel = join(wheel_parts, "Wheel")
    print("triangles: body %d, wheel %d" % (sum(len(p.vertices) - 2 for p in car.data.polygons), sum(len(p.vertices) - 2 for p in wheel.data.polygons)))
    bpy.ops.object.select_all(action="DESELECT")
    car.select_set(True)
    wheel.select_set(True)
    for e in markers():
        e.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, "woody.glb"), use_selection=True, export_apply=True, export_yup=True,
                              export_tangents=False, export_materials="EXPORT")
    print("wrote woody.glb")
    if PREVIEW:
        # the wheel four times, for the pictures only
        for x, y, z in WHEELS:
            w = bpy.data.objects.new("w", wheel.data)
            w.location = (x, y, z)
            if x < 0:
                w.rotation_euler = (0.0, 0.0, math.pi)
            bpy.context.scene.collection.objects.link(w)
        wheel.hide_render = True
        render(PREVIEW)
