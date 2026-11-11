"""forge_hall_gen.py - builds the Forge Hall room in Blender.

    exec(open(r"C:\\Users\\jonza\\Documents\\RedotHomeTheater\\stream_rooms\\blender\\forge_hall_gen.py").read())
    build_all(); export_glb()

A tall stone workshop hall with a little science fiction in it (from the owner's reference
picture): chunky stone pillars with cyan, orange and purple light strips, a wide alcove with
pipes across its top where the big screen hangs, a big forge fireplace built out from the right
wall with a second fire slot under the hearth, hexagonal lanterns on chains, slanted skylights
in the roof and bands of cyan light running round the walls. The rest of the room is filled in
our own way: three stepped rows of benches for 30 chatters, four podiums beside the screen, a
workbench and anvil, a boiler with pipes, barrels and crates, and a double door at the back.

The fire itself, the sunbeams from the skylights and their patches on the floor are built by
the room script (rooms/forge_hall/forge_hall_room.gd) from the FIRE_ and SHAFT_ markers.

Textures come from blender/make_forge_textures.py (rooms/forge_hall/textures).
Output: rooms/forge_hall/forge_hall.glb. ROOT below is the owner's PC; set ROOT before exec on
another machine (the cloud build does).

Blender axes: origin = the middle of the screen wall on the floor. -Y = toward the audience and
the back wall (y = BACK_Y), +X = the forge wall, Z = up. Markers follow the Stream Rooms
contract (rooms/room.gd): PRESENTER_/CHAT_Screen/REPLY_Screen/TARGET_/FIRE_ empties point -Y
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


def neon(mb, pts, m, w=0.07):
    """A light strip: a thin square bar through the points in order (material = one of the Neon_ ones)."""
    for a, b in zip(pts[:-1], pts[1:]):
        bar(mb, a, b, w, m)


# ════════════════════════════════════════════════════════════════
#  Plan. Units: metres. Origin = the middle of the screen wall on the floor, -Y = toward the
#  audience. The screen wall is y = 0 (its alcove goes back to y = ALC_D), the back wall is
#  y = BACK_Y, the side walls x = +-HALF_W. The roof is a gable: eaves along the side walls,
#  the ridge running front to back over x = 0.
# ════════════════════════════════════════════════════════════════
HALF_W = 9.0
BACK_Y = -17.0
EAVE_Z, RIDGE_Z = 8.0, 12.0
WAINSCOT_H = 1.2                   # the wood panelling round the bottom of every wall
BAND_Z0, BAND_Z1 = 5.0, 5.7        # the metal band with the cyan light lines on the side / back walls
ALC_HW, ALC_D, ALC_TOP = 5.0, 0.6, 7.6     # the screen alcove: half width, depth, height
SCREEN_W, SCREEN_H = 8.6, 4.8375   # same picture as the Lecture Hall (Panel)
SCREEN_Y, SCREEN_Z0 = -0.1, 1.9    # the picture hangs just proud of the wall, bottom 1.9 m up
PILLAR_D = 0.8                     # a pillar is 1.3 m wide and stands this far out from its wall
# pillars: (x, y, yaw). Built facing -Y; yaw turns the face into the room.
PILLARS = ([(s * (ALC_HW + 0.65), -PILLAR_D / 2, 0.0) for s in (-1, 1)]                     # beside the alcove
           + [(-HALF_W + PILLAR_D / 2, y, math.pi / 2) for y in (-5.0, -9.4, -14.6)]        # left wall
           + [(HALF_W - PILLAR_D / 2, y, -math.pi / 2) for y in (-9.4, -14.6)]              # right wall
           + [(s * 5.65, BACK_Y + PILLAR_D / 2, math.pi) for s in (-1, 1)])                 # back wall
# the forge: built out from the right wall, centred on y = FORGE_Y
FORGE_Y, FORGE_D = -5.4, 1.5       # FORGE_D = how far the chimney breast stands out
FORGE_HW, STACK_HW = 2.6, 1.7      # half width of the body / of the stack above the shoulders
HEARTH_Z = 1.1                     # the firebox floor (top of the base)
FIREBOX_HW, FIREBOX_TOP = 1.0, 2.9
# skylights in the left roof slope: centres along the hall, half width along the hall, and the
# stretch of slope they cover (0 = eave, 1 = ridge). The room script's sunbeams need SKY_HALF
# (forge_hall_room.gd: skylight_half).
SKY_YS = (-2.2, -5.6)
SKY_HW = 1.4
SKY_S0, SKY_S1 = 0.3, 0.85
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
# lanterns: centre of each lantern (hung on a chain from the roof straight above it)
LANTERNS = [Vector(p) for p in ((-6.0, -3.0, 5.0), (5.6, -5.4, 4.3), (-6.6, -10.6, 5.0), (6.6, -10.6, 5.0),
                                (0.0, -15.0, 5.6), (-2.2, -6.6, 6.4))]


def roof_z(x):
    """Height of the underside of the roof above x."""
    return EAVE_Z + (HALF_W - abs(x)) * (RIDGE_Z - EAVE_Z) / HALF_W


def setup_materials():
    """Every material the hall uses. Names must stay in step with forge_hall_room.gd (its neon
    and ember lists) and the room scene's glow_materials."""
    tex_mat("Stone_Slab", "stone_slab.png", 0.85)
    tex_mat("Floor_Tiles", "floor_tiles.png", 0.6)
    tex_mat("Wood_Panel", "wood_panel.png", 0.6)
    tex_mat("Roof_Planks", "roof_planks.png", 0.85)
    tex_mat("Metal_Plate", "metal_plate.png", 0.45, 0.8)
    tex_mat("Rune_Sign", "rune_sign.png", 0.5, 0.0, emit=2.5)
    mat("Beam_Wood", (0.11, 0.07, 0.045), 0.8)
    mat("Bench_Wood", (0.2, 0.12, 0.07), 0.55)
    mat("Barrel_Wood", (0.25, 0.15, 0.08), 0.7)
    mat("Log_Wood", (0.08, 0.05, 0.035), 0.9)
    mat("Dark_Iron", (0.05, 0.05, 0.06), 0.5, 0.7)
    mat("Pipe_Metal", (0.13, 0.13, 0.15), 0.4, 0.9)
    mat("Brass", (0.55, 0.38, 0.16), 0.35, 1.0)
    mat("Soot", (0.012, 0.01, 0.01), 0.95)
    mat("Neon_Cyan", (0.1, 0.9, 1.0), 0.3, 0.0, (0.1, 0.85, 1.0), 4.0)
    mat("Neon_Orange", (1.0, 0.45, 0.08), 0.3, 0.0, (1.0, 0.42, 0.06), 4.0)
    mat("Neon_Purple", (0.7, 0.25, 1.0), 0.3, 0.0, (0.65, 0.2, 1.0), 4.0)
    mat("Pipe_Glow", (1.0, 0.4, 0.1), 0.3, 0.0, (1.0, 0.36, 0.06), 2.5)
    mat("Lantern_Glass", (1.0, 0.8, 0.5), 0.2, 0.0, (1.0, 0.7, 0.36), 2.2)
    mat("Sky_Glass", (1.0, 0.9, 0.7), 0.3, 0.0, (1.0, 0.85, 0.6), 2.5)
    mat("Embers", (0.5, 0.1, 0.02), 0.8, 0.0, (1.0, 0.28, 0.04), 3.0)
    mat("Screen_Black", (0.0, 0.0, 0.0), 0.5)
    mat("Screen_Frame", (0.02, 0.02, 0.02), 0.7)


