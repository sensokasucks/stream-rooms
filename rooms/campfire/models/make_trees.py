#!/usr/bin/env python3
"""Models the Lakeside Campfire's detailed trees in Blender and writes everything the game needs
next to this file and in ../textures/. Our own procedural trees (no add-on, no downloaded
model); the twig pictures are drawn here, the fir and pine needle pictures are the room's
existing CC0 cards (textures/card_fir.png, card_pine.png, from Poly Haven photos).

    python3 rooms/campfire/models/make_trees.py [preview folder]

Needs Python 3.13 with `bpy` (Blender as a module: pip install bpy), numpy and scipy.
Takes a few minutes on the CPU (the far-tree pictures are rendered with Cycles). Run it again
only to change a tree; the results are committed. With a preview folder it also writes a sheet
of every tree's far-tree pictures there.

The idea (Sen's Blender forest tutorial, made to work in a game): the trees are modelled once
as real branching meshes with leaf "twig cards", in two levels of detail, and each one is also
photographed from eight sides into a picture sheet. The game draws a tree near the camera
with the full mesh, further out with the light one, and far away as one flat picture that
turns to face the camera (an "impostor": two triangles instead of a few thousand).
campfire_forest.gd does that part.

What it writes (campfire_forest.gd relies on all of it; change both together):
  trees.glb   one mesh object per species and level: fir_lod0, fir_lod1, young_fir_lod0, ...,
              for SPECIES below. Each is 1 unit tall, foot at the origin (the room scales it,
              like the low-poly trees). Surfaces by material name:
                trunk          bark: UV.x = the bark number camp_prop.gdshader knows (1 pine,
                               5 oak, 6 birch), vertex colour = the bark's colour
                needles_fir, needles_pine, twigs_oak, twigs_maple, twigs_birch
                               the cards: UV = the card picture, vertex colour rgb = shade
                               (darker inside the crown), normals point out of the crown
              Vertex colour alpha everywhere = how far the wind moves it (0 at the foot, 1 at
              the top), as camp_foliage.gdshader and camp_prop.gdshader expect.
  ../textures/twig_oak.png, twig_maple.png, twig_birch.png
              see-through pictures of a leafy twig (stem end at the bottom middle), drawn here
  ../textures/impostor_color.png   the far-tree pictures: one row per species (SPECIES order),
              IMPOSTOR_FRAMES columns, each frame the tree seen from one side (frame k from
              the angle k / IMPOSTOR_FRAMES of a turn round it; see camp_impostor.gdshader).
              rgb = colour, unlit; alpha = coverage.
  ../textures/impostor_normal.png  the same frames: rgb = the surface's direction in the
              tree's own space (Godot axes, 0.5 = 0), alpha = 1 on leaves, 0 on bark (so
              autumn colours only touch the leaves).

Blender space here: X right, Y forward, Z up. The glTF export turns Z up into Godot's Y up.
"""
import math
import os
import random
import sys

import bpy  # (first: bmesh and mathutils come with it)
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.normpath(os.path.join(HERE, "..", "textures"))
PREVIEW = sys.argv[1] if len(sys.argv) > 1 else ""

# The species, in the order of the impostor rows (campfire_forest.gd SPECIES must match).
SPECIES = ["fir", "young_fir", "pine", "oak", "maple", "birch"]
# Far-tree pictures: frames round each tree, pixels per frame, and the frame's size in tree
# units (it shows x from -IMP_HALF to +IMP_HALF and y from 0 to 2 * IMP_HALF).
IMPOSTOR_FRAMES = 8
IMP_PX = 256
IMP_HALF = 0.6

# The bark numbers camp_prop.gdshader knows (campfire_builder.gd MAT_ constants).
BARK_PINE = 1.0
BARK_OAK = 5.0
BARK_BIRCH = 6.0
# The card picture each species' leaves use (material name -> picture file in ../textures).
CARD_PICTURE = {"needles_fir": "card_fir.png", "needles_pine": "card_pine.png",
                "twigs_oak": "twig_oak.png", "twigs_maple": "twig_maple.png", "twigs_birch": "twig_birch.png"}
# The tint each card material gets in the game (camp_foliage.gdshader `tint`, set by
# campfire_forest.gd); the far-tree pictures are rendered with it so near and far match.
CARD_TINT = {"needles_fir": (0.82, 0.95, 0.85), "needles_pine": (0.9, 1.0, 0.85),
             "twigs_oak": (1.0, 1.0, 1.0), "twigs_maple": (1.0, 1.0, 1.0), "twigs_birch": (1.0, 1.0, 1.0)}
# The alpha below which a card's pixel is not drawn (camp_foliage.gdshader `cut`).
CUT = 0.33


def lerp(a, b, t):
    return a + (b - a) * t


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# ═══════════════════════════════════════════════════════════════════
# Part 1: the twig pictures (oak, maple, birch)
# ═══════════════════════════════════════════════════════════════════

