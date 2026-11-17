extends RefCounted
## Builds the Log Cabin out of plain coloured shapes, in code: the log walls, the glass gable
## wall with the stone chimney in the middle, the roof and its beams, the loft and its stairs,
## the furniture, the deck, the back stoop, and every marker the app looks for (rooms/room.gd
## lists them: TVScreen, CAM_*, PRESENTER_n, PODIUM_n, AUDIENCE_*, TARGET_*, LIGHTS_House with
## LAMP_* inside).
##
## FIRST PASS (2026-11-17): this is the layout only, from Sen's plan "Log Cabin room plan"
## (layout mockup v2). Everything is flat colour, the shapes are simple, and the outside is a
## placeholder clearing (_build_clearing). Shaders, better models, CC0 textures and the real
## outdoor scenes come later. The cabin itself is meant to be shared: the later scene rooms
## (Appalachian forest, lakeside, ocean, frozen north) will call build_cabin() and add their own
## outside instead of the clearing.
##
## The den (added the same day, from Sen's den picture): a small, low-beamed room off the great
## room's left wall, through a doorway, with its own stone fireplace, a leather sofa and an
## armchair. "Gather in" (cabin_view, the room script's reload key) picks where the guests sit:
## "great_room" puts the presenters on the four armchairs by the big fireplace and the big screen
## on the tall chimney; "den" sits them on the den's sofa and armchair, makes the den's screen
## the main one (TVScreen), puts the den's cameras first, and the other screen shows the same
## picture (SCREEN_Mirror_). Everything else is built the same either way.
##
## Called once by rooms/log_cabin/log_cabin_room.gd (_ready, before anything reads the room),
## which keeps the Dictionary build() returns: the materials and nodes it animates afterwards.
## There is no Blender model: to move or resize something, change the numbers in the "Layout"
## block below.
##
## Axes (metres): the floor inside is y = 0. The glass gable wall that faces the view is at
## z = 0, the back wall (entrance) at z = BACK_Z; -Z is the view (deck, then the outside), +Z is
## the back. x = 0 is the middle of the cabin (the chimney and the ridge), +X is the stairs' side.
## Markers that "face" something follow the app's rule: +Z points at what they face, except
## cameras, which look along -Z.

# ── Layout ───────────────────────────────────────────────────
## Half the cabin's width (outside of the logs) and how deep it is, front glass to back wall.
const HALF_W: float = 6.5
const BACK_Z: float = 9.0
## Height of the log walls (the eaves) and of the ridge, inside.
const EAVE_Y: float = 3.6
const RIDGE_Y: float = 8.6
## Logs: radius, and the metres between one log's middle and the next one's. The ends stick out
## past the corners by LOG_OVERHANG (the notched-corner look).
const LOG_R: float = 0.17
const LOG_STEP: float = 0.3
const LOG_OVERHANG: float = 0.32
## The roof reaches this far past the side walls (sideways) and past the front and back walls.
const ROOF_SIDE: float = 0.7
const ROOF_FRONT: float = 1.2
const ROOF_BACK: float = 0.8
## The ground outside: this far below the floor (the cabin stands on a stone footing).
const GROUND_Y: float = -0.9
## The deck in front of the glass: half its width, how far out it reaches (z), its top.
const DECK_HALF: float = 8.1
const DECK_DEPTH: float = 3.9
const DECK_Y: float = -0.1
## The deck's steps down to the ground (x from, x to) in its front railing.
const DECK_STEPS: Vector2 = Vector2(6.1, 7.5)
## The chimney: the wide lower part (half width, top), the narrower stack above it (half width),
## its top, and how far it reaches out the front (z) and in (z, its face in the room).
const CHIM_HALF: float = 2.1
const CHIM_WIDE_TOP: float = 4.6
const CHIM_STACK_HALF: float = 1.0
const CHIM_TOP: float = 10.0
const CHIM_OUT_Z: float = -0.9
const CHIM_IN_Z: float = 0.8
## The firebox opening in the chimney's face: half width, bottom, top, depth into the stone.
const FIREBOX_HALF: float = 0.7
const FIREBOX_Y: Vector2 = Vector2(0.4, 1.3)
const FIREBOX_DEPTH: float = 0.5
## The raised hearth in front of the chimney: half width, how far it sticks out, height.
const HEARTH_HALF: float = 2.6
const HEARTH_OUT: float = 0.5
const HEARTH_H: float = 0.4
## The mantel shelf: height of its top.
const MANTEL_Y: float = 1.78
## The big screen on the chimney above the mantel: width x height, bottom edge height.
const SCREEN_SIZE: Vector2 = Vector2(3.8, 2.14)
const SCREEN_BOTTOM: float = 1.95
## The loft across the back: its floor's top, and where its front edge (with the railing) is.
const LOFT_Y: float = 2.8
const LOFT_FRONT_Z: float = 5.4
## The stairs up to the loft along the right wall: x from, x to; z where they start; steps.
const STAIR_X: Vector2 = Vector2(5.25, 6.45)
const STAIR_START_Z: float = 1.7
const STAIR_STEPS: int = 14
## Windows in the side and back log walls: [wall ("left" x = -HALF_W, "right" x = +HALF_W,
## "back" z = BACK_Z), from, to (z for the side walls, x for the back wall), sill, top].
const WINDOWS: Array = [
	["left", 5.8, 8.0, 0.9, 2.2], ["left", 2.2, 4.4, 0.9, 2.3], ["right", 6.2, 8.2, 0.9, 2.2],
	["back", -5.6, -4.3, 1.2, 2.2], ["back", 3.4, 4.6, 1.2, 2.2],
]
## The doorway from the great room into the den, in the left wall: z from, z to, top.
const DEN_DOOR: Vector3 = Vector3(4.6, 5.6, 2.15)
## The back door (the entrance from the stoop): x from, x to, top.
const BACK_DOOR: Vector3 = Vector3(-0.5, 0.5, 2.1)
## The glass doors in the two front corners: x from, x to (left one; the right one is mirrored).
const GLASS_DOOR: Vector2 = Vector2(-6.2, -5.0)
## The front window wall's mullions (upright timbers) at these x (and mirrored).
const MULLIONS: Array[float] = [-6.5, -5.0, -3.55, -2.1]
## The collar ties across the roof (z) and their height.
const COLLARS_Z: Array[float] = [2.4, 4.4, 7.0]
const COLLAR_Y: float = 5.6
## The den: its far wall (x), the walls either side (z from, z to), the height of its log walls,
## its flat beamed ceiling and its roof's ridge (running along x, over DEN_MID_Z).
const DEN_FAR_X: float = -12.5
const DEN_Z: Vector2 = Vector2(2.0, 8.6)
const DEN_EAVE_Y: float = 3.3
const DEN_CEIL_Y: float = 3.15
const DEN_RIDGE_Y: float = 4.9
const DEN_MID_Z: float = 5.3
## The den's windows: [the z of the wall they are in, x from, x to, sill, top].
const DEN_WINDOWS: Array = [[8.6, -10.9, -8.7, 0.9, 2.4], [2.0, -11.3, -9.4, 0.9, 2.4]]
## The den's chimney on its far wall: how far it sticks into the room (x of its face), its z
## from / to, and the firebox in its face (z from, z to, bottom, top).
const DEN_CHIM_FACE_X: float = -11.85
const DEN_CHIM_Z: Vector2 = Vector2(4.15, 6.45)
const DEN_FIREBOX: Vector4 = Vector4(4.8, 5.8, 0.35, 1.2)
const DEN_MANTEL_Y: float = 1.62
## The den's screen above its mantel: width x height, bottom edge height.
const DEN_SCREEN_SIZE: Vector2 = Vector2(2.0, 1.125)
const DEN_SCREEN_BOTTOM: float = 1.8
## The den's sofa (three seats, 1.1 m apart) and armchair: where each stands (x, z) and the point
## (x, z) it is turned towards, so both open towards the den's main camera like in the picture.
const DEN_SOFA: Vector4 = Vector4(-9.4, 7.2, -8.0, 3.7)
const DEN_ARMCHAIR: Vector4 = Vector4(-10.0, 3.1, -8.0, 6.0)
const DEN_SEAT_Y: float = 0.45
## In "Gather in: Den" these cameras come first, then the great room's (CAMERAS, renumbered).
const DEN_CAMERAS: Array = [
	["01_Den_Fireside", Vector3(-6.95, 1.55, 5.15), Vector3(-12.0, 1.45, 5.3)],
	["02_Reaction_Den_Sofa", Vector3(-7.4, 1.35, 3.6), Vector3(-9.4, 0.95, 7.0)],
	["03_Den_Armchair", Vector3(-7.2, 1.4, 6.6), Vector3(-10.0, 0.95, 3.1)],
	["04_Den_Hearth", Vector3(-11.2, 1.75, 5.3), Vector3(-7.0, 1.1, 5.3)],
]

