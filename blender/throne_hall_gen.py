"""throne_hall_gen.py - builds the Throne Hall room in Blender.

    exec(open(r"C:\\Users\\jonza\\Documents\\RedotHomeTheater\\stream_rooms\\blender\\throne_hall_gen.py").read())
    build_all(); export_glb()

A vast dark throne hall: a long carpeted nave between black marble columns, each with a tall
crimson banner hung from a bracket, two railed galleries along each side wall, pale ribbed
cladding towering up to a coffered ceiling, three caged lantern chandeliers in a row, and a
raised dais at the far end with a tall throne. A shaft of
blue light falls from a slot in the ceiling onto the throne (the room script builds the beam
from the SHAFT_Throne marker). The big screen floats in front of the throne, the four presenter
podiums stand on the dais either side of it, and chat lines the carpet standing up (AUDIENCE_
empties about 0.9 m up; the room script drops them onto the BENCHES object when that is shown).

Own designs throughout; the banner cloth comes from blender/make_throne_textures.py, which
lifts the owner's crest picture onto it (rooms/throne_hall/textures).

Output: rooms/throne_hall/throne_hall.glb and crowd_seats.json next to it (the gallery crowd
for Room.crowd_seats_file). ROOT below is the owner's PC; set ROOT before exec on another
machine (the cloud build does).

Blender axes: origin = dais-front centre on the hall floor. -Y = toward the entrance and the
audience, +Y = toward the throne wall (y = 11), Z = up. Markers follow the Stream Rooms contract
(rooms/room.gd): PRESENTER_/CHAT_Screen/REPLY_Screen/TARGET_ empties point -Y at the audience,
cameras point +Y at what they look at.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Euler

ROOT = globals().get("ROOT", r"C:\Users\jonza\Documents\RedotHomeTheater\stream_rooms")
TEX = os.path.join(ROOT, "rooms", "throne_hall", "textures")
GLB = os.path.join(ROOT, "rooms", "throne_hall", "throne_hall.glb")
COLL, MARKERS = "Hall", "Hall_Markers"      # the two collections export_glb() exports


# ════════════════════════════════════════════════════════════════
#  Generic helpers (the same as lecture_hall_gen.py)
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
    """Another object sharing src's mesh (columns, banners, chandeliers: one mesh, many places).
    Redot imports shared meshes once, so the hall costs little memory however many columns."""
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


# ════════════════════════════════════════════════════════════════
#  Plan. Units: metres. Origin = dais-front centre on the hall floor, -Y = toward the entrance.
#  The nave runs from the entrance wall (y = BACK_Y) to the dais (y = 0); the dais and throne
#  fill y = 0 .. WALL_Y. Columns line the carpet at x = +-COL_X with the galleries behind them.
# ════════════════════════════════════════════════════════════════
HALF_W = 13.5                      # side walls at x = +-13.5
BACK_Y, WALL_Y = -50.0, 11.0       # entrance wall / throne wall
CEIL_Z = 30.0
CARPET_HW = 3.5                    # the runner is 7 m wide
COL_X, COL_R = 8.6, 0.85           # column centres and radius
COL_YS = [-4.0 - 6.0 * i for i in range(8)]   # 8 columns per side, 6 m apart
GAL_Z = (6.0, 11.5)                # the two gallery floors (top of the slab)
GAL_SLAB = 0.5
GAL_IN_X = COL_X + 0.35            # gallery front edge / railing (just behind the columns)
RIB_Z = GAL_Z[1] + 3.2             # from here up the walls are the pale ribbed cladding
DAIS_STEPS, STEP_H, STEP_D = 3, 0.4, 0.6
DAIS_Z = DAIS_STEPS * STEP_H       # 1.2 m: the dais floor
DAIS_HW = 9.0                      # the dais is 18 m wide
DAIS_Y0 = DAIS_STEPS * STEP_D      # the dais floor starts behind the steps (y = 1.8)
THRONE_Y = 7.5                     # the throne's seat centre
SCREEN_W, SCREEN_H = 8.6, 4.8375   # same picture as the Lecture Hall (Panel)
SCREEN_Y, SCREEN_LIFT = 5.0, 2.3   # floating in front of the throne, bottom 2.3 m above the dais
# presenter podiums on the dais: (x, y) of each podium's centre, left to right as the audience
# sees it. The inner pair flanks the screen, the outer pair stands nearer the dais front.
PODIUMS = [(-7.0, 2.8), (-5.0, 3.4), (5.0, 3.4), (7.0, 2.8)]
PRESENTER_W, PRESENTER_H = 1.3, 1.25         # the feed plane behind each podium (must match the room)
PRESENTER_BACK, PRESENTER_LIFT = 0.45, 0.75  # plane: this far behind the podium, bottom this high
CHANDS = [Vector((0.0, y, 17.0)) for y in (-10.0, -22.0, -34.0)]   # lantern centres
SHAFT_SIZE = (6.0, 3.0)            # the ceiling slot the blue light falls through (x by y)
# chat lines along the carpet: two lines each side, standing (markers STAND_Z up; the room
# script lowers them to SEAT_Z when the benches are shown)
LINE_XS = (4.3, 5.6)
LINE_Y0, LINE_Y1, LINE_PITCH = -4.6, -44.6, 1.0   # 1 m apart: the default Seat spacing keeps them all
STAND_Z, SEAT_Z = 0.9, 0.45
BENCH_GAP_Y = COL_YS               # the benches break at every column, leaving a way through

# the gallery crowd (filler people): recorded by gallery_crowd(), written by export_crowd_seats()
CROWD_SEATS = []
CROWD_PITCH = 0.6


def setup_materials():
    """Every material the hall uses. Names must stay in step with throne_hall_room.gd (its glow
    and polish lists) and the room scene's glow_materials."""
    tex_mat("Black_Marble", "black_marble.png", 0.22)
    tex_mat("Carpet", "carpet.png", 0.95)
    tex_mat("Stone_Wall", "stone_wall.png", 0.85)
    tex_mat("Ribbed_Tower", "ribbed_tower.png", 0.55, 0.1)
    tex_mat("Banner", "banner.png", 0.9, two_sided=True)
    mat("Gold", (0.85, 0.62, 0.22), 0.3, 1.0)
    mat("Dark_Iron", (0.05, 0.05, 0.06), 0.5, 0.7)
    mat("Blue_Glass", (0.25, 0.45, 1.0), 0.15, 0.0, (0.35, 0.55, 1.0), 3.0)
    mat("Candle_Flame", (1.0, 0.9, 0.7), 0.2, 0.0, (1.0, 0.72, 0.38), 6.0)
    mat("Sky_Slot", (0.5, 0.7, 1.0), 0.5, 0.0, (0.45, 0.65, 1.0), 3.0)
    mat("Ceiling_Dark", (0.03, 0.03, 0.04), 0.9)
    mat("Door_Dark", (0.08, 0.05, 0.04), 0.5)
    mat("Velvet_Dark", (0.16, 0.02, 0.05), 0.9)
    mat("Screen_Black", (0.0, 0.0, 0.0), 0.5)
    mat("Screen_Frame", (0.02, 0.02, 0.02), 0.7)