def leaf_outline(species: str, rnd: random.Random) -> list:
    """One leaf's outline in leaf space: the stalk end at (0, 0), the tip at (0, 1); x across.
    Our own simple shapes: a lobed oak leaf, a five-pointed maple leaf, a toothed birch leaf."""
    pts = []
    if species == "maple":
        # palmate: a polar outline round a point a third up, five main points
        centre = Vector((0.0, 0.42))
        n = 90
        for i in range(n):
            a = -math.pi / 2 + 2 * math.pi * i / n          # start at the stalk
            # five lobes pointing up, up-left, up-right, left, right; a notch at the stalk
            lobe = abs(math.cos(2.5 * (a - math.pi / 2))) ** 1.6
            side = 1.0 - 0.45 * max(0.0, -math.sin(a))      # smaller towards the stalk
            r = (0.22 + 0.36 * lobe) * side
            teeth = 0.03 * math.sin(i * 1.9) * lobe
            pts.append(Vector((math.cos(a) * (r + teeth) * 1.05, centre.y + math.sin(a) * (r + teeth))))
        return pts
    n = 40
    for side in (1, -1):
        rng = range(n + 1) if side == 1 else range(n, -1, -1)
        for i in rng:
            u = i / n
            if species == "oak":
                env = 0.36 * math.sin(math.pi * u ** 0.85) ** 0.8
                lobes = 0.62 + 0.38 * abs(math.cos(math.pi * 4.5 * u + (0.6 if side < 0 else 0.0)))
                w = env * lobes
            else:  # birch: an egg shape with a sharp point and small teeth
                env = 0.4 * math.sin(math.pi * min(1.0, u ** 0.75)) ** 0.9 * (1.0 - 0.25 * u)
                w = env * (1.0 + 0.06 * ((i % 2) * 2 - 1))
            pts.append(Vector((side * w, u)))
    return pts