## Chat seats: [name, x, seat height, z, what it faces ("screen" or a Vector3 point)].
## 18 on the main floor, 5 at the loft railing, 7 on the deck = 30 (plan v2). Seats along a row
## are 1 m apart or more, so all stay at the default Seat spacing (audience_seat_gap 1.0).
const SEATS: Array = [
	# sheepskins and cushions on the hearth rug
	["Hearth_1", -1.5, 0.12, 1.85, "screen"], ["Hearth_2", -0.5, 0.12, 1.85, "screen"],
	["Hearth_3", 0.5, 0.12, 1.85, "screen"], ["Hearth_4", 1.5, 0.12, 1.85, "screen"],
	# the two leather sofas
	["SofaL_1", -3.1, 0.45, 3.85, "screen"], ["SofaL_2", -2.1, 0.45, 3.85, "screen"], ["SofaL_3", -1.1, 0.45, 3.85, "screen"],
	["SofaR_1", 1.1, 0.45, 3.85, "screen"], ["SofaR_2", 2.1, 0.45, 3.85, "screen"], ["SofaR_3", 3.1, 0.45, 3.85, "screen"],
	# four armchairs
	["Arm_1", -4.5, 0.45, 1.9, "screen"], ["Arm_2", -5.3, 0.45, 3.7, "screen"],
	["Arm_3", 4.4, 0.45, 1.9, "screen"], ["Arm_4", 4.3, 0.45, 4.75, "screen"],
	# the dining bench, its back to the table, facing the view
	["Dining_1", -4.8, 0.45, 6.2, "screen"], ["Dining_2", -3.8, 0.45, 6.2, "screen"],
	["Dining_3", -2.8, 0.45, 6.2, "screen"], ["Dining_4", -1.8, 0.45, 6.2, "screen"],
	# the bench at the loft railing
	["Loft_1", -4.2, 3.22, 5.75, "screen"], ["Loft_2", -2.8, 3.22, 5.75, "screen"], ["Loft_3", -1.4, 3.22, 5.75, "screen"],
	["Loft_4", 1.4, 3.22, 5.75, "screen"], ["Loft_5", 2.8, 3.22, 5.75, "screen"],
	# the deck: Adirondack chairs facing the view, and three round the fire table
	["Deck_1", -6.0, 0.25, -2.9, Vector3(-6.0, 0.0, -30.0)], ["Deck_2", -4.2, 0.25, -2.9, Vector3(-4.2, 0.0, -30.0)],
	["Deck_3", 4.2, 0.25, -2.9, Vector3(4.2, 0.0, -30.0)], ["Deck_4", 6.0, 0.25, -2.9, Vector3(6.0, 0.0, -30.0)],
	["Deck_5", -1.2, 0.35, -2.3, Vector3(0.0, 0.0, -2.95)], ["Deck_6", 1.2, 0.35, -2.3, Vector3(0.0, 0.0, -2.95)],
	["Deck_7", 0.0, 0.35, -3.55, Vector3(0.0, 0.0, -2.95)],
]
## The podiums are leather armchairs with the presenter's picture standing on the seat:
## [x, z]; they face the audience (+Z). P1 and P2 by the hearth, P3 and P4 by the corner doors.
const PODIUMS: Array[Vector2] = [Vector2(-3.2, 0.95), Vector2(3.2, 0.95), Vector2(-5.6, 0.9), Vector2(5.6, 0.9)]
## Height of a podium chair's seat (where the presenter's picture stands).
const PODIUM_SEAT_Y: float = 0.45
## Camera views: [name (after "CAM_"; the leading number sets the order), where it stands, what
## it looks at]. The one with "Reaction" in its name is used for react pauses.
const CAMERAS: Array = [
	["01_Loft", Vector3(0.0, 4.7, 7.6), Vector3(0.0, 2.4, 0.8)],
	["02_Reaction_Hearth", Vector3(0.0, 1.6, 1.25), Vector3(0.0, 1.5, 8.0)],
	["03_Sofa", Vector3(-3.4, 1.3, 5.2), Vector3(0.6, 2.2, 0.8)],
	["04_Stair_Corner", Vector3(4.9, 2.5, 5.0), Vector3(-1.2, 1.7, 1.0)],
	["05_Deck_Looking_In", Vector3(-5.2, 1.6, -3.3), Vector3(-2.6, 1.8, 4.5)],
	["06_Deck_Looking_Out", Vector3(3.6, 1.7, -1.0), Vector3(1.0, 1.0, -30.0)],
	["07_Outside_Gable", Vector3(0.0, 2.6, -17.0), Vector3(0.0, 3.6, 3.0)],
	["08_Front_Door", Vector3(5.5, 1.6, 16.5), Vector3(0.0, 1.4, 9.0)],
	["09_Dining_Table", Vector3(-6.0, 1.7, 7.9), Vector3(0.4, 1.7, 1.0)],
	["10_Screen_Close", Vector3(0.0, 2.2, 4.9), Vector3(0.0, 2.95, 0.8)],
]

# ── Colours (flat for now; textures come later) ──────────────
const C_LOG := Color(0.55, 0.36, 0.2)
const C_LOG_END := Color(0.74, 0.56, 0.36)
const C_PINE := Color(0.8, 0.6, 0.38)
const C_FLOOR := Color(0.58, 0.38, 0.21)
const C_TIMBER := Color(0.45, 0.29, 0.16)
const C_STONE := Color(0.5, 0.48, 0.44)
const C_STONE_DARK := Color(0.33, 0.31, 0.29)
const C_SOOT := Color(0.06, 0.05, 0.05)
const C_ROOF := Color(0.24, 0.22, 0.21)
const C_LEATHER := Color(0.36, 0.2, 0.11)
const C_FABRIC := Color(0.72, 0.64, 0.52)
const C_WOOL := Color(0.86, 0.83, 0.76)
const C_RUG := Color(0.5, 0.17, 0.11)
const C_IRON := Color(0.09, 0.09, 0.09)
const C_DECK := Color(0.5, 0.37, 0.24)
const C_FRAME := Color(0.4, 0.26, 0.14)
const C_GRASS := Color(0.29, 0.4, 0.21)


