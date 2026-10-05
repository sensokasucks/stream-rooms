"""lecture_hall_gen.py - builds the lecture hall room in Blender.

    exec(open(r"C:\\Users\\jonza\\Documents\\RedotHomeTheater\\blender\\lecture_hall_gen.py").read())
    build_all(); export_glb()

A Victorian Gothic university lecture theatre modelled on Harvard's Sanders Theatre (layout
taken from its public floor plans / 3D tour): a U-shaped hall with straight pews on the
facets of a half-octagon, raked up to the walls around a flat pit, a shallow wrap-around
balcony on slender posts, an arcaded top gallery, a curved wooden sounding canopy over the
stage, a hammer-beam ceiling and a big ring chandelier. The inscription, shields and statues
are original stand-ins. The screen (14.4 m x 8.1 m) stands on the stage floor.

The orchestra is four stepped rows round the U (lowest at the pit, panelled ends at the
aisles, half steps up the back); the side rows stop short of the corners, where aisles lead
to tall carved oak exit doors under stained glass fanlights. Windows are pairs of pointed
lancets high on the walls with rose rondels under the gallery. Textures for the glass, the
door leaves and the EXIT sign come from make_hall_textures.py (rooms/lecture_hall/textures).
GLASS_n markers (one per lancet) feed the room's sunbeams.

Blender axes: origin = stage-front centre on the hall floor. -Y = toward the audience,
+Y = toward the stage wall (y = 9), Z = up. Markers follow the Stream Rooms contract.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix, Euler

TEX = r"C:\Users\jonza\Documents\RedotHomeTheater\stream_rooms\rooms\lecture_hall\textures"
# PANEL = True (set before exec) builds the "panel" copy: four presenter podiums, two each
# side of a smaller screen that hangs higher, and no piano / table / lectern on the stage.
PANEL = bool(globals().get("PANEL", False))
GLB = (r"C:\Users\jonza\Documents\RedotHomeTheater\stream_rooms\rooms\lecture_hall_panel\lecture_hall_panel.glb" if PANEL
       else r"C:\Users\jonza\Documents\RedotHomeTheater\stream_rooms\rooms\lecture_hall\lecture_hall.glb")


# ════════════════════════════════════════════════════════════════
#  Generic helpers
# ════════════════════════════════════════════════════════════════
def col(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
    if c.name not in [x.name for x in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(c)
    return c


def mat(name, color, rough=0.7, metal=0.0, emit=None, estr=0.0):
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
    return m


def tex_mat(name, image, rough=0.7, metal=0.0, emit=0.0):
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
    return m


class MB:
    def __init__(self, name, collection="Hall"):
        self.name, self.col = name, collection
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def done(self, origin=None):
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


def _face(mb, pts, m, uvs):
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


def cyl(mb, center, r, depth, m, axis="z", segs=16, r2=None):
    res = bmesh.ops.create_cone(mb.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                                radius2=r if r2 is None else r2, depth=depth)
    rot = {"z": Matrix.Identity(3), "x": Matrix.Rotation(math.pi / 2, 3, 'Y'), "y": Matrix.Rotation(-math.pi / 2, 3, 'X')}[axis]
    mtx = Matrix.Translation(Vector(center)) @ rot.to_4x4()
    bmesh.ops.transform(mb.bm, matrix=mtx, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mb.mi(m)


def sphere(mb, center, r, m, subdiv=2, scale=(1, 1, 1)):
    res = bmesh.ops.create_icosphere(mb.bm, subdivisions=subdiv, radius=r)
    mtx = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.transform(mb.bm, matrix=mtx, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mb.mi(m)
        f.smooth = True


def torus(mb, center, R, r, m, axis="z", segs=24, rsegs=6):
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


def empty(name, loc, parent=None, collection="Hall_Markers", size=0.2):
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
    d = Vector(target) - o.location
    o.rotation_euler = d.to_track_quat(forward, 'Z').to_euler()



# ════════════════════════════════════════════════════════════════
#  Plan (from the reference tour's floor plans): a U-shaped hall. Straight side walls run
#  from the stage wall back past the stage front, then a half-octagon closes the back.
#  Pews are straight runs on each facet, raked up toward the walls, around a flat "pit"
#  with its own block of pews right in front of the stage. A shallow balcony wraps the
#  whole U on slender posts, and a narrow arcaded gallery runs above it. Units: metres.
#  Blender axes: origin = stage-front centre on the pit floor, -Y = toward the audience.
# ════════════════════════════════════════════════════════════════
HALF_W = 14.0                  # side walls at x = +-14
STAGE_W, STAGE_D, STAGE_Z = 15.0, 7.5, 1.1
BACK_Y = STAGE_D               # stage wall
WALL = [(HALF_W, BACK_Y), (HALF_W, -4.0), (4.5, -13.5), (-4.5, -13.5), (-HALF_W, -4.0), (-HALF_W, BACK_Y)]
# Orchestra: four stepped rows round the U, raised theatre-style (lowest at the pit, highest
# at the wall). Every row follows the wall plan at a fixed distance, so the tiers form one
# clean band; the flat pit is everything inside that band.
ORCH_ROWS, ORCH_STEP, ORCH_RISE = 4, 0.95, 0.4
ORCH_D0 = ORCH_STEP / 2        # row 0 (at the wall): distance of its centre line from the wall
ORCH_DEPTH = ORCH_ROWS * ORCH_STEP
PIT_X = HALF_W - ORCH_DEPTH    # the side tiers start here
PEW_OFF = -0.02                # pews sit this far in from the row's centre line
# side tiers run from ORCH_SIDE_Y0 (near the stage) to ORCH_SIDE_Y1; the corner aisle beyond
# leads to the big exit doors on the side walls
ORCH_SIDE_Y0, ORCH_SIDE_Y1 = 2.6, -0.8
EXIT_DOOR_Y = -2.35            # centre of the corner exit doors (side walls, x = +-HALF_W)
BAL_ROWS, BAL_D0, BAL_STEP, BAL_Z0, BAL_RISE = 4, 0.85, 0.9, 6.2, 0.5
BAL_FRONT_D, BAL_SOFFIT = 4.45, 5.8
GAL_ROWS, GAL_D0, GAL_STEP, GAL_Z0, GAL_RISE = 2, 0.7, 0.9, 10.5, 0.45
GAL_FRONT_D, GAL_SOFFIT = 2.3, 10.15
CORNICE_Z, CEIL_MID_Z, CEIL_TOP = 15.5, 19.0, 20.2
SCREEN_W, SCREEN_H, SCREEN_Y = 14.4, 8.1, 3.8
SCREEN_LIFT = 0.02              # screen bottom above the stage floor
if PANEL:
    SCREEN_W, SCREEN_H, SCREEN_LIFT = 8.6, 4.8375, 2.0
# presenter podiums (panel copy): (x, y) of each podium's centre, left to right as the audience sees it
PODIUMS = [(-6.65, 2.55), (-5.2, 2.45), (5.2, 2.45), (6.65, 2.55)]
PRESENTER_W, PRESENTER_H = 1.3, 1.25         # the feed plane behind each podium (must match the room)
PRESENTER_BACK, PRESENTER_LIFT = 0.45, 0.75  # plane: this far behind the podium, bottom this high
CHAND = Vector((0.0, -4.0, 9.6))


def v2(x, y):
    return Vector((x, y))


def inward_normal(a, b):
    d = (b - a).normalized()
    n = v2(-d.y, d.x)
    mid = (a + b) / 2
    if n.dot(v2(0, -3.5) - mid) < 0:
        n = -n
    return n


def offset_line(pts, d):
    """Offset an open polyline toward the hall's inside by d (mitred corners)."""
    P2 = [v2(*p) for p in pts]
    segs = []
    for a, b in zip(P2[:-1], P2[1:]):
        n = inward_normal(a, b)
        segs.append((a + n * d, b + n * d))
    out = [segs[0][0]]
    for (a1, b1), (a2, b2) in zip(segs[:-1], segs[1:]):
        # intersect the two offset lines
        d1, d2 = b1 - a1, b2 - a2
        den = d1.x * d2.y - d1.y * d2.x
        if abs(den) < 1e-9:
            out.append(b1)
        else:
            t = ((a2.x - a1.x) * d2.y - (a2.y - a1.y) * d2.x) / den
            out.append(a1 + d1 * t)
    out.append(segs[-1][1])
    return out


def pieces(line, max_len):
    """Split a polyline into straight pieces: (a, b, inward normal, corner-distance)."""
    res = []
    for i, (a, b) in enumerate(zip(line[:-1], line[1:])):
        L = (b - a).length
        n = max(1, int(math.ceil(L / max_len)))
        nrm = inward_normal(a, b)
        for k in range(n):
            pa, pb = a + (b - a) * (k / n), a + (b - a) * ((k + 1) / n)
            mid = (pa + pb) / 2
            corner = min(((mid - c).length for c in line[1:-1]), default=99.0)
            res.append((pa, pb, nrm, corner, i))
    return res


def yaw_for(n):
    """Yaw so that a box's local +Y points along n."""
    return math.atan2(-n.x, n.y)