# ════════════════════════════════════════════════════════════════
#  Floor, walls, roof
# ════════════════════════════════════════════════════════════
def build_floor():
    """The stone floor (1.5 m flags), including the floor of the screen alcove."""
    mb = MB("Floor")
    floor_quad(mb, -HALF_W, HALF_W, BACK_Y, 0.0, 0.0, "Floor_Tiles", uvs=3.0)
    floor_quad(mb, -ALC_HW, ALC_HW, 0.0, ALC_D, 0.0, "Floor_Tiles", uvs=3.0)
    mb.done()


def _wall_strip(mb, axis, pos, a0, a1, facing, top=EAVE_Z, band=True):
    """One straight stretch of wall from the floor to `top`: wood wainscot, stone, the metal band
    (side and back walls) and stone again. axis / pos / facing as wall_quad."""
    L = abs(a1 - a0)
    wall_quad(mb, axis, pos, a0, a1, 0.0, WAINSCOT_H, "Wood_Panel", facing, u=(0, L / 2.4), v=(0, 1))
    wall_quad(mb, axis, pos, a0, a1, WAINSCOT_H, top, "Stone_Slab", facing, u=(a0 / 4.0, a1 / 4.0), v=(WAINSCOT_H / 4.0, top / 4.0))
    if band:
        c, t = (a0 + a1) / 2, 0.1
        if axis == "x":
            box(mb, (pos + facing * t / 2, c, (BAND_Z0 + BAND_Z1) / 2), (t, L, BAND_Z1 - BAND_Z0), "Metal_Plate", uvs=2.0)
        else:
            box(mb, (c, pos + facing * t / 2, (BAND_Z0 + BAND_Z1) / 2), (L, t, BAND_Z1 - BAND_Z0), "Metal_Plate", uvs=2.0)


def _band_lights(mb, axis, pos, a0, a1, facing):
    """The light lines on a wall's metal band: two cyan lines that step down halfway along, and a
    short orange line under the band."""
    off = pos + facing * 0.13
    P = (lambda a, z: (off, a, z)) if axis == "x" else (lambda a, z: (a, off, z))
    mid = (a0 + a1) / 2
    for dz in (0.0, -0.2):
        neon(mb, [P(a0, BAND_Z1 - 0.15 + dz), P(mid - 0.3, BAND_Z1 - 0.15 + dz), P(mid + 0.3, BAND_Z0 + 0.35 + dz), P(a1, BAND_Z0 + 0.35 + dz)], "Neon_Cyan", 0.06)
    off = pos + facing * 0.04
    q = a0 + (a1 - a0) * 0.62
    neon(mb, [P(q, BAND_Z0 - 0.2), P(q + (a1 - a0) * 0.2, BAND_Z0 - 0.2)], "Neon_Orange", 0.06)