# ── A mesh being put together ────────────────────────────────
## Collects flat-shaded, coloured triangles and turns them into one mesh (the same idea as the
## campfire room's builder). Every shape below adds to one of these, so a whole group of
## objects is a single mesh with a single material: cheap to draw.
class Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## One triangle. The normal comes from the corner order; the material draws both sides,
	## so the order never makes a face vanish.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		tri_round(a, b, c, n, n, n, col)

	## One triangle with a normal per corner (round things, such as a log's side, shade smoothly).
	func tri_round(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
		# the side drawn as the front is the one (c - a) x (b - a) points out of: turn the
		# triangle round if that isn't the side the given normals are on
		if (c - a).cross(b - a).dot(na + nb + nc) < 0.0:
			var keep := b
			b = c
			c = keep
			var keep_n := nb
			nb = nc
			nc = keep_n
		verts.append_array([a, b, c])
		normals.append_array([na, nb, nc])
		colors.append_array([col, col, col])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, c, b, col)
		tri(a, d, c, col)

	## A box: xf places its centre and turns it; size is its full width, height and depth.
	func box(xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		var p: Array[Vector3] = []
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					p.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
		# corners: index = 4 * (x side) + 2 * (y side) + (z side)
		quad(p[0], p[1], p[3], p[2], col)
		quad(p[4], p[6], p[7], p[5], col)
		quad(p[0], p[4], p[5], p[1], col)
		quad(p[2], p[3], p[7], p[6], col)
		quad(p[0], p[2], p[6], p[4], col)
		quad(p[1], p[5], p[7], p[3], col)

	## An upright box between two corners (min and max), no turning: the quick way to place most
	## of the furniture.
	func block(lo: Vector3, hi: Vector3, col: Color) -> void:
		box(Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), (hi - lo).abs(), col)

	## A cylinder or cone standing on xf's origin along its Y axis: r0 at the bottom, r1 at the
	## top, h tall. cap = the colour of the flat ends (a log's cut end).
	func cyl(xf: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var end := col if cap.a == 0.0 else cap
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var b0 := xf * Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
			var b1 := xf * Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
			var t0 := xf * Vector3(cos(a0) * r1, h, sin(a0) * r1)
			var t1 := xf * Vector3(cos(a1) * r1, h, sin(a1) * r1)
			if segs > 5:
				var tilt := (r0 - r1) / maxf(h, 0.001)
				var n0 := (xf.basis * Vector3(cos(a0), tilt, sin(a0))).normalized()
				var n1 := (xf.basis * Vector3(cos(a1), tilt, sin(a1))).normalized()
				tri_round(b0, t1, t0, n0, n1, n0, col)
				tri_round(b0, b1, t1, n0, n1, n1, col)
			else:
				quad(b0, t0, t1, b1, col)
			if r0 > 0.0:
				tri(xf * Vector3.ZERO, b0, b1, end)
			if r1 > 0.0:
				tri(xf * Vector3(0.0, h, 0.0), t1, t0, end)

	## A cylinder from one point to another (a log, a pole, a rail).
	func rod(from: Vector3, to: Vector3, radius: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var axis := to - from
		if axis.length() < 0.001:
			return
		var up := axis.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		cyl(Transform3D(Basis(side, up, side.cross(up)), from), radius, radius, axis.length(), segs, col, cap)

	## A board lying along a line in the x-y plane (from p0 to p1), reaching from z0 to z1, with
	## its bottom face on that line and `thick` metres of it above (for the roof and ceiling).
	func slab(p0: Vector2, p1: Vector2, z0: float, z1: float, thick: float, col: Color) -> void:
		var d := (p1 - p0).normalized()
		var n := Vector2(-d.y, d.x)
		if n.y < 0.0:
			n = -n
		var mid := (p0 + p1) * 0.5 + n * thick * 0.5
		var basis := Basis(Vector3(d.x, d.y, 0.0), Vector3(n.x, n.y, 0.0), Vector3(0.0, 0.0, 1.0))
		box(Transform3D(basis, Vector3(mid.x, mid.y, (z0 + z1) * 0.5)), Vector3(p0.distance_to(p1), thick, absf(z1 - z0)), col)

	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		if not verts.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## The height of the ceiling (the underside of the roof) at x: EAVE_Y at the side walls, rising
## in a straight line to RIDGE_Y over the middle.
static func roof_y(x: float) -> float:
	return EAVE_Y + (RIDGE_Y - EAVE_Y) * (1.0 - absf(x) / HALF_W)


## The plain material every flat-coloured part uses: the colour comes from the mesh's corners.
static func _flat_material(rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, mat: Material, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A marker node at `at` whose +Z axis points (level) at `toward`.
static func _marker_facing(parent: Node3D, node_name: String, at: Vector3, toward: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	parent.add_child(m)
	var dir := toward - at
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.BACK
	m.transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), at)
	return m


# ── The whole room ───────────────────────────────────────────
## Builds the cabin and the placeholder clearing under `room`. Returns what the room script
## goes on using:
##   screen (MeshInstance3D "TVScreen"): the main screen for this view (see the den note above),
##   fires (Array[Marker3D] "FIRE_Hearth", "FIRE_Den"): bottom centre of each fire's flames,
##   ember_mat (StandardMaterial3D): the glowing coals under both fires,
##   glow_mat (StandardMaterial3D): lampshades, the chandelier's candles and the lantern, which
##     glow with the house lights.
static func build(room: Node3D, view: String = "great_room") -> Dictionary:
	var out := build_cabin(room, view)
	_build_clearing(room.get_node("Set") as Node3D)
	return out


## Just the cabin (with the den), its deck and stoop, its furniture and its markers (no outside).
## The scene rooms planned for later call this and add their own scenery. view = "great_room" or
## "den" (cabin_view, "Gather in"): where the presenters sit and which screen is the main one.
static func build_cabin(room: Node3D, view: String = "great_room") -> Dictionary:
	var out: Dictionary = {}
	var fires: Array[Marker3D] = []
	out["fires"] = fires
	var set_root := Node3D.new()
	set_root.name = "Set"
	room.add_child(set_root)
	var markers := Node3D.new()
	markers.name = "Markers"
	room.add_child(markers)
	var flat := _flat_material()
	out["flat_mat"] = flat

	var logs := Buf.new()             # the log walls
	_build_walls(logs)
	_add_mesh(set_root, "LogWalls", logs.to_mesh(), flat)
	var shell := Buf.new()            # floor, footing, roof, beams, gable boards, frames, loft, stairs
	_build_shell(shell)
	_build_loft(shell)
	_add_mesh(set_root, "Shell", shell.to_mesh(), flat)
	var stone := Buf.new()            # the chimney and the hearth
	_build_chimney(stone, markers, out)
	_add_mesh(set_root, "Chimney", stone.to_mesh(), flat)
	var stuff := Buf.new()            # furniture and things
	_build_great_room(stuff)
	_build_back_rooms(stuff)
	_build_outside_bits(stuff)
	_add_mesh(set_root, "Furniture", stuff.to_mesh(), flat)
	var den := Buf.new()              # the den: walls, ceiling, roof, chimney, sofa, armchair
	_build_den(den, markers, out)
	_add_mesh(set_root, "Den", den.to_mesh(), flat)
	_build_glass(set_root)
	_build_screens(set_root, out, view)
	if view == "den":
		_den_presenters(markers)
	else:
		_build_podiums(set_root, markers, flat)
	_build_lamps(set_root, room, out)
	_build_markers(markers, view)
	return out


# ── Walls ────────────────────────────────────────────────────
## The three log walls (left, right, back). Each log row runs the wall's length, broken where a
## window or door is; the end logs stick out past the corners.
static func _build_walls(b: Buf) -> void:
	var rows := int(floor((EAVE_Y - LOG_R) / LOG_STEP)) + 1
	for r in rows:
		var y := LOG_R + float(r) * LOG_STEP
		# the two side walls run from the glass wall (z = 0) to the back wall
		for side: String in ["left", "right"]:
			var x := -HALF_W if side == "left" else HALF_W
			for span in _spans(side, -LOG_OVERHANG, BACK_Z + LOG_OVERHANG, y):
				b.rod(Vector3(x, y, span.x), Vector3(x, y, span.y), LOG_R, 10, C_LOG.darkened(0.06 * float(r % 3)), C_LOG_END)
		# the back wall runs across
		for span in _spans("back", -HALF_W - LOG_OVERHANG, HALF_W + LOG_OVERHANG, y + LOG_STEP * 0.5):
			b.rod(Vector3(span.x, y + LOG_STEP * 0.5, BACK_Z), Vector3(span.y, y + LOG_STEP * 0.5, BACK_Z), LOG_R, 10, C_LOG.darkened(0.06 * float((r + 1) % 3)), C_LOG_END)
	# the back gable above the logs: upright boards up to the ridge
	var top := EAVE_Y + LOG_STEP * 0.5
	b.tri(Vector3(-HALF_W, top, BACK_Z), Vector3(HALF_W, top, BACK_Z), Vector3(0.0, RIDGE_Y + 0.1, BACK_Z), C_PINE.darkened(0.2))
	# window frames and the back door's frame and door
	for w: Array in WINDOWS:
		_window_frame(b, String(w[0]), float(w[1]), float(w[2]), float(w[3]), float(w[4]))
	_window_frame(b, "left", DEN_DOOR.x, DEN_DOOR.y, 0.0, DEN_DOOR.z)
	b.block(Vector3(BACK_DOOR.x, 0.0, BACK_Z - 0.06), Vector3(BACK_DOOR.y, BACK_DOOR.z, BACK_Z + 0.06), C_TIMBER.darkened(0.2))
	b.block(Vector3(BACK_DOOR.x - 0.1, 0.0, BACK_Z - 0.2), Vector3(BACK_DOOR.x, BACK_DOOR.z + 0.1, BACK_Z + 0.2), C_FRAME)
	b.block(Vector3(BACK_DOOR.y, 0.0, BACK_Z - 0.2), Vector3(BACK_DOOR.y + 0.1, BACK_DOOR.z + 0.1, BACK_Z + 0.2), C_FRAME)
	b.block(Vector3(BACK_DOOR.x - 0.1, BACK_DOOR.z, BACK_Z - 0.2), Vector3(BACK_DOOR.y + 0.1, BACK_DOOR.z + 0.12, BACK_Z + 0.2), C_FRAME)


## The pieces of one log row along a wall at height y: [from, to] spans between the wall's ends,
## skipping each window or door the row passes through.
static func _spans(wall: String, from: float, to: float, y: float) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for w: Array in WINDOWS:
		if String(w[0]) == wall and y > float(w[3]) - LOG_R * 0.5 and y < float(w[4]) + LOG_R * 0.5:
			cuts.append(Vector2(float(w[1]), float(w[2])))
	if wall == "back" and y < BACK_DOOR.z + LOG_R * 0.5:
		cuts.append(Vector2(BACK_DOOR.x, BACK_DOOR.y))
	if wall == "left" and y < DEN_DOOR.z + LOG_R * 0.5:
		cuts.append(Vector2(DEN_DOOR.x, DEN_DOOR.y))
	cuts.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
	var out: Array[Vector2] = []
	var at := from
	for c in cuts:
		if c.x > at:
			out.append(Vector2(at, c.x))
		at = maxf(at, c.y)
	if to > at:
		out.append(Vector2(at, to))
	return out


## A timber frame round a window opening, with a sill.
static func _window_frame(b: Buf, wall: String, from: float, to: float, sill: float, top: float) -> void:
	var t := 0.08
	if wall == "back":
		b.block(Vector3(from - t, sill - t, BACK_Z - 0.22), Vector3(to + t, sill, BACK_Z + 0.22), C_FRAME)
		b.block(Vector3(from - t, top, BACK_Z - 0.2), Vector3(to + t, top + t, BACK_Z + 0.2), C_FRAME)
		b.block(Vector3(from - t, sill, BACK_Z - 0.2), Vector3(from, top, BACK_Z + 0.2), C_FRAME)
		b.block(Vector3(to, sill, BACK_Z - 0.2), Vector3(to + t, top, BACK_Z + 0.2), C_FRAME)
		return
	var x := -HALF_W if wall == "left" else HALF_W
	b.block(Vector3(x - 0.22, sill - t, from - t), Vector3(x + 0.22, sill, to + t), C_FRAME)
	b.block(Vector3(x - 0.2, top, from - t), Vector3(x + 0.2, top + t, to + t), C_FRAME)
	b.block(Vector3(x - 0.2, sill, from - t), Vector3(x + 0.2, top, from), C_FRAME)
	b.block(Vector3(x - 0.2, sill, to), Vector3(x + 0.2, top, to + t), C_FRAME)


# ── Floor, roof, beams, the front frame ──────────────────────
static func _build_shell(b: Buf) -> void:
	# the floor and the stone footing under the cabin
	b.block(Vector3(-HALF_W, -0.2, 0.0), Vector3(HALF_W, 0.0, BACK_Z), C_FLOOR)
	b.block(Vector3(-HALF_W - 0.15, GROUND_Y - 0.1, -0.1), Vector3(HALF_W + 0.15, -0.2, BACK_Z + 0.15), C_STONE_DARK)
	# the roof: a thin pine ceiling right on the roof line, the roofing on top of it
	var eave := Vector2(HALF_W + ROOF_SIDE, roof_y(HALF_W + ROOF_SIDE))
	for sx: float in [-1.0, 1.0]:
		var e := Vector2(eave.x * sx, eave.y)
		b.slab(e, Vector2(0.0, RIDGE_Y), -ROOF_FRONT, BACK_Z + ROOF_BACK, 0.06, C_PINE)
		b.slab(Vector2(e.x, e.y + 0.07), Vector2(0.0, RIDGE_Y + 0.07), -ROOF_FRONT - 0.05, BACK_Z + ROOF_BACK + 0.05, 0.22, C_ROOF)
	# the ridge beam, and the log rafters and collar ties across the great room
	b.block(Vector3(-0.18, RIDGE_Y - 0.42, -ROOF_FRONT), Vector3(0.18, RIDGE_Y, BACK_Z + ROOF_BACK), C_TIMBER)
	for z in COLLARS_Z:
		var cx := HALF_W * (1.0 - (COLLAR_Y - EAVE_Y) / (RIDGE_Y - EAVE_Y))
		b.rod(Vector3(-cx, COLLAR_Y, z), Vector3(cx, COLLAR_Y, z), 0.15, 10, C_TIMBER, C_LOG_END)
		b.rod(Vector3(0.0, COLLAR_Y, z), Vector3(0.0, RIDGE_Y - 0.4, z), 0.12, 10, C_TIMBER)
		for sx: float in [-1.0, 1.0]:
			b.rod(Vector3(sx * HALF_W, EAVE_Y - 0.1, z), Vector3(0.0, RIDGE_Y - 0.25, z), 0.15, 10, C_TIMBER)
	# the front window wall's timber frame: posts, the beam at eave height, and beams under the
	# roof line (the glass itself is _build_glass)
	for i in MULLIONS.size():
		for sx: float in [-1.0, 1.0]:
			var x := MULLIONS[i] * sx
			b.block(Vector3(x - 0.09, 0.0, -0.1), Vector3(x + 0.09, roof_y(x), 0.1), C_FRAME)
	for sx: float in [-1.0, 1.0]:
		b.block(Vector3(minf(sx * HALF_W, sx * CHIM_HALF), EAVE_Y - 0.08, -0.1), Vector3(maxf(sx * HALF_W, sx * CHIM_HALF), EAVE_Y + 0.08, 0.1), C_FRAME)
		b.block(Vector3(minf(sx * HALF_W, sx * CHIM_HALF), 0.0, -0.12), Vector3(maxf(sx * HALF_W, sx * CHIM_HALF), 0.12, 0.12), C_FRAME)
		b.slab(Vector2(sx * HALF_W, EAVE_Y - 0.12), Vector2(0.0, RIDGE_Y - 0.12), -0.12, 0.12, 0.12, C_FRAME)
	# the glass doors' frames in the two front corners (thicker, with a handle)
	for sx: float in [-1.0, 1.0]:
		var x0 := minf(GLASS_DOOR.x * sx, GLASS_DOOR.y * sx)
		var x1 := maxf(GLASS_DOOR.x * sx, GLASS_DOOR.y * sx)
		b.block(Vector3(x0, 2.2, -0.12), Vector3(x1, 2.32, 0.12), C_FRAME)
		var hx := x1 - 0.12 if sx < 0.0 else x0 + 0.12
		b.block(Vector3(hx - 0.02, 0.95, -0.14), Vector3(hx + 0.02, 1.15, 0.14), C_IRON)


## The loft across the back: its floor, two log posts holding its front edge, the railing (with
## the gap where the stairs arrive) and the stairs up the right wall.
static func _build_loft(b: Buf) -> void:
	b.block(Vector3(-HALF_W, LOFT_Y - 0.25, LOFT_FRONT_Z), Vector3(HALF_W, LOFT_Y, BACK_Z), C_FLOOR)
	b.block(Vector3(-HALF_W, LOFT_Y - 0.45, LOFT_FRONT_Z - 0.05), Vector3(HALF_W, LOFT_Y - 0.25, LOFT_FRONT_Z + 0.25), C_TIMBER)
	for x: float in [-2.4, 2.4]:
		b.rod(Vector3(x, 0.0, LOFT_FRONT_Z + 0.1), Vector3(x, LOFT_Y - 0.25, LOFT_FRONT_Z + 0.1), 0.16, 10, C_LOG, C_LOG_END)
	var rail_y := LOFT_Y + 1.0
	var rail_end := STAIR_X.x
	b.rod(Vector3(-HALF_W, rail_y, LOFT_FRONT_Z + 0.05), Vector3(rail_end, rail_y, LOFT_FRONT_Z + 0.05), 0.05, 8, C_TIMBER)
	b.rod(Vector3(-HALF_W, LOFT_Y + 0.12, LOFT_FRONT_Z + 0.05), Vector3(rail_end, LOFT_Y + 0.12, LOFT_FRONT_Z + 0.05), 0.04, 6, C_TIMBER)
	var x := -HALF_W + 0.2
	while x < rail_end:
		b.rod(Vector3(x, LOFT_Y, LOFT_FRONT_Z + 0.05), Vector3(x, rail_y, LOFT_FRONT_Z + 0.05), 0.022 if fmod(x + HALF_W, 1.3) > 0.2 else 0.06, 5, C_TIMBER)
		x += 0.22
	# the stairs: solid wooden steps, rising towards the back
	var run := (LOFT_FRONT_Z - STAIR_START_Z) / float(STAIR_STEPS)
	var rise := LOFT_Y / float(STAIR_STEPS)
	for i in STAIR_STEPS:
		var z0 := STAIR_START_Z + float(i) * run
		b.block(Vector3(STAIR_X.x, 0.0, z0), Vector3(STAIR_X.y, rise * float(i + 1), z0 + run), C_FLOOR.darkened(0.05 * float(i % 2)))
	b.rod(Vector3(STAIR_X.x, 1.0, STAIR_START_Z), Vector3(STAIR_X.x, LOFT_Y + 1.0, LOFT_FRONT_Z), 0.045, 8, C_TIMBER)
	for i in range(0, STAIR_STEPS, 2):
		var z := STAIR_START_Z + (float(i) + 0.5) * run
		var y := rise * float(i + 1)
		b.rod(Vector3(STAIR_X.x, y, z), Vector3(STAIR_X.x, y + 0.95, z), 0.03, 5, C_TIMBER)


# ── The chimney ──────────────────────────────────────────────
## The stone chimney standing in the middle of the glass wall: a wide lower part (the fireplace,
## with the screen above the mantel on its room side), a narrower stack up through the roof, the
## raised hearth in front with a niche of split logs, and the mantel shelf on two corbels.
static func _build_chimney(b: Buf, markers: Node3D, out: Dictionary) -> void:
	var fb_back := CHIM_IN_Z - FIREBOX_DEPTH
	# behind the firebox, full width and height of the wide part
	b.block(Vector3(-CHIM_HALF, 0.0, CHIM_OUT_Z), Vector3(CHIM_HALF, CHIM_WIDE_TOP, fb_back), C_STONE)
	# either side of the firebox, under it and over it
	b.block(Vector3(-CHIM_HALF, 0.0, fb_back), Vector3(-FIREBOX_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	b.block(Vector3(FIREBOX_HALF, 0.0, fb_back), Vector3(CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	b.block(Vector3(-FIREBOX_HALF, 0.0, fb_back), Vector3(FIREBOX_HALF, FIREBOX_Y.x, CHIM_IN_Z), C_STONE_DARK)
	b.block(Vector3(-FIREBOX_HALF, FIREBOX_Y.y, fb_back), Vector3(FIREBOX_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	# the sooty inside of the firebox
	b.block(Vector3(-FIREBOX_HALF, FIREBOX_Y.x, fb_back - 0.01), Vector3(FIREBOX_HALF, FIREBOX_Y.y, fb_back + 0.02), C_SOOT)
	# the shoulders slope in to the stack, and the stack goes up through the roof
	var stack_z := Vector2(CHIM_OUT_Z + 0.25, CHIM_IN_Z - 0.35)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * CHIM_HALF, CHIM_WIDE_TOP, CHIM_OUT_Z), Vector3(sx * CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x),
			Vector3(sx * CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.y), Vector3(sx * CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	b.quad(Vector3(-CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), Vector3(CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z),
		Vector3(CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.y), Vector3(-CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.y), C_STONE)
	b.quad(Vector3(-CHIM_HALF, CHIM_WIDE_TOP, CHIM_OUT_Z), Vector3(CHIM_HALF, CHIM_WIDE_TOP, CHIM_OUT_Z),
		Vector3(CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x), Vector3(-CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x), C_STONE)
	b.block(Vector3(-CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x), Vector3(CHIM_STACK_HALF, CHIM_TOP, stack_z.y), C_STONE)
	b.block(Vector3(-CHIM_STACK_HALF - 0.1, CHIM_TOP, stack_z.x - 0.1), Vector3(CHIM_STACK_HALF + 0.1, CHIM_TOP + 0.18, stack_z.y + 0.1), C_STONE_DARK)
	# a few darker stones scattered over the face, so it reads as stone even without a texture
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	for i in 60:
		var x := rng.randf_range(-CHIM_HALF + 0.2, CHIM_HALF - 0.2)
		var y := rng.randf_range(0.2, CHIM_WIDE_TOP - 0.2)
		var fire_hole := absf(x) < FIREBOX_HALF + 0.15 and y < FIREBOX_Y.y + 0.15
		var behind_screen := absf(x) < SCREEN_SIZE.x * 0.5 + 0.05 and y > SCREEN_BOTTOM - 0.05 and y < SCREEN_BOTTOM + SCREEN_SIZE.y + 0.05
		if fire_hole or behind_screen:
			continue
		var s := Vector3(rng.randf_range(0.25, 0.5), rng.randf_range(0.18, 0.3), 0.04)
		b.block(Vector3(x - s.x * 0.5, y - s.y * 0.5, CHIM_IN_Z), Vector3(x + s.x * 0.5, y + s.y * 0.5, CHIM_IN_Z + s.z), C_STONE.darkened(rng.randf_range(0.05, 0.25)))
	# the raised hearth, with a niche of split logs in its front
	b.block(Vector3(-HEARTH_HALF, 0.0, CHIM_IN_Z), Vector3(HEARTH_HALF, HEARTH_H, CHIM_IN_Z + HEARTH_OUT), C_STONE.lightened(0.1))
	b.block(Vector3(-HEARTH_HALF + 0.3, 0.05, CHIM_IN_Z + HEARTH_OUT - 0.02), Vector3(-0.9, HEARTH_H - 0.06, CHIM_IN_Z + HEARTH_OUT + 0.005), C_SOOT)
	for r in 3:
		for c in 4:
			var at := Vector3(-HEARTH_HALF + 0.42 + float(c) * 0.32 + (0.16 if r % 2 == 1 else 0.0), 0.12 + float(r) * 0.1, CHIM_IN_Z + 0.08)
			if at.x < -1.0:
				b.rod(at, at + Vector3(0.0, 0.0, HEARTH_OUT - 0.07), 0.055, 7, C_LOG, C_LOG_END)
	# the mantel shelf on two corbels
	b.block(Vector3(-1.95, MANTEL_Y - 0.2, CHIM_IN_Z), Vector3(1.95, MANTEL_Y, CHIM_IN_Z + 0.3), C_TIMBER)
	for sx: float in [-1.0, 1.0]:
		b.block(Vector3(sx * 1.6 - 0.08, MANTEL_Y - 0.48, CHIM_IN_Z), Vector3(sx * 1.6 + 0.08, MANTEL_Y - 0.2, CHIM_IN_Z + 0.22), C_TIMBER)
	# andirons and logs in the firebox
	var fire_at := Vector3(0.0, FIREBOX_Y.x + 0.02, CHIM_IN_Z - FIREBOX_DEPTH * 0.45)
	for sx: float in [-0.35, 0.35]:
		b.rod(fire_at + Vector3(sx, 0.0, -0.15), fire_at + Vector3(sx, 0.0, 0.2), 0.025, 5, C_IRON)
	b.rod(fire_at + Vector3(-0.45, 0.08, -0.05), fire_at + Vector3(0.45, 0.1, -0.08), 0.07, 8, C_LOG.darkened(0.4), C_LOG_END)
	b.rod(fire_at + Vector3(-0.4, 0.08, 0.1), fire_at + Vector3(0.4, 0.14, 0.05), 0.06, 8, C_LOG.darkened(0.4), C_LOG_END)
	var fire := Marker3D.new()
	fire.name = "FIRE_Hearth"
	markers.add_child(fire)
	fire.position = fire_at
	(out["fires"] as Array[Marker3D]).append(fire)
	# the glowing coals under the logs (their glow follows the Fire setting, in the room script)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.albedo_color = Color(0.25, 0.06, 0.02)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.35, 0.08)
	ember_mat.emission_energy_multiplier = 2.0
	var coals := BoxMesh.new()
	coals.size = Vector3(0.9, 0.05, 0.35)
	var coal_mi := MeshInstance3D.new()
	coal_mi.name = "Embers"
	coal_mi.mesh = coals
	coal_mi.material_override = ember_mat
	coal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markers.get_parent().get_node("Set").add_child(coal_mi)
	coal_mi.position = fire_at
	out["ember_mat"] = ember_mat


# ── The great room ───────────────────────────────────────────
## Everything in the tall part of the room: rug, coffee table, cushions, the two leather sofas,
## the armchairs with their side tables, and the chandelier.
static func _build_great_room(b: Buf) -> void:
	b.block(Vector3(-3.4, 0.0, 1.45), Vector3(3.4, 0.015, 4.65), C_RUG)
	b.block(Vector3(-3.25, 0.016, 1.6), Vector3(3.25, 0.02, 4.5), C_RUG.lightened(0.15))
	# a live-edge coffee table
	b.block(Vector3(-1.0, 0.36, 2.45), Vector3(1.0, 0.44, 3.05), C_TIMBER.lightened(0.1))
	for sx: float in [-0.8, 0.8]:
		b.block(Vector3(sx - 0.06, 0.0, 2.6), Vector3(sx + 0.06, 0.36, 2.9), C_TIMBER)
	# sheepskins and cushions by the hearth (under the Hearth_ seats)
	for s: Array in SEATS:
		if String(s[0]).begins_with("Hearth"):
			var x := float(s[1])
			var z := float(s[3])
			b.block(Vector3(x - 0.3, 0.0, z - 0.3), Vector3(x + 0.3, 0.12, z + 0.3), C_WOOL if int(x * 2.0) % 2 == 0 else C_FABRIC)
	# the sofas: seat, back and arms; each seats three
	for sx: float in [-1.0, 1.0]:
		var x0 := minf(sx * 0.6, sx * 3.6)
		var x1 := maxf(sx * 0.6, sx * 3.6)
		b.block(Vector3(x0, 0.0, 3.5), Vector3(x1, 0.45, 4.3), C_LEATHER)
		b.block(Vector3(x0, 0.0, 4.15), Vector3(x1, 0.95, 4.4), C_LEATHER.darkened(0.1))
		b.block(Vector3(x0 - 0.18, 0.0, 3.5), Vector3(x0, 0.65, 4.4), C_LEATHER.darkened(0.15))
		b.block(Vector3(x1, 0.0, 3.5), Vector3(x1 + 0.18, 0.65, 4.4), C_LEATHER.darkened(0.15))
		# a throw over the back
		b.block(Vector3(x0 + 0.2, 0.55, 4.12), Vector3(x0 + 0.9, 0.97, 4.42), C_FABRIC)
	# the four armchairs (under the Arm_ seats), turned to face the screen
	for s: Array in SEATS:
		if String(s[0]).begins_with("Arm"):
			_armchair(b, Vector3(float(s[1]), 0.0, float(s[3])), C_LEATHER.lightened(0.08))
	# side tables beside the left armchairs and by the stairs (the table lamps stand on them)
	for at: Vector3 in [Vector3(-5.6, 0.0, 2.6), Vector3(4.95, 0.0, 2.9)]:
		b.block(at + Vector3(-0.25, 0.0, -0.25), at + Vector3(0.25, 0.6, 0.25), C_TIMBER)
		b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.6, 0.0)), 0.08, 0.06, 0.32, 8, C_STONE_DARK)
	# the chandelier: an iron ring of candles hanging from the ridge on a chain
	var ch := Vector3(0.0, 5.0, 3.0)
	b.rod(ch, Vector3(0.0, RIDGE_Y - 0.4, 3.0), 0.02, 4, C_IRON)
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		b.rod(ch + Vector3(cos(a0), 0.0, sin(a0)) * 0.65, ch + Vector3(cos(a1), 0.0, sin(a1)) * 0.65, 0.025, 5, C_IRON)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		b.rod(ch + Vector3(cos(a), 0.0, sin(a)) * 0.65, ch + Vector3(0.0, 0.8, 0.0), 0.012, 4, C_IRON)


## A leather armchair standing at `at`, facing the screen (-Z, where the chimney is).
static func _armchair(b: Buf, at: Vector3, col: Color) -> void:
	var to_screen := Vector3(0.0, 0.0, CHIM_IN_Z) - at
	to_screen.y = 0.0
	var basis := Basis.looking_at(to_screen.normalized(), Vector3.UP)      # -Z = towards the screen
	var xf := Transform3D(basis, at)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.0)), Vector3(0.85, 0.45, 0.8), col)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.32)), Vector3(0.85, 1.0, 0.2), col.darkened(0.1))
	for sx: float in [-0.42, 0.42]:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.32, 0.0)), Vector3(0.14, 0.64, 0.8), col.darkened(0.15))