def prism_piece(mb, a, b, n, d_in, d_out, z_top, z_bot, m_top, m_side):
    """Tier block under a straight run: corners a/b on the row line, n = inward normal.
    d_in/d_out: how far the block reaches toward the inside / the wall."""
    ai, bi = a + n * d_in, b + n * d_in
    ao, bo = a - n * d_out, b - n * d_out
    P3 = lambda p, z: Vector((p.x, p.y, z))
    top = [P3(ao, z_top), P3(bo, z_top), P3(bi, z_top), P3(ai, z_top)]
    f = _face(mb, top, m_top, [(p.x / 2, p.y / 2) for p in top])
    f.normal_update()
    if f.normal.z < 0:
        f.normal_flip()
    if z_top - z_bot > 0.01:
        riser = [P3(ai, z_bot), P3(bi, z_bot), P3(bi, z_top), P3(ai, z_top)]
        f = _face(mb, riser, m_side, [(0, 0), (1, 0), (1, (z_top - z_bot)), (0, (z_top - z_bot))])
        f.normal_update()
        if f.normal.to_2d().dot(n) < 0:
            f.normal_flip()


# Seats for the app's filler crowd (tiers, balcony, gallery): pew_piece records them while
# CROWD_TAG is set; export_crowd_seats() writes them next to the room's .glb.
CROWD_SEATS = []
CROWD_TAG = None
CROWD_ROW = 0
CROWD_PITCH = 0.6       # metres per person along a pew


def pew_piece(mb, a, b, n, z, leather=False, shelf=True, end_a=False, end_b=False):
    if CROWD_TAG:
        L = (b - a).length
        k = max(1, int(round(L / CROWD_PITCH)))
        top = z + (0.495 if leather else 0.455)
        for i in range(k):
            p = a + (b - a) * ((i + 0.5) / k) + n * 0.05
            CROWD_SEATS.append({"p": [round(p.x, 3), round(top, 3), round(-p.y, 3)],
                                "n": [round(n.x, 3), round(-n.y, 3)], "s": CROWD_TAG, "r": CROWD_ROW})
    yaw = yaw_for(n)
    L = (b - a).length + 0.02
    c = (a + b) / 2
    def at(local_y, zz):
        p = c + n * local_y
        return (p.x, p.y, zz)
    box(mb, at(0.05, z + 0.43), (L, 0.46, 0.05), "Oak", rot=(0, 0, yaw))
    if leather:
        box(mb, at(0.05, z + 0.475), (L - 0.04, 0.42, 0.04), "Leather", rot=(0, 0, yaw))
    box(mb, at(0.26, z + 0.22), (L, 0.03, 0.4), "Oak_Dark", rot=(0, 0, yaw))
    box(mb, at(-0.22, z + 0.78), (L, 0.05, 0.62), "Oak", rot=(-0.14, 0, yaw))
    if shelf:
        box(mb, at(-0.33, z + 0.97), (L, 0.18, 0.03), "Oak_Dark", rot=(0, 0, yaw))
    d = (b - a).normalized()
    for flag, p in ((end_a, a), (end_b, b)):
        if flag:
            q = p + n * 0.02
            box(mb, (q.x, q.y, z + 0.5), (0.07, 0.72, 1.0), "Oak_Dark", rot=(0, 0, yaw))


def seat_row(mb, line, z, keep, leather, shelf, aisle_gap=0.6, piece_len=1.5):
    """Pews along a row line; pieces failing keep(mid) or near an aisle are skipped."""
    ps = pieces(line, piece_len)
    flags = []
    for (a, b, n, corner, fi) in ps:
        mid = (a + b) / 2
        ok = keep(mid) and corner > aisle_gap and not (fi == 2 and abs(mid.x) < aisle_gap)
        flags.append(ok)
    for i, (a, b, n, corner, fi) in enumerate(ps):
        if not flags[i]:
            continue
        end_a = i == 0 or not flags[i - 1]
        end_b = i == len(ps) - 1 or not flags[i + 1]
        pew_piece(mb, a, b, n, z, leather, shelf, end_a, end_b)


def baluster_rail(mb, pts, z, h, m_rail, m_bal, spacing=0.17, solid_base=True):
    """Handrail + turned balusters along a polyline of 2D points."""
    for i in range(len(pts) - 1):
        a, b = Vector((pts[i][0], pts[i][1], 0)), Vector((pts[i + 1][0], pts[i + 1][1], 0))
        L = (b - a).length
        if L < 1e-3:
            continue
        yaw = math.atan2(b.y - a.y, b.x - a.x)
        mid = (a + b) / 2
        box(mb, (mid.x, mid.y, z + h), (L + 0.02, 0.14, 0.09), m_rail, rot=(0, 0, yaw))
        if solid_base:
            box(mb, (mid.x, mid.y, z + 0.06), (L + 0.02, 0.12, 0.12), m_rail, rot=(0, 0, yaw))
        n = max(1, int(L / spacing))
        for k in range(n):
            p = a + (b - a) * ((k + 0.5) / n)
            cyl(mb, (p.x, p.y, z + 0.12 + (h - 0.16) / 2), 0.028, h - 0.16, m_bal, segs=6)
            sphere(mb, (p.x, p.y, z + 0.12 + (h - 0.16) * 0.55), 0.042, m_bal, subdiv=1)


def orch_z(j):
    """Top of orchestra row j (0 = at the wall, the highest)."""
    return ORCH_RISE * (ORCH_ROWS - j)


def bal_z(k):
    return BAL_Z0 + (BAL_ROWS - 1 - k) * BAL_RISE


def gal_z(k):
    return GAL_Z0 + (GAL_ROWS - 1 - k) * GAL_RISE


def orch_spans(fi, a, b):
    """Kept stretches of facet fi's segment a->b (a row line): [(t0, t1, cut0, cut1)].
    cut = the stretch ends at a cut across the tiers (not at a mitred corner)."""
    if fi in (0, len(WALL) - 2):          # side walls: cut straight across at two y values
        t = sorted((a.y - yy) / (a.y - b.y) for yy in (ORCH_SIDE_Y0, ORCH_SIDE_Y1))
        return [(t[0], t[1], True, True)]
    # the diagonals start at the corner aisle: that mitred end shows, so it gets a cap too
    return [(0.0, 1.0, fi == 1, fi == len(WALL) - 3)]


# ════════════════════════════════════════════════════════════════
#  Materials
# ════════════════════════════════════════════════════════════════
def setup_materials():
    tex_mat("Oak", "oak.png", 0.45)
    tex_mat("Oak_Gothic", "gothic_panel.png", 0.5)
    tex_mat("Stage_Floor", "wood_light.png", 0.35)
    tex_mat("Carpet", "carpet.png", 0.95)
    tex_mat("Ochre_Panel", "ochre_panel.png", 0.85)
    tex_mat("Red_Wall", "red_wall.png", 0.85)
    tex_mat("Ceiling_Panel", "ceiling_panel.png", 0.9)
    tex_mat("Tympanum", "tympanum.png", 0.6, 0.2)
    tex_mat("Glass_Lancet", "glass_lancet.png", 0.25, emit=0.8)
    tex_mat("Glass_Rondel", "glass_rondel.png", 0.25, emit=0.8)
    tex_mat("Glass_Fan", "glass_fan.png", 0.25, emit=0.6)
    tex_mat("Door_Leaf", "door_leaf.png", 0.45)
    tex_mat("Exit_Sign", "exit_sign.png", 0.4, emit=2.0)
    tex_mat("Shield", "shield.png", 0.5)
    tex_mat("Arcade_Glow", "arcade_glow.png", 0.8, emit=1.2)
    mat("Oak_Dark", (0.16, 0.08, 0.035), 0.45)
    mat("Leather", (0.30, 0.07, 0.05), 0.55)
    mat("Brass", (0.75, 0.55, 0.25), 0.3, 1.0)
    mat("Bulb", (1.0, 0.95, 0.85), 0.2, 0.0, (1.0, 0.82, 0.55), 6.0)
    mat("Marble", (0.86, 0.85, 0.82), 0.35)
    mat("Screen_Black", (0.0, 0.0, 0.0), 0.5)
    mat("Screen_Frame", (0.02, 0.02, 0.02), 0.7)
    mat("Black_Metal", (0.03, 0.03, 0.035), 0.5, 0.6)
    mat("Piano_Cover", (0.03, 0.03, 0.035), 0.9)
    mat("Monitor_Black", (0.02, 0.02, 0.025), 0.4, 0.2)
    mat("Door_Dark", (0.12, 0.06, 0.03), 0.5)
    mat("Booth_Glass", (0.02, 0.02, 0.03), 0.1)
    mat("Podium_Lamp", (1.0, 0.95, 0.85), 0.2, 0.0, (1.0, 0.85, 0.6), 4.0)