# ════════════════════════════════════════════════════════════════
#  Floor, walls, ceiling
# ════════════════════════════════════════════════════════════
def build_floor():
    """The marble floor of the nave and side aisles, with the carpet runner laid on top."""
    mb = MB("Floor")
    floor_quad(mb, -HALF_W, HALF_W, BACK_Y, DAIS_Y0, 0.0, "Black_Marble", uvs=6.0)
    # the runner: 1 cm proud of the marble; the texture tiles every 8 m along the hall
    floor_quad(mb, -CARPET_HW, CARPET_HW, BACK_Y + 1.0, 0.0, 0.01, "Carpet", uvs=1.0)
    # the runner's UVs: across = 0..1 (the gold borders at its edges), along = metres / 8
    mb.bm.faces.ensure_lookup_table()
    f = mb.bm.faces[-1]
    for lp in f.loops:
        p = lp.vert.co
        lp[mb.uv].uv = ((p.x + CARPET_HW) / (2 * CARPET_HW), p.y / 8.0)
    mb.done()


def build_walls():
    """Side walls (stone below RIB_Z, ribbed cladding above), the entrance wall with its doors and
    the throne wall, plus a pilaster on each side wall behind every column."""
    mb = MB("Walls")
    for s in (-1, 1):
        x = s * HALF_W
        wall_quad(mb, "x", x, BACK_Y, WALL_Y, 0.0, RIB_Z, "Stone_Wall", facing=-s, u=(0, (WALL_Y - BACK_Y) / 8.0), v=(0, RIB_Z / 8.0))
        wall_quad(mb, "x", x, BACK_Y, WALL_Y, RIB_Z, CEIL_Z, "Ribbed_Tower", facing=-s, u=(0, (WALL_Y - BACK_Y) / 4.0), v=(0, (CEIL_Z - RIB_Z) / 16.0))
        for y in COL_YS:
            box(mb, (x - s * 0.3, y, CEIL_Z / 2), (0.6, 1.2, CEIL_Z), "Black_Marble", uvs=4.0)
    # entrance wall: stone with a tall double door in the middle
    wall_quad(mb, "y", BACK_Y, -HALF_W, HALF_W, 0.0, RIB_Z, "Stone_Wall", facing=1, u=(0, 2 * HALF_W / 8.0), v=(0, RIB_Z / 8.0))
    wall_quad(mb, "y", BACK_Y, -HALF_W, HALF_W, RIB_Z, CEIL_Z, "Ribbed_Tower", facing=1, u=(0, 2 * HALF_W / 4.0), v=(0, (CEIL_Z - RIB_Z) / 16.0))
    box(mb, (0, BACK_Y + 0.15, 5.0), (7.0, 0.3, 10.0), "Door_Dark")
    box(mb, (0, BACK_Y + 0.32, 5.0), (0.12, 0.05, 9.8), "Gold")
    for sx in (-3.6, 3.6):
        box(mb, (sx, BACK_Y + 0.32, 5.0), (0.3, 0.1, 10.4), "Gold")
    box(mb, (0, BACK_Y + 0.32, 10.2), (7.6, 0.1, 0.3), "Gold")
    # throne wall: ribbed cladding full height, with a dark recess behind the throne
    wall_quad(mb, "y", WALL_Y, -HALF_W, HALF_W, 0.0, CEIL_Z, "Ribbed_Tower", facing=-1, u=(0, 2 * HALF_W / 4.0), v=(0, CEIL_Z / 16.0))
    box(mb, (0, WALL_Y - 0.2, 8.0), (6.0, 0.4, 16.0), "Ceiling_Dark")
    mb.done()