# ── Under the loft ───────────────────────────────────────────
## The kitchen in the back left corner, the dining table with its bench, the mudroom bench and
## coat pegs by the back door, and the bookshelves; plus a bench and a bed up in the loft.
static func _build_back_rooms(b: Buf) -> void:
	# kitchen: an L of base cupboards with a worktop, wall cupboards, a stove
	b.block(Vector3(-HALF_W + 0.15, 0.0, 8.35), Vector3(-2.1, 0.88, BACK_Z - 0.15), C_TIMBER.lightened(0.15))
	b.block(Vector3(-HALF_W + 0.15, 0.88, 8.3), Vector3(-2.05, 0.94, BACK_Z - 0.15), C_STONE_DARK)
	b.block(Vector3(-HALF_W + 0.15, 0.0, 7.35), Vector3(-5.85, 0.88, 8.35), C_TIMBER.lightened(0.15))
	b.block(Vector3(-HALF_W + 0.15, 0.88, 7.3), Vector3(-5.8, 0.94, 8.35), C_STONE_DARK)
	b.block(Vector3(-HALF_W + 0.15, 1.5, 8.6), Vector3(-2.1, 2.2, BACK_Z - 0.15), C_TIMBER.lightened(0.2))
	b.block(Vector3(-3.4, 0.94, 8.5), Vector3(-2.6, 1.0, 8.85), C_IRON)
	# dining: a long live-edge table under the pendant lamp, and the bench facing the view
	b.block(Vector3(-5.2, 0.72, 6.6), Vector3(-1.6, 0.8, 7.45), C_TIMBER.lightened(0.08))
	for x: float in [-5.0, -1.8]:
		for z: float in [6.75, 7.3]:
			b.block(Vector3(x - 0.05, 0.0, z - 0.05), Vector3(x + 0.05, 0.72, z + 0.05), C_TIMBER)
	b.block(Vector3(-5.25, 0.38, 6.0), Vector3(-1.45, 0.45, 6.4), C_TIMBER.lightened(0.05))
	for x: float in [-5.1, -1.6]:
		b.block(Vector3(x - 0.05, 0.0, 6.05), Vector3(x + 0.05, 0.38, 6.35), C_TIMBER)
	for x: float in [-4.6, -3.4, -2.2]:      # chairs on the far side of the table
		b.block(Vector3(x - 0.22, 0.42, 7.6), Vector3(x + 0.22, 0.47, 8.0), C_TIMBER)
		b.block(Vector3(x - 0.22, 0.47, 7.95), Vector3(x + 0.22, 1.0, 8.02), C_TIMBER)
	# the pendant lamp's cord down from the loft's underside
	b.rod(Vector3(-3.4, 1.9, 7.0), Vector3(-3.4, LOFT_Y - 0.25, 7.0), 0.01, 4, C_IRON)
	# mudroom: a bench and coat pegs by the back door
	b.block(Vector3(0.8, 0.38, 8.45), Vector3(2.2, 0.45, 8.85), C_TIMBER)
	b.block(Vector3(0.8, 1.55, 8.82), Vector3(2.2, 1.65, 8.85), C_TIMBER)
	for i in 4:
		b.rod(Vector3(0.95 + float(i) * 0.38, 1.6, 8.82), Vector3(0.95 + float(i) * 0.38, 1.6, 8.62), 0.015, 4, C_IRON)
	b.block(Vector3(1.0, 0.0, 8.5), Vector3(1.4, 0.3, 8.75), C_IRON.lightened(0.15))       # boots
	# bookshelves along the back wall, with rows of books
	b.block(Vector3(2.7, 0.0, 8.55), Vector3(4.9, 2.4, BACK_Z - 0.15), C_TIMBER.darkened(0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for shelf in 5:
		var y := 0.1 + float(shelf) * 0.46
		var x := 2.8
		while x < 4.75:
			var w := rng.randf_range(0.04, 0.09)
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.6), rng.randf_range(0.3, 0.6))
			b.block(Vector3(x, y, 8.5), Vector3(x + w, y + rng.randf_range(0.26, 0.36), 8.75), col)
			x += w + 0.01
	# loft: the bench at the railing (the Loft_ seats), and a bed and rug behind it
	b.block(Vector3(-4.8, LOFT_Y + 0.35, 5.6), Vector3(3.4, LOFT_Y + 0.42, 6.0), C_TIMBER.lightened(0.05))
	for x: float in [-4.6, -2.1, 0.0, 2.1, 3.2]:
		b.block(Vector3(x - 0.05, LOFT_Y, 5.65), Vector3(x + 0.05, LOFT_Y + 0.35, 5.95), C_TIMBER)
	b.block(Vector3(-3.0, LOFT_Y, 7.0), Vector3(-0.8, LOFT_Y + 0.5, BACK_Z - 0.2), C_FABRIC.darkened(0.2))
	b.block(Vector3(-3.0, LOFT_Y + 0.5, 8.4), Vector3(-0.8, LOFT_Y + 0.65, BACK_Z - 0.25), C_WOOL)
	b.block(Vector3(-2.0, LOFT_Y, 6.3), Vector3(2.0, LOFT_Y + 0.01, 6.9), C_RUG.darkened(0.1))