def build_twig_scene(species: str) -> None:
    """A twig with its leaves, laid flat on the XY plane inside the square x -0.5..0.5,
    y 0..1, stem end at (0, 0). Emission materials only, so the picture is the colours as
    they are (the game lights the cards)."""
    # a string seed, so every run draws the same twig (Python's hash() of a string changes per run)
    rnd = random.Random("twig_" + species)
    # [leaves on the main stem, leaf length, colour (sRGB), side twigs]
    look = {"oak": (11, 0.25, (0.20, 0.33, 0.09), 2), "maple": (9, 0.27, (0.22, 0.38, 0.10), 2),
            "birch": (16, 0.15, (0.30, 0.45, 0.11), 3)}[species]
    count, size, base_col, sides = look
    mesh = bpy.data.meshes.new("twig")
    bm = bmesh.new()
    col_layer = bm.loops.layers.float_color.new("Col")
    uv_layer = bm.loops.layers.uv.new("UVMap")

    def quad_strip(path, w0, w1, col, z):
        """A flat stem along a path of 2D points, w0 wide at the start and w1 at the end."""
        for i in range(len(path) - 1):
            a, b = path[i], path[i + 1]
            d = (b - a).normalized()
            nrm = Vector((-d.y, d.x))
            wa = lerp(w0, w1, i / (len(path) - 1)) * 0.5
            wb = lerp(w0, w1, (i + 1) / (len(path) - 1)) * 0.5
            vs = [bm.verts.new((p.x, p.y, z)) for p in (a - nrm * wa, a + nrm * wa, b + nrm * wb, b - nrm * wb)]
            f = bm.faces.new(vs)
            for lp in f.loops:
                lp[col_layer] = (*col, 1.0)
                lp[uv_layer].uv = (0.0, 0.5)

    def leaf(at, ang, length, z):
        """One leaf: its outline as a face, turned to `ang` (radians from up), stalk at `at`."""
        outline = leaf_outline(species, rnd)
        # each leaf a little different in colour and in how much light it catches
        shade = rnd.uniform(0.78, 1.12)
        hue = rnd.uniform(-0.06, 0.06)
        col = tuple(srgb_to_linear(max(0.0, min(1.0, c * shade + (hue if k == 0 else -hue * 0.5))))
                    for k, c in enumerate(base_col))
        rot = Matrix.Rotation(-ang, 2)
        stalk = length * 0.12
        tip_dir = rot @ Vector((0.0, 1.0))
        quad_strip([at, at + tip_dir * stalk], 0.006, 0.004, (0.06, 0.04, 0.02), z)
        start = at + tip_dir * stalk
        vs = []
        for p in outline:
            q = start + rot @ (p * length)
            vs.append(bm.verts.new((q.x, q.y, z + 0.0005)))
        face = bm.faces.new(vs)
        for lp in face.loops:
            lp[col_layer] = (*col, 1.0)
            # leaf space in UV: x across (-0.5..0.5), y along (0..1), for the vein lines
            local = rot.transposed() @ (Vector((lp.vert.co.x, lp.vert.co.y)) - start) / length
            lp[uv_layer].uv = (local.x, local.y)

    # the main stem: a gentle curve from the bottom middle to near the top
    bend = rnd.uniform(-0.06, 0.06)
    reach = 0.95 - size * 0.95             # the tip leaf must end inside the picture
    stem = [Vector((bend * math.sin(math.pi * t), 0.02 + reach * t)) for t in np.linspace(0, 1, 9)]
    quad_strip(stem, 0.016, 0.005, (0.09, 0.06, 0.035), 0.0)
    z = 0.001
    # leaves alternate up the stem, bigger in the middle, the last one at the tip
    for i in range(count):
        t = lerp(0.18, 1.0, i / (count - 1))
        k = min(int(t * 8), 7)
        at = stem[k].lerp(stem[k + 1], t * 8 - k)
        side = 1 if i % 2 == 0 else -1
        ang = side * rnd.uniform(0.55, 0.95) * (1.0 - 0.7 * t ** 3)
        length = size * (0.7 + 0.45 * math.sin(math.pi * min(1.0, t * 1.1))) * rnd.uniform(0.9, 1.1)
        if i == count - 1:
            ang, length = rnd.uniform(-0.1, 0.1), size * 0.9
        z += 0.002
        leaf(at, ang, length, z)
    # side twigs with a few leaves each, low on the stem
    for s in range(sides):
        t = lerp(0.25, 0.6, s / max(1, sides - 1))
        k = int(t * 8)
        at = stem[k]
        side = 1 if s % 2 == 0 else -1
        d = Vector((side * 0.8, 0.6)).normalized()
        end = at + d * rnd.uniform(0.25, 0.32)
        quad_strip([at, at.lerp(end, 0.5) + Vector((0.0, 0.02)), end], 0.009, 0.004, (0.09, 0.06, 0.035), z)
        for j in range(4 if species != "birch" else 5):
            u = lerp(0.35, 1.0, j / 3)
            p = at.lerp(end, u)
            z += 0.002
            ang = math.atan2(d.x, d.y) + (1 if j % 2 == 0 else -1) * rnd.uniform(0.4, 0.8) * (1.0 - 0.6 * u)
            leaf(p, ang, size * rnd.uniform(0.7, 0.95), z)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("twig", mesh)
    bpy.context.scene.collection.objects.link(obj)
    # emission: the vertex colour, a pale midrib and a darker edge (from the leaf-space UV)
    m = bpy.data.materials.new("twig_mat")
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    ab = nt.nodes.new("ShaderNodeMath")
    ab.operation = "ABSOLUTE"
    nt.links.new(sep.outputs["X"], ab.inputs[0])
    rib = nt.nodes.new("ShaderNodeMapRange")              # 1.25 on the midrib, 1 off it
    rib.inputs["From Min"].default_value = 0.0
    rib.inputs["From Max"].default_value = 0.025
    rib.inputs["To Min"].default_value = 1.3
    rib.inputs["To Max"].default_value = 1.0
    nt.links.new(ab.outputs[0], rib.inputs["Value"])
    noise = nt.nodes.new("ShaderNodeTexNoise")            # a faint mottle
    noise.inputs["Scale"].default_value = 60.0
    mot = nt.nodes.new("ShaderNodeMapRange")
    mot.inputs["To Min"].default_value = 0.85
    mot.inputs["To Max"].default_value = 1.1
    nt.links.new(noise.outputs["Fac"], mot.inputs["Value"])
    mul1 = nt.nodes.new("ShaderNodeMath")
    mul1.operation = "MULTIPLY"
    nt.links.new(rib.outputs[0], mul1.inputs[0])
    nt.links.new(mot.outputs[0], mul1.inputs[1])
    mix = nt.nodes.new("ShaderNodeVectorMath")
    mix.operation = "SCALE"
    nt.links.new(attr.outputs["Color"], mix.inputs[0])
    nt.links.new(mul1.outputs[0], mix.inputs["Scale"])
    nt.links.new(mix.outputs[0], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    obj.data.materials.append(m)


def render_twig(species: str) -> None:
    """Renders the twig scene from above into ../textures/twig_<species>.png (512 x 512)."""
    reset_scene()
    build_twig_scene(species)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.0
    cam.location = (0.0, 0.5, 2.0)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    path = os.path.join(TEX, f"twig_{species}.png")
    render_to(path, 512, 512, samples=24)
    bleed(path)
    print("wrote", path)


# ═══════════════════════════════════════════════════════════════════
# Part 2: the trees
# ═══════════════════════════════════════════════════════════════════

class Geo:
    """Triangles and quads of one tree while they are put together. Every face has one
    material (an index into `mats`) and every corner its own uv, colour and normal."""

    def __init__(self, mats: list):
        self.mats = mats
        self.verts: list = []
        self.faces: list = []
        self.face_mat: list = []
        self.uvs: list = []      # per corner, in face order
        self.cols: list = []
        self.nrms: list = []

    def tube(self, pts: list, radii: list, sides: int, bark: float, col: tuple, wind_top: float = 1.0) -> None:
        """A round, tapering stick along `pts` (a trunk or a branch), radii[i] thick at pts[i].
        bark = which bark photo (UV.x), col = the bark's colour. The rings turn with the path
        (parallel transport), so a bent branch keeps its shape."""
        if len(pts) < 2:
            return
        up = (pts[1] - pts[0]).normalized()
        a = up.cross(Vector((1, 0, 0)) if abs(up.x) < 0.9 else Vector((0, 1, 0))).normalized()
        rings = []
        for i, p in enumerate(pts):
            d = ((pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])).normalized()
            a = (a - d * a.dot(d)).normalized()
            b = d.cross(a)
            ring = []
            for s in range(sides):
                ang = 2 * math.pi * s / sides
                out = a * math.cos(ang) + b * math.sin(ang)
                ring.append((len(self.verts), out))
                self.verts.append(p + out * radii[i])
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(sides):
                s2 = (s + 1) % sides
                corners = [rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s]]
                self.faces.append([c[0] for c in corners])
                self.face_mat.append(0)
                for k, (vi, out) in enumerate(corners):
                    v = self.verts[vi]
                    self.uvs.append((bark, (i + (k >= 2)) * 0.25))
                    self.cols.append((col[0], col[1], col[2], max(0.0, min(1.0, v.z * wind_top))))
                    self.nrms.append(out)

    def card(self, base: Vector, tip: Vector, side: Vector, width: float, n: Vector,
             shade_base: float, shade_tip: float, mat: int) -> None:
        """One card: a rectangle from `base` (the picture's bottom edge, its stem end) to
        `tip`, `width` across along `side`; all four corners get the normal `n`."""
        h = side.normalized() * width * 0.5
        first = len(self.verts)
        self.verts += [base - h, base + h, tip + h, tip - h]
        self.faces.append([first, first + 1, first + 2, first + 3])
        self.face_mat.append(mat)
        n = n.normalized()
        for k, (u, v) in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
            s = shade_base if k < 2 else shade_tip
            z = (base if k < 2 else tip).z
            self.uvs.append((u, v))
            self.cols.append((s, s, s, max(0.0, min(1.0, z))))
            self.nrms.append(n)

    def to_object(self, name: str) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        for m in self.mats:
            mesh.materials.append(material(m))
        for poly, mi in zip(mesh.polygons, self.face_mat):
            poly.material_index = mi
        uv = mesh.uv_layers.new(name="UVMap")
        col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        for li in range(len(mesh.loops)):
            uv.data[li].uv = self.uvs[li]
            col.data[li].color = self.cols[li]
        mesh.color_attributes.active_color = col
        mesh.normals_split_custom_set([tuple(n) for n in self.nrms])
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