def build_ceiling():
    """The dark ceiling with cross beams at every column, and the glowing slot the throne's light
    falls through (the beam itself is built by the room script from SHAFT_Throne)."""
    mb = MB("Ceiling")
    floor_quad(mb, -HALF_W, HALF_W, BACK_Y, WALL_Y, CEIL_Z, "Ceiling_Dark", uvs=8.0, up=False)
    for y in COL_YS:
        box(mb, (0, y, CEIL_Z - 0.45), (2 * HALF_W, 1.0, 0.9), "Black_Marble", uvs=4.0)
    for x in (-COL_X, COL_X):
        box(mb, (x, (BACK_Y + WALL_Y) / 2, CEIL_Z - 0.45), (1.0, WALL_Y - BACK_Y, 0.9), "Black_Marble", uvs=4.0)
    sx, sy = SHAFT_SIZE
    box(mb, (0, THRONE_Y, CEIL_Z - 0.6), (sx + 0.6, sy + 0.6, 0.3), "Dark_Iron")
    floor_quad(mb, -sx / 2, sx / 2, THRONE_Y - sy / 2, THRONE_Y + sy / 2, CEIL_Z - 0.76, "Sky_Slot", up=False)
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Columns, banners, galleries
# ════════════════════════════════════════════════════════════
def build_columns():
    """One column mesh (black marble shaft, gold bands, square plinth and capital) placed 16 times."""
    mb = MB("Column_1")
    h = CEIL_Z
    box(mb, (0, 0, 0.4), (2.4, 2.4, 0.8), "Black_Marble", uvs=2.0)
    cyl(mb, (0, 0, h / 2), COL_R, h, "Black_Marble", segs=20, smooth=True)
    for z in (1.2, GAL_Z[0] - 0.3, GAL_Z[1] - 0.3, RIB_Z, 22.0):
        cyl(mb, (0, 0, z), COL_R + 0.08, 0.35, "Gold", segs=20)
    box(mb, (0, 0, h - 0.6), (2.6, 2.6, 1.2), "Black_Marble", uvs=2.0)
    src = mb.done()                    # built around its own origin: placed by location only
    src.location = (-COL_X, COL_YS[0], 0)
    k = 1
    for y in COL_YS:
        for s in (-1, 1):
            if (s, y) == (-1, COL_YS[0]):
                continue
            k += 1
            instance("Column_%d" % k, src, (s * COL_X, y, 0))