# ── The den ──────────────────────────────────────────────────
## The den off the great room's left wall (Sen's den picture): log walls with a window behind the
## sofa and one behind the armchair, a flat pine ceiling with heavy log beams, its own small gable
## roof (which tucks under the great room's roof), a stone chimney on the far wall with a raised
## hearth, a heavy mantel on corbels and a fire (FIRE_Den), a rug, a coffee table, the leather sofa
## and armchair the presenters sit on in "Gather in: Den", a side table, a floor lamp's stand and a
## stack of firewood. Called by build_cabin after _build_chimney (which makes out["ember_mat"]).
static func _build_den(b: Buf, markers: Node3D, out: Dictionary) -> void:
	var near_x := -HALF_W          # the great room's left wall, which the den leans on
	var in_lo := DEN_FAR_X + LOG_R  # the inside faces of the den's walls
	var in_hi := near_x - LOG_R
	var z_lo := DEN_Z.x + LOG_R
	var z_hi := DEN_Z.y - LOG_R
	# floor and footing
	b.block(Vector3(DEN_FAR_X, -0.2, DEN_Z.x), Vector3(near_x, 0.0, DEN_Z.y), C_FLOOR.darkened(0.04))
	b.block(Vector3(DEN_FAR_X - 0.15, GROUND_Y - 0.1, DEN_Z.x - 0.15), Vector3(near_x, -0.2, DEN_Z.y + 0.15), C_STONE_DARK)
	# log walls: the two long walls (z = DEN_Z.x, DEN_Z.y) and the far wall (x = DEN_FAR_X), a half
	# log higher so the corners interlock like the great room's
	var rows := int(floor((DEN_EAVE_Y - LOG_R) / LOG_STEP)) + 1
	for r in rows:
		var y := LOG_R + float(r) * LOG_STEP
		var col := C_LOG.darkened(0.06 * float(r % 3))
		for z: float in [DEN_Z.x, DEN_Z.y]:
			for span in _den_spans(z, DEN_FAR_X - LOG_OVERHANG, in_hi, y):
				b.rod(Vector3(span.x, y, z), Vector3(span.y, y, z), LOG_R, 10, col, C_LOG_END)
		var yf := y + LOG_STEP * 0.5
		if yf < DEN_EAVE_Y:
			b.rod(Vector3(DEN_FAR_X, yf, DEN_Z.x - LOG_OVERHANG), Vector3(DEN_FAR_X, yf, DEN_Z.y + LOG_OVERHANG), LOG_R, 10, C_LOG.darkened(0.06 * float((r + 1) % 3)), C_LOG_END)
	for w: Array in DEN_WINDOWS:
		var z := float(w[0])
		var t := 0.08
		b.block(Vector3(float(w[1]) - t, float(w[3]) - t, z - 0.22), Vector3(float(w[2]) + t, float(w[3]), z + 0.22), C_FRAME)
		b.block(Vector3(float(w[1]) - t, float(w[4]), z - 0.2), Vector3(float(w[2]) + t, float(w[4]) + t, z + 0.2), C_FRAME)
		b.block(Vector3(float(w[1]) - t, float(w[3]), z - 0.2), Vector3(float(w[1]), float(w[4]), z + 0.2), C_FRAME)
		b.block(Vector3(float(w[2]), float(w[3]), z - 0.2), Vector3(float(w[2]) + t, float(w[4]), z + 0.2), C_FRAME)
	# the gable over the far wall, up to the den's ridge
	var top := rows * LOG_STEP
	b.tri(Vector3(DEN_FAR_X, top, DEN_Z.x), Vector3(DEN_FAR_X, top, DEN_Z.y), Vector3(DEN_FAR_X, DEN_RIDGE_Y + 0.1, DEN_MID_Z), C_PINE.darkened(0.2))
	# the low flat ceiling of pine boards, with heavy log beams across it (none along the middle:
	# it would hang right across the Den Fireside camera's view)
	b.block(Vector3(in_lo, DEN_CEIL_Y, z_lo), Vector3(in_hi, DEN_CEIL_Y + 0.05, z_hi), C_PINE)
	for x: float in [-7.5, -8.9, -10.3]:
		b.rod(Vector3(x, DEN_CEIL_Y - 0.14, z_lo), Vector3(x, DEN_CEIL_Y - 0.14, z_hi), 0.14, 10, C_TIMBER, C_LOG_END)
	# the roof: two slopes from the eaves up to a ridge along x, ending where they meet the great
	# room's roof (_great_roof_x), so nothing pokes through into the great room
	var overhang := 0.5
	var slope := (DEN_RIDGE_Y - DEN_EAVE_Y) / (DEN_MID_Z - DEN_Z.x)
	var far := DEN_FAR_X - overhang
	for side: float in [-1.0, 1.0]:
		var ze := DEN_Z.x - overhang if side < 0.0 else DEN_Z.y + overhang
		var ye := DEN_EAVE_Y - overhang * slope
		for layer: Array in [[0.0, C_PINE], [0.2, C_ROOF]]:
			var lift := float(layer[0])
			b.quad(Vector3(far, ye + lift, ze), Vector3(_great_roof_x(ye + lift), ye + lift, ze),
				Vector3(_great_roof_x(DEN_RIDGE_Y + lift), DEN_RIDGE_Y + lift, DEN_MID_Z), Vector3(far, DEN_RIDGE_Y + lift, DEN_MID_Z), layer[1])
		# the roof's edge at the far end
		b.quad(Vector3(far, ye, ze), Vector3(far, ye + 0.2, ze), Vector3(far, DEN_RIDGE_Y + 0.2, DEN_MID_Z), Vector3(far, DEN_RIDGE_Y, DEN_MID_Z), C_ROOF.darkened(0.2))
	_build_den_chimney(b, markers, out)
	_build_den_furniture(b)


