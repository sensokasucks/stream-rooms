"""forge_hall_gen.py - builds the Forge Hall room in Blender.

    exec(open(r"C:\\Users\\jonza\\Documents\\RedotHomeTheater\\stream_rooms\\blender\\forge_hall_gen.py").read())
    build_all(); export_glb()

A long, tall workshop hall in polished granite with a little science fiction in it (from the
owner's reference picture, cross-section sketch and notes): pillars and walls carved from single
slabs, with cyan, orange and purple light inlaid flush in them like the traces on a circuit
board, over a finer, dimmer second layer of circuit lines; a wide alcove with pipes across its
top where the hologram screen floats; a forge fireplace built out from the right wall, covered
in steam-age machinery (gears, pistons, coils, a control panel); wood-panelled alcoves between
the pillars down both side walls and on the back wall, each with a spot for an art frame; a
ledge at the top of the walls, slanted windows above it (none round the forge), and a raised
ceiling of dark diamond plate on steel girders with air ducts and pipes hung under it;
hexagonal lanterns close under the ceiling; steam pipes with hand wheels and gauges round the
hall. Three stepped rows of benches seat 30 chatters in the front half, four podiums stand
beside the screen, and the back half holds a workbench, a steam engine and stores.

The fire, the sky, the sunbeams from the windows and their patches on the floor, the art
frames, the three small live screens and the big screen's shape are built by the room script
(rooms/forge_hall/forge_hall_room.gd) from the FIRE_, SHAFT_, ART_ and SCREEN_ markers and
the TVScreen rectangle.

Textures come from blender/make_forge_textures.py (rooms/forge_hall/textures).
Output: rooms/forge_hall/forge_hall.glb. ROOT below is the owner's PC; set ROOT before exec on
another machine (the cloud build does).

Blender axes: origin = the middle of the screen wall on the floor. -Y = toward the audience and
the back wall (y = BACK_Y), +X = the forge wall, Z = up. Markers follow the Stream Rooms
contract (rooms/room.gd): PRESENTER_/CHAT_Screen/REPLY_Screen/TARGET_/FIRE_/ART_ empties point -Y
(or into the room) at the audience, cameras point +Y at what they look at.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Euler

ROOT = globals().get("ROOT", r"C:\Users\jonza\Documents\RedotHomeTheater\stream_rooms")
TEX = os.path.join(ROOT, "rooms", "forge_hall", "textures")
GLB = os.path.join(ROOT, "rooms", "forge_hall", "forge_hall.glb")
COLL, MARKERS = "Hall", "Hall_Markers"      # the two collections export_glb() exports


# ════════════════════════════════════════════════════════════════
#  Generic helpers (the same as throne_hall_gen.py)
# ════════════════════════════════════════════════════════════════
def col(name):
    """The collection with this name, made and linked to the scene if it isn't there yet."""
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
    if c.name not in [x.name for x in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(c)
    return c


def mat(name, color, rough=0.7, metal=0.0, emit=None, estr=0.0, two_sided=False):
    """A plain Principled material (reused by name). color / emit: linear RGB 0..1; estr = emission
    strength. two_sided turns backface culling off (Redot keeps that: the banners show both sides)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = estr
    m.diffuse_color = (*color, 1)
    m.use_backface_culling = not two_sided
    return m


def tex_mat(name, image, rough=0.7, metal=0.0, emit=0.0, two_sided=False):
    """A material using a texture from TEX as its colour (and as emission when emit > 0).
    The name is what the room's script looks for after import (glow_materials, set shaders).
    """
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    t = nt.nodes.get("Tex") or nt.nodes.new("ShaderNodeTexImage")
    t.name = "Tex"
    im = bpy.data.images.get(image) or bpy.data.images.load(os.path.join(TEX, image))
    t.image = im
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0:
        nt.links.new(t.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = emit
    m.use_backface_culling = not two_sided
    return m


class MB:
    """Mesh builder: collects faces in a bmesh, then done() turns them into one object
    (replacing an old object of the same name) in the given collection.
    """
    def __init__(self, name, collection=COLL):
        self.name, self.col = name, collection
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.mats = []

    def mi(self, m):
        """Material slot index for material name m (added on first use)."""
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def done(self, origin=None):
        """Writes the mesh and links the object. origin: optional object origin (the mesh is moved
        so the object can sit there, e.g. to be copied to other places with instance()).
        """
        old = bpy.data.objects.get(self.name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        me_old = bpy.data.meshes.get(self.name)
        if me_old and me_old.users == 0:
            bpy.data.meshes.remove(me_old)
        me = bpy.data.meshes.new(self.name)
        if origin is not None:
            bmesh.ops.translate(self.bm, vec=-Vector(origin), verts=self.bm.verts)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(bpy.data.materials[m])
        o = bpy.data.objects.new(self.name, me)
        col(self.col).objects.link(o)
        if origin is not None:
            o.location = origin
        return o


def instance(name, src, loc, yaw=0.0):
    """Another object sharing src's mesh (pillars, lanterns: one mesh, many places).
    Redot imports shared meshes once, so the hall costs little memory however many pillars."""
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    o = bpy.data.objects.new(name, src.data)
    o.location = loc
    o.rotation_euler = (0, 0, yaw)
    col(COLL).objects.link(o)
    return o


def _face(mb, pts, m, uvs):
    """One face from 3D points, with material m and one UV per point."""
    vs = [mb.bm.verts.new(p) for p in pts]
    f = mb.bm.faces.new(vs)
    f.material_index = mb.mi(m)
    for lp, t in zip(f.loops, uvs):
        lp[mb.uv].uv = t
    return f


def box(mb, center, size, m, rot=(0, 0, 0), uvs=1.0, faces="all"):
    """Box with world-scale UVs (1 UV unit = uvs metres). rot = XYZ euler (radians)."""
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    R = Euler(rot, 'XYZ').to_matrix()
    c = Vector(center)
    P = lambda x, y, z: c + R @ Vector((x, y, z))
    quads = {
        "+z": ([(-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)], (0, 1)),
        "-z": ([(-sx, sy, -sz), (sx, sy, -sz), (sx, -sy, -sz), (-sx, -sy, -sz)], (0, 1)),
        "+y": ([(sx, sy, -sz), (-sx, sy, -sz), (-sx, sy, sz), (sx, sy, sz)], (0, 2)),
        "-y": ([(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)], (0, 2)),
        "+x": ([(sx, -sy, -sz), (sx, sy, -sz), (sx, sy, sz), (sx, -sy, sz)], (1, 2)),
        "-x": ([(-sx, sy, -sz), (-sx, -sy, -sz), (-sx, -sy, sz), (-sx, sy, sz)], (1, 2)),
    }
    for k, (pts, (a, b)) in quads.items():
        if faces != "all" and k not in faces:
            continue
        uv = [((p[a] + (center[a] if rot == (0, 0, 0) else 0)) / uvs, (p[b] + (center[b] if rot == (0, 0, 0) else 0)) / uvs) for p in pts]
        _face(mb, [P(*p) for p in pts], m, uv)


def quad(mb, p0, p1, p2, p3, m, u=(0, 1), v=(0, 1)):
    """p0 bottom-left, p1 bottom-right, p2 top-right, p3 top-left, seen from the front."""
    _face(mb, [Vector(p) for p in (p0, p1, p2, p3)], m, [(u[0], v[0]), (u[1], v[0]), (u[1], v[1]), (u[0], v[1])])


def wall_quad(mb, axis, pos, a0, a1, z0, z1, m, facing, u=(0, 1), v=(0, 1)):
    """Upright rectangle on a wall plane. axis 'x': plane x=pos spanning y a0..a1.
    axis 'y': plane y=pos spanning x a0..a1. facing = +1/-1 along the plane's normal axis."""
    if axis == "y":
        if facing < 0:   # seen from -y: left = -x
            quad(mb, (a0, pos, z0), (a1, pos, z0), (a1, pos, z1), (a0, pos, z1), m, u, v)
        else:
            quad(mb, (a1, pos, z0), (a0, pos, z0), (a0, pos, z1), (a1, pos, z1), m, u, v)
    else:
        if facing < 0:   # seen from -x: left = +y
            quad(mb, (pos, a1, z0), (pos, a0, z0), (pos, a0, z1), (pos, a1, z1), m, u, v)
        else:
            quad(mb, (pos, a0, z0), (pos, a1, z0), (pos, a1, z1), (pos, a0, z1), m, u, v)


def floor_quad(mb, x0, x1, y0, y1, z, m, uvs=1.0, up=True):
    """Horizontal rectangle with world-scale UVs (uvs metres per UV unit), facing up (or down)."""
    pts = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    if not up:
        pts.reverse()
    _face(mb, [Vector(p) for p in pts], m, [(p[0] / uvs, p[1] / uvs) for p in pts])


def cyl(mb, center, r, depth, m, axis="z", segs=16, r2=None, smooth=False):
    """Capped cylinder (or cone when r2 differs) along axis "x", "y" or "z"."""
    res = bmesh.ops.create_cone(mb.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                                radius2=r if r2 is None else r2, depth=depth)
    rot = {"z": Matrix.Identity(3), "x": Matrix.Rotation(math.pi / 2, 3, 'Y'), "y": Matrix.Rotation(-math.pi / 2, 3, 'X')}[axis]
    mtx = Matrix.Translation(Vector(center)) @ rot.to_4x4()
    bmesh.ops.transform(mb.bm, matrix=mtx, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mb.mi(m)
        if smooth and len(f.verts) == 4:
            f.smooth = True


def sphere(mb, center, r, m, subdiv=2, scale=(1, 1, 1)):
    """Smooth icosphere, optionally squashed by scale."""
    res = bmesh.ops.create_icosphere(mb.bm, subdivisions=subdiv, radius=r)
    mtx = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.transform(mb.bm, matrix=mtx, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mb.mi(m)
        f.smooth = True


def torus(mb, center, R, r, m, axis="z", segs=24, rsegs=6):
    """Smooth ring: R = ring radius, r = tube radius, around the given axis."""
    rot = {"z": Matrix.Identity(3), "x": Matrix.Rotation(math.pi / 2, 3, 'Y'), "y": Matrix.Rotation(math.pi / 2, 3, 'X')}[axis]
    ring = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(rsegs):
            b = 2 * math.pi * j / rsegs
            p = Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
            row.append(mb.bm.verts.new(Vector(center) + rot @ p))
        ring.append(row)
    mi = mb.mi(m)
    for i in range(segs):
        for j in range(rsegs):
            f = mb.bm.faces.new((ring[i][j], ring[(i + 1) % segs][j], ring[(i + 1) % segs][(j + 1) % rsegs], ring[i][(j + 1) % rsegs]))
            f.material_index = mi
            f.smooth = True


def bar(mb, a, b, t, m):
    """Square bar between two points."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    q = d.to_track_quat('Z', 'Y')
    e = q.to_euler('XYZ')
    box(mb, (a + b) / 2, (t, t, L), m, rot=(e.x, e.y, e.z))


def empty(name, loc, parent=None, collection=MARKERS, size=0.2):
    """A marker empty (replaces one of the same name). Names follow the Stream Rooms contract
    (CAM_, LAMP_, PRESENTER_, TARGET_, AUDIENCE_ ... see rooms/room.gd).
    """
    o = bpy.data.objects.get(name)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = 'ARROWS'
    o.empty_display_size = size
    o.location = loc
    col(collection).objects.link(o)
    if parent:
        o.parent = parent
    return o


def aim(o, target, forward='Y'):
    """Turns o so its forward axis points at target (Z kept up)."""
    d = Vector(target) - o.location
    o.rotation_euler = d.to_track_quat(forward, 'Z').to_euler()



# ── helpers this room adds ──────────────────────────────────────
def face_to(mb, pts, m, uvs, toward):
    """One face whose front looks toward the point `toward` (the point order is flipped if needed).
    Used for the roof slopes and gables, where working out the winding by hand is error-prone."""
    pts = [Vector(p) for p in pts]
    n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
    c = sum(pts, Vector()) / len(pts)
    if n.dot(Vector(toward) - c) < 0:
        pts.reverse()
        uvs = list(reversed(uvs))
    _face(mb, pts, m, uvs)


def prism(mb, pts, plane, a, b, m, uvs=2.0):
    """A solid with the outline pts (a list of 2D points) pushed from a to b along the third axis.
    plane "xz": outline in x / z, pushed along y. "yz": outline in y / z, pushed along x.
    "xy": outline in x / y, pushed along z. UVs are world-scale (uvs metres per UV unit)."""
    def P(u, v, w):
        return {"xz": Vector((u, w, v)), "yz": Vector((w, u, v)), "xy": Vector((u, v, w))}[plane]
    va = [mb.bm.verts.new(P(u, v, a)) for (u, v) in pts]
    vb = [mb.bm.verts.new(P(u, v, b)) for (u, v) in pts]
    mi = mb.mi(m)
    new = []
    for ring in (va, vb):
        f = mb.bm.faces.new(ring)
        for lp, (u, v) in zip(f.loops, pts):
            lp[mb.uv].uv = (u / uvs, v / uvs)
        new.append(f)
    run = 0.0
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        seg = (Vector(pts[j]) - Vector(pts[i])).length
        f = mb.bm.faces.new((va[i], va[j], vb[j], vb[i]))
        for lp, t in zip(f.loops, [(run / uvs, a / uvs), ((run + seg) / uvs, a / uvs), ((run + seg) / uvs, b / uvs), (run / uvs, b / uvs)]):
            lp[mb.uv].uv = t
        run += seg
        new.append(f)
    for f in new:
        f.material_index = mi
    bmesh.ops.recalc_face_normals(mb.bm, faces=new)    # a closed solid: this turns every face outward


def tube(mb, a, b, r, m, segs=10):
    """A round pipe between two points."""
    a, b = Vector(a), Vector(b)
    d = b - a
    res = bmesh.ops.create_cone(mb.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r, depth=d.length)
    mtx = Matrix.Translation((a + b) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bmesh.ops.transform(mb.bm, matrix=mtx, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mb.mi(m)
        if len(f.verts) == 4:
            f.smooth = True


def pipe_run(mb, pts, r, m, collar=None):
    """A pipe through the points in order, with a ball at every bend. collar: material for a
    wider ring at both ends and halfway along each straight (a pipe coupling), or None."""
    for a, b in zip(pts[:-1], pts[1:]):
        tube(mb, a, b, r, m)
        if collar:
            a, b = Vector(a), Vector(b)
            d = (b - a).normalized()
            for t in (0.06, 0.5, 0.94):
                c = a.lerp(b, t)
                tube(mb, c - d * 0.07, c + d * 0.07, r * 1.35, collar, segs=10)
    for p in pts[1:-1]:
        sphere(mb, p, r * 1.15, m, subdiv=1)


def traces(mb, S, paths, m, w=0.06, lift=0.006, pads=True):
    """Light inlays, like the traces on a circuit board: flat ribbons lying in a surface (not
    standing out from it), each path a run of straight pieces with a small eight-sided pad at
    both ends. S(u, v, lift) maps the surface's own 2D coordinates to a point `lift` metres in
    front of it (see the S_ surfaces below); paths = lists of (u, v) points; m = a Neon_ material."""
    def flat(pts2):
        mid = sum((Vector(p) for p in pts2), Vector((0, 0))) / len(pts2)
        face_to(mb, [S(p[0], p[1], lift) for p in pts2], m, [(0, 0)] * len(pts2), S(mid.x, mid.y, lift + 1.0))
    for path in paths:
        for a, b in zip(path[:-1], path[1:]):
            a, b = Vector(a), Vector(b)
            d = (b - a).normalized()
            p = Vector((-d.y, d.x)) * (w / 2)
            a2, b2 = a - d * (w / 2), b + d * (w / 2)      # a little long, so bends join up
            flat([a2 - p, b2 - p, b2 + p, a2 + p])
        if pads:
            for c in (Vector(path[0]), Vector(path[-1])):
                flat([c + Vector((math.cos(k * math.pi / 4 + math.pi / 8), math.sin(k * math.pi / 4 + math.pi / 8))) * w * 1.5 for k in range(8)])


def fine_circuit(mb, S, rect, seed, per_m2=0.35, avoid=(), w=0.014, lift=0.003, upright=0.5):
    """The fine second layer of circuit lines (round 3): bundles of two to five thin parallel
    lines scattered over a surface, each bundle running straight, jogging 45 degrees together
    and running on, every line ending in a small square pad. S = the surface (as for traces()),
    rect = (u0, u1, v0, v1) on it, avoid = rectangles (same form) no line may enter (alcoves,
    pillars, doors), per_m2 = bundles per square metre, upright = the share of bundles that run
    along v instead of u. The same seed always gives the same pattern. They lie under the main
    inlays (lift is smaller), so where the two cross the main line wins."""
    import random
    rng = random.Random(seed)
    u0, u1, v0, v1 = rect

    def ok(p):
        if not (u0 <= p[0] <= u1 and v0 <= p[1] <= v1):
            return False
        return not any(a[0] <= p[0] <= a[1] and a[2] <= p[1] <= a[3] for a in avoid)

    def flat(pts2, m):
        mid = sum((Vector(q) for q in pts2), Vector((0, 0))) / len(pts2)
        face_to(mb, [S(q[0], q[1], lift) for q in pts2], m, [(0, 0)] * len(pts2), S(mid.x, mid.y, lift + 1.0))

    for _ in range(int((u1 - u0) * (v1 - v0) * per_m2)):
        d = Vector((0, 1)) if rng.random() < upright else Vector((1, 0))
        if rng.random() < 0.5:
            d = -d
        n = Vector((-d.y, d.x))
        start = Vector((round(rng.uniform(u0, u1) / 0.05) * 0.05, round(rng.uniform(v0, v1) / 0.05) * 0.05))
        run1, run2 = rng.uniform(0.35, 1.7), rng.uniform(0.3, 1.4)
        jog = rng.choice((-1, 1)) * rng.uniform(0.1, 0.35)
        m = "Neon_Fine_Amber" if rng.random() < 0.25 else "Neon_Fine_Cyan"
        lines = []
        for i in range(rng.randint(2, 5)):
            a = start + n * (0.045 * i) + d * (0.05 * i)
            b = a + d * run1
            c = b + d * abs(jog) + n * jog
            e = c + d * max(run2 - 0.09 * i, 0.15)
            lines.append([a, b, c, e])
        if not all(ok(q) and ok((q + r) / 2) for ln in lines for q, r in zip(ln, ln[1:] + ln[-1:])):
            continue
        for ln in lines:
            for q, r in zip(ln[:-1], ln[1:]):
                t = (r - q).normalized()
                side = Vector((-t.y, t.x)) * (w / 2)
                q2, r2 = q - t * (w / 2), r + t * (w / 2)
                flat([q2 - side, r2 - side, r2 + side, q2 + side], m)
            for c in (ln[0], ln[-1]):
                h = w * 1.3
                flat([c + Vector((-h, -h)), c + Vector((h, -h)), c + Vector((h, h)), c + Vector((-h, h))], m)


def gear(mb, pos, r, teeth, m="Dark_Iron", t=0.08):
    """A toothed wheel lying against a wall that faces -X or +X (its axle along X), centred on
    pos: a disc, a square tooth every 360 / teeth degrees and a brass hub."""
    pos = Vector(pos)
    cyl(mb, pos, r, t, m, axis="x", segs=max(teeth, 10))
    for k in range(teeth):
        a = 2 * math.pi * k / teeth
        box(mb, pos + Vector((0, math.cos(a) * (r + 0.03), math.sin(a) * (r + 0.03))), (t, 0.11, 2 * math.pi * r / teeth * 0.5), m, rot=(a, 0, 0))
    cyl(mb, pos, r * 0.28, t + 0.06, "Brass", axis="x", segs=10)
    for k in range(4):                                     # four round holes' worth of dark spokes
        a = math.pi / 4 + math.pi / 2 * k
        cyl(mb, pos + Vector((-t / 2 - 0.004, math.cos(a) * r * 0.6, math.sin(a) * r * 0.6)), r * 0.16, 0.01, "Soot", axis="x", segs=8)


def valve(mb, pos, axis="x", r=0.17):
    """A red hand wheel on a short stem, its spindle along axis ("x" or "y"), centred on pos."""
    pos = Vector(pos)
    torus(mb, pos, r, 0.025, "Valve_Red", axis=axis, segs=16, rsegs=5)
    d = Vector((1, 0, 0)) if axis == "x" else Vector((0, 1, 0))
    side = Vector((0, 1, 0)) if axis == "x" else Vector((1, 0, 0))
    for v in (side, Vector((0, 0, 1))):
        bar(mb, pos - v * r, pos + v * r, 0.025, "Valve_Red")
    tube(mb, pos - d * 0.16, pos + d * 0.04, 0.03, "Brass", segs=8)


def gauge(mb, pos, axis="x", facing=1, r=0.13):
    """A brass pressure gauge with a pale dial, facing +axis or -axis (facing = +1 / -1)."""
    pos = Vector(pos)
    d = (Vector((1, 0, 0)) if axis == "x" else Vector((0, 1, 0))) * facing
    cyl(mb, pos, r, 0.07, "Brass", axis=axis, segs=12)
    cyl(mb, pos + d * 0.04, r * 0.8, 0.02, "Gauge_Face", axis=axis, segs=12)


# ════════════════════════════════════════════════════════════════
#  Plan. Units: metres. Origin = the middle of the screen wall on the floor, -Y = toward the
#  audience. The screen wall is y = 0 (its alcove goes back to y = ALC_D), the back wall is
#  y = BACK_Y, the side walls x = +-HALF_W.
#
#  Cross-section (the owner's sketch), the same all the way down the hall, mirrored left/right:
#    side wall straight up to a ledge (LEDGE_Z), a slanted window leaning in from the ledge up
#    to (SLANT_X, SHELF_Z), a flat shelf in to UPPER_X, the upper wall straight up to UPPER_Z,
#    a chamfer in to CEIL_HW and the flat ceiling at CEIL_Z.
# ════════════════════════════════════════════════════════════════
HALF_W = 9.0
BACK_Y = -34.0                     # (round 3: the hall is twice as long as it was)
LEDGE_Z = 6.0
SLANT_X, SHELF_Z = 7.35, 9.0
UPPER_X, UPPER_Z = 5.0, 11.0
CEIL_HW, CEIL_Z = 4.0, 12.0
FRAME_YS = tuple(-0.2 - 2.8 * k for k in range(13))        # the steel portal frames down the hall (the last at -33.8)
WAINSCOT_H = 1.2                   # the wood panelling inside the alcoves
ALC_HW, ALC_D, ALC_TOP = 5.0, 0.6, 7.6     # the screen alcove: half width, depth, height
SCREEN_W, SCREEN_H = 8.6, 4.8375   # same picture as the Lecture Hall (Panel)
SCREEN_Y, SCREEN_Z0 = -0.1, 1.9    # the picture floats just proud of the wall, bottom 1.9 m up
PILLAR_D = 0.8                     # a pillar is 1.3 m wide and stands this far out from its wall
PILLAR_TOP, PILLAR_TOP_TALL = LEDGE_Z - 0.1, 8.2     # side / back pillars stop under the ledge
SIDE_PILLAR_YS = tuple(-5.4 - 4.4 * k for k in range(7))    # a side-wall pillar every 4.4 m (the last at -31.8)
# pillars: (x, y, yaw, tall). Built facing -Y; yaw turns the face into the room.
PILLARS = ([(s * (ALC_HW + 0.65), -PILLAR_D / 2, 0.0, True) for s in (-1, 1)]                    # beside the screen alcove
           + [(-HALF_W + PILLAR_D / 2, y, math.pi / 2, False) for y in SIDE_PILLAR_YS]           # left wall
           + [(HALF_W - PILLAR_D / 2, y, -math.pi / 2, False) for y in SIDE_PILLAR_YS[1:]]       # right wall (the forge takes the first)
           + [(s * 5.65, BACK_Y + PILLAR_D / 2, math.pi, False) for s in (-1, 1)])               # back wall
# wall alcoves between the pillars: (wall, centre along the wall, half width). Walls: "L", "R"
# (centre = y) and "B" the back wall (centre = x). One art frame hangs in each (ART_n markers,
# numbered in this order).
ALCOVES = ([("L", y - 2.2, 1.2) for y in SIDE_PILLAR_YS[:-1]] + [("R", y - 2.2, 1.2) for y in SIDE_PILLAR_YS[1:-1]]
           + [("B", -3.55, 1.0), ("B", 3.55, 1.0)])        # 6 left, 5 right, 2 back = 13 (ART_COUNT in the room script)
ALCOVE_Z0, ALCOVE_Z1, ALCOVE_D = 0.35, 4.5, 0.5
ART_Z = 2.65                       # middle of the art frames
# the forge: built out from the right wall, centred on y = FORGE_Y
FORGE_Y, FORGE_D = -5.4, 1.5       # FORGE_D = how far the chimney breast stands out
FORGE_HW, STACK_HW = 2.6, 1.7      # half width of the body / of the stack above the shoulders
HEARTH_Z = 1.1                     # the firebox floor (top of the base)
FIREBOX_HW, FIREBOX_TOP = 1.0, 2.9
# the window bays the sunbeams come through: centre along the hall, per side (SHAFT_SkyL_n /
# SHAFT_SkyR_n markers; the morning sun uses the left ones, the afternoon sun the right ones),
# and half width; the room script's sunbeams need the half sizes (forge_hall_room.gd:
# skylight_half). The right side has no glass from the screen wall to SOLID_TO (round 3: no
# window round the forge), so its bays start behind the seats.
SKY_YS = {"L": (-1.6, -4.4, -18.4, -24.0, -29.6), "R": (-15.6, -21.2, -26.8)}
SOLID_TO = -8.6                    # right side: stone instead of glass from y = 0 back to here
SKY_HW = 1.25
SKY_HALF_SLANT = 1.37
# seating: three rows either side of a centre aisle, each row a step higher than the one in front
ROW_YS = (-8.5, -10.4, -12.3)
TIER_Z = (0.0, 0.35, 0.7)
TIER_Y0 = (None, -9.5, -11.4)      # where the 2nd and 3rd steps begin (front edge)
TIER_HW, TIER_BACK = 6.2, -13.4    # the stepped block: half width, back edge
SEATS_PER_SIDE, SEAT_X0, SEAT_PITCH = 5, 1.1, 1.0     # 5 + 5 seats a row = 30; 1 m apart: the
SEAT_H = 0.45                                         # default Seat spacing keeps them all
# presenter podiums: (x, y) of each podium's centre, left to right as the audience sees it
PODIUMS = [(-7.3, -1.7), (-5.3, -2.3), (5.3, -2.3), (7.3, -1.7)]
PRESENTER_W, PRESENTER_H = 1.3, 1.25         # the feed plane behind each podium (must match the room)
PRESENTER_BACK, PRESENTER_LIFT = 0.45, 0.75  # plane: this far behind the podium, bottom this high
# lanterns: centre of each lantern, on a short chain from the shelf (the outer four) or the
# ceiling (the two down the middle) straight above it
LANTERNS = ([Vector((s * 6.2, y, 8.05)) for y in (-3.6, -12.4, -21.2, -30.0) for s in (-1, 1)]
            + [Vector((0.0, y, 10.9)) for y in (-8.0, -17.0, -26.0)])
MID_LANTERN = 8                    # index of the first lantern down the middle (TARGET_Lantern)
# the three small live screens the room script builds (forge_hall_room.gd, _build_live_screens):
# one rises out of the floor chip's inner square, two hang on the screen wall above the alcove
CHIP = (0.0, -4.6)                 # centre of the floor chip (and of SCREEN_Lift)
UPPER_SCREENS = ((-2.6, 9.4), (2.6, 9.4))        # (x, z) of the middle of each upper screen
# the second floor chip, in the back half of the hall
CHIP2 = (0.0, -24.0)


def ceil_z(x):
    """Height of the underside of the roof above x (the cross-section in the Plan above)."""
    ax = abs(x)
    if ax > SLANT_X:
        return LEDGE_Z + (HALF_W - ax) * (SHELF_Z - LEDGE_Z) / (HALF_W - SLANT_X)
    if ax > UPPER_X:
        return SHELF_Z
    if ax > CEIL_HW:
        return UPPER_Z + (UPPER_X - ax) * (CEIL_Z - UPPER_Z) / (UPPER_X - CEIL_HW)
    return CEIL_Z


# Surfaces the light inlays lie in: each maps its own 2D coordinates to a point `l` metres in
# front of it (see traces()). Walls use (distance along the wall, height); the floor (x, y).
S_LEFT = lambda y, z, l: Vector((-HALF_W + l, y, z))
S_RIGHT = lambda y, z, l: Vector((HALF_W - l, y, z))
S_BACK = lambda x, z, l: Vector((x, BACK_Y + l, z))
S_FRONT = lambda x, z, l: Vector((x, -l, z))
S_FLOOR = lambda x, y, l: Vector((x, y, l))
S_FORGE = lambda y, z, l: Vector((HALF_W - FORGE_D - l, y, z))
# Wall coordinates for alcoves: (distance along the wall, depth behind the wall face, height)
W_MAP = {"L": lambda a, d, z: Vector((-HALF_W - d, a, z)),
         "R": lambda a, d, z: Vector((HALF_W + d, a, z)),
         "B": lambda a, d, z: Vector((a, BACK_Y - d, z))}
W_SURF = {"L": S_LEFT, "R": S_RIGHT, "B": S_BACK}


def setup_materials():
    """Every material the hall uses. Names must stay in step with forge_hall_room.gd (its neon
    and ember lists) and the room scene's glow_materials."""
    tex_mat("Stone_Slab", "slab_granite.png", 0.16, 0.0)       # polished granite
    tex_mat("Pillar_Marble", "pillar_marble.png", 0.14, 0.0)   # the pillars: lighter, veined marble
    tex_mat("Forge_Granite", "forge_granite.png", 0.24, 0.55)  # the forge: granite with a metallic glint
    tex_mat("Floor_Tiles", "floor_slab.png", 0.12, 0.0)
    tex_mat("Diamond_Plate", "diamond_plate.png", 0.5, 0.9)
    tex_mat("Wood_Panel", "wood_panel.png", 0.6)
    tex_mat("Roof_Planks", "roof_planks.png", 0.85)
    tex_mat("Metal_Plate", "metal_plate.png", 0.45, 0.8)
    tex_mat("Rune_Sign", "rune_sign.png", 0.5, 0.0, emit=2.5)
    mat("Beam_Wood", (0.11, 0.07, 0.045), 0.8)
    mat("Bench_Wood", (0.2, 0.12, 0.07), 0.55)
    mat("Barrel_Wood", (0.25, 0.15, 0.08), 0.7)
    mat("Log_Wood", (0.08, 0.05, 0.035), 0.9)
    mat("Dark_Iron", (0.05, 0.05, 0.06), 0.5, 0.7)
    mat("Steel_Girder", (0.09, 0.095, 0.11), 0.45, 0.9)
    mat("Pipe_Metal", (0.13, 0.13, 0.15), 0.4, 0.9)
    mat("Brass", (0.55, 0.38, 0.16), 0.35, 1.0)
    mat("Valve_Red", (0.5, 0.05, 0.03), 0.5, 0.3)
    mat("Gauge_Face", (0.9, 0.88, 0.8), 0.6, 0.0, (0.9, 0.85, 0.7), 0.4)
    mat("Soot", (0.012, 0.01, 0.01), 0.95)
    mat("Neon_Cyan", (0.1, 0.9, 1.0), 0.3, 0.0, (0.1, 0.85, 1.0), 4.0)
    mat("Neon_Orange", (1.0, 0.45, 0.08), 0.3, 0.0, (1.0, 0.42, 0.06), 4.0)
    mat("Neon_Purple", (0.7, 0.25, 1.0), 0.3, 0.0, (0.65, 0.2, 1.0), 4.0)
    # the fine second layer of circuit lines: dimmer than the main inlays
    mat("Neon_Fine_Cyan", (0.1, 0.7, 0.8), 0.3, 0.0, (0.1, 0.8, 1.0), 1.6)
    mat("Neon_Fine_Amber", (0.8, 0.45, 0.1), 0.3, 0.0, (1.0, 0.5, 0.1), 1.6)
    mat("Duct_Metal", (0.36, 0.38, 0.41), 0.38, 0.9)          # galvanised ducting
    mat("Copper", (0.62, 0.3, 0.16), 0.3, 1.0)
    mat("Pipe_Glow", (1.0, 0.4, 0.1), 0.3, 0.0, (1.0, 0.36, 0.06), 2.5)
    mat("Lantern_Glass", (1.0, 0.8, 0.5), 0.2, 0.0, (1.0, 0.7, 0.36), 2.2)
    mat("Sky_Glass", (1.0, 0.9, 0.7), 0.3, 0.0, (1.0, 0.85, 0.6), 1.6)
    mat("Embers", (0.5, 0.1, 0.02), 0.8, 0.0, (1.0, 0.28, 0.04), 3.0)
    mat("Screen_Black", (0.0, 0.0, 0.0), 0.5)


# ════════════════════════════════════════════════════════════════
#  Floor, walls, the upper hall
# ════════════════════════════════════════════════════════════
def build_floor():
    """The polished stone floor (3 m slabs), including the floor of the screen alcove, and the
    light inlays in it: an eight-sided "chip" outline in the middle of the open floor with
    leads running out to the screen wall, the forge, the boiler, the aisle and the side aisles."""
    mb = MB("Floor")
    floor_quad(mb, -HALF_W, HALF_W, BACK_Y, 0.0, 0.0, "Floor_Tiles", uvs=6.0)
    floor_quad(mb, -ALC_HW, ALC_HW, 0.0, ALC_D, 0.0, "Floor_Tiles", uvs=6.0)
    cx, cy, r = 0.0, -4.6, 1.5
    k = r * math.sin(math.pi / 8) / math.cos(math.pi / 8)          # half a side of the octagon
    ring = [(cx + r, cy - k), (cx + r, cy + k), (cx + k, cy + r), (cx - k, cy + r), (cx - r, cy + k), (cx - r, cy - k), (cx - k, cy - r), (cx + k, cy - r), (cx + r, cy - k)]
    traces(mb, S_FLOOR, [ring], "Neon_Orange", 0.08, pads=False)
    traces(mb, S_FLOOR, [[(cx - 0.5, cy - 0.5), (cx + 0.5, cy - 0.5), (cx + 0.5, cy + 0.5), (cx - 0.5, cy + 0.5), (cx - 0.5, cy - 0.5)]], "Neon_Orange", 0.05, pads=False)
    d = r * 0.7071
    leads = []
    for s in (-1, 1):
        # to the screen wall, in three parallel lines
        for i, off in enumerate((-0.16, 0.0, 0.16)):
            leads.append([(s * (d + off), cy + d - off), (s * (2.5 + off), cy + d + (2.5 - d) - off), (s * (2.5 + off), -0.45 - 0.2 * i)])
        # down the side aisles to the back of the hall
        leads.append([(s * d, cy - d), (s * 2.4, cy - d - (2.4 - d)), (s * 6.0, cy - d - (2.4 - d)), (s * 7.4, cy - d - (2.4 - d) - 1.4), (s * 7.4, BACK_Y + 1.2)])
        # up the centre aisle as far as the first step
        leads.append([(s * 0.2, cy - r), (s * 0.2, -9.25)])
    # to the forge hearth and to the boiler
    for off in (-0.16, 0.0, 0.16):
        leads.append([(r, cy + off), (4.0 + off, cy + off), (4.8 + off, cy - 0.8 + off), (6.55, cy - 0.8 + off)])
    leads.append([(-r, cy), (-4.0, cy), (-6.2, cy + 2.2), (-6.2, -1.9), (-7.4, -1.9)])
    # the second chip, in the back half: leads out to both side aisles, on to the back door,
    # forward to the seats, and to the engine and the workbench
    c2x, c2y = CHIP2
    ring2 = [(c2x + (px - cx), c2y + (py - cy)) for (px, py) in ring]
    traces(mb, S_FLOOR, [ring2], "Neon_Orange", 0.08, pads=False)
    traces(mb, S_FLOOR, [[(c2x - 0.5, c2y - 0.5), (c2x + 0.5, c2y - 0.5), (c2x + 0.5, c2y + 0.5), (c2x - 0.5, c2y + 0.5), (c2x - 0.5, c2y - 0.5)]], "Neon_Orange", 0.05, pads=False)
    for s in (-1, 1):
        for off in (-0.16, 0.0, 0.16):
            leads.append([(s * r, c2y + off), (s * (5.4 + off), c2y + off), (s * (6.4 + off), c2y - 1.0 + off), (s * 7.25, c2y - 1.0 + off)])
        leads.append([(s * 0.2, c2y - r), (s * 0.2, BACK_Y + 0.6)])
        leads.append([(s * 0.2, c2y + r), (s * 0.2, TIER_BACK - 0.5)])
        leads.append([(s * d, c2y + d), (s * 3.2, c2y + d + (3.2 - d)), (s * 3.2, -17.2), (s * 4.4, -16.0), (s * 6.6, -16.0)])
    traces(mb, S_FLOOR, leads, "Neon_Cyan", 0.06)
    # the fine layer over the whole floor (not under the stepped seats, the forge or the chips)
    fine_circuit(mb, S_FLOOR, (-HALF_W + 0.3, HALF_W - 0.3, BACK_Y + 0.3, -0.3), 101, 0.36,
                 avoid=[(-TIER_HW - 0.1, TIER_HW + 0.1, TIER_BACK - 0.1, -9.4), (HALF_W - FORGE_D - 0.8, HALF_W, FORGE_Y - FORGE_HW - 0.3, FORGE_Y + FORGE_HW + 0.3),
                        (cx - 1.7, cx + 1.7, cy - 1.7, cy + 1.7), (c2x - 1.7, c2x + 1.7, c2y - 1.7, c2y + 1.7)])
    mb.done()


def _wall_with_holes(mb, S, a0, a1, z0, z1, holes):
    """A flat stretch of stone wall with rectangular openings. S = the wall's surface (S_LEFT ...),
    a0..a1 along it, z0..z1 up it; holes = [(h0, h1, hz0, hz1)] sorted along the wall, not touching."""
    def piece(b0, b1, y0, y1):
        if b1 - b0 < 1e-4 or y1 - y0 < 1e-4:
            return
        face_to(mb, [S(b0, y0, 0), S(b1, y0, 0), S(b1, y1, 0), S(b0, y1, 0)], "Stone_Slab",
                [(b0 / 6.0, y0 / 6.0), (b1 / 6.0, y0 / 6.0), (b1 / 6.0, y1 / 6.0), (b0 / 6.0, y1 / 6.0)], S((b0 + b1) / 2, (y0 + y1) / 2, 1.0))
    at = a0
    for (h0, h1, hz0, hz1) in sorted(holes):
        piece(at, h0, z0, z1)
        piece(h0, h1, z0, hz0)
        piece(h0, h1, hz1, z1)
        at = h1
    piece(at, a1, z0, z1)


def _alcove(mb, wall, c, hw):
    """One wall alcove: a recess with stone sides, a wood-panelled back (wainscot below, dark
    boards above, a ledge between) and an orange inlay line round its opening."""
    M, S = W_MAP[wall], W_SURF[wall]
    a0, a1, z0, z1, D = c - hw, c + hw, ALCOVE_Z0, ALCOVE_Z1, ALCOVE_D
    inside = M(c, -1.0, (z0 + z1) / 2)
    F = lambda pts, m, uv: face_to(mb, [M(*p) for p in pts], m, uv, inside)
    L = 2 * hw
    F([(a0, D, z0), (a1, D, z0), (a1, D, z0 + WAINSCOT_H), (a0, D, z0 + WAINSCOT_H)], "Wood_Panel", [(0, 0), (L / 2.4, 0), (L / 2.4, 1), (0, 1)])
    F([(a0, D, z0 + WAINSCOT_H), (a1, D, z0 + WAINSCOT_H), (a1, D, z1), (a0, D, z1)], "Roof_Planks", [(0, 0), (L / 2.0, 0), (L / 2.0, 2.0), (0, 2.0)])
    for a in (a0, a1):
        F([(a, 0, z0), (a, D, z0), (a, D, z1), (a, 0, z1)], "Stone_Slab", [(0, z0 / 6), (D / 6, z0 / 6), (D / 6, z1 / 6), (0, z1 / 6)])
    for z in (z0, z1):
        F([(a0, 0, z), (a1, 0, z), (a1, D, z), (a0, D, z)], "Stone_Slab", [(a0 / 6, 0), (a1 / 6, 0), (a1 / 6, D / 6), (a0 / 6, D / 6)])
    # the ledge on top of the wainscot (a thin wooden moulding)
    p0, p1 = M(a0, D - 0.05, z0 + WAINSCOT_H + 0.04), M(a1, D - 0.05, z0 + WAINSCOT_H + 0.04)
    bar(mb, p0, p1, 0.09, "Beam_Wood")
    g, cut = 0.14, 0.3
    traces(mb, S, [[(a0 - g, z0 - 0.05), (a0 - g, z1 + g - cut), (a0 - g + cut, z1 + g), (a1 + g - cut, z1 + g), (a1 + g, z1 + g - cut), (a1 + g, z0 - 0.05)]], "Neon_Orange", 0.05)


def _wall_bus(mb, S, a0, a1, flip=False):
    """Three cyan inlay lines along a wall above the alcoves, from a0 to a1, stepping down
    halfway (the "data bus"), with one short branch dropping to a pad."""
    mid = (a0 + a1) / 2
    sgn = -1 if a1 < a0 else 1
    paths = []
    for i in range(3):
        z = 5.4 - 0.15 * i
        j = mid + sgn * (0.15 * i - 0.2)
        paths.append([(a0, z), (j, z), (j + sgn * 0.25, z - 0.25), (a1, z - 0.25)])
    q = a0 + (a1 - a0) * (0.82 if flip else 0.18)
    paths.append([(q, 5.4 - 0.3 - (0.25 if flip else 0.0)), (q + sgn * 0.2, 4.9 - (0.25 if flip else 0.0)), (q + sgn * 0.2, 4.72)])
    traces(mb, S, paths, "Neon_Cyan", 0.05)


def build_walls():
    """The lower walls (floor to the ledge) with their alcoves and light inlays, the screen wall
    with the big alcove the screen floats in, and both end walls above the ledge."""
    mb = MB("Walls")
    for wall, S in (("L", S_LEFT), ("R", S_RIGHT), ("B", S_BACK)):
        holes = [(c - hw, c + hw, ALCOVE_Z0, ALCOVE_Z1) for (w, c, hw) in ALCOVES if w == wall]
        if wall == "B":
            _wall_with_holes(mb, S, -HALF_W, HALF_W, 0.0, LEDGE_Z, holes)
        else:
            _wall_with_holes(mb, S, BACK_Y, 0.0, 0.0, LEDGE_Z, holes)
    for (w, c, hw) in ALCOVES:
        _alcove(mb, w, c, hw)
    # the cyan bus lines, bay by bay between the pillars (none behind the forge)
    bays = [(a - 0.8, b + 0.8) for a, b in zip(SIDE_PILLAR_YS[:-1], SIDE_PILLAR_YS[1:])] + [(SIDE_PILLAR_YS[-1] - 0.8, BACK_Y + 0.3)]
    for k, (a0, a1) in enumerate([(-0.4, SIDE_PILLAR_YS[0] + 0.8)] + bays):
        _wall_bus(mb, S_LEFT, a0, a1, k % 2 == 1)
    for k, (a0, a1) in enumerate([(-0.4, FORGE_Y + FORGE_HW + 0.2)] + bays[1:]):
        _wall_bus(mb, S_RIGHT, a0, a1, k % 2 == 0)
    # the fine layer on the lower walls, clear of the alcoves, the pillars, the forge and the door
    for wall, S in (("L", S_LEFT), ("R", S_RIGHT)):
        keep_off = [(c - hw - 0.2, c + hw + 0.2, 0.0, ALCOVE_Z1 + 0.22) for (w, c, hw) in ALCOVES if w == wall]
        keep_off += [(y - 0.68, y + 0.68, 0.0, LEDGE_Z) for y in SIDE_PILLAR_YS]
        if wall == "R":
            keep_off.append((FORGE_Y - FORGE_HW - 0.4, FORGE_Y + FORGE_HW + 0.4, 0.0, LEDGE_Z))
        else:
            keep_off.append((-4.6, 0.0, 0.0, LEDGE_Z))       # the boiler corner's pipes and sign
        fine_circuit(mb, S, (BACK_Y + 0.3, -0.3, 0.3, 5.85), 201 if wall == "L" else 202, 1.6, keep_off, upright=0.35)
    fine_circuit(mb, S_BACK, (-HALF_W + 0.3, HALF_W - 0.3, 0.3, 5.0), 203, 0.5,
                 [(c - hw - 0.3, c + hw + 0.3, 0.0, ALCOVE_Z1 + 0.3) for (w, c, hw) in ALCOVES if w == "B"]
                 + [(-2.3, 2.3, 0.0, 5.0), (-6.6, -4.7, 0.0, LEDGE_Z), (4.7, 6.6, 0.0, LEDGE_Z), (6.2, HALF_W, 0.0, 2.2)], upright=0.6)
    for s in (-1, 1):       # the screen wall either side of the tall pillars, and a strip over the alcove
        fine_circuit(mb, S_FRONT, (min(s * 6.45, s * 8.8), max(s * 6.45, s * 8.8), 0.4, 5.8), 204 + s, 0.6, upright=0.7)
    fine_circuit(mb, S_FRONT, (-4.4, 4.4, ALC_TOP + 0.28, 8.12), 206, 1.2, upright=0.2)
    for (a0, a1) in ((-8.7, -6.5), (-4.8, -2.5), (2.5, 4.8), (6.5, 8.7)):
        _wall_bus(mb, S_BACK, a0, a1, a0 > 0)
    # the end walls above the ledge follow the cross-section: three pieces each
    for S, hole in ((S_BACK, False), (S_FRONT, True)):
        to = lambda x, z: S(x, z, 1.0)
        uv = lambda pts: [(p[0] / 6.0, p[1] / 6.0) for p in pts]
        def P(pts):
            face_to(mb, [S(p[0], p[1], 0) for p in pts], "Stone_Slab", uv(pts), to(sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)))
        if hole:    # the screen alcove rises above the ledge line: leave it open
            xa = HALF_W - (ALC_TOP - LEDGE_Z) * (HALF_W - SLANT_X) / (SHELF_Z - LEDGE_Z)
            for s in (-1, 1):
                P([(s * ALC_HW, LEDGE_Z), (s * HALF_W, LEDGE_Z), (s * xa, ALC_TOP), (s * ALC_HW, ALC_TOP)])
            P([(-xa, ALC_TOP), (xa, ALC_TOP), (SLANT_X, SHELF_Z), (-SLANT_X, SHELF_Z)])
        else:
            P([(-HALF_W, LEDGE_Z), (HALF_W, LEDGE_Z), (SLANT_X, SHELF_Z), (-SLANT_X, SHELF_Z)])
        P([(-UPPER_X, SHELF_Z), (UPPER_X, SHELF_Z), (UPPER_X, UPPER_Z), (-UPPER_X, UPPER_Z)])
        P([(-UPPER_X, UPPER_Z), (UPPER_X, UPPER_Z), (CEIL_HW, CEIL_Z), (-CEIL_HW, CEIL_Z)])
    # screen wall below the ledge, either side of the alcove
    for s in (-1, 1):
        _wall_with_holes(mb, S_FRONT, min(s * ALC_HW, s * HALF_W), max(s * ALC_HW, s * HALF_W), 0.0, LEDGE_Z, [])
    # the screen alcove: wood wainscot and dark boards on its back, stone sides and ceiling
    wall_quad(mb, "y", ALC_D, -ALC_HW, ALC_HW, 0.0, WAINSCOT_H, "Wood_Panel", -1, u=(0, 2 * ALC_HW / 2.4), v=(0, 1))
    wall_quad(mb, "y", ALC_D, -ALC_HW, ALC_HW, WAINSCOT_H, ALC_TOP, "Roof_Planks", -1, u=(0, 2 * ALC_HW / 2.0), v=(0, 3.0))
    box(mb, (0, ALC_D - 0.06, WAINSCOT_H + 0.04), (2 * ALC_HW, 0.12, 0.08), "Beam_Wood")     # the ledge on the wainscot
    for s in (-1, 1):
        wall_quad(mb, "x", s * ALC_HW, 0.0, ALC_D, 0.0, ALC_TOP, "Stone_Slab", -s, u=(0, ALC_D / 6), v=(0, ALC_TOP / 6))
    floor_quad(mb, -ALC_HW, ALC_HW, 0.0, ALC_D, ALC_TOP, "Stone_Slab", uvs=6.0, up=False)
    # the projector rail the hologram screen rises from: a metal bar along the alcove floor
    box(mb, (0, ALC_D - 0.3, 0.12), (7.0, 0.4, 0.24), "Metal_Plate", uvs=1.0)
    box(mb, (0, ALC_D - 0.3, 0.245), (6.6, 0.12, 0.01), "Neon_Cyan")
    # inlays over the alcove: a cyan line along its top, with circuit branches up the gable
    paths = [[(-ALC_HW - 0.1, ALC_TOP + 0.14), (ALC_HW + 0.1, ALC_TOP + 0.14)]]
    for s in (-1, 1):
        paths.append([(s * 4.6, ALC_TOP + 0.14), (s * 4.6, 9.2), (s * 4.2, 9.6), (s * 4.2, 10.6)])
        paths.append([(s * 4.75, ALC_TOP + 0.14), (s * 4.75, 9.9), (s * 4.5, 10.15), (s * 4.5, 10.6)])
    traces(mb, S_FRONT, paths, "Neon_Cyan", 0.06)
    # (the wall between those branches is left clear for the reply screen and the two small
    # live screens the room script hangs there: UPPER_SCREENS)
    traces(mb, S_FRONT, [[(-0.9, 11.25), (-0.3, 11.25), (0, 11.55), (0.3, 11.25), (0.9, 11.25)]], "Neon_Orange", 0.06)
    # the two pipes across the top of the alcove (as in the reference)
    pipe_run(mb, [(-ALC_HW, 0.3, 7.28), (ALC_HW, 0.3, 7.28)], 0.11, "Pipe_Metal", collar="Brass")
    pipe_run(mb, [(-ALC_HW, 0.36, 7.0), (ALC_HW, 0.36, 7.0)], 0.07, "Pipe_Metal", collar="Dark_Iron")
    mb.done()


def build_back_door():
    """The tall double door in the middle of the back wall: plated leaves in a stone frame with a
    pointed head, outlined with a cyan inlay."""
    mb = MB("Back_Door")
    y = BACK_Y
    hw, h = 1.6, 3.7
    box(mb, (0, y + 0.08, h / 2), (2 * hw, 0.16, h), "Metal_Plate", uvs=1.6)
    box(mb, (0, y + 0.18, h / 2), (0.08, 0.06, h), "Dark_Iron")                      # where the leaves meet
    for s in (-1, 1):
        box(mb, (s * (hw + 0.2), y + 0.15, h / 2), (0.4, 0.3, h), "Stone_Slab", uvs=6.0)
        box(mb, (s * 0.35, y + 0.2, 1.7), (0.08, 0.08, 0.5), "Brass")                # handles
    # the pointed head over the door
    prism(mb, [(-hw - 0.4, h), (hw + 0.4, h), (hw + 0.4, h + 0.35), (0, h + 1.0), (-hw - 0.4, h + 0.35)], "xz", y, y + 0.3, "Stone_Slab", uvs=6.0)
    door_face = lambda x, z, l: Vector((x, BACK_Y + 0.3 + l, z))
    traces(mb, door_face, [[(-hw - 0.2, 0.4), (-hw - 0.2, h + 0.3), (0, h + 0.82), (hw + 0.2, h + 0.3), (hw + 0.2, 0.4)]], "Neon_Cyan", 0.06)
    mb.done()


def build_upper():
    """Everything above the ledge, the same down the whole hall: the stone ledge, the slanted
    windows (glowing glass in steel glazing bars), the shelf and the ceiling in very dark
    diamond plate, the stone upper walls, and the steel frame: a portal frame at every FRAME_YS
    following the cross-section, tied together by girders running the length of the hall."""
    mb = MB("Upper")
    y0, y1, L = BACK_Y, 0.0, -BACK_Y
    yc = BACK_Y / 2
    inside = (0, yc, 3.0)
    for s in (-1, 1):
        # ledge (also along the back wall, below)
        box(mb, (s * (HALF_W - 0.175), yc, LEDGE_Z), (0.35, L, 0.2), "Stone_Slab", uvs=6.0)
        # the slanted window: one long pane, steel glazing bars over it
        a, b = Vector((s * HALF_W, 0, LEDGE_Z)), Vector((s * SLANT_X, 0, SHELF_Z))
        # (the right side is solid stone from the screen wall back past the forge: SOLID_TO)
        g1 = SOLID_TO if s > 0 else y1                    # the glass runs from the back wall to here
        face_to(mb, [(a.x, y0, a.z), (a.x, g1, a.z), (b.x, g1, b.z), (b.x, y0, b.z)], "Sky_Glass", [(0, 0), (1, 0), (1, 1), (0, 1)], inside)
        if g1 < y1:
            sl = (b - a).length
            face_to(mb, [(a.x, g1, a.z), (a.x, y1, a.z), (b.x, y1, b.z), (b.x, g1, b.z)], "Stone_Slab",
                    [(g1 / 6, 0), (y1 / 6, 0), (y1 / 6, sl / 6), (g1 / 6, sl / 6)], inside)
        n = Vector((-s * (SHELF_Z - LEDGE_Z), 0, -(HALF_W - SLANT_X))).normalized()      # into the room
        for t in (0.34, 0.67):
            p = a.lerp(b, t) + n * 0.04
            bar(mb, (p.x, y0, p.z), (p.x, g1, p.z), 0.08, "Steel_Girder")
        for k in range(len(FRAME_YS) - 1):
            ym = (FRAME_YS[k] + FRAME_YS[k + 1]) / 2
            if ym < g1:
                bar(mb, (a.x + n.x * 0.04, ym, a.z + n.z * 0.04), (b.x + n.x * 0.04, ym, b.z + n.z * 0.04), 0.08, "Steel_Girder")
        # shelf (underside), upper wall, chamfer
        face_to(mb, [(s * SLANT_X, y0, SHELF_Z), (s * SLANT_X, y1, SHELF_Z), (s * UPPER_X, y1, SHELF_Z), (s * UPPER_X, y0, SHELF_Z)], "Diamond_Plate",
                [(0, y0 / 2), (0, y1 / 2), ((SLANT_X - UPPER_X) / 2, y1 / 2), ((SLANT_X - UPPER_X) / 2, y0 / 2)], inside)
        face_to(mb, [(s * UPPER_X, y0, SHELF_Z), (s * UPPER_X, y1, SHELF_Z), (s * UPPER_X, y1, UPPER_Z), (s * UPPER_X, y0, UPPER_Z)], "Stone_Slab",
                [(y0 / 6, SHELF_Z / 6), (y1 / 6, SHELF_Z / 6), (y1 / 6, UPPER_Z / 6), (y0 / 6, UPPER_Z / 6)], inside)
        face_to(mb, [(s * UPPER_X, y0, UPPER_Z), (s * UPPER_X, y1, UPPER_Z), (s * CEIL_HW, y1, CEIL_Z), (s * CEIL_HW, y0, CEIL_Z)], "Diamond_Plate",
                [(0, y0 / 2), (0, y1 / 2), (0.7, y1 / 2), (0.7, y0 / 2)], inside)
        # girders along the hall at every corner of the cross-section
        for (x, z, t) in ((HALF_W - 0.5, LEDGE_Z + 0.22, 0.2), (SLANT_X - 0.13, SHELF_Z - 0.15, 0.24), (UPPER_X - 0.15, SHELF_Z - 0.15, 0.24),
                          (UPPER_X - 0.15, UPPER_Z - 0.08, 0.2), (CEIL_HW - 0.06, CEIL_Z - 0.15, 0.24)):
            box(mb, (s * x, yc, z), (t, L, t), "Steel_Girder")
        box(mb, (s * (UPPER_X - 0.06), yc, (SHELF_Z + UPPER_Z) / 2), (0.1, L, 0.16), "Steel_Girder")     # rail along the upper wall
    box(mb, (0, BACK_Y + 0.175, LEDGE_Z), (2 * HALF_W, 0.35, 0.2), "Stone_Slab", uvs=6.0)
    face_to(mb, [(-CEIL_HW, y0, CEIL_Z), (CEIL_HW, y0, CEIL_Z), (CEIL_HW, y1, CEIL_Z), (-CEIL_HW, y1, CEIL_Z)], "Diamond_Plate",
            [(-CEIL_HW / 2, y0 / 2), (CEIL_HW / 2, y0 / 2), (CEIL_HW / 2, y1 / 2), (-CEIL_HW / 2, y1 / 2)], inside)
    box(mb, (0, yc, CEIL_Z - 0.15), (0.24, L, 0.24), "Steel_Girder")
    # the portal frames: one polyline of girders per frame, a plate at every corner
    half = [(HALF_W - 0.2, LEDGE_Z + 0.1), (SLANT_X - 0.13, SHELF_Z - 0.15), (UPPER_X - 0.15, SHELF_Z - 0.15), (UPPER_X - 0.15, UPPER_Z - 0.08), (CEIL_HW - 0.06, CEIL_Z - 0.15)]
    line = half + [(-x, z) for (x, z) in reversed(half)]
    for y in FRAME_YS:
        for (p, q) in zip(line[:-1], line[1:]):
            bar(mb, (p[0], y, p[1]), (q[0], y, q[1]), 0.3, "Steel_Girder")
        for (x, z) in line[1:-1]:
            box(mb, (x, y, z), (0.5, 0.36, 0.5), "Steel_Girder")
            cyl(mb, (x, y - 0.19, z), 0.07, 0.03, "Brass", axis="y", segs=8)
        for s in (-1, 1):       # a steel post up the upper wall, and a foot on the ledge
            box(mb, (s * (HALF_W - 0.25), y, LEDGE_Z + 0.16), (0.5, 0.4, 0.12), "Steel_Girder")
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Pillars, forge, lanterns, pipes
# ════════════════════════════════════════════════════════════
def _pillar_mesh(name, top):
    """One pillar, built facing -Y around its own origin, carved as a single piece: a flared
    foot, a plain shaft and a flared head up to `top`. Three inlaid light traces (cyan, orange,
    purple) run up its face like tracks on a circuit board, and a cyan chevron sits in the head."""
    mb = MB(name)
    hd = PILLAR_D / 2
    prism(mb, [(-0.85, 0), (0.85, 0), (0.85, 0.75), (0.65, 1.15), (-0.65, 1.15), (-0.85, 0.75)], "xz", -hd - 0.1, hd, "Pillar_Marble", uvs=6.0)
    box(mb, (0, 0, (1.15 + top - 0.9) / 2), (1.3, PILLAR_D, top - 0.9 - 1.15), "Pillar_Marble", uvs=6.0)
    prism(mb, [(-0.65, top - 0.9), (0.65, top - 0.9), (0.9, top - 0.45), (0.9, top), (-0.9, top), (-0.9, top - 0.45)], "xz", -hd - 0.15, hd, "Pillar_Marble", uvs=6.0)
    face = lambda x, z, l: Vector((x, -hd - l, z))
    zt = top - 1.15
    traces(mb, face, [[(-0.3, 1.4), (-0.3, 2.6), (-0.1, 2.8), (-0.1, zt)]], "Neon_Cyan", 0.06)
    traces(mb, face, [[(0.1, 1.4), (0.1, 3.3), (0.3, 3.5), (0.3, zt)]], "Neon_Orange", 0.06)
    traces(mb, face, [[(0.3, 1.4), (0.3, 2.9)], [(-0.3, 3.2), (-0.3, zt)]], "Neon_Purple", 0.06)
    fine_circuit(mb, face, (-0.58, 0.58, 1.3, zt + 0.1), 301 + int(top * 10), 1.6, upright=0.9)
    head = lambda x, z, l: Vector((x, -hd - 0.15 - l, z))
    traces(mb, head, [[(-0.6, top - 0.2), (0, top - 0.5), (0.6, top - 0.2)]], "Neon_Cyan", 0.06, pads=False)
    return mb.done()


def build_pillars():
    """Two pillar meshes (the tall pair beside the screen alcove, and the ones that stop under
    the ledge), placed at every PILLARS spot."""
    src = {}
    for k, (x, y, yaw, tall) in enumerate(PILLARS):
        name = "Pillar_%d" % (k + 1)
        if tall not in src:
            o = _pillar_mesh(name, PILLAR_TOP_TALL if tall else PILLAR_TOP)
            o.location = (x, y, 0)
            o.rotation_euler = (0, 0, yaw)
            src[tall] = o
        else:
            instance(name, src[tall], (x, y, 0), yaw)


def build_forge():
    """The forge fireplace on the right wall: a stone body with the firebox (an opening with
    cut-off top corners), a hearth slab on two corbels, a low fire slot under the hearth, angled
    shoulders and a stack that goes up and out through the slanted window. A metal arch frames
    the firebox, orange inlay lines arch over it, cyan ones follow the shoulders, and a coil
    spring stands either side. The flames are not here: the room script builds them at the
    FIRE_ markers."""
    mb = MB("Forge")
    xw, xf = HALF_W, HALF_W - FORGE_D          # the wall, and the front face of the body
    xc, yc = (xw + xf) / 2, FORGE_Y
    B = lambda y0, y1, z0, z1, m="Forge_Granite": box(mb, (xc, yc + (y0 + y1) / 2, (z0 + z1) / 2), (FORGE_D, y1 - y0, z1 - z0), m, uvs=6.0)
    slot_hw, slot_z0, slot_z1 = 0.9, 0.25, 0.8
    # the base, leaving the low fire slot open
    B(-FORGE_HW, -slot_hw, 0, HEARTH_Z)
    B(slot_hw, FORGE_HW, 0, HEARTH_Z)
    B(-slot_hw, slot_hw, 0, slot_z0)
    B(-slot_hw, slot_hw, slot_z1, HEARTH_Z)
    # the piers either side of the firebox and the lintel over it
    B(-FORGE_HW, -FIREBOX_HW, HEARTH_Z, FIREBOX_TOP)
    B(FIREBOX_HW, FORGE_HW, HEARTH_Z, FIREBOX_TOP)
    B(-FORGE_HW, FORGE_HW, FIREBOX_TOP, 3.4)
    for s in (-1, 1):       # the cut-off top corners of the firebox opening
        prism(mb, [(yc + s * FIREBOX_HW, FIREBOX_TOP), (yc + s * (FIREBOX_HW - 0.45), FIREBOX_TOP), (yc + s * FIREBOX_HW, FIREBOX_TOP - 0.45)],
              "yz", xf, xw, "Forge_Granite", uvs=6.0)
    # shoulders and stack (the stack leaves through the slanted window)
    prism(mb, [(yc - FORGE_HW, 3.4), (yc + FORGE_HW, 3.4), (yc + STACK_HW, 4.6), (yc - STACK_HW, 4.6)], "yz", xf, xw, "Forge_Granite", uvs=6.0)
    B(-STACK_HW, STACK_HW, 4.6, 8.8)
    # soot inside both openings
    wall_quad(mb, "x", xw - 0.02, yc - FIREBOX_HW, yc + FIREBOX_HW, HEARTH_Z, FIREBOX_TOP, "Soot", -1)
    wall_quad(mb, "x", xw - 0.02, yc - slot_hw, yc + slot_hw, slot_z0, slot_z1, "Soot", -1)
    floor_quad(mb, xf, xw, yc - FIREBOX_HW, yc + FIREBOX_HW, HEARTH_Z + 0.005, "Soot")
    # the hearth slab and its corbels
    box(mb, (xf - 0.3, yc, HEARTH_Z - 0.05), (0.7, 2 * FORGE_HW + 0.4, 0.2), "Forge_Granite", uvs=6.0)
    for s in (-1, 1):
        prism(mb, [(xf - 0.55, HEARTH_Z - 0.15), (xf, HEARTH_Z - 0.15), (xf, HEARTH_Z - 0.75)], "xz", yc + s * 1.9 - 0.2, yc + s * 1.9 + 0.2, "Forge_Granite", uvs=6.0)
    # the metal arch round the firebox (proud of the stone), with bolts on the shoulders
    fx = xf - 0.07
    arch = lambda hw, top, cut: [(yc - hw, HEARTH_Z + 0.1), (yc - hw, top - cut), (yc - hw + cut, top), (yc + hw - cut, top), (yc + hw, top - cut), (yc + hw, HEARTH_Z + 0.1)]
    frame = arch(1.2, 3.15, 0.5)
    for a, b in zip(frame[:-1], frame[1:]):
        bar(mb, (fx, a[0], a[1]), (fx, b[0], b[1]), 0.24, "Metal_Plate")
    for s in (-1, 1):
        cyl(mb, (fx - 0.05, yc + s * 1.85, 3.95), 0.3, 0.12, "Metal_Plate", axis="x", segs=8)
        cyl(mb, (fx - 0.12, yc + s * 1.85, 3.95), 0.1, 0.06, "Brass", axis="x", segs=8)
    # light inlays: two orange arches over the firebox, cyan along the shoulders and up the stack
    traces(mb, S_FORGE, [arch(1.55, 3.6, 0.7)[1:-1], [(yc - 0.9, 4.2), (yc - 0.45, 4.45), (yc + 0.45, 4.45), (yc + 0.9, 4.2)]], "Neon_Orange", 0.07)
    cy = [[(yc - FORGE_HW + 0.14, 3.3), (yc - STACK_HW + 0.14, 4.75), (yc + STACK_HW - 0.14, 4.75), (yc + FORGE_HW - 0.14, 3.3)]]
    for s in (-1, 1):
        cy.append([(yc + s * (STACK_HW - 0.35), 5.2), (yc + s * (STACK_HW - 0.35), 6.6), (yc + s * (STACK_HW - 0.7), 6.95), (yc + s * (STACK_HW - 0.7), 7.6)])
        cy.append([(yc + s * 0.3, 5.2), (yc + s * 0.3, 7.2)])
    traces(mb, S_FORGE, cy, "Neon_Cyan", 0.06)
    for s in (-1, 1):
        # the coil springs on the piers
        cx, cy2 = xf - 0.28, yc + s * 1.85
        cyl(mb, (cx, cy2, 2.0), 0.12, 1.5, "Dark_Iron", segs=10)
        for k in range(7):
            torus(mb, (cx, cy2, 1.4 + 0.2 * k), 0.2, 0.05, "Pipe_Metal", segs=14, rsegs=5)
    # logs and embers in both fires
    for (z, hw, n) in ((HEARTH_Z, 0.7, 3), (slot_z0, 0.75, 2)):
        for k in range(n):
            tube(mb, (xc - 0.25 + 0.3 * k, yc - hw, z + 0.1), (xc - 0.4 + 0.3 * k, yc + hw, z + 0.1), 0.09, "Log_Wood", segs=8)
        box(mb, (xc - 0.1, yc, z + 0.03), (0.9, 2 * hw - 0.2, 0.06), "Embers")
    fine_circuit(mb, S_FORGE, (yc - STACK_HW + 0.1, yc + STACK_HW - 0.1, 4.7, 8.6), 401, 1.4, upright=0.8)
    _forge_machinery(mb, xf, xc, yc)
    mb.done()


def _forge_machinery(mb, xf, xc, yc):
    """Round 3: the steam-age and science-fiction machinery on the forge. xf = the body's front
    face (x), xc = the middle of its depth, yc = its centre along the wall. On the stack:
    riveted bands, a pair of meshing gears, a brass ring round the big gauge and a louvred vent.
    From the shoulders: a piston either side. On the hearth slab: two glowing cells in brass
    cages. Round the risers: copper coils. On the side facing the seats: a control panel with
    lit buttons, two gauges and a lever."""
    # riveted bands round the stack
    for z in (5.0, 6.45, 7.85):
        box(mb, (xf - 0.03, yc, z), (0.06, 2 * STACK_HW + 0.08, 0.22), "Metal_Plate", uvs=1.0)
        y = yc - STACK_HW + 0.15
        while y < yc + STACK_HW - 0.1:
            for dz in (-0.07, 0.07):
                cyl(mb, (xf - 0.07, y, z + dz), 0.028, 0.03, "Brass", axis="x", segs=6)
            y += 0.34
    # two gears that mesh, between the upper bands
    gear(mb, (xf - 0.08, yc - 0.48, 7.15), 0.5, 14)
    gear(mb, (xf - 0.08, yc + 0.5, 7.1), 0.3, 9, "Brass")
    # a brass ring with six lit studs round the big gauge (the gauge itself is in build_pipes)
    torus(mb, (xf - 0.05, yc, 5.6), 0.36, 0.04, "Brass", axis="x", segs=18, rsegs=5)
    for k in range(6):
        a = math.pi / 3 * k + math.pi / 6
        cyl(mb, (xf - 0.06, yc + math.cos(a) * 0.5, 5.6 + math.sin(a) * 0.5), 0.04, 0.04, "Neon_Fine_Amber", axis="x", segs=6)
    # the louvred vent at the top of the stack
    box(mb, (xf - 0.03, yc, 8.35), (0.06, 1.5, 0.5), "Dark_Iron")
    for k in range(5):
        box(mb, (xf - 0.08, yc, 8.17 + 0.09 * k), (0.07, 1.36, 0.02), "Metal_Plate", rot=(0, 0.5, 0), uvs=1.0)
    for s in (-1, 1):
        # a piston from each shoulder up to the stack: iron barrel, brass collars, bright rod
        a = Vector((xf - 0.2, yc + s * 2.3, 3.75))
        b = Vector((xf - 0.2, yc + s * 1.5, 5.25))
        mid = a.lerp(b, 0.55)
        tube(mb, a, mid, 0.12, "Dark_Iron", segs=10)
        tube(mb, mid, b, 0.045, "Pipe_Metal", segs=8)
        for q in (a.lerp(b, 0.06), a.lerp(b, 0.5)):
            tube(mb, q, q + (b - a).normalized() * 0.07, 0.15, "Brass", segs=10)
        for q in (a, b):
            cyl(mb, q, 0.1, 0.3, "Dark_Iron", axis="x", segs=8)
        # a glowing cell in a brass cage on each end of the hearth slab
        cx, cy = xf - 0.4, yc + s * 2.5
        z0 = HEARTH_Z + 0.05
        cyl(mb, (cx, cy, z0 + 0.3), 0.1, 0.5, "Neon_Fine_Cyan", segs=10)
        for z in (z0 + 0.03, z0 + 0.57):
            cyl(mb, (cx, cy, z), 0.15, 0.06, "Brass", segs=10)
        for k in range(4):
            ang = math.pi / 4 + math.pi / 2 * k
            bar(mb, (cx + 0.14 * math.cos(ang), cy + 0.14 * math.sin(ang), z0 + 0.05), (cx + 0.14 * math.cos(ang), cy + 0.14 * math.sin(ang), z0 + 0.55), 0.025, "Brass")
        # copper coils round the risers beside the body
        for k in range(7):
            torus(mb, (xf + 0.4, yc + s * (FORGE_HW + 0.25), 2.0 + 0.13 * k), 0.15, 0.03, "Copper", segs=12, rsegs=4)
    # the control panel on the side that faces the seats (the body's -Y side)
    py = yc - FORGE_HW - 0.04
    box(mb, (xc, py, 1.95), (1.0, 0.08, 1.1), "Metal_Plate", uvs=1.0)
    for r in range(3):
        for c in range(4):
            m = ("Neon_Fine_Amber", "Neon_Fine_Cyan", "Valve_Red", "Neon_Fine_Cyan")[(r + c) % 4]
            box(mb, (xc - 0.33 + 0.14 * c, py - 0.05, 1.62 + 0.13 * r), (0.07, 0.03, 0.07), m)
    for dx in (0.12, 0.34):
        gauge(mb, (xc + dx - 0.02, py - 0.04, 2.25), "y", -1, r=0.09)
    bar(mb, (xc + 0.3, py - 0.05, 1.6), (xc + 0.36, py - 0.22, 1.85), 0.03, "Brass")            # the lever
    sphere(mb, (xc + 0.36, py - 0.22, 1.87), 0.05, "Valve_Red", subdiv=1)
    box(mb, (xc - 0.1, py - 0.05, 2.3), (0.5, 0.02, 0.12), "Neon_Fine_Cyan")                    # a readout strip


def build_lanterns():
    """One hexagonal lantern (iron frame, glowing glass) placed at every LANTERNS spot, each on
    a short chain so it hangs close under the shelf or the ceiling."""
    mb = MB("Lantern_1")
    cyl(mb, (0, 0, 0.42), 0.3, 0.22, "Dark_Iron", segs=6, r2=0.1)
    torus(mb, (0, 0, 0.6), 0.07, 0.02, "Dark_Iron", axis="x", segs=10, rsegs=4)
    cyl(mb, (0, 0, 0.0), 0.2, 0.62, "Lantern_Glass", segs=6, r2=0.25)
    cyl(mb, (0, 0, -0.36), 0.24, 0.1, "Dark_Iron", segs=6, r2=0.12)
    for k in range(6):
        a = math.pi / 3 * k
        bar(mb, (0.21 * math.cos(a), 0.21 * math.sin(a), -0.31), (0.26 * math.cos(a), 0.26 * math.sin(a), 0.31), 0.035, "Dark_Iron")
    src = mb.done()
    src.location = tuple(LANTERNS[0])
    for i, p in enumerate(LANTERNS[1:]):
        instance("Lantern_%d" % (i + 2), src, tuple(p))
    ch = MB("Lantern_Chains")
    for p in LANTERNS:
        top = ceil_z(p.x)
        bar(ch, (p.x, p.y, p.z + 0.62), (p.x, p.y, top), 0.03, "Dark_Iron")
        z = p.z + 0.72
        while z < top - 0.05:                         # chain links: a small block every 12 cm
            box(ch, (p.x, p.y, z), (0.07, 0.05, 0.07), "Dark_Iron")
            z += 0.12
        cyl(ch, (p.x, p.y, top - 0.03), 0.12, 0.06, "Steel_Girder", segs=8)      # the ceiling plate
    ch.done()


def build_pipes():
    """Steam-age pipework round the hall: a main and a thinner line along each ledge, joined
    across the back wall, with hand wheels and gauges; drops from the main down the wall beside
    the left pillars; a pair of risers on the forge stack; a manifold over the back door; a
    line along each upper wall; and a steam tank in the back right corner."""
    mb = MB("Pipes")
    zl = LEDGE_Z + 0.36
    for s in (-1, 1):
        x = s * (HALF_W - 0.52)
        pipe_run(mb, [(x, -0.25, zl), (x, BACK_Y + 0.5, zl)], 0.13, "Pipe_Metal", collar="Brass")
        for y in (-3.4, -11.2, -20.0, -28.4):                                         # fat couplings
            tube(mb, (x, y, zl), (x, y - 0.5, zl), 0.2, "Brass", segs=12)
        pipe_run(mb, [(s * (HALF_W - 0.2), -0.25, zl + 0.5), (s * (HALF_W - 0.2), BACK_Y + 0.2, zl + 0.5)], 0.06, "Pipe_Glow" if s > 0 else "Pipe_Metal")
        for y in (-7.2, -13.0, -19.2, -25.6, -31.0):
            valve(mb, (x - s * 0.24, y, zl), "x")
            gauge(mb, (x - s * 0.2, y - 0.6, zl + 0.05), "x", -s)
        # along the upper wall
        xu = s * (UPPER_X - 0.25)
        pipe_run(mb, [(xu, -0.6, 10.2), (xu, BACK_Y + 0.6, 10.2)], 0.09, "Pipe_Metal", collar="Brass")
        pipe_run(mb, [(xu, -0.6, 9.75), (xu, -6.0, 9.75), (xu, -6.0, 9.35), (xu, BACK_Y + 0.6, 9.35)], 0.05, "Pipe_Glow" if s < 0 else "Pipe_Metal")
    # the two ledge mains meet across the back wall
    pipe_run(mb, [(-HALF_W + 0.52, BACK_Y + 0.5, zl), (HALF_W - 0.52, BACK_Y + 0.5, zl)], 0.13, "Pipe_Metal", collar="Brass")
    # drops beside the left pillars: from the main down the wall, then into it
    for py in SIDE_PILLAR_YS:
        y = py + 0.95
        pipe_run(mb, [(-HALF_W + 0.52, y, zl), (-HALF_W + 0.2, y, zl - 0.3), (-HALF_W + 0.2, y, 5.75), (-HALF_W, y, 5.75)], 0.06, "Pipe_Metal")
    # risers on the forge stack, bending in over the shoulders
    xf = HALF_W - FORGE_D
    for s in (-1, 1):
        y = FORGE_Y + s * (STACK_HW + 0.3)
        pipe_run(mb, [(xf + 0.4, FORGE_Y + s * (FORGE_HW + 0.25), 0.0), (xf + 0.4, FORGE_Y + s * (FORGE_HW + 0.25), 3.6), (xf + 0.4, y, 4.5), (xf + 0.4, y, zl)], 0.09, "Pipe_Metal", collar="Brass")
        valve(mb, (xf + 0.18, FORGE_Y + s * (FORGE_HW + 0.25), 1.5), "x")
    gauge(mb, (xf - 0.04, FORGE_Y, 5.6), "x", -1, r=0.22)
    # the manifold over the back door
    yb = BACK_Y + 0.22
    pipe_run(mb, [(-4.7, yb, 5.45), (4.7, yb, 5.45)], 0.1, "Pipe_Metal", collar="Brass")
    for x in (-4.7, 4.7):
        pipe_run(mb, [(x, yb, 5.45), (x, yb, zl - 0.1), (x, BACK_Y + 0.5, zl)], 0.1, "Pipe_Metal")
    for x in (-1.2, 0.0, 1.2):
        tube(mb, (x, yb, 5.45), (x, yb, 5.05), 0.06, "Pipe_Metal")
        gauge(mb, (x, yb + 0.06, 4.95), "y", 1)
    for x in (-3.0, 3.0):
        valve(mb, (x, yb + 0.22, 5.45), "y")
    # the steam tank against the back wall, right of the right-hand back pillar
    tx, ty = 7.3, BACK_Y + 0.65
    cyl(mb, (tx, ty, 0.85), 0.45, 1.3, "Pipe_Metal", axis="x", segs=14, smooth=True)
    for sx in (-1, 1):
        sphere(mb, (tx + sx * 0.65, ty, 0.85), 0.45, "Pipe_Metal", subdiv=2, scale=(0.4, 1, 1))
        box(mb, (tx + sx * 0.4, ty, 0.2), (0.12, 0.7, 0.4), "Dark_Iron")
        cyl(mb, (tx + sx * 0.3, ty, 0.85), 0.47, 0.08, "Brass", axis="x", segs=14)
    pipe_run(mb, [(tx, ty, 1.3), (tx, ty, zl - 0.1), (tx, BACK_Y + 0.5, zl)], 0.07, "Pipe_Metal", collar="Brass")
    gauge(mb, (tx, ty + 0.47, 0.95), "y", 1)
    mb.done()


def build_ducts():
    """Round 3: ducting and more pipework hung under the flat ceiling, down the whole hall, all
    of it inside the upper level (|x| under 4 m, above 10.7 m) so nothing crosses the slanted
    windows. Left of centre: a rectangular galvanised air duct with a flange at every bay,
    grilles underneath, a fan unit, and round branches out to the left upper wall. Right of
    centre: a round duct with flanges, and three pipes side by side (one copper) with hand
    wheels, tied across to the left at three of the frames."""
    mb = MB("Ducts")
    y0, y1 = -0.6, BACK_Y + 0.6
    yc, L = (y0 + y1) / 2, y0 - y1
    dx, dz = -2.2, 11.25
    box(mb, (dx, yc, dz), (1.0, L, 0.6), "Duct_Metal")
    for k in range(len(FRAME_YS) - 1):
        ym = (FRAME_YS[k] + FRAME_YS[k + 1]) / 2
        box(mb, (dx, ym, dz), (1.08, 0.06, 0.68), "Duct_Metal")                    # flange
        for sx in (-0.42, 0.42):                                                   # hangers up to the ceiling
            bar(mb, (dx + sx, ym, dz + 0.3), (dx + sx, ym, CEIL_Z - 0.02), 0.03, "Dark_Iron")
        if k % 2 == 1:                                                             # a grille underneath
            box(mb, (dx, ym + 0.9, dz - 0.31), (0.7, 1.0, 0.03), "Dark_Iron")
            for j in range(5):
                box(mb, (dx, ym + 0.5 + 0.2 * j, dz - 0.34), (0.62, 0.03, 0.04), "Duct_Metal")
    # the fan unit, with a round grille underneath
    fy = -17.0
    box(mb, (dx, fy, dz - 0.05), (1.3, 1.7, 0.8), "Metal_Plate", uvs=1.0)
    cyl(mb, (dx, fy, dz - 0.47), 0.48, 0.06, "Dark_Iron", segs=14)
    for k in range(3):
        box(mb, (dx, fy, dz - 0.5), (0.9, 0.05, 0.03), "Duct_Metal", rot=(0, 0, math.pi / 3 * k))
    # round branches to the left upper wall, ending in a cone-shaped outlet pointing down
    for by in (-10.0, -21.2, -29.6):
        pipe_run(mb, [(dx - 0.5, by, dz), (-4.25, by, dz), (-4.25, by, 9.75)], 0.2, "Duct_Metal", collar="Duct_Metal")
        cyl(mb, (-4.25, by, 9.62), 0.2, 0.26, "Duct_Metal", segs=12, r2=0.36)
    # the round duct right of centre
    rx, rz = 1.6, 11.32
    tube(mb, (rx, y0, rz), (rx, y1, rz), 0.3, "Duct_Metal", segs=14)
    y = y0 - 0.7
    while y > y1:
        cyl(mb, (rx, y, rz), 0.34, 0.05, "Duct_Metal", axis="y", segs=14)
        y -= 1.4
    for k in range(0, len(FRAME_YS) - 1, 2):
        ym = (FRAME_YS[k] + FRAME_YS[k + 1]) / 2
        bar(mb, (rx, ym, rz + 0.3), (rx, ym, CEIL_Z - 0.02), 0.03, "Dark_Iron")
    # three pipes side by side
    for (x, r, m) in ((2.65, 0.07, "Pipe_Metal"), (2.9, 0.05, "Copper"), (3.2, 0.09, "Pipe_Metal")):
        pipe_run(mb, [(x, y0, 11.5), (x, y1, 11.5)], r, m, collar="Brass")
    for y in (-6.0, -15.0, -24.0, -31.0):
        valve(mb, (3.2, y, 11.3), "y", r=0.14)
        box(mb, (2.92, y - 0.8, 11.62), (0.8, 0.08, 0.06), "Dark_Iron")            # a pipe bracket
    for y in (-11.6, -22.8, -31.2):                 # ties across the hall, under the ducts
        pipe_run(mb, [(3.2, y, 11.5), (3.2, y, 10.75), (-3.7, y, 10.75), (-3.7, y, 11.6)], 0.06, "Pipe_Metal", collar="Brass")
        gauge(mb, (0.6, y - 0.08, 10.75), "y", -1, r=0.11)
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Screen, podiums, seating, props
# ════════════════════════════════════════════════════════════
def build_screen():
    """The TVScreen mesh the app shows the video on (its own object, by contract). A plain flat
    rectangle here: the room script reshapes it (moves, resizes and bends it) from the Room tab's
    screen settings, starting from this rectangle. It has no frame: it is a hologram."""
    x0, x1 = -SCREEN_W / 2, SCREEN_W / 2
    sb = MB("TVScreen")
    wall_quad(sb, "y", SCREEN_Y, x0, x1, SCREEN_Z0, SCREEN_Z0 + SCREEN_H, "Screen_Black", facing=-1)
    sb.done()


def podium_yaw(x, y):
    """Podiums turn a little toward the middle of the hall."""
    return math.atan2(-(0.0 - x), (-12.0 - y)) + math.pi


def build_podiums():
    """Four stone podiums, each its own object (PODIUM_n) so the room can hide it: a stone body
    with a cyan inlay down the front, a metal desk and a small lantern lamp on the desk
    (PODIUM_LIGHT_n goes at the lamp)."""
    for i, (x, y) in enumerate(PODIUMS):
        pm = MB("PODIUM_%d" % (i + 1))
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        P = lambda lx, ly, lz: tuple(Vector((x, y, 0)) + R @ Vector((lx, ly, lz)))
        box(pm, P(0, 0, 0.05), (0.95, 0.65, 0.1), "Stone_Slab", rot=(0, 0, yaw), uvs=6.0)
        box(pm, P(0, 0, 0.55), (0.72, 0.46, 0.95), "Stone_Slab", rot=(0, 0, yaw), uvs=6.0)
        front = lambda u, z, l: Vector(P(u, -0.23 - l, z))
        traces(pm, front, [[(-0.2, 0.3), (-0.2, 0.55), (0.0, 0.75), (0.0, 0.95)], [(0.2, 0.3), (0.2, 0.9)]], "Neon_Cyan", 0.04)
        box(pm, P(0, 0.02, 1.07), (0.84, 0.6, 0.05), "Metal_Plate", rot=(math.radians(-14), 0, yaw), uvs=1.0)
        box(pm, P(0, -0.28, 1.02), (0.84, 0.04, 0.08), "Dark_Iron", rot=(0, 0, yaw))
        cyl(pm, P(0.27, -0.12, 1.17), 0.06, 0.04, "Dark_Iron", segs=6)
        cyl(pm, P(0.27, -0.12, 1.28), 0.045, 0.18, "Lantern_Glass", segs=6)
        cyl(pm, P(0.27, -0.12, 1.4), 0.06, 0.06, "Dark_Iron", segs=6, r2=0.02)
        pm.done()


def podium_markers():
    """PRESENTER_n (feed plane: bottom centre, +Z of the marker faces the audience in Redot),
    PODIUM_LIGHT_n (the desk lamp: aims at the presenter's face)."""
    for i, (x, y) in enumerate(PODIUMS):
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        back = R @ Vector((0, PRESENTER_BACK, 0))
        base = Vector((x, y, 0)) + back + Vector((0, 0, PRESENTER_LIFT))
        pm = empty("PRESENTER_%d" % (i + 1), base)
        aim(pm, base + R @ Vector((0, -5.0, 0)), forward='-Y')
        lamp = Vector((x, y, 0)) + R @ Vector((0.27, -0.12, 1.3))
        lm = empty("PODIUM_LIGHT_%d" % (i + 1), lamp)
        aim(lm, base + Vector((0, 0, PRESENTER_H * 0.55)))


def build_seating():
    """The stepped stone block the back two rows stand on (with steps up the centre aisle, a cyan
    inlay along the face of each step and a rail along the back), and the six benches: wooden
    seats and backs on stone legs, five places each."""
    mb = MB("Seating")
    for t in (1, 2):
        y0, z0, z1 = TIER_Y0[t], TIER_Z[t - 1], TIER_Z[t]
        box(mb, (0, (y0 + TIER_BACK) / 2, (z0 + z1) / 2), (2 * TIER_HW, y0 - TIER_BACK, z1 - z0), "Stone_Slab", uvs=6.0)
        box(mb, (0, y0 + 0.175, z0 + 0.0875), (1.2, 0.35, 0.175), "Stone_Slab", uvs=6.0)      # the half step in the aisle
        riser = lambda x, z, l, y0=y0: Vector((x, y0 + l, z))
        zm = (z0 + z1) / 2
        traces(mb, riser, [[(s * 0.8, zm), (s * 3.0, zm), (s * 3.1, zm + 0.1), (s * (TIER_HW - 0.15), zm + 0.1)] for s in (-1, 1)], "Neon_Cyan", 0.04)
    # rail along the back edge of the top step
    zt = TIER_Z[2]
    for k in range(9):
        x = -TIER_HW + 0.1 + k * (2 * TIER_HW - 0.2) / 8
        bar(mb, (x, TIER_BACK + 0.08, zt), (x, TIER_BACK + 0.08, zt + 0.95), 0.06, "Dark_Iron")
    box(mb, (0, TIER_BACK + 0.08, zt + 0.95), (2 * TIER_HW, 0.08, 0.06), "Dark_Iron")
    # benches
    L = SEAT_PITCH * SEATS_PER_SIDE
    for y, z in zip(ROW_YS, TIER_Z):
        for s in (-1, 1):
            xc = s * (SEAT_X0 + SEAT_PITCH * (SEATS_PER_SIDE - 1) / 2)
            box(mb, (xc, y, z + SEAT_H - 0.04), (L, 0.5, 0.08), "Bench_Wood")
            for dx in (-L / 2 + 0.3, 0.0, L / 2 - 0.3):
                box(mb, (xc + dx, y, z + (SEAT_H - 0.08) / 2), (0.4, 0.4, SEAT_H - 0.08), "Stone_Slab", uvs=6.0)
                bar(mb, (xc + dx, y - 0.3, z), (xc + dx, y - 0.34, z + SEAT_H + 0.45), 0.06, "Dark_Iron")
            box(mb, (xc, y - 0.33, z + SEAT_H + 0.3), (L, 0.06, 0.3), "Bench_Wood")
    mb.done()


def _barrel(mb, x, y, z=0.0):
    """A wooden barrel with two iron hoops, standing on (x, y, z)."""
    cyl(mb, (x, y, z + 0.17), 0.33, 0.34, "Barrel_Wood", segs=12, r2=0.4)
    cyl(mb, (x, y, z + 0.5), 0.4, 0.32, "Barrel_Wood", segs=12)
    cyl(mb, (x, y, z + 0.83), 0.4, 0.34, "Barrel_Wood", segs=12, r2=0.33)
    for zz in (0.32, 0.68):
        cyl(mb, (x, y, z + zz), 0.415, 0.05, "Dark_Iron", segs=12)


def _crate(mb, x, y, z, size, yaw=0.0):
    """A wooden crate with iron corner bands, its bottom centre at (x, y, z)."""
    box(mb, (x, y, z + size / 2), (size, size, size), "Bench_Wood", rot=(0, 0, yaw))
    box(mb, (x, y, z + size - 0.03), (size + 0.04, size + 0.04, 0.06), "Dark_Iron", rot=(0, 0, yaw))
    box(mb, (x, y, z + 0.03), (size + 0.04, size + 0.04, 0.06), "Dark_Iron", rot=(0, 0, yaw))


def build_props():
    """What fills the rest of the room. Front left corner: a boiler with pipes running up and
    along the wall (one of them glowing orange) and the round cyan sign. Out on the floor: an
    anvil on a stump. The back half: a free-standing workbench, a steam engine with a flywheel,
    barrels and crates."""
    mb = MB("Props")
    xl = -HALF_W
    # boiler in the front-left corner
    bx, by = xl + 0.75, -1.5
    cyl(mb, (bx, by, 1.25), 0.5, 1.7, "Pipe_Metal", segs=14, smooth=True)
    sphere(mb, (bx, by, 2.1), 0.5, "Pipe_Metal", subdiv=2, scale=(1, 1, 0.5))
    for a in range(3):
        ang = 2.1 * a + 0.4
        bar(mb, (bx + 0.4 * math.cos(ang), by + 0.4 * math.sin(ang), 0), (bx + 0.4 * math.cos(ang), by + 0.4 * math.sin(ang), 0.45), 0.08, "Dark_Iron")
    for z in (0.7, 1.8):
        cyl(mb, (bx, by, z), 0.52, 0.08, "Brass", segs=14)
    gauge(mb, (bx + 0.5, by, 1.4), "x", 1, r=0.14)
    box(mb, (bx + 0.51, by, 1.0), (0.04, 0.3, 0.12), "Embers")                    # the glowing fire door
    valve(mb, (bx + 0.2, by - 0.62, 1.6), "y")
    # pipes from the boiler: up, along the wall, and up to the main on the ledge
    px = xl + 0.25
    pipe_run(mb, [(bx, by, 2.3), (bx, by, 4.3), (px, by, 4.3), (px, -4.2, 4.3), (px, -4.2, LEDGE_Z - 0.1)], 0.1, "Pipe_Metal", collar="Brass")
    pipe_run(mb, [(px, -0.5, 0.0), (px, -0.5, 3.9), (px, -3.9, 3.9), (px, -3.9, 2.2), (px, -2.6, 2.2)], 0.06, "Pipe_Glow")
    pipe_run(mb, [(bx + 0.3, by + 0.5, 0.5), (bx + 0.3, -0.35, 0.5), (bx + 0.3, -0.35, 3.2), (px, -0.35, 3.2), (px, -0.35, LEDGE_Z - 0.1)], 0.07, "Pipe_Metal", collar="Brass")
    # the round sign
    cyl(mb, (xl + 0.08, -3.0, 3.1), 0.62, 0.1, "Metal_Plate", axis="x", segs=8)
    wall_quad(mb, "x", xl + 0.14, -3.45, -2.55, 2.65, 3.55, "Rune_Sign", 1)
    # the anvil on its stump, out on the floor
    ax, ay = -6.9, -5.9
    cyl(mb, (ax, ay, 0.28), 0.36, 0.56, "Log_Wood", segs=12)
    prism(mb, [(ay - 0.28, 0.56), (ay + 0.28, 0.56), (ay + 0.28, 0.66), (ay + 0.14, 0.72), (ay + 0.14, 0.86), (ay + 0.36, 0.9), (ay + 0.36, 1.02),
               (ay - 0.36, 1.02), (ay - 0.36, 0.9), (ay - 0.14, 0.86), (ay - 0.14, 0.72), (ay - 0.28, 0.66)], "yz", ax - 0.14, ax + 0.14, "Dark_Iron")
    cyl(mb, (ax, ay + 0.55, 0.96), 0.07, 0.4, "Dark_Iron", axis="y", segs=8, r2=0.01)   # the horn
    # right wall, front corner: pipes floor to ledge (as on the right of the reference)
    xr = HALF_W
    pipe_run(mb, [(xr - 0.3, -0.5, 0), (xr - 0.3, -0.5, 3.0), (xr - 0.3, -1.6, 3.0), (xr - 0.3, -1.6, LEDGE_Z - 0.1)], 0.11, "Pipe_Metal", collar="Brass")
    pipe_run(mb, [(xr - 0.25, -0.9, LEDGE_Z - 0.1), (xr - 0.25, -0.9, 3.6), (xr - 0.25, -2.2, 3.6), (xr - 0.25, -2.2, 1.4)], 0.06, "Pipe_Glow")
    valve(mb, (xr - 0.52, -1.6, 4.4), "x")
    gauge(mb, (xr - 0.44, -0.5, 1.8), "x", -1)
    # the workbench: free-standing in the back half (every wall bay there is an art alcove)
    wx, wy = 5.0, -19.6
    box(mb, (wx, wy, 0.92), (1.0, 2.2, 0.1), "Bench_Wood")
    for dy in (-0.95, 0.95):
        for ddx in (-0.4, 0.4):
            box(mb, (wx + ddx, wy + dy, 0.435), (0.12, 0.12, 0.87), "Beam_Wood")
    box(mb, (wx, wy, 0.3), (0.9, 2.0, 0.05), "Beam_Wood")
    box(mb, (wx, wy + 0.7, 1.05), (0.3, 0.5, 0.16), "Metal_Plate", uvs=1.0)       # a vice block
    _crate(mb, wx, wy - 0.5, 0.33, 0.45, 0.3)
    _crate(mb, wx + 1.0, wy + 0.3, 0.0, 0.6, 0.4)
    # the steam engine in the back half, left of the aisle: a bed plate, a copper cylinder with
    # its piston rod, and a spoked flywheel
    ex, ey = -5.0, -20.6
    box(mb, (ex, ey, 0.2), (1.3, 2.8, 0.4), "Metal_Plate", uvs=1.0)
    cyl(mb, (ex, ey - 0.7, 0.85), 0.34, 1.1, "Copper", axis="y", segs=14, smooth=True)
    for dy in (-1.27, -0.13):
        cyl(mb, (ex, ey + dy, 0.85), 0.37, 0.07, "Brass", axis="y", segs=14)
    box(mb, (ex, ey - 0.7, 0.5), (0.5, 0.9, 0.22), "Dark_Iron")
    tube(mb, (ex, ey - 0.1, 0.85), (ex, ey + 0.75, 1.05), 0.04, "Pipe_Metal", segs=8)          # the piston rod
    fy = ey + 0.95
    torus(mb, (ex - 0.25, fy, 1.25), 0.82, 0.07, "Dark_Iron", axis="x", segs=24, rsegs=6)
    for k in range(6):
        a = math.pi / 3 * k
        bar(mb, (ex - 0.25, fy, 1.25), (ex - 0.25, fy + 0.8 * math.cos(a), 1.25 + 0.8 * math.sin(a)), 0.05, "Dark_Iron")
    cyl(mb, (ex - 0.05, fy, 1.25), 0.13, 0.6, "Brass", axis="x", segs=10)
    for sx in (-0.42, 0.35):
        prism(mb, [(fy - 0.35, 0.4), (fy + 0.35, 0.4), (fy + 0.12, 1.3), (fy - 0.12, 1.3)], "yz", ex + sx - 0.05, ex + sx + 0.05, "Dark_Iron")
    gauge(mb, (ex + 0.36, ey - 0.7, 1.1), "x", 1)
    valve(mb, (ex, ey - 1.45, 0.85), "y")
    pipe_run(mb, [(ex, ey - 0.7, 1.19), (ex, ey - 0.7, 1.9), (ex - 0.6, ey - 0.7, 1.9), (ex - 0.6, ey - 0.7, 0.4)], 0.05, "Pipe_Metal", collar="Brass")
    # more barrels and crates down the back half
    for (bx2, by2) in ((7.6, -22.6), (7.0, -23.1), (-7.4, -27.2)):
        _barrel(mb, bx2, by2)
    _crate(mb, -7.3, -26.2, 0.0, 0.8, 0.2)
    _crate(mb, -7.2, -26.25, 0.8, 0.5, -0.3)
    _crate(mb, 7.2, -30.6, 0.0, 0.7, 0.1)
    # barrels and crates along the back wall, left of the left-hand back pillar
    _barrel(mb, -7.5, BACK_Y + 0.6)
    _barrel(mb, -6.7, BACK_Y + 0.65)
    _crate(mb, -7.1, BACK_Y + 0.6, 1.0, 0.6, 0.2)
    # and beside the forge
    _barrel(mb, HALF_W - 0.6, FORGE_Y - FORGE_HW - 0.75)
    _crate(mb, HALF_W - 0.55, FORGE_Y + FORGE_HW + 0.75, 0.0, 0.7, 0.15)
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Markers
# ════════════════════════════════════════════════════════════
def build_markers():
    """The Stream Rooms markers: LIGHTS_House with its LAMP_ empties (the lanterns, and a cyan
    wash either side), the SHAFT_Sky_n windows, FIRE_ spots and ART_n frames the room script
    builds on, the CAM_ presets, the presenter / chat / reply screen markers, the reaction
    targets and the 30 AUDIENCE_ seats."""
    screen_c = Vector((0, SCREEN_Y, SCREEN_Z0 + SCREEN_H / 2))
    lh = empty("LIGHTS_House", (0, 0, 0))
    for i, p in enumerate(LANTERNS):
        empty("LAMP_Lantern_%d" % (i + 1), p + Vector((0, 0, -0.5)), parent=lh)
    for s, n in ((-1, "L"), (1, "R")):
        for k, y in enumerate((-12.0, -26.0)):
            empty("LAMP_Neon_%s%d" % (n, k + 1), (s * 7.4, y, 4.4), parent=lh)
    # sunbeam windows, both sides: the marker sits in the middle of the pane. Its X axis runs
    # along the hall, its Y axis up the slant and its Z axis into the room; the room script
    # reads the pane's outline from those (X and -Z of the node in Redot) and skylight_half.
    for s, side in ((-1, "L"), (1, "R")):
        d = Vector((-s * (HALF_W - SLANT_X), 0, SHELF_Z - LEDGE_Z))
        up = d.normalized()
        n = Vector((-s * (SHELF_Z - LEDGE_Z), 0, -(HALF_W - SLANT_X))).normalized()
        for i, yc in enumerate(SKY_YS[side]):
            c = Vector((s * HALF_W, yc, LEDGE_Z)) + d * 0.5 + n * 0.1
            sk = empty("SHAFT_Sky%s_%d" % (side, i + 1), c)
            sk.rotation_euler = Matrix((Vector((0, -s, 0)), up, n)).transposed().to_euler()
    # the small live screens: SCREEN_Lift on the floor in the middle of the chip (the screen
    # rises out of the floor there), SCREEN_Upper_n at the middle of each screen on the wall
    # above the alcove; all face the audience
    aim(empty("SCREEN_Lift", (CHIP[0], CHIP[1], 0.0)), (CHIP[0], -30.0, 0.0), forward='-Y')
    for i, (x, z) in enumerate(UPPER_SCREENS):
        aim(empty("SCREEN_Upper_%d" % (i + 1), (x, -0.08, z)), (x, -30.0, z), forward='-Y')
    # the two fires: bottom centre of the flames, facing into the room
    xm = HALF_W - FORGE_D * 0.55
    for name, z in (("FIRE_Main", HEARTH_Z + 0.1), ("FIRE_Slot", 0.3)):
        aim(empty(name, (xm, FORGE_Y, z)), (0, FORGE_Y, z), forward='-Y')
    # the art frames: middle of each alcove's back wall, facing into the room
    for i, (wall, c, hw) in enumerate(ALCOVES):
        p = W_MAP[wall](c, ALCOVE_D - 0.03, ART_Z)
        aim(empty("ART_%d" % (i + 1), p), W_MAP[wall](c, -5.0, ART_Z), forward='-Y')
    cams = [("CAM_01_Centre_Aisle", Vector((0.0, -15.0, 2.4)), screen_c),
            # the reference picture's view: the screen alcove on the left, the forge on the right
            ("CAM_02_Forge_Corner", Vector((-7.2, -11.2, 2.3)), Vector((3.2, -2.0, 3.4))),
            ("CAM_03_Front_Row", Vector((0.0, -6.8, 1.4)), screen_c),
            ("CAM_04_Fireside", Vector((6.6, -9.0, 1.7)), Vector((-1.5, 0.0, 3.6))),
            ("CAM_05_Rafters", Vector((2.6, -31.0, 8.4)), Vector((0.0, -4.0, 3.0))),
            ("CAM_06_Skylight", Vector((-7.7, -8.0, 5.2)), Vector((7.0, -4.2, 1.4))),
            ("CAM_07_Panel_Wide", Vector((0.0, -7.2, 2.2)), Vector((0.0, 0.0, 2.6))),
            ("CAM_08_Panel_Left", Vector((-2.2, -5.4, 1.7)), Vector((-6.3, -1.6, 1.5))),
            ("CAM_09_Panel_Right", Vector((2.2, -5.4, 1.7)), Vector((6.3, -1.6, 1.5))),
            # the react-pause view: the forge fire, seen from the middle of the floor
            ("CAM_10_Reaction", Vector((2.6, -5.0, 1.6)), Vector((HALF_W, FORGE_Y, 2.3)))]
    for name, p, t in cams:
        aim(empty(name, p), t)
    podium_markers()
    # chat screen: top centre, just under the screen; reply screen on the wall above the alcove
    top = Vector((0.0, SCREEN_Y - 0.03, SCREEN_Z0 - 0.25))
    aim(empty("CHAT_Screen", top), top + Vector((0.0, -10.0, 0.0)), forward='-Y')
    rtop = Vector((0.0, -0.06, 9.5))
    aim(empty("REPLY_Screen", rtop), rtop + Vector((0.0, -10.0, 0.0)), forward='-Y')
    # reaction targets (!tomato forge ...)
    for name, p, to in (("TARGET_Forge", (HALF_W - FORGE_D - 0.1, FORGE_Y, 3.9), (0, FORGE_Y, 3.9)),
                        ("TARGET_Lantern", tuple(LANTERNS[MID_LANTERN]), (LANTERNS[MID_LANTERN].x, -30, LANTERNS[MID_LANTERN].z)),
                        ("TARGET_Anvil", (-6.9, -5.9, 1.1), (-6.9, -30, 1.1)),
                        ("TARGET_Boiler", (-HALF_W + 1.3, -1.5, 1.5), (0, -1.5, 1.5))):
        aim(empty(name, p), to, forward='-Y')
    # the seats: on the bench tops
    for r, (y, z) in enumerate(zip(ROW_YS, TIER_Z)):
        for s, side in ((-1, "L"), (1, "R")):
            for k in range(SEATS_PER_SIDE):
                empty("AUDIENCE_%d%s_%d" % (r + 1, side, k + 1), (s * (SEAT_X0 + SEAT_PITCH * k), y, z + SEAT_H), size=0.3)


def build_all():
    """Builds the whole hall from scratch (clearing the Hall collections first). Returns the
    polygon count per mesh object."""
    setup_materials()
    for cname in (COLL, MARKERS):
        c = bpy.data.collections.get(cname)
        if c:
            for o in list(c.objects):
                bpy.data.objects.remove(o, do_unlink=True)
    build_floor()
    build_walls()
    build_back_door()
    build_upper()
    build_pillars()
    build_forge()
    build_lanterns()
    build_pipes()
    build_ducts()
    build_screen()
    build_podiums()
    build_seating()
    build_props()
    build_markers()
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    return {o.name: len(o.data.polygons) for o in col(COLL).objects if o.type == "MESH"}


def export_glb(path=None):
    """Exports the Hall and Hall_Markers collections as a GLB (Y up, as Redot expects); path defaults to GLB."""
    path = path or GLB
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for cname in (COLL, MARKERS):
        for o in bpy.data.collections[cname].all_objects:
            o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials='EXPORT', export_image_format='AUTO')