def build_banners():
    """One banner mesh placed on every column's aisle side: a gold bracket from the column holds a
    crossbar, and the pennant (a rectangle ending in a point) hangs from it, swung a little
    towards the carpet. The texture's top is at the crossbar (V = 1); the point is V = 0."""
    mb = MB("Banner_1")
    W, H_RECT, H_POINT = 2.6, 5.4, 1.6     # width along the hall, straight part, point below it
    top_z, reach = 13.0, 1.5               # crossbar height, how far it stands out from the column
    x0 = COL_R                             # the column's aisle-side surface (built for a left-hand
                                           # column, +X towards the carpet; right-hand ones turn 180)
    xb = x0 + reach
    # bracket: a rod from the column up to the crossbar, with a short brace
    bar(mb, (x0, 0, top_z - 1.2), (xb, 0, top_z), 0.07, "Gold")
    bar(mb, (x0, 0, top_z + 0.3), (xb, 0, top_z), 0.05, "Gold")
    bar(mb, (xb, -W / 2 - 0.15, top_z), (xb, W / 2 + 0.15, top_z), 0.06, "Gold")
    for yy in (-W / 2 - 0.15, W / 2 + 0.15):
        sphere(mb, (xb, yy, top_z), 0.09, "Gold", subdiv=1)
    # the cloth: hangs from the crossbar; its bottom swings 0.5 m out over the carpet
    xt, xbot = xb, xb + 0.5
    zb = top_z - H_RECT
    zp = zb - H_POINT
    vb = H_POINT / (H_RECT + H_POINT)
    quad(mb, (xbot, -W / 2, zb), (xbot, W / 2, zb), (xt, W / 2, top_z), (xt, -W / 2, top_z), "Banner", v=(vb, 1))
    _face(mb, [Vector((xbot, -W / 2, zb)), Vector((xbot + 0.15, 0, zp)), Vector((xbot, W / 2, zb))], "Banner", [(0, vb), (0.5, 0), (1, vb)])
    # a gold tassel at the point
    sphere(mb, (xbot + 0.15, 0, zp - 0.1), 0.1, "Gold", subdiv=1)
    src = mb.done()
    src.location = (-COL_X, COL_YS[0], 0)
    k = 1
    for y in COL_YS:
        for s in (-1, 1):
            if (s, y) == (-1, COL_YS[0]):
                continue
            k += 1
            instance("Banner_%d" % k, src, (s * COL_X, y, 0), yaw=0.0 if s < 0 else math.pi)


def gallery_crowd(tier, s, x, z):
    """Records one row of filler seats along a gallery at x, facing the carpet (inward)."""
    y = -2.0
    while y > BACK_Y + 1.5:
        CROWD_SEATS.append({"p": [round(s * x, 3), round(z + 0.45, 3), round(-y, 3)], "n": [-s, 0.0],
                            "s": "bal" if tier == 0 else "gal", "r": 0 if x < GAL_IN_X + 1.0 else 1})
        y -= CROWD_PITCH


def build_galleries():
    """Two railed galleries along each side wall, behind the columns, with stone benches for the
    filler crowd (two rows per tier) and a lit torch sconce on every other pilaster."""
    mb = MB("Galleries")
    ya, yb = BACK_Y + 0.5, -1.0            # the galleries run the length of the nave
    yc, L = (ya + yb) / 2, yb - ya
    for s in (-1, 1):
        xi, xo = s * GAL_IN_X, s * HALF_W
        for tier, z in enumerate(GAL_Z):
            box(mb, ((xi + xo) / 2, yc, z - GAL_SLAB / 2), (abs(xo - xi), L, GAL_SLAB), "Stone_Wall", uvs=4.0)
            # the rail: a stone kerb, gold posts every metre (not through a column) and a gold handrail
            box(mb, (xi, yc, z + 0.1), (0.25, L, 0.2), "Black_Marble", uvs=2.0)
            box(mb, (xi, yc, z + 1.1), (0.14, L, 0.1), "Gold")
            y = ya + 1.0
            while y < yb:
                if min(abs(y - cy) for cy in COL_YS) > 1.3:
                    cyl(mb, (xi, y, z + 0.6), 0.04, 0.95, "Gold", segs=6)
                y += 1.0
            # two long stone benches on each tier (two rows of filler people facing the carpet;
            # the back row is a step higher so it sees over the front one)
            for row, bx in enumerate((GAL_IN_X + 0.9, GAL_IN_X + 2.4)):
                h = 0.46 + 0.3 * row
                box(mb, (s * bx, yc, z + h / 2), (0.5, L - 1.0, h), "Stone_Wall", uvs=2.0)
                gallery_crowd(tier, s, bx, z + 0.3 * row)
        # torch sconces on the pilasters between the tiers
        for y in COL_YS[1::2]:
            x = s * (HALF_W - 0.6)
            bar(mb, (x, y, GAL_Z[1] + 2.0), (x - s * 0.35, y, GAL_Z[1] + 2.5), 0.05, "Dark_Iron")
            cyl(mb, (x - s * 0.35, y, GAL_Z[1] + 2.6), 0.14, 0.25, "Dark_Iron", segs=8, r2=0.09)
            sphere(mb, (x - s * 0.35, y, GAL_Z[1] + 2.85), 0.13, "Candle_Flame", subdiv=1, scale=(1, 1, 1.5))
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Dais, throne, screen, podiums, benches, chandeliers
# ════════════════════════════════════════════════════════════
def build_dais():
    """Three marble steps with gold nosings up to the dais, the dais floor and its carpet."""
    mb = MB("Dais")
    for i in range(DAIS_STEPS):
        y0, z1 = i * STEP_D, (i + 1) * STEP_H
        box(mb, (0, (y0 + WALL_Y) / 2, z1 / 2), (2 * DAIS_HW, WALL_Y - y0, z1), "Black_Marble", uvs=4.0)
        box(mb, (0, y0 + 0.03, z1 - 0.02), (2 * DAIS_HW, 0.06, 0.04), "Gold")
    # carpet over the step treads and the dais floor, 1 cm proud
    for i in range(DAIS_STEPS):
        y0, z1 = i * STEP_D, (i + 1) * STEP_H
        floor_quad(mb, -CARPET_HW, CARPET_HW, y0, y0 + STEP_D, z1 + 0.01, "Carpet", uvs=7.0)
        wall_quad(mb, "y", y0 - 0.005, -CARPET_HW, CARPET_HW, z1 - STEP_H, z1, "Carpet", facing=-1)
    floor_quad(mb, -CARPET_HW, CARPET_HW, DAIS_Y0, WALL_Y - 0.5, DAIS_Z + 0.01, "Carpet", uvs=7.0)
    mb.done()