## Where the great room's roof (its pine underside) is at height y, on the den's (left) side.
static func _great_roof_x(y: float) -> float:
	return -HALF_W * (1.0 - (y - EAVE_Y) / (RIDGE_Y - EAVE_Y))


## The pieces of one log row along a den wall (at z) at height y, skipping its windows.
static func _den_spans(z: float, from: float, to: float, y: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := from
	for w: Array in DEN_WINDOWS:
		if is_equal_approx(float(w[0]), z) and y > float(w[3]) - LOG_R * 0.5 and y < float(w[4]) + LOG_R * 0.5:
			out.append(Vector2(at, float(w[1])))
			at = float(w[2])
	out.append(Vector2(at, to))
	return out


## The den's chimney on its far wall: stone from the floor up through the roof (sticking out
## behind the wall too, like an outside chimney), the firebox, raised hearth, the heavy mantel on
## two corbels, andirons and logs, the FIRE_Den marker and its glowing coals. The fire faces +X
## (into the den), so its marker is turned a quarter round: the room script places the flames and
## the light in the marker's own axes, the same way for both fires.
static func _build_den_chimney(b: Buf, markers: Node3D, out: Dictionary) -> void:
	var back_x := DEN_FAR_X - 0.4
	var fb := DEN_FIREBOX       # z from, z to, bottom, top
	var fb_back := DEN_CHIM_FACE_X - 0.45
	var stone := C_STONE.lightened(0.04)
	b.block(Vector3(back_x, 0.0, DEN_CHIM_Z.x), Vector3(fb_back, DEN_CEIL_Y, DEN_CHIM_Z.y), stone)
	b.block(Vector3(fb_back, 0.0, DEN_CHIM_Z.x), Vector3(DEN_CHIM_FACE_X, DEN_CEIL_Y, fb.x), stone)
	b.block(Vector3(fb_back, 0.0, fb.y), Vector3(DEN_CHIM_FACE_X, DEN_CEIL_Y, DEN_CHIM_Z.y), stone)
	b.block(Vector3(fb_back, 0.0, fb.x), Vector3(DEN_CHIM_FACE_X, fb.z, fb.y), C_STONE_DARK)
	b.block(Vector3(fb_back, fb.w, fb.x), Vector3(DEN_CHIM_FACE_X, DEN_CEIL_Y, fb.y), stone)
	b.block(Vector3(fb_back - 0.02, fb.z, fb.x), Vector3(fb_back + 0.01, fb.w, fb.y), C_SOOT)
	# the stack through the roof
	b.block(Vector3(back_x, DEN_CEIL_Y, 4.75), Vector3(DEN_FAR_X + 0.25, DEN_RIDGE_Y + 1.2, 5.85), stone)
	b.block(Vector3(back_x - 0.08, DEN_RIDGE_Y + 1.2, 4.67), Vector3(DEN_FAR_X + 0.33, DEN_RIDGE_Y + 1.36, 5.93), C_STONE_DARK)
	# darker stones over the face, kept off the firebox and the screen
	var rng := RandomNumberGenerator.new()
	rng.seed = 1117
	var screen_z := Vector2(DEN_MID_Z - DEN_SCREEN_SIZE.x * 0.5 - 0.05, DEN_MID_Z + DEN_SCREEN_SIZE.x * 0.5 + 0.05)
	for i in 40:
		var z := rng.randf_range(DEN_CHIM_Z.x + 0.15, DEN_CHIM_Z.y - 0.15)
		var y := rng.randf_range(0.2, DEN_CEIL_Y - 0.2)
		var fire_hole := z > fb.x - 0.12 and z < fb.y + 0.12 and y < fb.w + 0.12
		var behind_screen := z > screen_z.x and z < screen_z.y and y > DEN_SCREEN_BOTTOM - 0.05 and y < DEN_SCREEN_BOTTOM + DEN_SCREEN_SIZE.y + 0.05
		if fire_hole or behind_screen:
			continue
		var s := Vector3(0.04, rng.randf_range(0.16, 0.28), rng.randf_range(0.22, 0.42))
		b.block(Vector3(DEN_CHIM_FACE_X, y - s.y * 0.5, z - s.z * 0.5), Vector3(DEN_CHIM_FACE_X + s.x, y + s.y * 0.5, z + s.z * 0.5), stone.darkened(rng.randf_range(0.05, 0.25)))
	# raised hearth, and the heavy mantel beam on two corbels (wider than the chimney, as in the picture)
	b.block(Vector3(DEN_CHIM_FACE_X, 0.0, DEN_CHIM_Z.x - 0.25), Vector3(DEN_CHIM_FACE_X + 0.5, 0.3, DEN_CHIM_Z.y + 0.25), C_STONE.lightened(0.12))
	b.block(Vector3(DEN_CHIM_FACE_X, DEN_MANTEL_Y - 0.24, DEN_CHIM_Z.x - 0.15), Vector3(DEN_CHIM_FACE_X + 0.32, DEN_MANTEL_Y, DEN_CHIM_Z.y + 0.15), C_TIMBER.darkened(0.1))
	for z: float in [DEN_CHIM_Z.x + 0.2, DEN_CHIM_Z.y - 0.2]:
		b.block(Vector3(DEN_CHIM_FACE_X, DEN_MANTEL_Y - 0.55, z - 0.08), Vector3(DEN_CHIM_FACE_X + 0.24, DEN_MANTEL_Y - 0.24, z + 0.08), C_TIMBER.darkened(0.1))
	# andirons and logs, placed in the fire marker's axes (+Z = out into the den)
	var fire_at := Vector3(DEN_CHIM_FACE_X - 0.45 * 0.5, fb.z + 0.02, DEN_MID_Z)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), fire_at)
	for sx: float in [-0.3, 0.3]:
		b.rod(xf * Vector3(sx, 0.0, -0.13), xf * Vector3(sx, 0.0, 0.18), 0.025, 5, C_IRON)
	b.rod(xf * Vector3(-0.38, 0.08, -0.05), xf * Vector3(0.38, 0.1, -0.07), 0.065, 8, C_LOG.darkened(0.4), C_LOG_END)
	b.rod(xf * Vector3(-0.34, 0.08, 0.08), xf * Vector3(0.34, 0.13, 0.04), 0.055, 8, C_LOG.darkened(0.4), C_LOG_END)
	var fire := Marker3D.new()
	fire.name = "FIRE_Den"
	markers.add_child(fire)
	fire.transform = xf
	(out["fires"] as Array[Marker3D]).append(fire)
	var coals := BoxMesh.new()
	coals.size = Vector3(0.75, 0.05, 0.3)
	var coal_mi := MeshInstance3D.new()
	coal_mi.name = "Embers_Den"
	coal_mi.mesh = coals
	coal_mi.material_override = out["ember_mat"]
	coal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markers.get_parent().get_node("Set").add_child(coal_mi)
	coal_mi.transform = xf