# ════════════════════════════════════════════════════════════════
#  Seating
# ════════════════════════════════════════════════════════════════
def build_pit_and_orchestra():
    global CROWD_TAG, CROWD_ROW
    CROWD_SEATS.clear()
    CROWD_TAG = None
    mb = MB("Seating_Orchestra")
    box(mb, (0, -3, -0.05), (40, 30, 0.1), "Carpet", uvs=2.0)
    # the block of straight pews in front of the stage (centre aisle)
    for r in range(6):
        y = -1.35 - r * 0.95
        for x0, x1 in ((-4.8, -0.65), (0.65, 4.8)):
            pew_piece(mb, v2(x0, y), v2(x1, y), v2(0, 1), 0.0, False, r > 0, True, True)
    # stepped rows round the U, highest at the walls
    for j in range(ORCH_ROWS):
        z = orch_z(j)
        La = offset_line(WALL, j * ORCH_STEP if j else -0.3)      # outer edge (row 0 tucks into the wall)
        Lb = offset_line(WALL, (j + 1) * ORCH_STEP)               # inner edge (the riser)
        Lp = offset_line(WALL, ORCH_D0 + j * ORCH_STEP + PEW_OFF)  # the pews
        for fi in range(len(WALL) - 1):
            for (Ao, Bo, c0, c1), (Ai, Bi, _, _) in zip(orch_span_pts(fi, La), orch_span_pts(fi, Lb)):
                tier_block(mb, Ao, Bo, Ai, Bi, z, c0, c1)
            CROWD_TAG, CROWD_ROW = "orch", ORCH_ROWS - 1 - j      # row 0 = nearest the pit
            for (Pa, Pb, c0, c1) in orch_span_pts(fi, Lp):
                orch_pews(mb, fi, Pa, Pb, c0, c1, z, shelf=j > 0)
            CROWD_TAG = None
        # half steps in the back row's centre gap (each row is ORCH_RISE higher than the next)
        dmid = (j + 1.25) * ORCH_STEP
        zs = z - ORCH_RISE / 2
        box(mb, (0.0, WALL[2][1] + dmid, zs / 2), (1.0, ORCH_STEP / 2, zs), "Oak_Dark", uvs=0.6)
        box(mb, (0.0, WALL[2][1] + dmid, zs - 0.01), (1.04, ORCH_STEP / 2 + 0.04, 0.04), "Carpet")
    mb.done()


def orch_span_pts(fi, line):
    """The kept stretches of facet fi on a row line, as end points: [(A, B, cutA, cutB)]."""
    a, b = line[fi], line[fi + 1]
    return [(a + (b - a) * t0, a + (b - a) * t1, c0, c1) for (t0, t1, c0, c1) in orch_spans(fi, a, b)]


def tier_block(mb, Ao, Bo, Ai, Bi, z, cap_a, cap_b):
    """One stretch of an orchestra row: carpeted top, oak riser down to the floor, an oak
    nosing on the step, and panelled end caps where the row stops at an aisle."""
    P = lambda p, zz: Vector((p.x, p.y, zz))
    top = [P(Ao, z), P(Bo, z), P(Bi, z), P(Ai, z)]
    f = _face(mb, top, "Carpet", [(p.x / 2, p.y / 2) for p in top])
    f.normal_update()
    if f.normal.z < 0:
        f.normal_flip()
    L = (Bi - Ai).length
    inward = (Ai - Ao)
    riser = [P(Ai, 0.0), P(Bi, 0.0), P(Bi, z), P(Ai, z)]
    f = _face(mb, riser, "Oak_Dark", [(0, 0), (L, 0), (L, z), (0, z)])
    f.normal_update()
    if f.normal.to_2d().dot(inward) < 0:
        f.normal_flip()
    bar(mb, P(Ai, z - 0.03), P(Bi, z - 0.03), 0.07, "Oak")
    along = (Bo - Ao)
    for flag, O, I, away in ((cap_a, Ao, Ai, -along), (cap_b, Bo, Bi, along)):
        if not flag:
            continue
        w = (I - O).length
        q = [P(O, 0.0), P(I, 0.0), P(I, z), P(O, z)]
        uo = (O.x + O.y) / 1.8
        f = _face(mb, q, "Oak_Gothic", [(uo, 0), (uo + w / 1.8, 0), (uo + w / 1.8, z / 1.8), (uo, z / 1.8)])
        f.normal_update()
        if f.normal.to_2d().dot(away) < 0:
            f.normal_flip()
        # a capping rail along the top of the end
        bar(mb, P(O, z + 0.04), P(I, z + 0.04), 0.09, "Oak_Dark")


def orch_pews(mb, fi, a, b, cut_a, cut_b, z, shelf):
    """Pews along one kept stretch of a row: split into pieces of at most 1.6 m, end panels at
    the stretch ends. Mitred ends stop short so neighbouring facets' pews never cross."""
    d = (b - a).normalized()
    diag_cut = fi in (1, len(WALL) - 3)
    trim_a = (0.3 if diag_cut else 0.08) if cut_a else 0.42
    trim_b = (0.3 if diag_cut else 0.08) if cut_b else 0.42
    a, b = a + d * trim_a, b - d * trim_b
    runs = [(a, b)]
    if fi == (len(WALL) - 1) // 2:           # back wall: a centre gap for the steps up
        runs = []
        for (p, q) in ((a, b),):
            ta = (p.x - 0.5) / (p.x - q.x)
            tb = (p.x + 0.5) / (p.x - q.x)
            runs = [(p, p + (q - p) * ta), (p + (q - p) * tb, q)]
    n = inward_normal(a, b)
    for (p, q) in runs:
        L = (q - p).length
        k = max(1, int(math.ceil(L / 1.6)))
        for i in range(k):
            pa, pb = p + (q - p) * (i / k), p + (q - p) * ((i + 1) / k)
            pew_piece(mb, pa, pb, n, z, False, shelf, i == 0, i == k - 1)


def build_balcony_and_gallery():
    global CROWD_TAG, CROWD_ROW
    mb = MB("Seating_Balcony")
    for k in range(BAL_ROWS):
        d = BAL_D0 + k * BAL_STEP
        z = bal_z(k)
        CROWD_TAG, CROWD_ROW = "bal", BAL_ROWS - 1 - k
        for (a, b, n, corner, fi) in pieces(offset_line(WALL, d), 0.8):
            prism_piece(mb, a, b, n, BAL_STEP / 2 + (0.2 if k == BAL_ROWS - 1 else 0), BAL_STEP / 2 + (0.3 if k == 0 else 0), z, BAL_SOFFIT, "Carpet", "Oak_Gothic")
        seat_row(mb, offset_line(WALL, d - 0.1), z, lambda p: True, leather=True, shelf=True, aisle_gap=0.55)
    CROWD_TAG = None
    # soffit, fascia, handrail, posts
    front = offset_line(WALL, BAL_FRONT_D)
    for (a, b, n, corner, fi) in pieces(front, 3.0):
        wall_a, wall_b = a - n * BAL_FRONT_D, b - n * BAL_FRONT_D
        q = [Vector((a.x, a.y, BAL_SOFFIT)), Vector((b.x, b.y, BAL_SOFFIT)), Vector((wall_b.x, wall_b.y, BAL_SOFFIT)), Vector((wall_a.x, wall_a.y, BAL_SOFFIT))]
        f = _face(mb, q, "Oak", [(p.x / 2, p.y / 2) for p in q])
        f.normal_update()
        if f.normal.z > 0:
            f.normal_flip()
    mb.done()

    rails = MB("Balustrades")
    baluster_rail(rails, [(p.x, p.y) for p in front], bal_z(BAL_ROWS - 1) - 0.1, 0.9, "Oak", "Oak")
    # posts under the balcony front at corners and facet midpoints
    # (the front stands clear of the orchestra tiers, so every post runs down to the pit floor;
    # the back wall's short front needs no middle post)
    posts = list(front[1:-1])
    back_fi = (len(WALL) - 1) // 2
    for i, (a, b) in enumerate(zip(front[:-1], front[1:])):
        if i != back_fi:
            posts.append((a + b) / 2)
    posts += [front[0] + (front[1] - front[0]) * t for t in (0.2,)] + [front[-1] + (front[-2] - front[-1]) * t for t in (0.2,)]
    for p in posts:
        cyl(rails, (p.x, p.y, BAL_SOFFIT / 2), 0.1, BAL_SOFFIT, "Oak_Dark", segs=10)
        box(rails, (p.x, p.y, BAL_SOFFIT - 0.12), (0.32, 0.32, 0.24), "Oak_Dark")
        box(rails, (p.x, p.y, 0.2), (0.3, 0.3, 0.4), "Oak_Dark")          # plinth
        box(rails, (p.x, p.y, 0.43), (0.24, 0.24, 0.06), "Oak")
        torus(rails, (p.x, p.y, 1.1), 0.105, 0.025, "Oak", segs=12, rsegs=4)  # turned rings
        torus(rails, (p.x, p.y, BAL_SOFFIT - 0.35), 0.105, 0.025, "Oak", segs=12, rsegs=4)
    # upper gallery: two rows behind an arcade of pointed arches
    gm = MB("Seating_Gallery")
    for k in range(GAL_ROWS):
        d = GAL_D0 + k * GAL_STEP
        z = gal_z(k)
        CROWD_TAG, CROWD_ROW = "gal", GAL_ROWS - 1 - k
        for (a, b, n, corner, fi) in pieces(offset_line(WALL, d), 0.8):
            prism_piece(gm, a, b, n, GAL_STEP / 2 + (0.15 if k == GAL_ROWS - 1 else 0), GAL_STEP / 2 + (0.3 if k == 0 else 0), z, GAL_SOFFIT, "Carpet", "Oak_Gothic")
        seat_row(gm, offset_line(WALL, d - 0.1), z, lambda p: True, leather=True, shelf=False, aisle_gap=0.5)
    CROWD_TAG = None
    gfront = offset_line(WALL, GAL_FRONT_D)
    for (a, b, n, corner, fi) in pieces(gfront, 3.0):
        wa, wb = a - n * GAL_FRONT_D, b - n * GAL_FRONT_D
        q = [Vector((a.x, a.y, GAL_SOFFIT)), Vector((b.x, b.y, GAL_SOFFIT)), Vector((wb.x, wb.y, GAL_SOFFIT)), Vector((wa.x, wa.y, GAL_SOFFIT))]
        f = _face(gm, q, "Oak", [(p.x / 2, p.y / 2) for p in q])
        f.normal_update()
        if f.normal.z > 0:
            f.normal_flip()
    # the gallery also crosses the stage wall high up
    box(gm, (0, BACK_Y - 0.6, GAL_Z0 - 0.1), (2 * HALF_W, 1.2, 0.2), "Oak")
    gm.done()
    baluster_rail(rails, [(p.x, p.y) for p in gfront], GAL_Z0 - 0.05, 0.85, "Oak", "Oak", spacing=0.2)
    baluster_rail(rails, [(-HALF_W + GAL_FRONT_D, BACK_Y - 1.2), (HALF_W - GAL_FRONT_D, BACK_Y - 1.2)], GAL_Z0, 0.85, "Oak", "Oak", spacing=0.2)
    # arcade: posts and pointed arches along the gallery front
    arc = MB("Gallery_Arcade")
    for (a, b, n, corner, fi) in pieces(gfront, 2.2):
        mid = (a + b) / 2
        yaw = yaw_for(n)
        L = (b - a).length
        base, spring = GAL_Z0 + 0.9, GAL_Z0 + 3.1
        top = spring + L * 0.45
        for p in (a,):
            box(arc, (p.x, p.y, (GAL_Z0 + top) / 2), (0.16, 0.16, top - GAL_Z0), "Oak_Dark", rot=(0, 0, yaw))
        # arch outline (two sloped bars) + lintel above
        d = (b - a).normalized()
        sa = Vector((a.x, a.y, spring)) + Vector((d.x, d.y, 0)) * 0.08
        sb = Vector((b.x, b.y, spring)) - Vector((d.x, d.y, 0)) * 0.08
        apex = Vector((mid.x, mid.y, top - 0.1))
        bar(arc, sa, apex, 0.09, "Oak")
        bar(arc, sb, apex, 0.09, "Oak")
        bar(arc, Vector((a.x, a.y, top + 0.25)), Vector((b.x, b.y, top + 0.25)), 0.22, "Oak_Dark")
    p = gfront[-1]
    box(arc, (p.x, p.y, (GAL_Z0 + GAL_Z0 + 4.2) / 2), (0.16, 0.16, 4.2), "Oak_Dark")
    arc.done()
    rails.done()