def build_throne():
    """The throne: a two-step plinth, a block seat with a velvet cushion, tall arms and a pointed
    back rising 9 m, all black marble with gold edges. Its own object (TARGET_Throne sits on it)."""
    mb = MB("Throne")
    y = THRONE_Y
    z = DAIS_Z
    box(mb, (0, y + 0.3, z + 0.2), (5.0, 3.6, 0.4), "Black_Marble", uvs=2.0)
    box(mb, (0, y + 0.4, z + 0.6), (3.6, 2.8, 0.4), "Black_Marble", uvs=2.0)
    for (c, sz) in (((0, y - 1.5, z + 0.4), (5.0, 0.06, 0.04)), ((0, y - 1.0, z + 0.8), (3.6, 0.06, 0.04))):
        box(mb, c, sz, "Gold")
    z0 = z + 0.8
    box(mb, (0, y, z0 + 0.5), (2.0, 1.4, 1.0), "Black_Marble", uvs=2.0)
    box(mb, (0, y - 0.05, z0 + 1.05), (1.8, 1.2, 0.14), "Velvet_Dark")
    for sx in (-1, 1):
        box(mb, (sx * 1.15, y, z0 + 0.95), (0.3, 1.5, 1.9), "Black_Marble", uvs=2.0)
        box(mb, (sx * 1.15, y, z0 + 1.92), (0.34, 1.54, 0.06), "Gold")
    # the back: a slab that narrows as it rises, topped with a point
    yb = y + 0.75
    quad(mb, (-1.3, yb, z0), (1.3, yb, z0), (0.8, yb, z0 + 7.5), (-0.8, yb, z0 + 7.5), "Black_Marble")
    quad(mb, (1.3, yb + 0.5, z0), (-1.3, yb + 0.5, z0), (-0.8, yb + 0.5, z0 + 7.5), (0.8, yb + 0.5, z0 + 7.5), "Black_Marble")
    for sx in (-1, 1):
        quad(mb, (sx * 1.3, yb + (0.5 if sx > 0 else 0), z0), (sx * 1.3, yb + (0 if sx > 0 else 0.5), z0),
             (sx * 0.8, yb + (0 if sx > 0 else 0.5), z0 + 7.5), (sx * 0.8, yb + (0.5 if sx > 0 else 0), z0 + 7.5), "Black_Marble")
    _face(mb, [Vector((-0.8, yb, z0 + 7.5)), Vector((0.8, yb, z0 + 7.5)), Vector((0, yb, z0 + 9.0))], "Black_Marble", [(0, 0), (1, 0), (0.5, 1)])
    _face(mb, [Vector((0.8, yb + 0.5, z0 + 7.5)), Vector((-0.8, yb + 0.5, z0 + 7.5)), Vector((0, yb + 0.5, z0 + 9.0))], "Black_Marble", [(0, 0), (1, 0), (0.5, 1)])
    _face(mb, [Vector((-0.8, yb + 0.5, z0 + 7.5)), Vector((-0.8, yb, z0 + 7.5)), Vector((0, yb, z0 + 9.0)), Vector((0, yb + 0.5, z0 + 9.0))], "Black_Marble", [(0, 0), (1, 0), (1, 1), (0, 1)])
    _face(mb, [Vector((0.8, yb, z0 + 7.5)), Vector((0.8, yb + 0.5, z0 + 7.5)), Vector((0, yb + 0.5, z0 + 9.0)), Vector((0, yb, z0 + 9.0))], "Black_Marble", [(0, 0), (1, 0), (1, 1), (0, 1)])
    # gold filigree lines up the back
    for sx in (-0.45, 0.45):
        bar(mb, (sx, yb - 0.02, z0 + 0.3), (sx * 0.6, yb - 0.02, z0 + 7.0), 0.05, "Gold")
    bar(mb, (0, yb - 0.02, z0 + 1.6), (0, yb - 0.02, z0 + 8.6), 0.06, "Gold")
    mb.done()