MAT_CACHE: dict = {}


def material(name: str) -> bpy.types.Material:
    """The material of that name. In the .glb only the name matters (campfire_forest.gd puts
    the game's own materials on by name); here it is set up for the far-tree pictures:
    unlit, the card picture times the vertex colour times the species tint, cut at CUT."""
    if name in MAT_CACHE:
        return MAT_CACHE[name]
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    if name == "trunk":
        nt.links.new(vc.outputs["Color"], emit.inputs["Color"])
        nt.links.new(emit.outputs[0], out.inputs["Surface"])
    else:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(os.path.join(TEX, CARD_PICTURE[name]))
        img.interpolation = "Linear"
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(img.outputs["Color"], mul.inputs["A"])
        nt.links.new(vc.outputs["Color"], mul.inputs["B"])
        tint = nt.nodes.new("ShaderNodeMix")
        tint.data_type = "RGBA"
        tint.blend_type = "MULTIPLY"
        tint.inputs["Factor"].default_value = 1.0
        nt.links.new(mul.outputs["Result"], tint.inputs["A"])
        tint.inputs["B"].default_value = (*CARD_TINT[name], 1.0)
        nt.links.new(tint.outputs["Result"], emit.inputs["Color"])
        cut = nt.nodes.new("ShaderNodeMath")
        cut.operation = "GREATER_THAN"
        cut.inputs[1].default_value = CUT
        nt.links.new(img.outputs["Alpha"], cut.inputs[0])
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(cut.outputs[0], mix.inputs["Fac"])
        nt.links.new(clear.outputs[0], mix.inputs[1])
        nt.links.new(emit.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    MAT_CACHE[name] = m
    return m


def jitter(rnd: random.Random, s: float) -> Vector:
    return Vector((rnd.uniform(-s, s), rnd.uniform(-s, s), rnd.uniform(-s, s)))


def random_side(rnd: random.Random, d: Vector) -> Vector:
    """A direction across `d`, picked at random."""
    return d.cross(Vector((rnd.random() - 0.5, rnd.random() - 0.5, rnd.random() - 0.5))).normalized()


def curve(a: Vector, b: Vector, sag: float, n: int) -> list:
    """n points from a to b, bowed down by `sag` (negative = up) in the middle."""
    return [a.lerp(b, t) - Vector((0, 0, sag * math.sin(math.pi * t))) for t in np.linspace(0, 1, n)]


# ── conifers ───────────────────────────────────────────────────────

def fir(lod: int, whorls: int, first: float, reach: float, seed: str) -> Geo:
    """A fir / spruce: rings ("whorls") of drooping boughs up a straight trunk, long at the
    bottom and short at the top, each bough carrying overlapping needle cards (and a thin
    bare branch in the lower half, where the boughs are long enough to show one) rolled to different angles, so the tree has a body from every side and gaps to see into.
    lod 1: no branch meshes, one long card per bough.
    Sen (round 2): the firs looked thin (sky and bare trunk showing between the boughs, worst on
    the slim firs behind the screen), so there are more boughs per whorl, wider cards and, on
    the lower boughs, a third card lying flat across the other two."""
    rnd = random.Random(seed)
    g = Geo(["trunk", "needles_fir"])
    bark = (0.34, 0.26, 0.2)
    g.tube([Vector((0, 0, 0)), Vector((0, 0, 0.5)), Vector((0, 0, 0.98))], [0.024, 0.014, 0.003], 8 if lod == 0 else 5, BARK_PINE, bark)
    for w in range(whorls):
        t = w / (whorls - 1)
        y = lerp(first, 0.9, t) + rnd.uniform(-0.012, 0.012)
        length = reach * (1.0 - t) ** 0.82 + 0.05
        boughs = 9 if t < 0.5 else (8 if t < 0.8 else 6)
        turn = rnd.random() * math.tau
        for i in range(boughs):
            ang = turn + math.tau * i / boughs + rnd.uniform(-0.25, 0.25)
            out = Vector((math.cos(ang), math.sin(ang), 0.0))
            l = length * rnd.uniform(0.82, 1.12)
            droop = lerp(0.5, 0.25, t) + rnd.uniform(-0.08, 0.1)
            base = Vector((0, 0, y))
            tip = base + out * l * math.cos(droop) - Vector((0, 0, l * math.sin(droop))) + Vector((0, 0, 0.02 * l))
            tip.z = max(tip.z, 0.03)            # the lowest boughs rest on the ground, not under it
            path = curve(base, tip, -0.06 * l, 4)
            if lod == 0 and t < 0.45:
                # a bare branch only where the boughs are long enough to show one under the
                # needles (the lower half); higher up the cards hide it, so it would only cost
                g.tube(path[:3], [0.0055 * (1 - t * 0.5), 0.004, 0.0025], 3, BARK_PINE, bark)
            n = (out * 0.55 + Vector((0, 0, 0.85))).normalized()
            d = (tip - base).normalized()
            if lod == 0:
                # two overlapping cards along the bough, each rolled differently round it
                for s0, s1, wid in ((0.0, 0.62, 0.75), (0.4, 1.05, 0.66)):
                    a = base.lerp(tip, s0)
                    b = base.lerp(tip, s1)
                    side = d.cross(Vector((0, 0, 1))).normalized()
                    side = Matrix.Rotation(rnd.uniform(-0.6, 0.6), 3, d) @ side
                    g.card(a, b, side, (s1 - s0) * l * wid * 1.6, n, lerp(0.45, 0.75, s0), lerp(0.85, 1.0, s1), 1)
                if t < 0.6:
                    # the third card, on its edge (turned a quarter round the bough), so a bough
                    # seen end-on still shows needles instead of a thin line
                    side = Matrix.Rotation(math.pi / 2 + rnd.uniform(-0.3, 0.3), 3, d) @ d.cross(Vector((0, 0, 1))).normalized()
                    g.card(base.lerp(tip, 0.15), base.lerp(tip, 0.9), side, l * 0.5, n, 0.5, 0.9, 1)
            else:
                side = Matrix.Rotation(rnd.uniform(-0.4, 0.4), 3, d) @ d.cross(Vector((0, 0, 1))).normalized()
                g.card(base, tip + d * 0.05 * l, side, l * 0.85, n, 0.5, 1.0, 1)
                if i % 2 == 0:
                    g.card(base, tip, d.cross(side), l * 0.55, (out + Vector((0, 0, 0.3))).normalized(), 0.45, 0.9, 1)
    # the leader at the top: three upright cards
    for i in range(3):
        ang = math.pi * i / 3
        g.card(Vector((0, 0, 0.8)), Vector((0, 0, 1.0)), Vector((math.cos(ang), math.sin(ang), 0)), 0.14, Vector((0, 0, 1)), 0.7, 1.0, 1)
    return g


def pine(lod: int) -> Geo:
    """A Scots-type pine: a tall bare trunk, a broad flat-topped crown of rising limbs that
    fork once, and tufts of long needles (crossed cards) at the twig ends."""
    rnd = random.Random("pine")
    g = Geo(["trunk", "needles_pine"])
    bark = (0.4, 0.27, 0.19)
    sides = 8 if lod == 0 else 5
    trunk = [Vector((0, 0, 0)), Vector((0.005, 0, 0.3)), Vector((0.012, 0.004, 0.55)), Vector((0.02, 0.01, 0.8)), Vector((0.022, 0.012, 0.94))]
    g.tube(trunk, [0.032, 0.025, 0.02, 0.012, 0.004], sides, BARK_PINE, bark)
    crown = Vector((0.0, 0.0, 0.8))
    tufts = []          # [point, direction]
    limbs = 14
    for i in range(limbs):
        t = i / (limbs - 1)
        y = lerp(0.52, 0.9, t)
        ang = i * 2.4 + rnd.uniform(-0.3, 0.3)
        out = Vector((math.cos(ang), math.sin(ang), 0))
        d = (out + Vector((0, 0, rnd.uniform(0.25, 0.7)))).normalized()
        length = lerp(0.34, 0.14, t) * rnd.uniform(0.85, 1.15)
        a = Vector((0.015 * t, 0, y))
        b = a + d * length
        g.tube(curve(a, b, -0.02, 3), [0.011, 0.007, 0.003], 5 if lod == 0 else 3, BARK_PINE, (bark[0] * 1.1, bark[1] * 1.1, bark[2] * 1.1))
        # one fork part way along, ending in its own tuft
        fork_at = a.lerp(b, 0.55)
        fd = (d + random_side(rnd, d) * 0.7 + Vector((0, 0, 0.3))).normalized()
        fe = fork_at + fd * length * 0.5
        if lod == 0:
            g.tube([fork_at, fe], [0.005, 0.002], 3, BARK_PINE, bark)
        for p, dd in ((b, d), (fe, fd), (a.lerp(b, 0.75), d), (a.lerp(b, 0.4), d)):
            tufts.append((p, dd))
    tufts.append((trunk[-1], Vector((0, 0, 1))))
    per = 3 if lod == 0 else 1
    for p, dd in tufts:
        for k in range(per):
            d = (dd + Vector((rnd.uniform(-0.7, 0.7), rnd.uniform(-0.7, 0.7), rnd.uniform(-0.1, 0.7)))).normalized()
            size = rnd.uniform(0.15, 0.22) * (1.0 if lod == 0 else 1.5)
            base = p - d * size * 0.3
            side = random_side(rnd, d)
            n = ((p - crown).normalized() + Vector((0, 0, 0.5))).normalized()
            g.card(base, base + d * size, side, size, n, 0.6, 1.0, 1)
            g.card(base, base + d * size, d.cross(side), size, n, 0.55, 0.95, 1)
    return g


# ── leafy trees ────────────────────────────────────────────────────

LEAFY = {
    # bark number, bark colour, trunk radius, fork height, crown middle height, crown half
    # sizes (x = z, height), limbs, limb thickness (share of the trunk's), rise (0 = limbs
    # spread sideways, 1 = they sweep up), twig cards at lod 0, card length, droop (1 = the
    # twigs hang), card material
    "oak": dict(bark=BARK_OAK, col=(0.4, 0.36, 0.31), trunk=0.05, fork=0.26, centre=0.62, radii=(0.47, 0.3),
                limbs=9, limb_r=0.55, rise=0.2, cards=440, size=0.16, droop=0.1, mat="twigs_oak"),
    "maple": dict(bark=BARK_OAK, col=(0.36, 0.33, 0.3), trunk=0.034, fork=0.3, centre=0.66, radii=(0.3, 0.34),
                  limbs=8, limb_r=0.45, rise=0.65, cards=420, size=0.15, droop=0.05, mat="twigs_maple"),
    # birch (Sen, round 2: leaves were too big): smaller cards, more of them
    "birch": dict(bark=BARK_BIRCH, col=(0.66, 0.65, 0.61), trunk=0.022, fork=0.42, centre=0.7, radii=(0.21, 0.3),
                  limbs=8, limb_r=0.38, rise=0.75, cards=430, size=0.085, droop=0.55, mat="twigs_birch"),
}


def leafy(species: str, lod: int) -> Geo:
    """A leafy tree: trunk, limbs that bend and fork into branches and twiglets, and twig cards
    on them. The crown is an egg shape (centre, radii); its outside gets the most twigs, the
    inside stays darker and has gaps, as real crowns do. lod 1: no small branches and half as
    many twig cards, each bigger, on the same branches (so the outline matches).
    Every card's stem end sits on a branch or twiglet (Sen, round 2: cards scattered round
    the branch ends, and over the crown's skin to close holes, left leaves floating in the air
    on the birches). The holes are closed by more branches instead."""
    p = LEAFY[species]
    rnd = random.Random(species)
    g = Geo(["trunk", p["mat"]])
    bark, col = p["bark"], p["col"]
    rx, ry = p["radii"]
    centre = Vector((0, 0, p["centre"]))
    r = p["trunk"]
    sides = 9 if lod == 0 else 5
    fork = Vector((rnd.uniform(-0.01, 0.01), rnd.uniform(-0.01, 0.01), p["fork"]))
    top = centre + Vector((0.01, 0, ry * 0.6))
    # the trunk, slightly flared at the foot and wandering a little
    g.tube([Vector((0, 0, 0)), Vector((0, 0, 0.04)), fork * 0.5 + Vector((0.004, 0, 0)), fork], [r * 1.35, r, r * 0.86, r * 0.75], sides, bark, col)
    g.tube([fork, fork.lerp(top, 0.5) + Vector((-0.01, 0.006, 0)), top], [r * 0.75, r * 0.45, r * 0.08], sides - 2, bark, col)

    def inside(v: Vector) -> float:
        q = v - centre
        return math.sqrt((q.x / rx) ** 2 + (q.y / rx) ** 2 + (q.z / ry) ** 2)

    # the pieces of wood the twig cards grow from: [from, to]; a card's stem end sits somewhere
    # on the outer two thirds of one
    wood = [(fork.lerp(top, 0.7), top)]
    limbs = p["limbs"]
    rise = p["rise"]
    lr = r * p["limb_r"]
    for i in range(limbs):
        t = i / (limbs - 1)
        ang = i * 2.4 + rnd.uniform(-0.3, 0.3)
        out = Vector((math.cos(ang), math.sin(ang), 0))
        start = fork.lerp(top, t * 0.65)
        reach = lerp(1.0, 0.65, t) * rnd.uniform(0.82, 1.0)
        tip = Vector((out.x * rx * reach, out.y * rx * reach, 0))
        tip.z = start.z + (centre.z + ry * 0.5 - start.z) * lerp(0.2, 0.85, rise) * rnd.uniform(0.7, 1.1)
        # keep the tip inside the crown
        while inside(tip) > 0.92:
            tip = centre + (tip - centre) * 0.95
        elbow = start.lerp(tip, 0.5) + Vector((0, 0, (tip.z - start.z) * lerp(-0.15, 0.2, rise) + 0.02))
        path = [start, start.lerp(elbow, 0.5), elbow, elbow.lerp(tip, 0.5) + jitter(rnd, 0.01), tip]
        rad0 = lr * lerp(1.0, 0.6, t)
        g.tube(path, [rad0, rad0 * 0.8, rad0 * 0.55, rad0 * 0.35, rad0 * 0.1], 5 if lod == 0 else 4, bark, col)
        wood.append((elbow.lerp(tip, 0.3), tip))
        # branches off the limb's outer half, reaching out to the crown's skin, each with two
        # twiglets (the wood the outer cards hang on)
        for k in range(7):
            s = lerp(0.3, 0.95, k / 6) + rnd.uniform(-0.04, 0.04)
            seg = min(int(s * 4), 3)
            at = path[seg].lerp(path[seg + 1], s * 4 - seg)
            d = ((at - centre).normalized() * 0.6 + random_side(rnd, (tip - start).normalized()) * 0.6
                 + Vector((0, 0, lerp(0.1, 0.5, rise) - p["droop"] * 0.5))).normalized()
            blen = rnd.uniform(0.12, 0.2) * (rx + ry)
            end = at + d * blen
            while inside(end) > 0.97:
                end = centre + (end - centre) * 0.96
            if lod == 0:
                g.tube(curve(at, end, 0.01 * p["droop"], 3), [rad0 * 0.32, rad0 * 0.18, rad0 * 0.05], 3, bark, col)
            wood.append((at, end))
            for j in range(2):
                tat = at.lerp(end, rnd.uniform(0.4, 0.85))
                td = (d + random_side(rnd, d) * 0.9 - Vector((0, 0, p["droop"] * 0.6))).normalized()
                tend = tat + td * blen * rnd.uniform(0.4, 0.6)
                while inside(tend) > 1.0:
                    tend = centre + (tend - centre) * 0.96
                if lod == 0:
                    g.tube([tat, tend], [rad0 * 0.1, rad0 * 0.03], 3, bark, col)
                wood.append((tat, tend))
    # branches off the top of the trunk, up into the crown's top (without them the top of a
    # wide crown, the oak's, was a hole: its limbs all reach sideways)
    for k in range(6):
        at = fork.lerp(top, lerp(0.55, 0.95, k / 5))
        ang = k * 2.4 + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang) * 0.8, math.sin(ang) * 0.8, 1.0)).normalized()
        end = at + d * (rx + ry) * 0.3
        while inside(end) > 0.95:
            end = centre + (end - centre) * 0.96
        if lod == 0:
            g.tube([at, at.lerp(end, 0.5), end], [lr * 0.3, lr * 0.18, lr * 0.05], 3, bark, col)
        wood.append((at.lerp(end, 0.3), end))
    # twig cards: each one's stem end on a piece of wood (most on its outer part), pointing
    # out of the crown, down a little where the species' twigs hang
    count = p["cards"] if lod == 0 else p["cards"] // 2
    size = p["size"] * (1.0 if lod == 0 else 1.45)
    droop = p["droop"]
    # pieces whose end reaches the crown's skin get more cards (a crown is leafy outside and
    # shows its wood inside): weight = how far out the end is, squared
    weights = [max(0.05, min(1.0, inside(b))) ** 2 for _, b in wood]
    for i in range(count):
        a, b = rnd.choices(wood, weights)[0]
        at = a.lerp(b, rnd.uniform(0.3, 1.0) ** 0.7)
        from_c = at - centre
        outward = Vector((from_c.x / rx, from_c.y / rx, from_c.z / ry))
        along = (b - a).normalized()
        d = (outward.normalized() * 0.7 + along * 0.5 + jitter(rnd, 0.55) + Vector((0, 0, 0.2))
             - Vector((0, 0, droop * 1.5))).normalized()
        l = size * rnd.uniform(0.85, 1.2)
        base = at
        side = random_side(rnd, d)
        n = (outward.normalized() + Vector((0, 0, 0.35))).normalized()
        depth = min(1.0, outward.length)
        shade = lerp(0.5, 1.0, depth) * lerp(0.72, 1.0, max(0.0, min(1.0, outward.z * 0.5 + 0.5)))
        g.card(base, base + d * l, side, l, n, shade * 0.85, shade, 1)
    return g