# ════════════════════════════════════════════════════════════════
#  Walls, stage wall, ceiling
# ════════════════════════════════════════════════════════════════
def wall_band(mb, z0, z1, m, d=0.0, unit=False, uvs=2.0):
    """Faces on the U wall between heights z0 and z1, facing the inside."""
    line = offset_line(WALL, d) if d else [v2(*p) for p in WALL]
    acc = 0.0
    for a, b in zip(line[:-1], line[1:]):
        L = (b - a).length
        q = [Vector((a.x, a.y, z0)), Vector((b.x, b.y, z0)), Vector((b.x, b.y, z1)), Vector((a.x, a.y, z1))]
        uv = [(0, 0), (1, 0), (1, 1), (0, 1)] if unit else [(acc / uvs, z0 / uvs), ((acc + L) / uvs, z0 / uvs), ((acc + L) / uvs, z1 / uvs), (acc / uvs, z1 / uvs)]
        f = _face(mb, q, m, uv)
        f.normal_update()
        if f.normal.to_2d().dot(inward_normal(a, b)) < 0:
            f.normal_flip()
        acc += L


class Frame:
    """A local frame on a wall: x along the wall (to the right as you face it from inside),
    y out from the wall into the hall, z up."""
    def __init__(self, c, n):
        self.c, self.n = v2(c.x, c.y), n.normalized()
        self.d = v2(-self.n.y, self.n.x)
        self.yaw = yaw_for(self.n)

    def __call__(self, x, y, z):
        p = self.c + self.d * x + self.n * y
        return Vector((p.x, p.y, z))


def _facing_face(mb, pts, m, uvs, n):
    f = _face(mb, pts, m, uvs)
    f.normal_update()
    if f.normal.to_2d().dot(n) < 0:
        f.normal_flip()
    return f


def window_bays():
    """Centres of the window columns: a pair in every half-bay between the pilasters
    (the back wall's pairs sit a little outward, clear of the projection booth)."""
    line = [v2(*p) for p in WALL]
    res = []
    for i, (a, b) in enumerate(zip(line[:-1], line[1:])):
        n = inward_normal(a, b)
        dvec = (b - a).normalized()
        mid = (a + b) / 2
        for (p, q) in ((a, mid), (mid, b)):
            c = (p + q) / 2
            if i == (len(WALL) - 1) // 2:
                c = c + dvec * (0.35 if (c - mid).dot(dvec) > 0 else -0.35)
            for off in (-0.65, 0.65):
                res.append((c + dvec * off, n))
    return res


def arch_pts(W, rise, z_spring, segs=10):
    """Outline (x, z) of a pointed arch of span W, left spring -> apex -> right spring.
    rise / W = sqrt(3)/2 gives an equilateral arch."""
    c = 0.25 * W + rise * rise / W        # arc radius, centres on the spring line
    pts = []
    for k in range(segs + 1):             # left arc: centre (-W/2 + c), from 180 deg to the apex
        a0 = math.pi
        a1 = math.atan2(rise, W / 2 - c)
        t = a0 + (a1 - a0) * k / segs
        pts.append((-W / 2 + c + c * math.cos(t), z_spring + c * math.sin(t)))
    right = [(-x, z) for (x, z) in reversed(pts[:-1])]
    return pts + right


def lancet(mb, c, n, W=1.1, z0=None):
    """A tall pointed stained glass lancet (1 : 2) with an oak frame, sill and hood moulding."""
    z0 = z0 if z0 is not None else gal_z(0) + 1.55
    F = Frame(c, n)
    rise = W * math.sqrt(3) / 2
    zs = z0 + 2 * W - rise
    outline = [(-W / 2, z0), (W / 2, z0)] + [(x, z) for (x, z) in reversed(arch_pts(W, rise, zs, 10))]
    # (reversed: right spring -> apex -> left spring, continuing round from the bottom right)
    pts = [F(x, 0.03, z) for (x, z) in outline]
    uvs = [((x + W / 2) / W, (z - z0) / (2 * W)) for (x, z) in outline]
    _facing_face(mb, pts, "Glass_Lancet", uvs, F.n)
    ring = outline + [outline[0]]
    for (xa, za), (xb, zb) in zip(ring[:-1], ring[1:]):
        bar(mb, F(xa, 0.07, za), F(xb, 0.07, zb), 0.09, "Oak_Dark")
    # hood moulding over the arch, ending in two small label stops
    hood = arch_pts(W + 0.34, (W + 0.34) * math.sqrt(3) / 2, zs, 10)
    for (xa, za), (xb, zb) in zip(hood[:-1], hood[1:]):
        bar(mb, F(xa, 0.09, za), F(xb, 0.09, zb), 0.07, "Oak")
    for sx in (-1, 1):
        sphere(mb, F(sx * (W / 2 + 0.17), 0.1, zs - 0.06), 0.06, "Oak", subdiv=1)
    box(mb, F(0, 0.1, z0 - 0.06), (W + 0.3, 0.2, 0.1), "Oak_Dark", rot=(0, 0, F.yaw))
    box(mb, F(0, 0.06, z0 - 0.17), (W + 0.1, 0.12, 0.12), "Oak", rot=(0, 0, F.yaw))


def rondel(mb, c, n, zc, R=0.43, segs=32):
    """A round rose window with a double oak ring."""
    F = Frame(c, n)
    ring = [(R * math.cos(2 * math.pi * k / segs), zc + R * math.sin(2 * math.pi * k / segs)) for k in range(segs)]
    pts = [F(x, 0.03, z) for (x, z) in ring]
    uvs = [(0.5 + x / R * 0.49, 0.5 + (z - zc) / R * 0.49) for (x, z) in ring]
    _facing_face(mb, pts, "Glass_Rondel", uvs, F.n)
    for rr, t, dep, m in ((R + 0.02, 0.07, 0.07, "Oak_Dark"), (R + 0.11, 0.06, 0.05, "Oak")):
        for k in range(segs):
            a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
            bar(mb, F(rr * math.cos(a0), dep, zc + rr * math.sin(a0)), F(rr * math.cos(a1), dep, zc + rr * math.sin(a1)), t, m)
    for k in range(4):                    # four small bosses on the outer ring
        a = math.pi / 4 + k * math.pi / 2
        sphere(mb, F((R + 0.11) * math.cos(a), 0.08, zc + (R + 0.11) * math.sin(a)), 0.045, "Oak_Dark", subdiv=1)


LANCET_W = 1.1          # the room's sun shafts use the same size (lecture_hall_room.gd)


def build_windows():
    """Lancets high on the walls with rose rondels under the gallery, in pairs per half-bay.
    GLASS_n markers sit at each lancet's centre; +Z (in Redot) points into the hall."""
    mb = MB("Hall_Windows")
    zc = (bal_z(0) + 1.3 + GAL_SOFFIT) / 2
    z0 = gal_z(0) + 1.55
    for i, (c, n) in enumerate(window_bays()):
        lancet(mb, c, n, W=LANCET_W, z0=z0)
        rondel(mb, c, n, zc)
        p = Vector((c.x, c.y, z0 + LANCET_W)) + Vector((n.x, n.y, 0)) * 0.04
        o = empty("GLASS_%02d" % (i + 1), p)
        aim(o, p + Vector((n.x, n.y, 0)) * 5.0, forward='-Y')
    mb.done()