def build_screen():
    """The screen frame and the TVScreen mesh the app shows the video on (its own object, by contract).
    Hung from the ceiling on three iron chains in front of the throne."""
    mb = MB("Screen_Frame")
    x0, x1 = -SCREEN_W / 2, SCREEN_W / 2
    z0, z1 = DAIS_Z + SCREEN_LIFT, DAIS_Z + SCREEN_LIFT + SCREEN_H
    y = SCREEN_Y
    fy = y + 0.02      # the frame sits 2 cm behind the picture and never overlaps it (no flicker)
    for (c, sz) in [((0, fy, z1 + 0.1), (SCREEN_W + 0.5, 0.06, 0.2)), ((0, fy, z0 - 0.1), (SCREEN_W + 0.5, 0.06, 0.2)),
                    ((x0 - 0.15, fy, (z0 + z1) / 2), (0.3, 0.06, SCREEN_H)), ((x1 + 0.15, fy, (z0 + z1) / 2), (0.3, 0.06, SCREEN_H))]:
        box(mb, c, sz, "Screen_Frame")
    for (c, sz) in [((0, fy + 0.01, z1 + 0.24), (SCREEN_W + 0.6, 0.05, 0.08)), ((0, fy + 0.01, z0 - 0.24), (SCREEN_W + 0.6, 0.05, 0.08))]:
        box(mb, c, sz, "Gold")
    wall_quad(mb, "y", y + 0.06, x0, x1, z0, z1, "Screen_Black", facing=1)
    for sx in (x0 + 0.4, 0.0, x1 - 0.4):
        bar(mb, (sx, y + 0.05, z1 + 0.3), (sx, y + 0.05, CEIL_Z), 0.05, "Dark_Iron")
    mb.done()
    sb = MB("TVScreen")
    wall_quad(sb, "y", y, x0, x1, z0, z1, "Screen_Black", facing=-1)
    sb.done()


def podium_yaw(x, y):
    """Podiums turn a little toward the middle of the hall."""
    return math.atan2(-(0.0 - x), (-12.0 - y)) + math.pi


def build_podiums():
    """Four stone podiums, each its own object (PODIUM_n) so the room can hide it, with a candle
    lamp on the desk (PODIUM_LIGHT_n goes at the flame)."""
    for i, (x, y) in enumerate(PODIUMS):
        pm = MB("PODIUM_%d" % (i + 1))
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        P = lambda lx, ly, lz: tuple(Vector((x, y, 0)) + R @ Vector((lx, ly, lz)))
        box(pm, P(0, 0, DAIS_Z + 0.04), (0.9, 0.6, 0.08), "Black_Marble", rot=(0, 0, yaw), uvs=2.0)
        box(pm, P(0, 0, DAIS_Z + 0.55), (0.7, 0.46, 0.95), "Black_Marble", rot=(0, 0, yaw), uvs=2.0)
        box(pm, P(0, -0.235, DAIS_Z + 0.75), (0.5, 0.02, 0.3), "Gold", rot=(0, 0, yaw))
        box(pm, P(0, 0.02, DAIS_Z + 1.07), (0.82, 0.58, 0.05), "Black_Marble", rot=(math.radians(-14), 0, yaw), uvs=2.0)
        box(pm, P(0, -0.27, DAIS_Z + 1.02), (0.82, 0.04, 0.08), "Gold", rot=(0, 0, yaw))
        # the candle lamp on the desk corner
        cyl(pm, P(0.25, -0.12, DAIS_Z + 1.16), 0.06, 0.03, "Gold", segs=10)
        cyl(pm, P(0.25, -0.12, DAIS_Z + 1.3), 0.025, 0.25, "Candle_Flame", segs=8)
        sphere(pm, P(0.25, -0.12, DAIS_Z + 1.47), 0.035, "Candle_Flame", subdiv=1, scale=(1, 1, 1.6))
        pm.done()


def podium_markers():
    """PRESENTER_n (feed plane: bottom centre, +Z of the marker faces the audience in Redot),
    PODIUM_LIGHT_n (the candle: aims at the presenter's face)."""
    for i, (x, y) in enumerate(PODIUMS):
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        back = R @ Vector((0, PRESENTER_BACK, 0))
        base = Vector((x, y, 0)) + back + Vector((0, 0, DAIS_Z + PRESENTER_LIFT))
        pm = empty("PRESENTER_%d" % (i + 1), base)
        front = base + R @ Vector((0, -5.0, 0))
        aim(pm, front, forward='-Y')
        lamp = Vector((x, y, 0)) + R @ Vector((0.25, -0.12, DAIS_Z + 1.45))
        lm = empty("PODIUM_LIGHT_%d" % (i + 1), lamp)
        aim(lm, base + Vector((0, 0, PRESENTER_H * 0.55)))