## The den's furniture: rug, coffee table (with a few books), the three-seat leather sofa with
## cushions and throws, the armchair, a side table under LAMP_Den_Table, the floor lamp's stand
## under LAMP_Den_Floor, and firewood stacked by the hearth.
static func _build_den_furniture(b: Buf) -> void:
	b.block(Vector3(-11.0, 0.0, 3.6), Vector3(-7.6, 0.015, 7.3), C_RUG.darkened(0.1))
	b.block(Vector3(-10.85, 0.016, 3.75), Vector3(-7.75, 0.02, 7.15), Color(0.42, 0.3, 0.18))
	# a chunky wooden coffee table
	b.block(Vector3(-9.95, 0.36, 5.2), Vector3(-8.65, 0.46, 6.0), C_TIMBER.lightened(0.12))
	b.block(Vector3(-9.85, 0.08, 5.3), Vector3(-8.75, 0.12, 5.9), C_TIMBER)
	for x: float in [-9.85, -8.81]:
		for z: float in [5.26, 5.88]:
			b.block(Vector3(x, 0.0, z), Vector3(x + 0.06, 0.36, z + 0.06), C_TIMBER.darkened(0.1))
	b.block(Vector3(-9.6, 0.46, 5.45), Vector3(-9.2, 0.52, 5.75), Color(0.3, 0.38, 0.32))
	b.block(Vector3(-9.57, 0.52, 5.48), Vector3(-9.25, 0.56, 5.7), Color(0.55, 0.2, 0.15))
	# the sofa: local axes from _den_seat_xf (-Z = the way it faces)
	var sofa := _den_seat_xf(DEN_SOFA)
	var col := C_LEATHER.darkened(0.05)
	b.box(sofa * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.19, 0.0)), Vector3(3.7, 0.38, 0.9), col)
	b.box(sofa * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.38)), Vector3(3.7, 1.0, 0.24), col.darkened(0.1))
	for sx: float in [-1.0, 1.0]:
		b.box(sofa * Transform3D(Basis.IDENTITY, Vector3(sx * 1.76, 0.33, 0.0)), Vector3(0.2, 0.66, 0.9), col.darkened(0.15))
	for i in 3:
		var sx := (float(i) - 1.0) * 1.1
		b.box(sofa * Transform3D(Basis.IDENTITY, Vector3(sx, 0.415, -0.05)), Vector3(1.06, 0.07, 0.76), col.lightened(0.06))
		b.box(sofa * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(sx, 0.72, 0.2)), Vector3(1.0, 0.5, 0.14), col.lightened(0.04))
	# throws: a wool one over the far arm, a red one over the back; two little pillows
	b.box(sofa * Transform3D(Basis.IDENTITY, Vector3(-1.76, 0.5, 0.0)), Vector3(0.26, 0.34, 0.95), C_WOOL)
	b.box(sofa * Transform3D(Basis.IDENTITY, Vector3(0.7, 0.85, 0.4)), Vector3(0.9, 0.32, 0.3), C_RUG)
	for sx: float in [-1.45, 1.45]:
		b.box(sofa * Transform3D(Basis(Vector3.FORWARD, 0.3 * signf(sx)), Vector3(sx, 0.65, 0.12)), Vector3(0.4, 0.38, 0.14), C_FABRIC)
	# the armchair
	var arm := _den_seat_xf(DEN_ARMCHAIR)
	var acol := C_LEATHER.lightened(0.05)
	b.box(arm * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.19, 0.0)), Vector3(1.0, 0.38, 0.9), acol)
	b.box(arm * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.415, -0.05)), Vector3(0.66, 0.07, 0.76), acol.lightened(0.06))
	b.box(arm * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.38)), Vector3(1.0, 1.1, 0.24), acol.darkened(0.1))
	for sx: float in [-0.41, 0.41]:
		b.box(arm * Transform3D(Basis.IDENTITY, Vector3(sx, 0.33, 0.0)), Vector3(0.18, 0.66, 0.9), acol.darkened(0.15))
	b.box(arm * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.5)), Vector3(0.7, 0.3, 0.12), C_FABRIC.darkened(0.15))
	# side table by the armchair (the table lamp stands on it)
	var st := Vector3(-11.35, 0.0, 3.0)
	b.block(st + Vector3(-0.25, 0.0, -0.25), st + Vector3(0.25, 0.6, 0.25), C_TIMBER)
	b.cyl(Transform3D(Basis.IDENTITY, st + Vector3(0.0, 0.6, 0.0)), 0.08, 0.06, 0.32, 8, C_STONE_DARK)
	# the floor lamp's stand behind the sofa's far end
	var fl := Vector3(-11.75, 0.0, 7.95)
	b.cyl(Transform3D(Basis.IDENTITY, fl), 0.18, 0.16, 0.04, 10, C_IRON)
	b.rod(fl, fl + Vector3(0.0, 1.42, 0.0), 0.018, 5, C_IRON)
	# split firewood stacked by the hearth
	for r in 4:
		for i in 3:
			var at := Vector3(-12.05 + float(i) * 0.2 + (0.1 if r % 2 == 1 else 0.0), 0.07 + float(r) * 0.13, 7.0)
			b.rod(at, at + Vector3(0.0, 0.0, 0.5), 0.065, 7, C_LOG.darkened(0.1), C_LOG_END)


## A transform for a den seat from its Vector4 (x, z, the x and z it is turned towards): origin
## on the floor at (x, z), -Z towards that point (so +Z is the backrest's side).
static func _den_seat_xf(v: Vector4) -> Transform3D:
	var dir := Vector3(v.z - v.x, 0.0, v.w - v.y).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(v.x, 0.0, v.y))


## "Gather in: Den": the four presenters sit in the den instead of on the podium chairs.
## PRESENTER_1..3 are the sofa's seats (from the fireplace end to the door end) and PRESENTER_4
## is the armchair; each faces the way its seat faces. There are no PODIUM_ meshes in this view
## (the sofa and armchair are always there), so the Presenters tab's on-set switch only shows or
## hides the person.
static func _den_presenters(markers: Node3D) -> void:
	var sofa := _den_seat_xf(DEN_SOFA)
	var seats: Array[Transform3D] = []
	for sx: float in [-1.1, 0.0, 1.1]:
		seats.append(sofa * Transform3D(Basis.IDENTITY, Vector3(sx, DEN_SEAT_Y, -0.05)))
	seats.append(_den_seat_xf(DEN_ARMCHAIR) * Transform3D(Basis.IDENTITY, Vector3(0.0, DEN_SEAT_Y, -0.05)))
	for i in seats.size():
		var at := seats[i].origin
		_marker_facing(markers, "PRESENTER_%d" % (i + 1), at, at - seats[i].basis.z)


# ── Outside the walls ────────────────────────────────────────
## The deck in front of the glass (on posts, with railing, steps, Adirondack chairs and a fire
## table), the covered stoop at the back door, and the woodpile against the left wall.
static func _build_outside_bits(b: Buf) -> void:
	b.block(Vector3(-DECK_HALF, DECK_Y - 0.15, -DECK_DEPTH), Vector3(DECK_HALF, DECK_Y, 0.0), C_DECK)
	for x in [-DECK_HALF + 0.1, -4.0, 0.0, 4.0, DECK_HALF - 0.1]:
		b.block(Vector3(float(x) - 0.1, GROUND_Y, -DECK_DEPTH + 0.05), Vector3(float(x) + 0.1, DECK_Y - 0.15, -DECK_DEPTH + 0.25), C_TIMBER)
	var rail_y := DECK_Y + 1.0
	var front := -DECK_DEPTH + 0.05
	# front railing (with the gap for the steps) and the two side railings
	var runs: Array = [[Vector3(-DECK_HALF, 0, front), Vector3(DECK_STEPS.x, 0, front)], [Vector3(DECK_STEPS.y, 0, front), Vector3(DECK_HALF, 0, front)],
		[Vector3(-DECK_HALF, 0, front), Vector3(-DECK_HALF, 0, -0.1)], [Vector3(DECK_HALF, 0, front), Vector3(DECK_HALF, 0, -0.1)]]
	for r: Array in runs:
		var a: Vector3 = r[0]
		var c: Vector3 = r[1]
		b.rod(Vector3(a.x, rail_y, a.z), Vector3(c.x, rail_y, c.z), 0.05, 6, C_TIMBER)
		var n := maxi(int(a.distance_to(c) / 0.16), 1)
		for i in n + 1:
			var p := a.lerp(c, float(i) / float(n))
			var post := i % 8 == 0 or i == n
			b.block(Vector3(p.x - (0.06 if post else 0.02), DECK_Y, p.z - (0.06 if post else 0.02)), Vector3(p.x + (0.06 if post else 0.02), rail_y, p.z + (0.06 if post else 0.02)), C_TIMBER)
	var steps := 4
	for i in steps:
		var y := DECK_Y - (DECK_Y - GROUND_Y) * float(i + 1) / float(steps + 1)
		b.block(Vector3(DECK_STEPS.x, GROUND_Y, -DECK_DEPTH - 0.28 * float(i + 1)), Vector3(DECK_STEPS.y, y, -DECK_DEPTH - 0.28 * float(i)), C_DECK.darkened(0.05))
	# Adirondack chairs (under the deck seats that face the view) and the fire table's chairs
	for s: Array in SEATS:
		if not String(s[0]).begins_with("Deck"):
			continue
		var at := Vector3(float(s[1]), DECK_Y, float(s[3]))
		var look: Vector3 = s[4]
		var dir := Vector3(look.x - at.x, 0.0, look.z - at.z).normalized()
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), at)      # -Z = the way it faces
		var seat_h := float(s[2]) - DECK_Y
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0.0, seat_h - 0.05, 0.0)), Vector3(0.7, 0.06, 0.6), C_FRAME.lightened(0.2))
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20.0)), Vector3(0.0, seat_h + 0.35, 0.35)), Vector3(0.7, 0.8, 0.06), C_FRAME.lightened(0.2))
		for sx: float in [-0.37, 0.37]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, (seat_h + 0.25) * 0.5, 0.0)), Vector3(0.06, seat_h + 0.25, 0.7), C_FRAME)
	b.block(Vector3(-0.5, DECK_Y, -3.2), Vector3(0.5, DECK_Y + 0.42, -2.7), C_STONE_DARK)
	# the back stoop: a small deck and steps under its own little roof
	b.block(Vector3(-1.1, DECK_Y - 0.15, BACK_Z), Vector3(1.1, DECK_Y, BACK_Z + 1.3), C_DECK)
	for i in 3:
		var y := DECK_Y - (DECK_Y - GROUND_Y) * float(i + 1) / 4.0
		b.block(Vector3(-0.8, GROUND_Y, BACK_Z + 1.3 + 0.28 * float(i)), Vector3(0.8, y, BACK_Z + 1.3 + 0.28 * float(i + 1)), C_DECK.darkened(0.05))
	for sx: float in [-1.0, 1.0]:
		b.rod(Vector3(sx * 1.0, DECK_Y, BACK_Z + 1.2), Vector3(sx * 1.0, 2.5, BACK_Z + 1.2), 0.07, 8, C_LOG, C_LOG_END)
		b.slab(Vector2(sx * 1.4, 2.45), Vector2(0.0, 3.1), BACK_Z + 0.2, BACK_Z + 1.5, 0.12, C_ROOF)
	# the woodpile against the back wall (outside), right of the stoop
	for r in 5:
		for i in 8:
			var x := 2.9 + float(i) * 0.3 + (0.15 if r % 2 == 1 else 0.0)
			if x > 5.3:
				continue
			var y := GROUND_Y + 0.12 + float(r) * 0.22
			b.rod(Vector3(x, y, BACK_Z + 0.3), Vector3(x, y, BACK_Z + 0.85), 0.11, 7, C_LOG.darkened(0.15), C_LOG_END)


## The see-through glass: the two big gable windows either side of the chimney (following the roof
## line), the corner glass doors, and the side and back windows. One mesh with its own
## see-through material, which casts no shadow (so sunlight comes in).
static func _build_glass(parent: Node3D) -> void:
	var g := Buf.new()
	var tint := Color(0.78, 0.86, 0.9, 0.12)
	for sx: float in [-1.0, 1.0]:
		var xo := sx * HALF_W
		var xi := sx * CHIM_HALF
		g.quad(Vector3(xo, 0.0, 0.0), Vector3(xi, 0.0, 0.0), Vector3(xi, roof_y(xi), 0.0), Vector3(xo, roof_y(xo), 0.0), tint)
	for w: Array in WINDOWS:
		var from := float(w[1])
		var to := float(w[2])
		var sill := float(w[3])
		var top := float(w[4])
		match String(w[0]):
			"back":
				g.quad(Vector3(from, sill, BACK_Z), Vector3(to, sill, BACK_Z), Vector3(to, top, BACK_Z), Vector3(from, top, BACK_Z), tint)
			_:
				var x := -HALF_W if String(w[0]) == "left" else HALF_W
				g.quad(Vector3(x, sill, from), Vector3(x, sill, to), Vector3(x, top, to), Vector3(x, top, from), tint)
	for w: Array in DEN_WINDOWS:
		var z := float(w[0])
		g.quad(Vector3(float(w[1]), float(w[3]), z), Vector3(float(w[2]), float(w[3]), z), Vector3(float(w[2]), float(w[4]), z), Vector3(float(w[1]), float(w[4]), z), tint)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(parent, "Glass", g.to_mesh(), m, false)