def build_walls():
    """The four walls. The screen wall has the alcove (a recess the screen hangs in front of) and
    its gable; the back wall has the double door; the side walls carry the light band."""
    mb = MB("Walls")
    # side walls, and their light lines bay by bay (between the pillars; none behind the forge)
    for s in (-1, 1):
        _wall_strip(mb, "x", s * HALF_W, BACK_Y, 0.0, -s)
    for (a0, a1) in ((-0.9, -4.3), (-5.7, -8.7), (-10.1, -13.9), (-15.3, -16.9)):
        _band_lights(mb, "x", -HALF_W, a0, a1, 1)
    for (a0, a1) in ((-0.9, FORGE_Y + FORGE_HW + 0.1), (-10.1, -13.9), (-15.3, -16.9)):
        _band_lights(mb, "x", HALF_W, a0, a1, -1)
    # back wall and its gable
    _wall_strip(mb, "y", BACK_Y, -HALF_W, HALF_W, 1)
    face_to(mb, [(-HALF_W, BACK_Y, EAVE_Z), (HALF_W, BACK_Y, EAVE_Z), (0, BACK_Y, RIDGE_Z)], "Stone_Slab",
            [(-HALF_W / 4, EAVE_Z / 4), (HALF_W / 4, EAVE_Z / 4), (0, RIDGE_Z / 4)], (0, 0, 4))
    for (a0, a1) in ((-8.9, -6.4), (-4.9, -2.3), (2.3, 4.9), (6.4, 8.9)):
        _band_lights(mb, "y", BACK_Y, a0, a1, 1)
    # screen wall: either side of the alcove, the strip over it, the gable
    for s in (-1, 1):
        _wall_strip(mb, "y", 0.0, s * ALC_HW, s * HALF_W, -1, band=False)
    wall_quad(mb, "y", 0.0, -ALC_HW, ALC_HW, ALC_TOP, EAVE_Z, "Stone_Slab", -1, u=(-ALC_HW / 4, ALC_HW / 4), v=(ALC_TOP / 4, EAVE_Z / 4))
    face_to(mb, [(-HALF_W, 0, EAVE_Z), (HALF_W, 0, EAVE_Z), (0, 0, RIDGE_Z)], "Stone_Slab",
            [(-HALF_W / 4, EAVE_Z / 4), (HALF_W / 4, EAVE_Z / 4), (0, RIDGE_Z / 4)], (0, -4, 4))
    # the alcove: wood wainscot and dark boards on its back, stone sides and ceiling
    wall_quad(mb, "y", ALC_D, -ALC_HW, ALC_HW, 0.0, WAINSCOT_H, "Wood_Panel", -1, u=(0, 2 * ALC_HW / 2.4), v=(0, 1))
    wall_quad(mb, "y", ALC_D, -ALC_HW, ALC_HW, WAINSCOT_H, ALC_TOP, "Roof_Planks", -1, u=(0, 2 * ALC_HW / 2.0), v=(0, 3.0))
    box(mb, (0, ALC_D - 0.06, WAINSCOT_H + 0.04), (2 * ALC_HW, 0.12, 0.08), "Beam_Wood")     # the ledge on the wainscot
    for s in (-1, 1):
        wall_quad(mb, "x", s * ALC_HW, 0.0, ALC_D, 0.0, ALC_TOP, "Stone_Slab", -s, u=(0, ALC_D / 4), v=(0, ALC_TOP / 4))
    floor_quad(mb, -ALC_HW, ALC_HW, 0.0, ALC_D, ALC_TOP, "Stone_Slab", uvs=4.0, up=False)
    # light along the alcove's top edge, and the two pipes across its top (as in the reference)
    neon(mb, [(-ALC_HW, -0.04, ALC_TOP + 0.12), (ALC_HW, -0.04, ALC_TOP + 0.12)], "Neon_Cyan", 0.07)
    neon(mb, [(-ALC_HW + 0.3, 0.1, ALC_TOP - 0.06), (ALC_HW - 0.3, 0.1, ALC_TOP - 0.06)], "Neon_Orange", 0.05)
    pipe_run(mb, [(-ALC_HW, 0.3, 7.28), (ALC_HW, 0.3, 7.28)], 0.11, "Pipe_Metal", collar="Brass")
    pipe_run(mb, [(-ALC_HW, 0.36, 7.0), (ALC_HW, 0.36, 7.0)], 0.07, "Pipe_Metal", collar="Dark_Iron")
    mb.done()


def build_back_door():
    """The tall double door in the middle of the back wall: plated leaves in a metal frame with a
    pointed head, outlined in cyan, with a purple strip either side."""
    mb = MB("Back_Door")
    y = BACK_Y
    hw, h = 1.6, 3.7
    box(mb, (0, y + 0.08, h / 2), (2 * hw, 0.16, h), "Metal_Plate", uvs=1.6)
    box(mb, (0, y + 0.18, h / 2), (0.08, 0.06, h), "Dark_Iron")                      # where the leaves meet
    for s in (-1, 1):
        box(mb, (s * (hw + 0.2), y + 0.15, h / 2), (0.4, 0.3, h), "Stone_Slab", uvs=2.0)
        box(mb, (s * 0.35, y + 0.2, 1.7), (0.08, 0.08, 0.5), "Brass")                # handles
        neon(mb, [(s * (hw + 0.2), y + 0.32, 0.4), (s * (hw + 0.2), y + 0.32, h - 0.2)], "Neon_Cyan", 0.06)
        neon(mb, [(s * (hw + 1.0), y + 0.04, 1.6), (s * (hw + 1.0), y + 0.04, 4.4)], "Neon_Purple", 0.07)
    # the pointed head over the door
    prism(mb, [(-hw - 0.4, h), (hw + 0.4, h), (hw + 0.4, h + 0.35), (0, h + 1.0), (-hw - 0.4, h + 0.35)], "xz", y, y + 0.32, "Stone_Slab")
    neon(mb, [(-hw - 0.2, y + 0.35, h + 0.28), (0, y + 0.35, h + 0.8), (hw + 0.2, y + 0.35, h + 0.28)], "Neon_Cyan", 0.06)
    mb.done()