FAN_RISE = 0.625       # the door fanlight's rise / span (matches glass_fan.png)


def grand_door(mb, c, n, W=2.0, Hs=3.0, sign=True):
    """A tall pair of carved oak doors under a pointed stained glass fanlight, framed by
    pinnacled jambs and a crocketed gable, with brass push bars and an EXIT sign above."""
    F = Frame(c, n)
    rise = W * FAN_RISE
    # leaves (the right one mirrors the texture)
    for x0, x1, u0, u1 in ((-W / 2, 0.0, 0.0, 1.0), (0.0, W / 2, 1.0, 0.0)):
        q = [F(x0, 0.065, 0.02), F(x1, 0.065, 0.02), F(x1, 0.065, Hs), F(x0, 0.065, Hs)]
        _facing_face(mb, q, "Door_Leaf", [(u0, 0), (u1, 0), (u1, 1), (u0, 1)], F.n)
    # a dark backing behind the leaves so the wall never shows through the gap lines
    q = [F(-W / 2, 0.05, 0.0), F(W / 2, 0.05, 0.0), F(W / 2, 0.05, Hs), F(-W / 2, 0.05, Hs)]
    _facing_face(mb, q, "Oak_Dark", [(0, 0), (1, 0), (1, 1), (0, 1)], F.n)
    # fanlight
    outline = arch_pts(W, rise, Hs, 12)
    pts = [F(x, 0.06, z) for (x, z) in reversed(outline)]
    uvs = [((x + W / 2) / W, (z - Hs) / rise) for (x, z) in reversed(outline)]
    _facing_face(mb, pts, "Glass_Fan", uvs, F.n)
    # transom, jambs and the moulded arch surround
    box(mb, F(0, 0.1, Hs), (W + 0.1, 0.2, 0.14), "Oak_Dark", rot=(0, 0, F.yaw))
    for sx in (-1, 1):
        box(mb, F(sx * (W / 2 + 0.12), 0.12, Hs / 2), (0.24, 0.24, Hs), "Oak_Dark", rot=(0, 0, F.yaw))
        box(mb, F(sx * (W / 2 + 0.12), 0.14, 0.15), (0.3, 0.28, 0.3), "Oak_Dark", rot=(0, 0, F.yaw))
    for off, t, dep, m in ((0.1, 0.2, 0.12, "Oak_Dark"), (0.24, 0.1, 0.16, "Oak")):
        ring = arch_pts(W + 2 * off, rise + off * 1.2, Hs, 12)
        for (xa, za), (xb, zb) in zip(ring[:-1], ring[1:]):
            bar(mb, F(xa, dep, za), F(xb, dep, zb), t, m)
    # pinnacles either side
    px = W / 2 + 0.34
    top = Hs + rise * 0.8
    for sx in (-1, 1):
        box(mb, F(sx * px, 0.13, top / 2), (0.2, 0.2, top), "Oak", rot=(0, 0, F.yaw))
        box(mb, F(sx * px, 0.14, 0.2), (0.28, 0.28, 0.4), "Oak_Dark", rot=(0, 0, F.yaw))
        cyl(mb, F(sx * px, 0.13, top + 0.25), 0.13, 0.5, "Oak_Dark", segs=4, r2=0.0)
        sphere(mb, F(sx * px, 0.13, top + 0.52), 0.045, "Brass", subdiv=1)
    # crocketed gable over the arch
    apex = F(0, 0.18, Hs + rise + 0.45)
    for sx in (-1, 1):
        foot = F(sx * (W / 2 + 0.3), 0.18, Hs + 0.35)
        bar(mb, foot, apex, 0.12, "Oak_Dark")
        for k in range(1, 4):
            p = foot + (apex - foot) * (k / 4.0)
            sphere(mb, p + Vector((0, 0, 0.09)), 0.055, "Oak", subdiv=1)
    cyl(mb, apex + Vector((0, 0, 0.14)), 0.07, 0.28, "Oak_Dark", segs=8, r2=0.0)
    sphere(mb, apex + Vector((0, 0, 0.3)), 0.05, "Brass", subdiv=1)
    # brass push bars, handles and kick plates
    for sx in (-1, 1):
        xa, xb = sx * 0.12, sx * (W / 2 - 0.12)
        bar(mb, F(xa, 0.13, 1.0), F(xb, 0.13, 1.0), 0.04, "Brass")
        for xx in (xa, xb):
            bar(mb, F(xx, 0.05, 1.0), F(xx, 0.13, 1.0), 0.03, "Brass")
        box(mb, F(sx * 0.07, 0.07, 1.25), (0.04, 0.05, 0.45), "Brass", rot=(0, 0, F.yaw))
        box(mb, F(sx * W / 4, 0.055, 0.14), (W / 2 - 0.1, 0.012, 0.24), "Brass", rot=(0, 0, F.yaw))
    box(mb, F(0, 0.25, 0.02), (W + 0.7, 0.5, 0.04), "Marble", rot=(0, 0, F.yaw))    # threshold
    if sign:
        zsign = Hs + rise + 1.0
        box(mb, F(0, 0.07, zsign), (0.8, 0.14, 0.32), "Black_Metal", rot=(0, 0, F.yaw))
        q = [F(-0.36, 0.145, zsign - 0.13), F(0.36, 0.145, zsign - 0.13), F(0.36, 0.145, zsign + 0.13), F(-0.36, 0.145, zsign + 0.13)]
        _facing_face(mb, q, "Exit_Sign", [(0, 0), (1, 0), (1, 1), (0, 1)], F.n)
    return F(0, 1.0, 1.5)


def build_walls():
    mb = MB("Hall_Walls")
    wall_band(mb, 0.0, 3.6, "Oak_Gothic", uvs=1.8)
    wall_band(mb, 3.6, BAL_SOFFIT, "Red_Wall")
    wall_band(mb, BAL_SOFFIT, bal_z(0) + 1.3, "Oak_Gothic", uvs=1.8)
    wall_band(mb, bal_z(0) + 1.3, GAL_SOFFIT, "Ochre_Panel", unit=True)
    wall_band(mb, GAL_SOFFIT, gal_z(0) + 1.2, "Oak_Gothic", uvs=1.8)
    wall_band(mb, gal_z(0) + 1.2, CORNICE_Z, "Red_Wall")
    wall_band(mb, CORNICE_Z - 0.4, CORNICE_Z + 0.3, "Oak_Dark", d=0.25)
    # pilasters at the facet corners and midpoints
    line = [v2(*p) for p in WALL]
    spots = list(line[1:-1]) + [(a + b) / 2 for a, b in zip(line[:-1], line[1:])]
    for p in spots:
        c = p - v2(0.0, 0.0)
        box(mb, (c.x, c.y, CORNICE_Z / 2), (0.45, 0.45, CORNICE_Z), "Oak_Dark")
    # the big exit doors at the corner aisles (side walls, between the side tiers and the corner)
    for s in (-1, 1):
        grand_door(mb, v2(s * HALF_W, EXIT_DOOR_Y), v2(-s, 0.0), W=2.0, Hs=3.0)

    # ── stage wall (y = BACK_Y) ──
    q = [Vector((-HALF_W, BACK_Y, 0)), Vector((HALF_W, BACK_Y, 0)), Vector((HALF_W, BACK_Y, CEIL_TOP + 1)), Vector((-HALF_W, BACK_Y, CEIL_TOP + 1))]
    _face(mb, q, "Red_Wall", [(0, 0), (14, 0), (14, 10.5), (0, 10.5)])
    # beadboard + Gothic panelling behind the stage, with three arched niches and shields
    wall_quad(mb, "y", BACK_Y - 0.03, -STAGE_W / 2, STAGE_W / 2, STAGE_Z, 6.2, "Oak_Gothic", facing=-1, u=(0, 7), v=(0, 2.5))
    for k, xx in enumerate((-2.6, 0.0, 2.6)):
        wall_quad(mb, "y", BACK_Y - 0.06, xx - 0.6, xx + 0.6, 4.0, 5.3, "Shield", facing=-1)
    box(mb, (0, BACK_Y - 0.2, 6.35), (STAGE_W + 0.4, 0.4, 0.3), "Oak_Dark")        # cornice
    for xx in [-7.5 + i * 1.875 for i in range(9)]:                                 # brackets
        bar(mb, (xx, BACK_Y - 0.05, 5.6), (xx, BACK_Y - 0.45, 6.2), 0.14, "Oak_Dark")
    # curved wooden sounding canopy over the stage (quarter barrel of slats)
    R, cy, cz = 3.0, BACK_Y, 6.5 + 3.0
    n = 14
    for i in range(n):
        t0, t1 = (i / n) * math.pi / 2, ((i + 1) / n) * math.pi / 2
        y0, z0 = cy - R * math.sin(t0), cz - R * math.cos(t0)
        y1, z1 = cy - R * math.sin(t1), cz - R * math.cos(t1)
        q = [Vector((STAGE_W / 2, y0, z0)), Vector((-STAGE_W / 2, y0, z0)), Vector((-STAGE_W / 2, y1, z1)), Vector((STAGE_W / 2, y1, z1))]
        f = _face(mb, q, "Oak", [(0, i / n * 2), (6, i / n * 2), (6, (i + 1) / n * 2), (0, (i + 1) / n * 2)])
        f.normal_update()
        if f.normal.dot(Vector((0, -1, -1))) < 0:
            f.normal_flip()
        if i % 2 == 0:
            bar(mb, (-STAGE_W / 2, y0 - 0.03, z0 - 0.03), (STAGE_W / 2, y0 - 0.03, z0 - 0.03), 0.06, "Oak_Dark")
    # side walls beside the stage, under the balcony: panelling + doors
    for s in (-1, 1):
        x0, x1 = sorted((s * STAGE_W / 2, s * HALF_W))
        wall_quad(mb, "y", BACK_Y - 0.03, x0, x1, 0.0, 3.6, "Oak_Gothic", facing=-1, u=(0, (x1 - x0) / 1.8), v=(0, 2))
        grand_door(mb, v2(s * 10.8, BACK_Y), v2(0.0, -1.0), W=1.6, Hs=2.4)
    # tympanum (inscription) above the gallery crossing
    tw, t0, t1 = 11.0, 11.6, 13.4
    wall_quad(mb, "y", BACK_Y - 0.05, -tw / 2, tw / 2, t0, t1, "Tympanum", facing=-1, v=(0, 0.72))
    nseg = 16
    for i in range(nseg):
        a, b = math.pi * i / nseg, math.pi * (i + 1) / nseg
        pa = Vector((-math.cos(a) * tw / 2, BACK_Y - 0.05, t1 + math.sin(a) * 1.9))
        pb = Vector((-math.cos(b) * tw / 2, BACK_Y - 0.05, t1 + math.sin(b) * 1.9))
        cc = Vector((0, BACK_Y - 0.05, t1))
        ua = (0.5 - math.cos(a) * 0.5, 0.72 + math.sin(a) * 0.28)
        ub = (0.5 - math.cos(b) * 0.5, 0.72 + math.sin(b) * 0.28)
        _face(mb, [pb, pa, cc], "Tympanum", [ub, ua, (0.5, 0.72)])
        bar(mb, (pa.x, pa.y - 0.1, pa.z), (pb.x, pb.y - 0.1, pb.z), 0.3, "Oak_Dark")
    bar(mb, (-tw / 2, BACK_Y - 0.15, t0 - 0.15), (tw / 2, BACK_Y - 0.15, t0 - 0.15), 0.3, "Oak_Dark")
    for s in (-1, 1):
        bar(mb, (s * tw / 2, BACK_Y - 0.15, t0 - 0.15), (s * tw / 2, BACK_Y - 0.15, t1), 0.3, "Oak_Dark")
    # clustered columns at the stage corners, up to the ceiling
    for s in (-1, 1):
        cx = s * (STAGE_W / 2 + 0.6)
        box(mb, (cx, BACK_Y - 0.5, CORNICE_Z / 2), (0.8, 0.8, CORNICE_Z), "Oak_Dark")
        for dx, dy in ((-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)):
            cyl(mb, (cx + dx * 0.8, BACK_Y - 0.5 + dy * 0.8, CORNICE_Z / 2), 0.14, CORNICE_Z, "Oak", segs=10)
    mb.done()