def build_benches():
    """BENCHES: low stone benches under the chat lines, in runs between the columns. One object,
    so the room script can show or hide it with the Benches tick box (throne_benches)."""
    mb = MB("BENCHES")
    runs = []
    edges = [LINE_Y0 + 0.4] + [y for y in BENCH_GAP_Y if LINE_Y1 < y < LINE_Y0] + [LINE_Y1 - 0.4]
    for a, b in zip(edges[:-1], edges[1:]):
        runs.append((a - 0.7, b + 0.7))
    for s in (-1, 1):
        for x in LINE_XS:
            for (ya, yb) in runs:
                c = ((ya + yb) / 2)
                L = abs(ya - yb)
                box(mb, (s * x, c, SEAT_Z - 0.04), (0.5, L, 0.08), "Black_Marble", uvs=2.0)
                box(mb, (s * x, c, (SEAT_Z - 0.08) / 2), (0.36, L - 0.3, SEAT_Z - 0.08), "Stone_Wall", uvs=2.0)
                box(mb, (s * (x + 0.22), c, SEAT_Z + 0.2), (0.06, L, 0.4), "Black_Marble", uvs=2.0)
                box(mb, (s * (x + 0.22), c, SEAT_Z + 0.42), (0.08, L, 0.04), "Gold")
    mb.done()


def build_chandeliers():
    """One caged lantern (a blue glass globe in an iron cage with a ring of candles) placed three
    times down the nave, each on a chain from the ceiling. LAMP_Chandelier_n sits at the globe."""
    mb = MB("Chandelier_1")
    c = Vector((0, 0, 0))
    bar(mb, c + Vector((0, 0, 1.6)), c + Vector((0, 0, CEIL_Z - CHANDS[0].z)), 0.06, "Dark_Iron")
    cyl(mb, c + Vector((0, 0, 1.4)), 0.35, 0.4, "Dark_Iron", segs=12, r2=0.12)
    torus(mb, c + Vector((0, 0, 1.0)), 1.25, 0.06, "Gold", segs=32, rsegs=5)
    torus(mb, c + Vector((0, 0, -1.0)), 1.25, 0.06, "Gold", segs=32, rsegs=5)
    sphere(mb, c, 1.0, "Blue_Glass", subdiv=3)
    for k in range(8):
        a = 2 * math.pi * k / 8
        p = Vector((math.cos(a), math.sin(a), 0))
        bar(mb, c + p * 1.25 + Vector((0, 0, 1.0)), c + p * 1.25 + Vector((0, 0, -1.0)), 0.05, "Dark_Iron")
        # candle arms on every other cage bar
        if k % 2 == 0:
            arm = c + p * 1.9 + Vector((0, 0, 0.3))
            bar(mb, c + p * 1.25 + Vector((0, 0, -0.2)), arm, 0.04, "Gold")
            cyl(mb, arm + Vector((0, 0, 0.05)), 0.08, 0.06, "Gold", segs=8)
            cyl(mb, arm + Vector((0, 0, 0.25)), 0.03, 0.35, "Candle_Flame", segs=8)
            sphere(mb, arm + Vector((0, 0, 0.5)), 0.05, "Candle_Flame", subdiv=1, scale=(1, 1, 1.8))
    cyl(mb, c + Vector((0, 0, -1.6)), 0.3, 1.0, "Dark_Iron", segs=10, r2=0.03)
    src = mb.done()
    src.location = tuple(CHANDS[0])
    for i, p in enumerate(CHANDS[1:]):
        instance("Chandelier_%d" % (i + 2), src, tuple(p))