def build_roof():
    """The roof boards (two slopes), the rafters, the ridge beam, two tie beams across the hall
    with a post up to the ridge, and the two skylights in the left slope."""
    mb = MB("Roof")
    for s in (-1, 1):
        pts = [(s * HALF_W, BACK_Y, EAVE_Z), (s * HALF_W, 0, EAVE_Z), (0, 0, RIDGE_Z), (0, BACK_Y, RIDGE_Z)]
        slope = math.hypot(HALF_W, RIDGE_Z - EAVE_Z)
        face_to(mb, pts, "Roof_Planks", [(0, BACK_Y / 2), (0, 0), (slope / 2, 0), (slope / 2, BACK_Y / 2)], (0, BACK_Y / 2, 0))
        for k in range(9):                                   # rafters every 2 m
            y = -0.5 - 2.0 * k
            bar(mb, (s * HALF_W, y, EAVE_Z - 0.12), (0, y, RIDGE_Z - 0.12), 0.26, "Beam_Wood")
        bar(mb, (s * 4.5, 0, roof_z(4.5) - 0.3), (s * 4.5, BACK_Y, roof_z(4.5) - 0.3), 0.22, "Beam_Wood")    # purlin
        box(mb, (s * (HALF_W - 0.15), BACK_Y / 2, EAVE_Z - 0.05), (0.3, -BACK_Y, 0.4), "Beam_Wood")           # wall plate
    box(mb, (0, BACK_Y / 2, RIDGE_Z - 0.3), (0.4, -BACK_Y, 0.5), "Beam_Wood")                                  # ridge beam
    for y in (-5.0, -11.0):
        box(mb, (0, y, EAVE_Z), (2 * HALF_W, 0.4, 0.4), "Beam_Wood")
        bar(mb, (0, y, EAVE_Z + 0.2), (0, y, RIDGE_Z - 0.5), 0.3, "Beam_Wood")
        for s in (-1, 1):
            bar(mb, (s * 3.2, y, EAVE_Z + 0.2), (0, y, RIDGE_Z - 1.4), 0.2, "Beam_Wood")
            box(mb, (s * 3.2, y, EAVE_Z - 0.03), (0.6, 0.46, 0.5), "Dark_Iron")      # iron straps
    # skylights: a glowing pane just under the boards, in an iron frame with glazing bars
    d = Vector((HALF_W, 0, RIDGE_Z - EAVE_Z))                # up the left slope, eave to ridge
    n = Vector((RIDGE_Z - EAVE_Z, 0, -HALF_W)).normalized()  # into the room
    S = lambda t, y, lift: Vector((-HALF_W, y, EAVE_Z)) + d * t + n * lift
    for yc in SKY_YS:
        y0, y1 = yc - SKY_HW, yc + SKY_HW
        face_to(mb, [S(SKY_S0, y0, 0.05), S(SKY_S0, y1, 0.05), S(SKY_S1, y1, 0.05), S(SKY_S1, y0, 0.05)], "Sky_Glass",
                [(0, 0), (1, 0), (1, 1), (0, 1)], (0, yc, 0))
        for (a, b) in ((S(SKY_S0, y0, 0.1), S(SKY_S0, y1, 0.1)), (S(SKY_S1, y0, 0.1), S(SKY_S1, y1, 0.1)),
                       (S(SKY_S0, y0, 0.1), S(SKY_S1, y0, 0.1)), (S(SKY_S0, y1, 0.1), S(SKY_S1, y1, 0.1))):
            bar(mb, a, b, 0.2, "Dark_Iron")
        bar(mb, S(SKY_S0, yc, 0.1), S(SKY_S1, yc, 0.1), 0.09, "Dark_Iron")
        for k in (1, 2, 3):
            t = SKY_S0 + (SKY_S1 - SKY_S0) * k / 4
            bar(mb, S(t, y0, 0.1), S(t, y1, 0.1), 0.09, "Dark_Iron")
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Pillars, forge, lanterns
# ════════════════════════════════════════════════════════════
def build_pillars():
    """One pillar mesh placed at every PILLARS spot: a flared stone foot, a shaft with a metal
    face plate carrying three light strips (cyan, orange, purple, each in two lengths as in the
    reference), and a flared head with a cyan chevron. Built facing -Y around its own origin."""
    mb = MB("Pillar_1")
    hd = PILLAR_D / 2
    prism(mb, [(-0.85, 0), (0.85, 0), (0.85, 0.75), (0.65, 1.15), (-0.65, 1.15), (-0.85, 0.75)], "xz", -hd - 0.1, hd, "Stone_Slab")
    box(mb, (0, 0, (1.15 + 6.6) / 2), (1.3, PILLAR_D, 6.6 - 1.15), "Stone_Slab", uvs=4.0)
    prism(mb, [(-0.65, 6.6), (0.65, 6.6), (0.9, 7.1), (0.9, EAVE_Z), (-0.9, EAVE_Z), (-0.9, 7.1)], "xz", -hd - 0.15, hd, "Stone_Slab")
    box(mb, (0, -hd - 0.03, 3.1), (0.95, 0.06, 3.4), "Metal_Plate", uvs=2.0)
    for x, m in ((-0.28, "Neon_Cyan"), (0.0, "Neon_Orange"), (0.28, "Neon_Purple")):
        for (z0, z1) in ((1.6, 2.9), (3.1, 4.6)):
            box(mb, (x, -hd - 0.07, (z0 + z1) / 2), (0.07, 0.04, z1 - z0), m)
    neon(mb, [(-0.6, -hd - 0.18, 7.45), (0, -hd - 0.18, 7.1), (0.6, -hd - 0.18, 7.45)], "Neon_Cyan", 0.06)
    src = mb.done()
    x, y, yaw = PILLARS[0]
    src.location = (x, y, 0)
    src.rotation_euler = (0, 0, yaw)
    for k, (x, y, yaw) in enumerate(PILLARS[1:]):
        instance("Pillar_%d" % (k + 2), src, (x, y, 0), yaw)