def build_ceiling():
    mb = MB("Hall_Ceiling")
    outer = [v2(*p) for p in WALL] + [v2(*WALL[0])]
    outer_closed = [v2(*p) for p in WALL]
    # a closed loop: the U wall plus the stage-wall edge
    loop = outer_closed
    cen = v2(0, -3.0)
    mid = [cen + (p - cen) * 0.55 for p in loop]
    top = [cen + (p - cen) * 0.22 for p in loop]
    Z = [CORNICE_Z + 0.3, CEIL_MID_Z, CEIL_TOP]
    rings = [loop, mid, top]
    nlp = len(loop)
    for ri in range(2):
        A, B = rings[ri], rings[ri + 1]
        for i in range(nlp):
            j = (i + 1) % nlp
            q = [Vector((A[i].x, A[i].y, Z[ri])), Vector((A[j].x, A[j].y, Z[ri])), Vector((B[j].x, B[j].y, Z[ri + 1])), Vector((B[i].x, B[i].y, Z[ri + 1]))]
            f = _face(mb, q, "Ceiling_Panel", [(0, 0), (1, 0), (1, 1), (0, 1)])
            f.normal_update()
            if f.normal.z > 0:
                f.normal_flip()
            # ribs along the facet joints + a middle rib
            bar(mb, q[0] - Vector((0, 0, 0.2)), q[3] - Vector((0, 0, 0.2)), 0.34, "Oak_Dark")
            m0 = (q[0] + q[1]) / 2
            m1 = (q[3] + q[2]) / 2
            bar(mb, m0 - Vector((0, 0, 0.2)), m1 - Vector((0, 0, 0.2)), 0.26, "Oak_Dark")
            bar(mb, q[3] - Vector((0, 0, 0.2)), q[2] - Vector((0, 0, 0.2)), 0.3, "Oak")
    cap = [Vector((p.x, p.y, CEIL_TOP)) for p in top]
    f = mb.bm.faces.new([mb.bm.verts.new(p) for p in cap])
    f.material_index = mb.mi("Ceiling_Panel")
    f.normal_update()
    if f.normal.z > 0:
        f.normal_flip()
    # hammer-beam brackets + crossing tie beams (the "X" trusses)
    for p in loop:
        n = (cen - p).normalized()
        a = Vector((p.x, p.y, CORNICE_Z + 0.1))
        bar(mb, a, a + Vector((n.x, n.y, 0)) * 2.6, 0.3, "Oak_Dark")
        bar(mb, Vector((p.x, p.y, CORNICE_Z - 1.6)), a + Vector((n.x, n.y, 0)) * 2.0, 0.22, "Oak_Dark")
    zc = CORNICE_Z + 1.3
    bar(mb, (-HALF_W, -4.0, zc), (HALF_W, -4.0, zc), 0.34, "Oak_Dark")
    bar(mb, (-HALF_W, 3.0, zc), (HALF_W, 3.0, zc), 0.34, "Oak_Dark")
    bar(mb, (HALF_W, -4.0, zc + 0.4), (-4.5, -13.5, zc + 0.4), 0.3, "Oak_Dark")
    bar(mb, (-HALF_W, -4.0, zc + 0.4), (4.5, -13.5, zc + 0.4), 0.3, "Oak_Dark")
    mb.done()


# ════════════════════════════════════════════════════════════════
#  Stage, screen, chandelier, statues, booth
# ════════════════════════════════════════════════════════════════
def build_stage():
    mb = MB("Stage")
    hw, c = STAGE_W / 2, 1.3
    poly = [(-hw, BACK_Y), (-hw, c), (-hw + c, 0.0), (hw - c, 0.0), (hw, c), (hw, BACK_Y)]
    f = mb.bm.faces.new([mb.bm.verts.new((x, y, STAGE_Z)) for x, y in poly])
    f.material_index = mb.mi("Stage_Floor")
    for lp in f.loops:
        lp[mb.uv].uv = (lp.vert.co.x / 3.0, lp.vert.co.y / 3.0)
    f.normal_update()
    if f.normal.z < 0:
        f.normal_flip()
    # inlaid octagon border on the stage floor
    oc = [(math.cos(math.radians(22.5 + 45 * k)) * 4.2, 3.4 + math.sin(math.radians(22.5 + 45 * k)) * 2.8) for k in range(9)]
    for (x0, y0), (x1, y1) in zip(oc[:-1], oc[1:]):
        bar(mb, (x0, y0, STAGE_Z + 0.004), (x1, y1, STAGE_Z + 0.004), 0.05, "Oak_Dark")
    for (x0, y0), (x1, y1) in zip(poly[:-1], poly[1:]):
        if y0 >= BACK_Y - 0.01 and y1 >= BACK_Y - 0.01:
            continue
        a, b = Vector((x0, y0, 0)), Vector((x1, y1, 0))
        L = (b - a).length
        q = [a, b, b + Vector((0, 0, STAGE_Z)), a + Vector((0, 0, STAGE_Z))]
        f = _face(mb, q, "Oak_Gothic", [(0, 0), (L / 1.2, 0), (L / 1.2, 1), (0, 1)])
        f.normal_update()
        mid = (a + b) / 2
        if f.normal.to_2d().dot(mid.to_2d() - Vector((0.0, BACK_Y / 2))) < 0:
            f.normal_flip()
        bar(mb, (a.x, a.y, STAGE_Z + 0.02), (b.x, b.y, STAGE_Z + 0.02), 0.1, "Oak_Dark")
    # steps at the chamfered corners
    for s in (-1, 1):
        for k in range(4):
            h = STAGE_Z * (k + 1) / 4
            off = 0.32 * (4 - k)
            ccx = s * (hw - c / 2 + off * 0.707)
            ccy = c / 2 - off * 0.707
            box(mb, (ccx, ccy, h / 2), (1.8, 0.32, h), "Oak", rot=(0, 0, s * math.radians(45)))
    # lectern, covered piano, table + laptop (the panel copy has podiums instead)
    if PANEL:
        return _finish_stage_panel(mb)
    box(mb, (1.6, 1.9, STAGE_Z + 0.55), (0.7, 0.5, 1.1), "Oak_Gothic", uvs=0.6)
    box(mb, (1.6, 1.85, STAGE_Z + 1.16), (0.8, 0.62, 0.05), "Oak_Dark", rot=(math.radians(-15), 0, 0))
    box(mb, (-5.3, 2.8, STAGE_Z + 0.55), (1.6, 2.2, 0.75), "Piano_Cover")
    box(mb, (-5.3, 2.8, STAGE_Z + 0.97), (1.65, 2.25, 0.12), "Piano_Cover", rot=(0.05, 0, 0))
    box(mb, (4.6, 2.2, STAGE_Z + 0.74), (1.6, 0.8, 0.05), "Oak")
    for dx in (-0.7, 0.7):
        for dy in (-0.32, 0.32):
            box(mb, (4.6 + dx, 2.2 + dy, STAGE_Z + 0.36), (0.06, 0.06, 0.72), "Oak_Dark")
    box(mb, (4.6, 2.2, STAGE_Z + 0.78), (0.35, 0.25, 0.02), "Black_Metal")
    box(mb, (4.6, 2.32, STAGE_Z + 0.9), (0.35, 0.02, 0.24), "Black_Metal", rot=(math.radians(-15), 0, 0))
    return _webcam_stand(mb)