def build(species: str, lod: int) -> Geo:
    if species == "fir":
        return fir(lod, 16 if lod == 0 else 11, 0.12, 0.3, "fir")
    if species == "young_fir":
        return fir(lod, 11 if lod == 0 else 8, 0.05, 0.38, "young_fir")
    if species == "pine":
        return pine(lod)
    return leafy(species, lod)


# ═══════════════════════════════════════════════════════════════════
# Part 3: rendering helpers and the far-tree pictures
# ═══════════════════════════════════════════════════════════════════

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MAT_CACHE.clear()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"       # colours as they are, no filmic curve
    scene.cycles.max_bounces = 0
    scene.cycles.transparent_max_bounces = 64
    scene.cycles.use_denoising = False
    world = bpy.data.worlds.new("w")
    world.color = (0, 0, 0)
    scene.world = world


def render_to(path: str, w: int, h: int, samples: int) -> None:
    scene = bpy.context.scene
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.cycles.samples = samples
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def bleed(path: str) -> None:
    """Fills the see-through pixels with the colour of the nearest drawn one, so the edges do not
    go dark when the picture is shrunk (mipmaps) or filtered."""
    from PIL import Image
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    solid = im[..., 3] > 8
    if solid.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        rgb = im[iy, ix, :3]
        im[..., :3] = np.where(solid[..., None], im[..., :3], rgb)
    Image.fromarray(im.clip(0, 255).astype(np.uint8)).save(path, optimize=True)