## The two screens: the big one on the tall chimney above the mantel, and the den's above its
## mantel. The one for the current view is TVScreen (the app puts the picture and the screen
## lights on it); the other is SCREEN_Mirror_<n>, which shows the same picture.
static func _build_screens(parent: Node3D, out: Dictionary, view: String) -> void:
	var great := _screen_quad(parent, "TVScreen" if view != "den" else "SCREEN_Mirror_Great_Room", SCREEN_SIZE,
		Transform3D(Basis.IDENTITY, Vector3(0.0, SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, CHIM_IN_Z + 0.06)))
	# the den's screen faces into the den (+X)
	var den := _screen_quad(parent, "TVScreen" if view == "den" else "SCREEN_Mirror_Den", DEN_SCREEN_SIZE,
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(DEN_CHIM_FACE_X + 0.06, DEN_SCREEN_BOTTOM + DEN_SCREEN_SIZE.y * 0.5, DEN_MID_Z)))
	out["screen"] = den if view == "den" else great


## One screen (a QuadMesh facing its +Z) with a thin dark bezel behind it.
static func _screen_quad(parent: Node3D, node_name: String, size: Vector2, xf: Transform3D) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var screen := MeshInstance3D.new()
	screen.name = node_name
	screen.mesh = quad
	screen.transform = xf
	parent.add_child(screen)
	var bezel := BoxMesh.new()
	bezel.size = Vector3(size.x + 0.08, size.y + 0.08, 0.05)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.03, 0.03, 0.035)
	bm.roughness = 0.4
	var bezel_mi := _add_mesh(parent, "Bezel_" + node_name, bezel, bm)
	bezel_mi.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.03))
	return screen


## The four podiums: high-backed leather armchairs, each its own mesh named PODIUM_n so the app
## shows it only while that presenter is on set, with PRESENTER_n on its seat (the bottom centre
## of the presenter's picture), facing the audience.
static func _build_podiums(parent: Node3D, markers: Node3D, mat: Material) -> void:
	for i in PODIUMS.size():
		var p := PODIUMS[i]
		var at := Vector3(p.x, 0.0, p.y)
		var b := Buf.new()
		# local axes: +Z = the way the chair faces (towards the audience)
		var col := C_LEATHER.darkened(0.1)
		b.block(Vector3(-0.45, 0.0, -0.4), Vector3(0.45, PODIUM_SEAT_Y, 0.4), col)
		b.block(Vector3(-0.45, 0.0, -0.45), Vector3(0.45, 1.25, -0.25), col.darkened(0.1))
		b.block(Vector3(-0.55, 0.0, -0.45), Vector3(-0.42, 0.68, 0.4), col.darkened(0.15))
		b.block(Vector3(0.42, 0.0, -0.45), Vector3(0.55, 0.68, 0.4), col.darkened(0.15))
		var chair := _add_mesh(parent, "PODIUM_%d" % (i + 1), b.to_mesh(), mat)
		var marker := _marker_facing(markers, "PRESENTER_%d" % (i + 1), at + Vector3(0.0, PODIUM_SEAT_Y, 0.0), at + Vector3(0.0, 0.0, 5.0))
		chair.transform = Transform3D(marker.transform.basis, at)


## The lamps: two table lamps, the chandelier, the pendant over the dining table and the lantern
## by the back door. Each is a LAMP_ marker under LIGHTS_House (Room turns it into a light and
## dims it with the house lights) plus a glowing shade or candle flames (glow_mat, whose glow the
## room script sets from the house light level).
static func _build_lamps(parent: Node3D, room: Node3D, out: Dictionary) -> void:
	var house := Node3D.new()
	house.name = "LIGHTS_House"
	room.add_child(house)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.86, 0.62)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.7, 0.4)
	glow.emission_energy_multiplier = 1.5
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	out["glow_mat"] = glow
	var shades := Buf.new()
	var lamps: Array = [
		["LAMP_Table_Left", Vector3(-5.6, 1.15, 2.6), "shade"],
		["LAMP_Table_Right", Vector3(4.95, 1.15, 2.9), "shade"],
		["LAMP_Chandelier", Vector3(0.0, 5.05, 3.0), "candles"],
		["LAMP_Dining", Vector3(-3.4, 1.8, 7.0), "pendant"],
		["LAMP_Back_Door", Vector3(0.8, 2.15, BACK_Z + 0.25), "lantern"],
		["LAMP_Den_Table", Vector3(-11.35, 1.2, 3.0), "shade"],
		["LAMP_Den_Floor", Vector3(-11.75, 1.6, 7.95), "shade"],
	]
	for l: Array in lamps:
		var at: Vector3 = l[1]
		var lamp := Marker3D.new()
		lamp.name = String(l[0])
		house.add_child(lamp)
		lamp.position = at
		match String(l[2]):
			"shade":
				shades.cyl(Transform3D(Basis.IDENTITY, at - Vector3(0.0, 0.2, 0.0)), 0.24, 0.14, 0.28, 12, C_WOOL)
			"pendant":
				shades.cyl(Transform3D(Basis.IDENTITY, at - Vector3(0.0, 0.05, 0.0)), 0.32, 0.08, 0.15, 14, C_FABRIC.lightened(0.2))
			"lantern":
				shades.block(at - Vector3(0.1, 0.15, 0.1), at + Vector3(0.1, 0.15, 0.1), C_WOOL)
			"candles":
				for i in 12:
					var a := TAU * float(i) / 12.0
					shades.cyl(Transform3D(Basis.IDENTITY, at + Vector3(cos(a) * 0.65, 0.0, sin(a) * 0.65)), 0.025, 0.02, 0.14, 6, C_WOOL)
	_add_mesh(parent, "LampGlow", shades.to_mesh(), glow, false)


## The camera views, and the reaction targets (things chat can throw at: "fireplace", "chandelier",
## "deck"). In the den view the den's cameras come first and "fireplace" is the den's fire.
static func _build_markers(markers: Node3D, view: String) -> void:
	var cams: Array = []
	if view == "den":
		cams.append_array(DEN_CAMERAS)
		for c: Array in CAMERAS:
			# renumber the great room's after the den's ("01_Loft" -> "05_Loft"); only the den's
			# own Reaction camera keeps "Reaction" in its name
			var parts := String(c[0]).split("_", false, 1)
			var label := String(parts[1]).replace("Reaction_", "")
			cams.append(["%02d_%s" % [int(parts[0]) + DEN_CAMERAS.size(), label], c[1], c[2]])
	else:
		cams.append_array(CAMERAS)
	for c: Array in cams:
		var cam := Marker3D.new()
		cam.name = "CAM_" + String(c[0])
		markers.add_child(cam)
		cam.transform = Transform3D(Basis.IDENTITY, c[1]).looking_at(c[2], Vector3.UP)
	for s: Array in SEATS:
		var at := Vector3(float(s[1]), float(s[2]), float(s[3]))
		var toward: Vector3 = Vector3(0.0, 0.0, CHIM_IN_Z) if s[4] is String else s[4]
		_marker_facing(markers, "AUDIENCE_" + String(s[0]), at, toward)
	if view == "den":
		_marker_facing(markers, "TARGET_Fireplace", Vector3(DEN_CHIM_FACE_X + 0.2, 0.75, DEN_MID_Z), Vector3(-7.0, 0.0, DEN_MID_Z))
	else:
		_marker_facing(markers, "TARGET_Fireplace", Vector3(0.0, 0.8, CHIM_IN_Z + 0.2), Vector3(0.0, 0.0, 8.0))
	_marker_facing(markers, "TARGET_Chandelier", Vector3(0.0, 5.0, 3.0), Vector3(0.0, 0.0, 8.0))
	_marker_facing(markers, "TARGET_Deck", Vector3(0.0, 0.4, -2.9), Vector3(0.0, 0.0, 8.0))


# ── The placeholder outside ──────────────────────────────────
## Stands in for the real scenery until the scene rooms are built: a flat grassy clearing, a ring
## of simple cone trees that leaves the view in front open, and a few far hills.
static func _build_clearing(parent: Node3D) -> void:
	var g := Buf.new()
	var size := 160.0
	g.quad(Vector3(-size, GROUND_Y, -size), Vector3(size, GROUND_Y, -size), Vector3(size, GROUND_Y, size), Vector3(-size, GROUND_Y, size), C_GRASS)
	# a trodden path from the deck steps out towards the view, and from the back stoop
	g.quad(Vector3(6.2, GROUND_Y + 0.01, -5.0), Vector3(7.4, GROUND_Y + 0.01, -5.0), Vector3(7.0, GROUND_Y + 0.01, -16.0), Vector3(5.8, GROUND_Y + 0.01, -16.0), C_GRASS.darkened(0.25).lerp(Color(0.45, 0.38, 0.28), 0.6))
	g.quad(Vector3(-0.7, GROUND_Y + 0.01, 11.2), Vector3(0.7, GROUND_Y + 0.01, 11.2), Vector3(1.6, GROUND_Y + 0.01, 22.0), Vector3(0.2, GROUND_Y + 0.01, 22.0), C_GRASS.darkened(0.25).lerp(Color(0.45, 0.38, 0.28), 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var planted := 0
	var tries := 0
	while planted < 170 and tries < 3000:
		tries += 1
		var r := rng.randf_range(15.0, 70.0)
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * r, sin(a) * r)
		# keep the view in front of the deck open (a wedge towards -Z)
		if p.y < -10.0 and absf(p.x) < -p.y * 0.9:
			continue
		var h := rng.randf_range(7.0, 15.0)
		var foot := Vector3(p.x, GROUND_Y, p.y)
		g.cyl(Transform3D(Basis.IDENTITY, foot), 0.22, 0.16, h * 0.35, 6, C_TIMBER.darkened(0.3))
		var green := Color(0.13, 0.26, 0.15).lightened(rng.randf_range(0.0, 0.12))
		g.cyl(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, h * 0.2, 0.0)), h * 0.22, 0.0, h * 0.55, 8, green)
		g.cyl(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, h * 0.5, 0.0)), h * 0.16, 0.0, h * 0.5, 8, green.lightened(0.05))
		planted += 1
	# far hills across the view, layered and bluer with distance
	for i in 9:
		var x := -160.0 + float(i) * 40.0 + rng.randf_range(-10.0, 10.0)
		var z := -150.0 - rng.randf_range(0.0, 60.0)
		var col := Color(0.33, 0.42, 0.5).lerp(Color(0.55, 0.62, 0.7), clampf((-z - 150.0) / 60.0, 0.0, 1.0))
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(x, GROUND_Y - 1.0, z)), rng.randf_range(45.0, 70.0), 0.0, rng.randf_range(22.0, 40.0), 10, col)
	var m := _flat_material(0.95)
	_add_mesh(parent, "Clearing", g.to_mesh(), m, true)