def build_forge():
    """The forge fireplace on the right wall: a stone body with the firebox (an opening with
    cut-off top corners), a hearth slab on two corbels, a low fire slot under the hearth, angled
    shoulders and a stack up through the roof. A metal arch frames the firebox, orange light
    lines arch over it, cyan lines follow the shoulders, and a coil spring stands either side.
    The flames are not here: the room script builds them at the FIRE_ markers."""
    mb = MB("Forge")
    xw, xf = HALF_W, HALF_W - FORGE_D          # the wall, and the front face of the body
    xc, yc = (xw + xf) / 2, FORGE_Y
    B = lambda y0, y1, z0, z1, m="Stone_Slab": box(mb, (xc, yc + (y0 + y1) / 2, (z0 + z1) / 2), (FORGE_D, y1 - y0, z1 - z0), m, uvs=4.0)
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
              "yz", xf, xw, "Stone_Slab")
    # shoulders and stack (the stack goes up through the roof boards)
    prism(mb, [(yc - FORGE_HW, 3.4), (yc + FORGE_HW, 3.4), (yc + STACK_HW, 4.6), (yc - STACK_HW, 4.6)], "yz", xf, xw, "Stone_Slab", uvs=4.0)
    B(-STACK_HW, STACK_HW, 4.6, 8.7)
    # soot inside both openings
    wall_quad(mb, "x", xw - 0.02, yc - FIREBOX_HW, yc + FIREBOX_HW, HEARTH_Z, FIREBOX_TOP, "Soot", -1)
    wall_quad(mb, "x", xw - 0.02, yc - slot_hw, yc + slot_hw, slot_z0, slot_z1, "Soot", -1)
    floor_quad(mb, xf, xw, yc - FIREBOX_HW, yc + FIREBOX_HW, HEARTH_Z + 0.005, "Soot")
    # the hearth slab and its corbels
    box(mb, (xf - 0.3, yc, HEARTH_Z - 0.05), (0.7, 2 * FORGE_HW + 0.4, 0.2), "Stone_Slab", uvs=4.0)
    for s in (-1, 1):
        prism(mb, [(xf - 0.55, HEARTH_Z - 0.15), (xf, HEARTH_Z - 0.15), (xf, HEARTH_Z - 0.75)], "xz", yc + s * 1.9 - 0.2, yc + s * 1.9 + 0.2, "Stone_Slab")
    # the metal arch round the firebox (proud of the stone), with bolts
    fx = xf - 0.07
    arch = lambda hw, top, cut: [(fx, yc - hw, HEARTH_Z + 0.1), (fx, yc - hw, top - cut), (fx, yc - hw + cut, top), (fx, yc + hw - cut, top), (fx, yc + hw, top - cut), (fx, yc + hw, HEARTH_Z + 0.1)]
    for a, b in zip(arch(1.2, 3.15, 0.5)[:-1], arch(1.2, 3.15, 0.5)[1:]):
        bar(mb, a, b, 0.24, "Metal_Plate")
    for s in (-1, 1):
        cyl(mb, (fx - 0.05, yc + s * 1.85, 3.95), 0.3, 0.12, "Metal_Plate", axis="x", segs=8)
        cyl(mb, (fx - 0.12, yc + s * 1.85, 3.95), 0.1, 0.06, "Brass", axis="x", segs=8)
    # light lines: two orange arches over the firebox, cyan along the shoulders and up the stack
    fx = xf - 0.05
    neon(mb, [(fx, y, z) for (_x, y, z) in arch(1.55, 3.6, 0.7)[1:-1]], "Neon_Orange", 0.07)
    neon(mb, [(fx, yc - 0.9, 4.2), (fx, yc - 0.45, 4.45), (fx, yc + 0.45, 4.45), (fx, yc + 0.9, 4.2)], "Neon_Orange", 0.06)
    neon(mb, [(fx, yc - FORGE_HW + 0.12, 3.3), (fx, yc - STACK_HW + 0.12, 4.75), (fx, yc + STACK_HW - 0.12, 4.75), (fx, yc + FORGE_HW - 0.12, 3.3)], "Neon_Cyan", 0.07)
    for s in (-1, 1):
        neon(mb, [(fx, yc + s * (STACK_HW - 0.3), 5.2), (fx, yc + s * (STACK_HW - 0.3), 7.6)], "Neon_Cyan", 0.06)
        # the coil springs on the piers
        cx, cy = xf - 0.28, yc + s * 1.85
        cyl(mb, (cx, cy, 2.0), 0.12, 1.5, "Dark_Iron", segs=10)
        for k in range(7):
            torus(mb, (cx, cy, 1.4 + 0.2 * k), 0.2, 0.05, "Pipe_Metal", segs=14, rsegs=5)
    # logs and embers in both fires
    for (z, hw, n) in ((HEARTH_Z, 0.7, 3), (slot_z0, 0.75, 2)):
        for k in range(n):
            tube(mb, (xc - 0.25 + 0.3 * k, yc - hw, z + 0.1), (xc - 0.4 + 0.3 * k, yc + hw, z + 0.1), 0.09, "Log_Wood", segs=8)
        box(mb, (xc - 0.1, yc, z + 0.03), (0.9, 2 * hw - 0.2, 0.06), "Embers")
    mb.done()