def normal_material(tree_obj: bpy.types.Object) -> None:
    """Swaps every material on the tree for one that shows the surface's direction in the
    tree's own space in Godot axes (x, z up -> y, -y forward -> z), as colour 0..1, alpha = 1 on
    leaves. The cards keep their see-through cut."""
    for slot in tree_obj.material_slots:
        old = slot.material
        name = old.name.split(".")[0]
        m = bpy.data.materials.new(name + "_n")
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        emit = nt.nodes.new("ShaderNodeEmission")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        # the shading normal in world space = the tree's space (the tree is never turned)
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Normal"], sep.inputs[0])
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        neg = nt.nodes.new("ShaderNodeMath")
        neg.operation = "MULTIPLY"
        neg.inputs[1].default_value = -1.0
        nt.links.new(sep.outputs["Y"], neg.inputs[0])
        nt.links.new(sep.outputs["X"], comb.inputs["X"])
        nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
        nt.links.new(neg.outputs[0], comb.inputs["Z"])
        half = nt.nodes.new("ShaderNodeVectorMath")
        half.operation = "MULTIPLY_ADD"
        nt.links.new(comb.outputs[0], half.inputs[0])
        half.inputs[1].default_value = (0.5, 0.5, 0.5)
        half.inputs[2].default_value = (0.5, 0.5, 0.5)
        nt.links.new(half.outputs[0], emit.inputs["Color"])
        if name == "trunk":
            nt.links.new(emit.outputs[0], out.inputs["Surface"])
        else:
            img = nt.nodes.new("ShaderNodeTexImage")
            img.image = bpy.data.images.load(os.path.join(TEX, CARD_PICTURE[name]), check_existing=True)
            cut = nt.nodes.new("ShaderNodeMath")
            cut.operation = "GREATER_THAN"
            cut.inputs[1].default_value = CUT
            nt.links.new(img.outputs["Alpha"], cut.inputs[0])
            clear = nt.nodes.new("ShaderNodeBsdfTransparent")
            mix = nt.nodes.new("ShaderNodeMixShader")
            nt.links.new(cut.outputs[0], mix.inputs["Fac"])
            nt.links.new(clear.outputs[0], mix.inputs[1])
            nt.links.new(emit.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs["Surface"])
        slot.material = m


