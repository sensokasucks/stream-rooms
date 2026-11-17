#!/usr/bin/env python3
"""Makes the Drive-In's modelled props (its "Detailed" set look): models/props.glb.

The Drive-In's set is the Blender model drive_in.glb, whose small things are plain blocks. On the
Detailed look drive_in_room.gd (_build_detailed_props) hides those blocks and puts these models
in their places instead; the Simple look keeps the blocks. Every model is original, built from
simple shapes in code with the Route 22 woody's tools (rooms/route22/models/make_woody.py: box,
cyl, rods, torus, bake, join), so nothing is downloaded.

    python3 rooms/drive_in/models/make_props.py [preview folder]

Needs Blender as a Python module (pip install bpy; the woody's tools also import shapely).
Pass a folder to also get a preview render of each prop (not part of the game).

The models (one mesh each; Blender +Y = the prop's front, which is -Z in the game; the ground
or the floor it stands on is z = 0; metres):
  speaker_post   the in-car speaker post: a steel post on a concrete footing, a junction box
                 and two speakers on hooks, one each side (left and right of the front), their
                 grilles facing outwards to the cars parked either side, with curly cords
  light_pole     a 9 m lot light: tapered steel pole on a concrete footing, an arm reaching
                 1 m forwards and a floodlight shade with its glowing lens facing down
  wall_lamp      the small lamp under the snack bar's canopy: a shade and its lens, facing down
  lawn_chair     a folding aluminium lawn chair with green and white webbing and wooden arm rests
  cooler         a picnic cooler: rounded body, white lid, chrome handles and latch
  popcorn        a striped popcorn bucket, heaped with popcorn
Their surfaces are named by material (post, concrete, speaker, grille, chrome, cord, steel,
shade, lamp_glow, alu, web_a, web_b, armrest, cooler, white, stripe_red, stripe_white,
popcorn); the game gives each its own look by that name (drive_in_room.gd PROP_LOOKS), so the
colours here only matter for the preview.
"""
import math
import os
import random
import sys

import bpy  # (first: bmesh and mathutils come with it)
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "route22", "models"))
import make_woody as W  # noqa: E402  (the shared tools)

PREVIEW = sys.argv[1] if len(sys.argv) > 1 else ""

# preview colours (name: r, g, b, metal, roughness); the game sets its own by name
W.COLORS.update({
    "post": (0.16, 0.22, 0.18, 0.3, 0.55), "concrete": (0.55, 0.54, 0.5, 0.0, 0.95), "speaker": (0.62, 0.64, 0.62, 0.6, 0.4),
    "grille": (0.05, 0.05, 0.05, 0.3, 0.6), "cord": (0.02, 0.02, 0.02, 0.0, 0.7), "steel": (0.3, 0.32, 0.33, 0.5, 0.5),
    "shade": (0.25, 0.3, 0.28, 0.5, 0.45), "lamp_glow": (1.0, 0.9, 0.7, 0.0, 0.3), "alu": (0.8, 0.8, 0.8, 1.0, 0.3),
    "web_a": (0.12, 0.45, 0.25, 0.0, 0.7), "web_b": (0.9, 0.9, 0.86, 0.0, 0.7), "armrest": (0.45, 0.28, 0.14, 0.0, 0.6),
    "cooler": (0.2, 0.5, 0.65, 0.0, 0.4), "stripe_red": (0.7, 0.05, 0.05, 0.0, 0.5), "stripe_white": (0.92, 0.9, 0.85, 0.0, 0.5),
    "popcorn": (0.98, 0.88, 0.6, 0.0, 0.8),
})

DONE: list = []