def build_lanterns():
    """One hexagonal lantern (iron frame, glowing glass) placed at every LANTERNS spot, plus the
    chains they hang on and the pulley block on the ridge beam (as in the reference)."""
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
        top = roof_z(p.x) - 0.1
        bar(ch, (p.x, p.y, p.z + 0.62), (p.x, p.y, top), 0.03, "Dark_Iron")
        z = p.z + 0.75
        while z < top:                                # chain links: a small block every 20 cm
            box(ch, (p.x, p.y, z), (0.07, 0.05, 0.1), "Dark_Iron")
            z += 0.2
    # the pulley block the long centre chain runs from
    p = LANTERNS[-1]
    top = roof_z(p.x)
    box(ch, (p.x, p.y, top - 0.75), (0.7, 0.6, 0.7), "Metal_Plate", uvs=1.0)
    cyl(ch, (p.x, p.y, top - 1.2), 0.2, 0.3, "Dark_Iron", segs=8, r2=0.08)
    cyl(ch, (p.x, p.y, top - 0.75), 0.25, 0.66, "Brass", axis="y", segs=12)
    ch.done()


# ════════════════════════════════════════════════════════════════
#  Screen, podiums, seating, props
# ════════════════════════════════════════════════════════════
def build_screen():
    """The screen frame and the TVScreen mesh the app shows the video on (its own object, by
    contract). The frame is bolted to the alcove's back wall on four arms."""
    mb = MB("Screen_Frame")
    x0, x1 = -SCREEN_W / 2, SCREEN_W / 2
    z0, z1 = SCREEN_Z0, SCREEN_Z0 + SCREEN_H
    y = SCREEN_Y
    fy = y + 0.03      # the frame sits 3 cm behind the picture and never overlaps it (no flicker)
    for (c, sz) in [((0, fy, z1 + 0.1), (SCREEN_W + 0.5, 0.08, 0.2)), ((0, fy, z0 - 0.1), (SCREEN_W + 0.5, 0.08, 0.2)),
                    ((x0 - 0.15, fy, (z0 + z1) / 2), (0.3, 0.08, SCREEN_H)), ((x1 + 0.15, fy, (z0 + z1) / 2), (0.3, 0.08, SCREEN_H))]:
        box(mb, c, sz, "Screen_Frame")
    wall_quad(mb, "y", y + 0.08, x0, x1, z0, z1, "Screen_Black", facing=1)
    for sx in (x0 + 0.8, x1 - 0.8):
        for z in (z0 + 0.6, z1 - 0.6):
            bar(mb, (sx, y + 0.08, z), (sx, ALC_D, z), 0.1, "Dark_Iron")
    mb.done()
    sb = MB("TVScreen")
    wall_quad(sb, "y", y, x0, x1, z0, z1, "Screen_Black", facing=-1)
    sb.done()


def podium_yaw(x, y):
    """Podiums turn a little toward the middle of the hall."""
    return math.atan2(-(0.0 - x), (-12.0 - y)) + math.pi