def render_impostors(frames_dir: str) -> None:
    """Photographs each species' full tree from IMPOSTOR_FRAMES sides (colour, then surface
    direction) and puts the frames together into the two picture sheets."""
    from PIL import Image
    os.makedirs(frames_dir, exist_ok=True)
    sheet_c = Image.new("RGBA", (IMP_PX * IMPOSTOR_FRAMES, IMP_PX * len(SPECIES)))
    sheet_n = Image.new("RGBA", sheet_c.size)
    for row, species in enumerate(SPECIES):
        for pass_name in ("color", "normal"):
            reset_scene()
            tree = build(species, 0).to_object(species)
            if pass_name == "normal":
                normal_material(tree)
            cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
            cam.data.type = "ORTHO"
            cam.data.ortho_scale = IMP_HALF * 2
            bpy.context.scene.collection.objects.link(cam)
            bpy.context.scene.camera = cam
            for k in range(IMPOSTOR_FRAMES):
                # frame k looks at the tree from Godot's direction (sin phi, 0, cos phi), phi =
                # k / frames of a turn: Blender (sin phi, -cos phi), level (orthographic)
                phi = math.tau * k / IMPOSTOR_FRAMES
                d = Vector((math.sin(phi), -math.cos(phi), 0))
                cam.location = d * 5 + Vector((0, 0, IMP_HALF))
                cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
                path = os.path.join(frames_dir, f"{species}_{pass_name}_{k}.png")
                render_to(path, IMP_PX, IMP_PX, 16)
                im = Image.open(path).convert("RGBA")
                if pass_name == "color":
                    sheet_c.paste(im, (k * IMP_PX, row * IMP_PX))
                else:
                    # alpha = 1 on leaves, 0 on bark: the bark is where the colour pass is bark
                    sheet_n.paste(im, (k * IMP_PX, row * IMP_PX))
            print("impostor", species, pass_name)
    # the leaf mask: bark pixels are the ones whose colour is a bark colour (greyish brown):
    # tell them by rendering is costly, so instead compare green to red (leaves are greener)
    c = np.asarray(sheet_c).astype(np.float32)
    n = np.asarray(sheet_n).astype(np.float32)
    leaf = (c[..., 1] > c[..., 0] * 1.02).astype(np.float32) * 255.0
    cover = c[..., 3] > 8
    n[..., 3] = np.where(cover, leaf, 0.0)
    # keep the colour sheet's alpha as the coverage; fill the clear pixels (see bleed)
    out_c = os.path.join(TEX, "impostor_color.png")
    out_n = os.path.join(TEX, "impostor_normal.png")
    Image.fromarray(c.astype(np.uint8)).save(out_c)
    # the normal sheet's own alpha is the leaf mask, so bleed it by the colour sheet's coverage
    solid = cover
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    n[..., :3] = np.where(solid[..., None], n[..., :3], n[iy, ix, :3])
    n[..., 3] = np.where(solid, n[..., 3], n[iy, ix, 3])
    Image.fromarray(n.clip(0, 255).astype(np.uint8)).save(out_n, optimize=True)
    bleed(out_c)
    print("wrote", out_c, out_n)
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        bg = Image.new("RGBA", sheet_c.size, (150, 175, 205, 255))
        Image.alpha_composite(bg, Image.open(out_c).convert("RGBA")).convert("RGB").save(os.path.join(PREVIEW, "impostor_sheet.jpg"), quality=90)


def export_trees() -> None:
    """Builds every species at both levels and writes trees.glb."""
    reset_scene()
    objs = []
    for species in SPECIES:
        for lod in (0, 1):
            g = build(species, lod)
            obj = g.to_object(f"{species}_lod{lod}")
            print(f"{species}_lod{lod}: {len(g.faces)} faces")
            objs.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, "trees.glb"), use_selection=True, export_yup=True,
                              export_tangents=False, export_materials="EXPORT", export_image_format="NONE", export_normals=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    print("wrote trees.glb")


if __name__ == "__main__":
    for sp in ("oak", "maple", "birch"):
        render_twig(sp)
    export_trees()
    # the single frames go to the preview folder, or to a throwaway folder outside the project
    import tempfile
    render_impostors(os.path.join(PREVIEW or tempfile.mkdtemp(prefix="tree_frames_"), "frames"))