def finish(name: str):
    """Bakes and joins everything built since the last finish() into one object `name`, its mesh
    placed so the object sits at the origin (the game reads the mesh alone)."""
    for ob in list(W.EXPORT):
        W.bake(ob)
    for ob in W.CUTTERS:
        bpy.data.objects.remove(ob)
    ob = W.join(list(W.EXPORT), name)
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    W.EXPORT.clear()
    W.CUTTERS.clear()
    DONE.append(ob)
    print("%-14s %6d triangles" % (name, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    return ob


def coil(name: str, start, end, turns: int, radius: float, material: str):
    """A curly phone-style cord from start to end (a helix round the straight line between)."""
    a, b = Vector(start), Vector(end)
    d = (b - a)
    side = d.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    up = side.cross(d.normalized())
    pts = []
    steps = turns * 5
    for i in range(steps + 1):
        t = i / steps
        ang = 2 * math.pi * turns * t
        sag = Vector((0.0, 0.0, -0.08 * math.sin(math.pi * t)))      # the cord hangs a little
        pts.append(tuple(a + d * t + sag + (side * math.cos(ang) + up * math.sin(ang)) * radius))
    return tube(name, pts, 0.0045, material)


def tube(name: str, pts: list, radius: float, material: str, segs: int = 4):
    """A thin bar along a polyline with no balls at its joints (lighter than W.rods for the
    cords: there are 111 speaker posts, so every triangle counts 222 times)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        p = Vector(p)
        d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        side = d.orthogonal().normalized()
        up = d.cross(side)
        rings.append([bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radius)
                      for a in [2 * math.pi * k / segs for k in range(segs)]])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new([r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]])
    return W.add(name, bm, material)


# ── the speaker post ──
def speaker(side: float):
    """One speaker hanging on the post's side `side` (+1 = right, -1 = left), grille outwards."""
    x = side * 0.155
    W.box("Speaker", (0.085, 0.24, 0.27), (x, 0.0, 1.0), "speaker", bevel=0.022)
    W.EXPORT[-1].modifiers["bevel"].segments = 2
    W.box("Grille", (0.012, 0.19, 0.19), (x + side * 0.042, 0.0, 0.985), "grille")
    # a chrome frame round the grille and the volume knob below it
    for dz in (-0.1, 0.07):
        W.box("Bar", (0.01, 0.2, 0.012), (x + side * 0.048, 0.0, 0.985 + dz + 0.015), "chrome")
    W.cyl("Knob", 0.018, 0.016, 0.02, (x + side * 0.05, 0.075, 0.9), "X", "chrome", 12)
    # the hook it hangs on, from the junction box over the speaker's top
    tube("Hook", [(side * 0.05, 0.0, 1.13), (x, 0.0, 1.16), (x, 0.0, 1.135)], 0.008, "chrome", 5)
    coil("Cord", (x - side * 0.03, -0.06, 0.87), (side * 0.04, -0.03, 0.78), 7, 0.012, "cord")


def speaker_post():
    W.cyl("Footing", 0.17, 0.15, 0.12, (0.0, 0.0, 0.03), "Z", "concrete", 12)
    W.cyl("Plate", 0.07, 0.07, 0.015, (0.0, 0.0, 0.095), "Z", "post", 12)
    W.cyl("Post", 0.033, 0.03, 1.0, (0.0, 0.0, 0.6), "Z", "post", 14)
    W.box("Junction", (0.11, 0.1, 0.16), (0.0, 0.0, 1.06), "post")
    W.box("Cap", (0.14, 0.13, 0.025), (0.0, 0.0, 1.155), "post")
    W.cyl("Conduit", 0.016, 0.016, 0.06, (0.0, -0.055, 0.98), "Y", "post", 10)
    speaker(1.0)
    speaker(-1.0)
    finish("speaker_post")


# ── the lot lights ──
def flood(at, glow_down: bool = True, size: float = 1.0):
    """A floodlight shade with its lens facing down, its top at `at`."""
    x, y, z = at
    W.cyl("Shade", 0.08 * size, 0.33 * size, 0.24 * size, (x, y, z - 0.12 * size), "Z", "shade", 24)
    # (create_cone puts radius1 at the bottom: flip so the wide end is down)
    W.EXPORT[-1].rotation_euler = (math.pi, 0.0, 0.0)
    W.cyl("Lens", 0.3 * size, 0.3 * size, 0.02 * size, (x, y, z - 0.245 * size), "Z", "lamp_glow", 24)
    W.cyl("Cowl", 0.09 * size, 0.09 * size, 0.08 * size, (x, y, z + 0.02 * size), "Z", "shade", 14)


def light_pole():
    W.cyl("Footing", 0.36, 0.32, 0.5, (0.0, 0.0, 0.2), "Z", "concrete", 20, bevel=0.02)
    W.box("Plate", (0.34, 0.34, 0.03), (0.0, 0.0, 0.465), "steel")
    for sx in (-1, 1):
        for sy in (-1, 1):
            W.cyl("Bolt", 0.018, 0.018, 0.06, (sx * 0.13, sy * 0.13, 0.49), "Z", "chrome", 8)
    W.cyl("Pole", 0.13, 0.07, 8.4, (0.0, 0.0, 0.48 + 4.2), "Z", "steel", 8)
    W.box("Handhole", (0.02, 0.1, 0.22), (0.0, 0.0, 0.0), "steel", bevel=0.005)
    W.EXPORT[-1].location = (0.0, -0.125, 1.1)
    W.box("ServiceBox", (0.22, 0.14, 0.3), (0.0, -0.17, 2.6), "steel", bevel=0.015)
    W.cyl("Cap", 0.09, 0.05, 0.12, (0.0, 0.0, 8.94), "Z", "steel", 8)
    # the arm curving out forwards (+Y) to the floodlight
    arm = [(0.0, 0.0, 8.55), (0.0, 0.35, 8.82), (0.0, 0.75, 8.95), (0.0, 0.95, 8.96)]
    W.rods("Arm", [arm], 0.035, "steel", segs=10)
    W.rods("Brace", [[(0.0, 0.0, 8.2), (0.0, 0.45, 8.8)]], 0.018, "steel", segs=8)
    flood((0.0, 0.95, 8.96))
    finish("light_pole")


def wall_lamp():
    W.cyl("Stem", 0.012, 0.012, 0.12, (0.0, 0.0, -0.06), "Z", "chrome", 8)
    flood((0.0, 0.0, -0.1), size=0.45)
    finish("wall_lamp")


# ── on the truck bed ──
def lawn_chair():
    """A folding aluminium chair (front = +Y), 0.56 wide, seat 0.36 up, its back leaning back."""
    w = 0.27                            # half width
    seat_f, seat_b, seat_z = 0.22, -0.2, 0.36
    back_top = (-0.36, 0.86)            # (y, z) the back frame's top
    tubes = []
    for sx in (-w, w):
        # the side frame: front leg up to the seat, along to the back, up the back
        tubes.append([(sx, seat_f + 0.04, 0.0), (sx, seat_f, seat_z), (sx, seat_b, seat_z), (sx, back_top[0], back_top[1])])
        # the rear leg, from the floor behind up to the arm rest
        tubes.append([(sx, -0.28, 0.0), (sx, 0.0, 0.42), (sx, 0.12, 0.58)])
        # the arm rest support from the front leg
        tubes.append([(sx, seat_f, seat_z), (sx, 0.2, 0.58)])
    # cross bars
    tubes.append([(-w, seat_f, seat_z), (w, seat_f, seat_z)])
    tubes.append([(-w, seat_b, seat_z), (w, seat_b, seat_z)])
    tubes.append([(-w, back_top[0], back_top[1]), (w, back_top[0], back_top[1])])
    tubes.append([(-w, seat_f + 0.04, 0.0), (-w, -0.28, 0.0)])
    tubes.append([(w, seat_f + 0.04, 0.0), (w, -0.28, 0.0)])
    W.rods("Frame", tubes, 0.011, "alu", segs=8)
    for sx in (-w, w):
        W.box("Armrest", (0.07, 0.38, 0.02), (sx, 0.04, 0.595), "armrest", bevel=0.006)
    # the webbing: straps across the seat and up the back, alternating colours, slightly sagging
    straps = 7
    for i in range(straps):
        t = (i + 0.5) / straps
        y = seat_f + (seat_b - seat_f) * t
        sag = -0.025 * math.sin(math.pi * 0.5) * (1.0 - abs(t - 0.5))
        W.box("SeatStrap", (2 * w, 0.045, 0.006), (0.0, y, seat_z + sag), "web_a" if i % 2 else "web_b")
    back_len = math.hypot(back_top[0] - seat_b, back_top[1] - seat_z)
    tilt = math.atan2(-(back_top[0] - seat_b), back_top[1] - seat_z)      # leaning back
    for i in range(8):
        t = (i + 0.5) / 8
        y = seat_b + (back_top[0] - seat_b) * t
        z = seat_z + (back_top[1] - seat_z) * t
        W.box("BackStrap", (2 * w, 0.006, back_len / 8 * 0.8), (0.0, y - 0.004, z), "web_b" if i % 2 else "web_a", rot=(tilt, 0.0, 0.0))
    for sx in (-w * 0.5, w * 0.5):        # two long straps running front to back over the others
        W.box("LongStrap", (0.045, seat_f - seat_b, 0.007), (sx, (seat_f + seat_b) / 2, seat_z + 0.004), "web_a")
    finish("lawn_chair")


def cooler():
    """A picnic cooler 0.66 long (x), 0.46 deep, 0.43 high; front = +Y."""
    W.box("Body", (0.66, 0.46, 0.34), (0.0, 0.0, 0.17), "cooler", bevel=0.05)
    W.box("Lid", (0.68, 0.48, 0.09), (0.0, 0.0, 0.385), "white", bevel=0.035)
    W.box("Lip", (0.67, 0.47, 0.02), (0.0, 0.0, 0.335), "white", bevel=0.008)
    for sx in (-1, 1):
        W.rods("Handle", [[(sx * 0.33, -0.1, 0.27), (sx * 0.37, -0.1, 0.28), (sx * 0.37, 0.1, 0.28), (sx * 0.33, 0.1, 0.27)]], 0.009, "chrome", segs=6)
        W.box("Pivot", (0.03, 0.04, 0.05), (sx * 0.335, 0.0, 0.27), "chrome", bevel=0.006)
    W.box("Latch", (0.08, 0.02, 0.07), (0.0, 0.235, 0.33), "chrome", bevel=0.006)
    W.cyl("Drain", 0.018, 0.018, 0.02, (0.24, 0.235, 0.05), "Y", "chrome", 10)
    W.box("Band", (0.665, 0.465, 0.03), (0.0, 0.0, 0.06), "white", bevel=0.012)
    finish("cooler")


def popcorn():
    """A striped popcorn bucket (0.3 high, wider at the top) heaped with popcorn."""
    segs = 24
    r0, r1, h = 0.105, 0.155, 0.28
    for i in range(segs):
        bm = bmesh.new()
        a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
        quad = [(r0, a0, 0.0), (r0, a1, 0.0), (r1, a1, h), (r1, a0, h)]
        vs = [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, a, z in quad]
        bm.faces.new(vs)
        # (a thin wall: the inside face too, so it shows from above)
        vi = [bm.verts.new((r * 0.97 * math.cos(a), r * 0.97 * math.sin(a), z)) for r, a, z in reversed(quad)]
        bm.faces.new(vi)
        W.add("Stripe", bm, "stripe_red" if (i // 2) % 2 else "stripe_white")
    W.cyl("Bottom", r0, r0, 0.01, (0.0, 0.0, 0.005), "Z", "stripe_white", segs)
    W.torus("Rim", r1, 0.007, (0.0, 0.0, h), "stripe_white")
    rnd = random.Random(7)
    bm = bmesh.new()
    for i in range(70):
        # a heap: kernels piled up to 0.09 above the rim, most in the middle
        rr = r1 * 0.95 * math.sqrt(rnd.random())
        a = rnd.random() * 2 * math.pi
        z = h - 0.03 + 0.09 * (1.0 - (rr / r1) ** 2) * rnd.uniform(0.6, 1.0)
        size = rnd.uniform(0.016, 0.024)
        m = Matrix.Translation((rr * math.cos(a), rr * math.sin(a), z)) @ Matrix.Diagonal((size, size * rnd.uniform(0.7, 1.1), size * rnd.uniform(0.7, 1.0), 1.0))
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
    for v in bm.verts:                  # lumpy, not round
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * 0.004
    W.add("Popcorn", bm, "popcorn")
    finish("popcorn")


def render(folder: str):
    """A preview picture of each prop (not part of the game)."""
    os.makedirs(folder, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 700, 700
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.82, 0.95, 1.0)
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(30.0))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for ob in DONE:
        ob.hide_render = True
    for ob in DONE:
        ob.hide_render = False
        size = max(ob.dimensions)
        mid = Vector((0.0, 0.0, ob.dimensions.z * 0.5))
        if ob.name == "light_pole":            # the top only
            mid = Vector((0.0, 0.4, 8.6))
            size = 1.6
        cam.location = mid + Vector((1.2, 1.6, 0.8)).normalized() * size * 2.0
        cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, ob.name + ".png")
        bpy.ops.render.render(write_still=True)
        ob.hide_render = True


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    speaker_post()
    light_pole()
    wall_lamp()
    lawn_chair()
    cooler()
    popcorn()
    bpy.ops.object.select_all(action="DESELECT")
    for ob in DONE:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, "props.glb"), use_selection=True, export_apply=True, export_yup=True,
                              export_tangents=False, export_materials="EXPORT")
    print("wrote props.glb")
    if PREVIEW:
        render(PREVIEW)