def build_podiums():
    """Four stone podiums, each its own object (PODIUM_n) so the room can hide it: a stone body
    with a cyan light strip down the front, a metal desk and a small lantern lamp on the desk
    (PODIUM_LIGHT_n goes at the lamp)."""
    for i, (x, y) in enumerate(PODIUMS):
        pm = MB("PODIUM_%d" % (i + 1))
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        P = lambda lx, ly, lz: tuple(Vector((x, y, 0)) + R @ Vector((lx, ly, lz)))
        box(pm, P(0, 0, 0.05), (0.95, 0.65, 0.1), "Stone_Slab", rot=(0, 0, yaw), uvs=2.0)
        box(pm, P(0, 0, 0.55), (0.72, 0.46, 0.95), "Stone_Slab", rot=(0, 0, yaw), uvs=2.0)
        box(pm, P(0, -0.24, 0.6), (0.07, 0.03, 0.7), "Neon_Cyan", rot=(0, 0, yaw))
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
    light line along each step and a rail along the back), and the six benches: wooden seats
    and backs on stone legs, five places each."""
    mb = MB("Seating")
    for t in (1, 2):
        y0, z0, z1 = TIER_Y0[t], TIER_Z[t - 1], TIER_Z[t]
        box(mb, (0, (y0 + TIER_BACK) / 2, (z0 + z1) / 2), (2 * TIER_HW, y0 - TIER_BACK, z1 - z0), "Stone_Slab", uvs=4.0)
        box(mb, (0, y0 + 0.175, z0 + 0.0875), (1.2, 0.35, 0.175), "Stone_Slab", uvs=4.0)      # the half step in the aisle
        for s in (-1, 1):
            neon(mb, [(s * 0.75, y0 + 0.02, z1 - 0.06), (s * TIER_HW, y0 + 0.02, z1 - 0.06)], "Neon_Cyan", 0.05)
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
                box(mb, (xc + dx, y, z + (SEAT_H - 0.08) / 2), (0.4, 0.4, SEAT_H - 0.08), "Stone_Slab", uvs=2.0)
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
    """What fills the rest of the room. Left wall: a boiler with pipes running up and along the
    wall (one of them glowing orange), the round cyan sign, a workbench with a tool board, an
    anvil on a stump, and a small side door. Right wall: pipes in the front corner, barrels and
    crates in the back bay. Barrels in the back corners."""
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
    cyl(mb, (bx + 0.5, by, 1.4), 0.14, 0.06, "Brass", axis="x", segs=10)          # the gauge
    box(mb, (bx + 0.51, by, 1.0), (0.04, 0.3, 0.12), "Embers")                    # the glowing fire door
    # pipes from the boiler: up, along the wall under the band, and up into the roof
    px = xl + 0.25
    pipe_run(mb, [(bx, by, 2.3), (bx, by, 4.3), (px, by, 4.3), (px, -4.2, 4.3), (px, -4.2, EAVE_Z)], 0.1, "Pipe_Metal", collar="Brass")
    pipe_run(mb, [(px, -0.5, 0.0), (px, -0.5, 3.9), (px, -3.9, 3.9), (px, -3.9, 2.2), (px, -2.6, 2.2)], 0.06, "Pipe_Glow")
    # the round sign
    cyl(mb, (xl + 0.08, -3.0, 3.1), 0.62, 0.1, "Metal_Plate", axis="x", segs=8)
    wall_quad(mb, "x", xl + 0.14, -3.45, -2.55, 2.65, 3.55, "Rune_Sign", 1)
    # workbench between the 1st and 2nd left pillars, with a tool board over it
    wy = -7.2
    box(mb, (xl + 0.6, wy, 0.92), (1.0, 2.8, 0.1), "Bench_Wood")
    for dy in (-1.2, 1.2):
        for dx in (0.2, 1.0):
            box(mb, (xl + dx, wy + dy, 0.435), (0.12, 0.12, 0.87), "Beam_Wood")
    box(mb, (xl + 0.6, wy, 0.3), (0.9, 2.5, 0.05), "Beam_Wood")
    box(mb, (xl + 0.06, wy, 2.2), (0.06, 2.4, 1.2), "Bench_Wood")
    for k, dy in enumerate((-0.8, -0.3, 0.3, 0.8)):       # hammers and tongs hung on the board
        bar(mb, (xl + 0.12, wy + dy, 1.75), (xl + 0.12, wy + dy, 2.5), 0.04, "Beam_Wood")
        box(mb, (xl + 0.14, wy + dy, 2.5), (0.08, 0.26 if k % 2 == 0 else 0.1, 0.12), "Dark_Iron")
    box(mb, (xl + 0.6, wy + 0.8, 1.05), (0.3, 0.5, 0.16), "Metal_Plate", uvs=1.0)       # a vice block
    _crate(mb, xl + 0.6, wy - 0.6, 0.33, 0.45, 0.3)
    # the anvil on its stump, out on the floor in front of the bench
    ax, ay = -6.9, -5.9
    cyl(mb, (ax, ay, 0.28), 0.36, 0.56, "Log_Wood", segs=12)
    prism(mb, [(ay - 0.28, 0.56), (ay + 0.28, 0.56), (ay + 0.28, 0.66), (ay + 0.14, 0.72), (ay + 0.14, 0.86), (ay + 0.36, 0.9), (ay + 0.36, 1.02),
               (ay - 0.36, 1.02), (ay - 0.36, 0.9), (ay - 0.14, 0.86), (ay - 0.14, 0.72), (ay - 0.28, 0.66)], "yz", ax - 0.14, ax + 0.14, "Dark_Iron")
    cyl(mb, (ax, ay + 0.55, 0.96), 0.07, 0.4, "Dark_Iron", axis="y", segs=8, r2=0.01)   # the horn
    # the side door, left wall between the 2nd and 3rd pillars
    dy = -12.0
    box(mb, (xl + 0.05, dy, 1.2), (0.1, 1.3, 2.4), "Bench_Wood")
    for (c, sz) in (((xl + 0.08, dy - 0.72, 1.25), (0.16, 0.14, 2.5)), ((xl + 0.08, dy + 0.72, 1.25), (0.16, 0.14, 2.5)), ((xl + 0.08, dy, 2.5), (0.16, 1.58, 0.16))):
        box(mb, c, sz, "Metal_Plate", uvs=1.0)
    for z in (1.6, 1.75, 1.9):
        box(mb, (xl + 0.17, dy + 0.72, z), (0.03, 0.06, 0.06), "Neon_Cyan")
    # right wall, front corner: pipes floor to roof (as on the right of the reference)
    xr = HALF_W
    pipe_run(mb, [(xr - 0.3, -0.5, 0), (xr - 0.3, -0.5, 3.0), (xr - 0.3, -1.6, 3.0), (xr - 0.3, -1.6, EAVE_Z)], 0.11, "Pipe_Metal", collar="Brass")
    pipe_run(mb, [(xr - 0.25, -0.9, EAVE_Z), (xr - 0.25, -0.9, 3.6), (xr - 0.25, -2.2, 3.6), (xr - 0.25, -2.2, 1.4)], 0.06, "Pipe_Glow")
    # right wall, back bay: barrels and crates
    _barrel(mb, xr - 0.6, -10.6)
    _barrel(mb, xr - 0.6, -11.5)
    _barrel(mb, xr - 1.4, -11.0)
    _crate(mb, xr - 0.65, -12.8, 0.0, 0.9, 0.1)
    _crate(mb, xr - 0.7, -12.75, 0.9, 0.6, -0.2)
    _crate(mb, xr - 0.6, -13.75, 0.0, 0.7, 0.4)
    # back corners
    _barrel(mb, -HALF_W + 0.7, BACK_Y + 0.7)
    _barrel(mb, HALF_W - 0.7, BACK_Y + 0.7)
    _crate(mb, -HALF_W + 1.6, BACK_Y + 0.6, 0.0, 0.7, 0.2)
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Markers
# ════════════════════════════════════════════════════════════
def build_markers():
    """The Stream Rooms markers: LIGHTS_House with its LAMP_ empties (the lanterns, and a cyan
    wash either side), the SHAFT_Sky_n skylights and FIRE_ spots the room script builds on, the
    CAM_ presets, the presenter / chat / reply screen markers, the reaction targets and the 30
    AUDIENCE_ seats."""
    screen_c = Vector((0, SCREEN_Y, SCREEN_Z0 + SCREEN_H / 2))
    lh = empty("LIGHTS_House", (0, 0, 0))
    for i, p in enumerate(LANTERNS):
        empty("LAMP_Lantern_%d" % (i + 1), p + Vector((0, 0, -0.5)), parent=lh)
    for s, n in ((-1, "L"), (1, "R")):
        empty("LAMP_Neon_%s" % n, (s * 7.4, -12.0, 4.4), parent=lh)
    # skylights: the marker sits in the middle of the pane. Its X axis runs along the hall, its
    # Y axis up the slope and its Z axis into the room; the room script reads the pane's
    # outline from those (X and -Z of the node in Redot) and skylight_half.
    d = Vector((HALF_W, 0, RIDGE_Z - EAVE_Z))
    up = d.normalized()
    n = Vector((RIDGE_Z - EAVE_Z, 0, -HALF_W)).normalized()
    for i, yc in enumerate(SKY_YS):
        c = Vector((-HALF_W, yc, EAVE_Z)) + d * ((SKY_S0 + SKY_S1) / 2) + n * 0.12
        sk = empty("SHAFT_Sky_%d" % (i + 1), c)
        sk.rotation_euler = Matrix((Vector((0, 1, 0)), up, n)).transposed().to_euler()
    # the two fires: bottom centre of the flames, facing into the room
    xm = HALF_W - FORGE_D * 0.55
    for name, z in (("FIRE_Main", HEARTH_Z + 0.1), ("FIRE_Slot", 0.3)):
        aim(empty(name, (xm, FORGE_Y, z)), (0, FORGE_Y, z), forward='-Y')
    cams = [("CAM_01_Centre_Aisle", Vector((0.0, -15.0, 2.4)), screen_c),
            # the reference picture's view: the screen alcove on the left, the forge on the right
            ("CAM_02_Forge_Corner", Vector((-7.2, -11.2, 2.3)), Vector((3.2, -2.0, 3.4))),
            ("CAM_03_Front_Row", Vector((0.0, -6.8, 1.4)), screen_c),
            ("CAM_04_Fireside", Vector((6.6, -9.0, 1.7)), Vector((-1.5, 0.0, 3.6))),
            ("CAM_05_Rafters", Vector((2.6, -16.0, 7.0)), Vector((0.0, 0.0, 3.2))),
            ("CAM_06_Skylight", Vector((-7.7, -8.0, 5.6)), Vector((7.0, -4.2, 1.4))),
            ("CAM_07_Panel_Wide", Vector((0.0, -7.2, 2.2)), Vector((0.0, 0.0, 2.6))),
            ("CAM_08_Panel_Left", Vector((-2.2, -5.4, 1.7)), Vector((-6.3, -1.6, 1.5))),
            ("CAM_09_Panel_Right", Vector((2.2, -5.4, 1.7)), Vector((6.3, -1.6, 1.5))),
            # the react-pause view: the forge fire, seen from the middle of the floor
            ("CAM_10_Reaction", Vector((2.6, -5.0, 1.6)), Vector((HALF_W, FORGE_Y, 2.3)))]
    for name, p, t in cams:
        aim(empty(name, p), t)
    podium_markers()
    # chat screen: top centre, just under the screen frame; reply screen up in the gable
    top = Vector((0.0, SCREEN_Y - 0.03, SCREEN_Z0 - 0.25))
    aim(empty("CHAT_Screen", top), top + Vector((0.0, -10.0, 0.0)), forward='-Y')
    rtop = Vector((0.0, -0.06, EAVE_Z + 1.5))
    aim(empty("REPLY_Screen", rtop), rtop + Vector((0.0, -10.0, 0.0)), forward='-Y')
    # reaction targets (!tomato forge ...)
    for name, p, to in (("TARGET_Forge", (HALF_W - FORGE_D - 0.1, FORGE_Y, 3.9), (0, FORGE_Y, 3.9)),
                        ("TARGET_Lantern", tuple(LANTERNS[-1]), (LANTERNS[-1].x, -20, LANTERNS[-1].z)),
                        ("TARGET_Anvil", (-6.9, -5.9, 1.1), (-6.9, -20, 1.1)),
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
    build_roof()
    build_pillars()
    build_forge()
    build_lanterns()
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