def _webcam_stand(mb):
    mx, my, mz = -3.4, 1.4, STAGE_Z + 1.7
    cyl(mb, (mx, my, STAGE_Z + 0.03), 0.32, 0.06, "Black_Metal", segs=16)
    cyl(mb, (mx, my, STAGE_Z + 0.82), 0.04, 1.55, "Black_Metal", segs=8)
    mb.done()
    mon = MB("Webcam_Monitor")
    box(mon, (0, 0.06, 0), (1.44, 0.08, 0.86), "Monitor_Black")
    o = mon.done()
    o.location = (mx, my, mz)
    return Vector((mx, my, mz))


def podium_yaw(x, y):
    """Podiums turn a little toward the middle of the audience."""
    return math.atan2(-(0.0 - x), (-8.0 - y)) + math.pi


def _finish_stage_panel(mb):
    """Panel copy: four oak podiums, each its own object (PODIUM_n) so the room can hide it."""
    for i, (x, y) in enumerate(PODIUMS):
        pm = MB("PODIUM_%d" % (i + 1))
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        P = lambda lx, ly, lz: tuple(Vector((x, y, 0)) + R @ Vector((lx, ly, lz)))
        box(pm, P(0, 0, STAGE_Z + 0.04), (0.8, 0.56, 0.08), "Oak_Dark", rot=(0, 0, yaw))
        box(pm, P(0, 0, STAGE_Z + 0.55), (0.66, 0.44, 0.95), "Oak_Gothic", rot=(0, 0, yaw), uvs=0.55)
        for dx in (-0.35, 0.35):
            box(pm, P(dx, -0.2, STAGE_Z + 0.55), (0.06, 0.06, 1.0), "Oak_Dark", rot=(0, 0, yaw))
        box(pm, P(0, 0.02, STAGE_Z + 1.07), (0.78, 0.56, 0.05), "Oak_Dark", rot=(math.radians(-14), 0, yaw))
        box(pm, P(0, -0.26, STAGE_Z + 1.02), (0.78, 0.04, 0.08), "Oak", rot=(0, 0, yaw))
        # brass reading lamp on the front edge of the desk
        cyl(pm, P(0.22, -0.16, STAGE_Z + 1.16), 0.05, 0.03, "Brass", segs=10)
        bar(pm, P(0.22, -0.16, STAGE_Z + 1.16), P(0.22, -0.02, STAGE_Z + 1.42), 0.012, "Brass")
        cyl(pm, P(0.22, 0.02, STAGE_Z + 1.42), 0.07, 0.07, "Brass", segs=12, r2=0.04)
        sphere(pm, P(0.22, 0.02, STAGE_Z + 1.39), 0.035, "Podium_Lamp", subdiv=1)
        pm.done()
    mb.done()
    return None     # no webcam monitor in the panel copy: the webcam uses the corner overlay


def podium_markers():
    """PRESENTER_n (feed plane: bottom centre, +Z of the marker faces the audience in Redot),
    PODIUM_LIGHT_n (the lamp: aims at the presenter's face)."""
    for i, (x, y) in enumerate(PODIUMS):
        yaw = podium_yaw(x, y)
        R = Matrix.Rotation(yaw, 3, 'Z')
        back = R @ Vector((0, PRESENTER_BACK, 0))
        base = Vector((x, y, 0)) + back + Vector((0, 0, STAGE_Z + PRESENTER_LIFT))
        pm = empty("PRESENTER_%d" % (i + 1), base)
        front = base + R @ Vector((0, -5.0, 0))
        aim(pm, front, forward='-Y')
        lamp = Vector((x, y, 0)) + R @ Vector((0.22, 0.02, STAGE_Z + 1.36))
        lm = empty("PODIUM_LIGHT_%d" % (i + 1), lamp)
        aim(lm, base + Vector((0, 0, PRESENTER_H * 0.55)))


def build_screen():
    mb = MB("Screen_Frame")
    x0, x1 = -SCREEN_W / 2, SCREEN_W / 2
    z0, z1 = STAGE_Z + SCREEN_LIFT, STAGE_Z + SCREEN_LIFT + SCREEN_H
    y = SCREEN_Y
    # the frame sits 1 cm proud of the picture and never overlaps it (no z-fighting on the edges)
    fy = y + 0.02
    for (c, s) in [((0, fy, z1 + 0.12), (SCREEN_W + 0.5, 0.06, 0.24)), ((0, fy, z0 - 0.03), (SCREEN_W + 0.5, 0.06, 0.06)),
                   ((x0 - 0.12, fy, (z0 + z1) / 2), (0.24, 0.06, SCREEN_H)), ((x1 + 0.12, fy, (z0 + z1) / 2), (0.24, 0.06, SCREEN_H))]:
        box(mb, c, s, "Screen_Frame")
    box(mb, (0, y + 0.06, z1 + 0.3), (SCREEN_W + 0.3, 0.3, 0.3), "Black_Metal")
    wall_quad(mb, "y", y + 0.07, x0, x1, z0, z1, "Screen_Black", facing=1)
    for sx in (x0 + 2.2, 0.0, x1 - 2.2):
        bar(mb, (sx, y + 0.06, z1 + 0.45), (sx, y + 0.06, CEIL_TOP), 0.03, "Black_Metal")
    if SCREEN_LIFT < 0.1:
        for sx in (x0 + 0.3, x1 - 0.3):     # floor feet
            box(mb, (sx, y + 0.3, STAGE_Z + 0.05), (0.2, 0.9, 0.1), "Black_Metal")
    mb.done()
    sb = MB("TVScreen")
    wall_quad(sb, "y", y, x0, x1, z0, z1, "Screen_Black", facing=-1)
    sb.done()


def build_chandelier():
    mb = MB("Chandelier")
    c = CHAND
    cyl(mb, (c.x, c.y, (c.z + CEIL_TOP) / 2), 0.05, CEIL_TOP - c.z, "Brass", segs=8)
    torus(mb, c, 2.3, 0.07, "Brass", segs=48, rsegs=6)
    torus(mb, c + Vector((0, 0, -0.18)), 2.22, 0.04, "Brass", segs=48, rsegs=5)
    for k in range(32):
        a = 2 * math.pi * k / 32
        sphere(mb, c + Vector((math.cos(a) * 2.3, math.sin(a) * 2.3, 0.12)), 0.075, "Bulb", subdiv=1)
    hub = c + Vector((0, 0, -0.55))
    for k in range(12):
        a = 2 * math.pi * k / 12
        d = Vector((math.cos(a), math.sin(a), 0))
        midp = hub + d * 1.2 + Vector((0, 0, 0.1))
        bar(mb, hub, midp, 0.035, "Brass")
        bar(mb, midp, c + d * 2.25, 0.035, "Brass")
        torus(mb, hub + d * 0.85 + Vector((0, 0, 0.16)), 0.16, 0.015, "Brass", axis="x" if abs(d.x) < 0.7 else "y", segs=12, rsegs=4)
    torus(mb, hub + Vector((0, 0, -0.1)), 1.0, 0.05, "Brass", segs=32, rsegs=5)
    for k in range(14):
        a = 2 * math.pi * k / 14
        sphere(mb, hub + Vector((math.cos(a), math.sin(a), 0.0)), 0.06, "Bulb", subdiv=1)
    sphere(mb, hub + Vector((0, 0, -0.2)), 0.28, "Brass", subdiv=2, scale=(1, 1, 0.8))
    cyl(mb, hub + Vector((0, 0, -0.72)), 0.16, 0.65, "Brass", segs=12, r2=0.02)
    up = c + Vector((0, 0, 1.5))
    torus(mb, up, 0.8, 0.04, "Brass", segs=32, rsegs=5)
    for k in range(12):
        a = 2 * math.pi * k / 12
        sphere(mb, up + Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, 0.08)), 0.06, "Bulb", subdiv=1)
        bar(mb, up + Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, 0)), c + Vector((math.cos(a) * 2.3, math.sin(a) * 2.3, 0)), 0.02, "Brass")
    # a second, smaller fixture hanging higher over the stage end (as in the reference)
    hi = Vector((0.0, 1.0, 15.5))
    cyl(mb, (hi.x, hi.y, (hi.z + CEIL_TOP) / 2), 0.04, CEIL_TOP - hi.z, "Brass", segs=8)
    torus(mb, hi, 1.5, 0.05, "Brass", segs=40, rsegs=5)
    for k in range(20):
        a = 2 * math.pi * k / 20
        sphere(mb, hi + Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, 0.1)), 0.06, "Bulb", subdiv=1)
        if k % 4 == 0:
            bar(mb, hi + Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, 0)), hi + Vector((0, 0, 1.1)), 0.02, "Brass")
    # small pendant lamps under the balcony (like the reference's hanging lanterns)
    # well back under the balcony, clear of the posts: one over each half-bay between the
    # wall pilasters on the diagonals and the back wall
    front = offset_line(WALL, 1.3)
    spots = []
    for a, b in zip(front[1:-2], front[2:-1]):
        spots += [a + (b - a) * 0.25, a + (b - a) * 0.75]
    for p in spots:
        cyl(mb, (p.x, p.y, BAL_SOFFIT - 0.4), 0.01, 0.8, "Brass", segs=6)
        sphere(mb, (p.x, p.y, BAL_SOFFIT - 0.9), 0.16, "Bulb", subdiv=2)
    mb.done()