# ════════════════════════════════════════════════════════════════
#  Markers
# ════════════════════════════════════════════════════════════
def build_markers():
    """The Stream Rooms markers: LIGHTS_House with its LAMP_ empties, SHAFT_Throne (the blue light),
    the CAM_ presets, the presenter / chat / reply screen markers, the reaction targets and the
    standing AUDIENCE_ lines along the carpet."""
    screen_c = Vector((0, SCREEN_Y, DAIS_Z + SCREEN_LIFT + SCREEN_H / 2))
    lh = empty("LIGHTS_House", (0, 0, 0))
    for i, p in enumerate(CHANDS):
        empty("LAMP_Chandelier_%d" % (i + 1), p + Vector((0, 0, -0.3)), parent=lh)
    for s, n in ((-1, "L"), (1, "R")):
        empty("LAMP_Throne_%s" % n, (s * 4.0, THRONE_Y + 0.5, DAIS_Z + 6.0), parent=lh)
        for k, y in enumerate(COL_YS[1::2]):
            empty("LAMP_Gallery_%s%d" % (n, k + 1), (s * (HALF_W - 1.2), y, GAL_Z[1] + 3.0), parent=lh)
    # the ceiling slot: the room script drops the beam from here to the dais floor
    sh = empty("SHAFT_Throne", (0, THRONE_Y, CEIL_Z - 0.8))
    aim(sh, (0, THRONE_Y, 0), forward='-Y')
    cams = [("CAM_01_Carpet_Entrance", Vector((0.0, BACK_Y + 4.0, 1.7)), screen_c),
            ("CAM_02_Column_Side", Vector((-6.8, -31.0, 1.0)), Vector((0.0, SCREEN_Y, 7.0))),
            ("CAM_03_Dais_Front", Vector((0.0, -9.5, 1.7)), screen_c),
            ("CAM_04_Gallery_Left", Vector((-GAL_IN_X - 1.0, -20.0, GAL_Z[0] + 1.6)), screen_c),
            ("CAM_05_Gallery_Right", Vector((GAL_IN_X + 1.0, -26.0, GAL_Z[1] + 1.6)), screen_c),
            ("CAM_06_Chandelier", Vector((0.0, -28.0, 15.0)), Vector((0.0, SCREEN_Y, 4.0))),
            ("CAM_07_Panel_Wide", Vector((0.0, -8.4, DAIS_Z + 2.9)), Vector((0.0, 4.0, DAIS_Z + 2.4))),
            ("CAM_08_Panel_Left", Vector((-1.6, -2.2, DAIS_Z + 2.1)), Vector((-6.0, 3.3, DAIS_Z + 1.5))),
            ("CAM_09_Panel_Right", Vector((1.6, -2.2, DAIS_Z + 2.1)), Vector((6.0, 3.3, DAIS_Z + 1.5))),
            # the react-pause view: the throne from the side of the dais, behind the screen's plane
            ("CAM_10_Reaction", Vector((-7.0, 6.8, DAIS_Z + 1.7)), Vector((0.0, THRONE_Y + 0.3, DAIS_Z + 2.2)))]
    for name, p, t in cams:
        aim(empty(name, p), t)
    podium_markers()
    # chat screen: top centre, just under the screen frame; reply screen above it
    top = Vector((0.0, SCREEN_Y - 0.03, DAIS_Z + SCREEN_LIFT - 0.3))
    aim(empty("CHAT_Screen", top), top + Vector((0.0, -10.0, 0.0)), forward='-Y')
    rtop = Vector((0.0, SCREEN_Y - 0.03, DAIS_Z + SCREEN_LIFT + SCREEN_H + 2.1))
    aim(empty("REPLY_Screen", rtop), rtop + Vector((0.0, -10.0, 0.0)), forward='-Y')
    # reaction targets (!tomato throne ...)
    for name, p in (("TARGET_Throne", (0.0, THRONE_Y + 0.4, DAIS_Z + 3.2)), ("TARGET_Chandelier", tuple(CHANDS[1])),
                    ("TARGET_Banner_Left", (-COL_X + COL_R + 1.7, COL_YS[2], 9.5)), ("TARGET_Banner_Right", (COL_X - COL_R - 1.7, COL_YS[2], 9.5))):
        aim(empty(name, p), (p[0], p[1] - 10.0, p[2]), forward='-Y')
    # the chat lines: standing people along both edges of the carpet
    for s, side in ((-1, "L"), (1, "R")):
        for li, x in enumerate(LINE_XS):
            y = LINE_Y0
            k = 0
            while y >= LINE_Y1:
                k += 1
                empty("AUDIENCE_%s%d_%02d" % (side, li + 1, k), (s * x, y, STAND_Z), size=0.3)
                y -= LINE_PITCH


def build_all():
    """Builds the whole hall from scratch (clearing the Hall collections first) and writes
    crowd_seats.json. Returns the polygon count per mesh object.
    """
    setup_materials()
    CROWD_SEATS.clear()
    for cname in (COLL, MARKERS):
        c = bpy.data.collections.get(cname)
        if c:
            for o in list(c.objects):
                bpy.data.objects.remove(o, do_unlink=True)
    build_floor()
    build_walls()
    build_ceiling()
    build_columns()
    build_banners()
    build_galleries()
    build_dais()
    build_throne()
    build_screen()
    build_podiums()
    build_benches()
    build_chandeliers()
    build_markers()
    export_crowd_seats()
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    return {o.name: len(o.data.polygons) for o in col(COLL).objects if o.type == "MESH"}


def export_crowd_seats(path=None):
    """crowd_seats.json next to the .glb (build_all writes it): one entry per gallery seat, in Redot
    axes (p = seat surface centre, n = the way it faces, s = bal (lower tier) / gal (upper), r = row)."""
    import json
    path = path or os.path.join(os.path.dirname(GLB), "crowd_seats.json")
    with open(path, "w") as f:
        json.dump({"pitch": CROWD_PITCH, "seats": CROWD_SEATS}, f, separators=(",", ":"))
    return len(CROWD_SEATS)


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