def build_statues():
    mb = MB("Statues")
    for s in (-1, 1):
        x, y = s * (STAGE_W / 2 + 1.6), 1.5
        box(mb, (x, y, 0.8), (0.9, 0.9, 1.6), "Marble")
        box(mb, (x, y, 1.65), (1.05, 1.05, 0.1), "Marble")
        cyl(mb, (x, y, 2.45), 0.36, 1.5, "Marble", segs=16, r2=0.23)
        cyl(mb, (x, y, 3.35), 0.25, 0.35, "Marble", segs=16, r2=0.19)
        sphere(mb, (x, y - 0.02, 3.7), 0.15, "Marble", subdiv=2, scale=(1, 1, 1.15))
        bar(mb, (x + s * 0.22, y, 3.3), (x + s * 0.3, y - 0.3, 2.7), 0.12, "Marble")
        box(mb, (x - s * 0.1, y - 0.2, 2.9), (0.3, 0.25, 0.9), "Marble", rot=(0.1, 0, 0))
    mb.done()


def build_booth_and_speakers():
    mb = MB("Booth_Speakers")
    # projection booth at the back of the upper gallery
    y = WALL[2][1] + 0.4
    box(mb, (0, y, GAL_Z0 + 1.9), (2.4, 0.8, 1.3), "Oak_Dark")
    wall_quad(mb, "y", y + 0.41, -0.6, 0.6, GAL_Z0 + 1.7, GAL_Z0 + 2.2, "Booth_Glass", facing=1)
    for s in (-1, 1):
        for (x, yy, z) in ((s * 9.5, 5.5, 13.5), (s * 5.5, 5.0, 14.5)):
            box(mb, (x, yy, z), (0.7, 0.6, 1.1), "Black_Metal", rot=(0.25, 0, s * 0.35))
    mb.done()
    return Vector((0.0, y + 0.5, GAL_Z0 + 1.95))


def seat_eye(kind, row, facet, t, lift=1.22):
    if kind == "pit":
        y = -1.35 - row * 0.95
        return Vector((facet, y - 0.05, lift))
    d0, step, zf = {"orch": (ORCH_D0 + PEW_OFF + 0.1, ORCH_STEP, orch_z), "bal": (BAL_D0, BAL_STEP, bal_z), "gal": (GAL_D0, GAL_STEP, gal_z)}[kind]
    line = offset_line(WALL, d0 + row * step - 0.1)
    a, b = line[facet], line[facet + 1]
    p = a + (b - a) * t
    n = inward_normal(a, b)
    p = p + n * 0.02
    return Vector((p.x, p.y, zf(row) + lift))


def rail_eye(facet, frac, back=0.45, lift=1.7):
    """Standing at the gallery rail, centred in an arcade bay (clear of the posts)."""
    ps = [(a, b, n) for (a, b, n, corner, fi) in pieces(offset_line(WALL, GAL_FRONT_D), 2.2) if fi == facet]
    a, b, n = ps[min(len(ps) - 1, int(frac * len(ps)))]
    m = (a + b) / 2 - n * back
    return Vector((m.x, m.y, GAL_Z0 + lift))


def build_markers(mon_pos, beam_pos):
    screen_c = Vector((0, SCREEN_Y, STAGE_Z + SCREEN_LIFT + SCREEN_H / 2))
    empty("BEAM_Projector", beam_pos)
    lh = empty("LIGHTS_House", (0, 0, 0))
    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        empty("LAMP_Chandelier_%d" % (k + 1), CHAND + Vector((math.cos(a) * 1.6, math.sin(a) * 1.6, -0.4)), parent=lh)
    empty("LAMP_Chandelier_High", Vector((0, 1.0, 14.9)), parent=lh)
    gline = offset_line(WALL, GAL_FRONT_D + 0.8)
    for k, (a, b) in enumerate(zip(gline[:-1], gline[1:])):
        p = (a + b) / 2
        empty("LAMP_Gallery_%d" % (k + 1), (p.x, p.y, GAL_Z0 + 3.2), parent=lh)
    for s, n in ((-1, "L"), (1, "R")):
        empty("LAMP_Stage_%s" % n, (s * 4.5, 1.0, 8.2), parent=lh)
    cams = [("CAM_01_Pit_Center", seat_eye("pit", 3, -1.6, 0), screen_c),
            ("CAM_02_Front_Row", seat_eye("pit", 0, 1.4, 0), screen_c),
            ("CAM_03_Center_Rows", seat_eye("orch", 3, 2, 0.35), screen_c),
            ("CAM_04_Rear_Diagonal", seat_eye("orch", 2, 1, 0.55), screen_c),
            ("CAM_05_Side_Right", seat_eye("orch", 0, 0, 0.6), screen_c),
            ("CAM_06_Balcony_Center", seat_eye("bal", 2, 2, 0.62), screen_c),
            ("CAM_07_Balcony_Diagonal", seat_eye("bal", 3, 3, 0.5), screen_c),
            ("CAM_08_Balcony_Side", seat_eye("bal", 2, 4, 0.25), screen_c),
            ("CAM_09_Gallery", rail_eye(2, 0.5), screen_c),
            ("CAM_10_Reaction", Vector((-2.2, -1.0, 2.0)), mon_pos if mon_pos else screen_c),
            ("CAM_11_Lectern", Vector((1.6, 2.5, STAGE_Z + 1.65)), Vector((0.0, -14.0, 4.5))),
            ("CAM_12_Chandelier", rail_eye(3, 0.5), Vector((0.0, 2.0, 3.5)))]
    if PANEL:
        stage_mid = Vector((0.0, 3.0, STAGE_Z + 2.4))
        cams += [("CAM_13_Panel_Wide", Vector((0.0, -8.4, 2.9)), stage_mid),
                 ("CAM_14_Panel_Left", Vector((-1.6, -2.2, 2.1)), Vector((-6.0, 2.9, STAGE_Z + 1.5))),
                 ("CAM_15_Panel_Right", Vector((1.6, -2.2, 2.1)), Vector((6.0, 2.9, STAGE_Z + 1.5)))]
        podium_markers()
        # chat screen (drawn by the app when switched on): top centre, just under the screen frame
        top = Vector((0.0, SCREEN_Y - 0.03, STAGE_Z + SCREEN_LIFT - 0.14))
        cs = empty("CHAT_Screen", top)
        aim(cs, top + Vector((0.0, -10.0, 0.0)), forward='-Y')
        # reply screen (Stream Core's answers to chat commands): top centre, above the screen's header
        rtop = Vector((0.0, SCREEN_Y - 0.03, STAGE_Z + SCREEN_LIFT + SCREEN_H + 2.1))
        rs = empty("REPLY_Screen", rtop)
        aim(rs, rtop + Vector((0.0, -10.0, 0.0)), forward='-Y')
    for name, p, t in cams:
        o = empty(name, p)
        aim(o, t)
    if mon_pos is None:
        return
    wf = empty("WEBCAM_Frame", mon_pos + (Vector((-2.2, -1.0, 2.0)) - mon_pos).normalized() * 0.03)
    aim(wf, Vector((-2.2, -1.0, 2.0)), forward='-Y')
    mon = bpy.data.objects.get("Webcam_Monitor")
    if mon:
        mon.rotation_euler = wf.rotation_euler


def build_all():
    setup_materials()
    for cname in ("Hall", "Hall_Markers"):
        c = bpy.data.collections.get(cname)
        if c:
            for o in list(c.objects):
                bpy.data.objects.remove(o, do_unlink=True)
    build_pit_and_orchestra()
    build_balcony_and_gallery()
    build_walls()
    build_windows()
    build_ceiling()
    mon = build_stage()
    build_screen()
    build_chandelier()
    build_statues()
    beam = build_booth_and_speakers()
    build_markers(mon, beam)
    export_crowd_seats()
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    return {o.name: len(o.data.polygons) for o in col("Hall").objects if o.type == "MESH"}


def export_crowd_seats(path=None):
    """crowd_seats.json next to the .glb (build_all writes it): one entry per crowd seat, in Redot axes
    (p = seat surface centre, n = the way the seat faces, s = orch/bal/gal, r = row, 0 = front)."""
    import json
    path = path or os.path.join(os.path.dirname(GLB), "crowd_seats.json")
    with open(path, "w") as f:
        json.dump({"pitch": CROWD_PITCH, "seats": CROWD_SEATS}, f, separators=(",", ":"))
    return len(CROWD_SEATS)


def export_glb(path=None):
    path = path or GLB
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for cname in ("Hall", "Hall_Markers"):
        for o in bpy.data.collections[cname].all_objects:
            o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials='EXPORT', export_image_format='AUTO')
