extends RefCounted
## Builds the Lakeside Campfire's set out of plain shapes, in code: the ground with its lake bed
## and stream bed, the two sheets of water, the forest, the tents, the log benches, the camp
## chairs, the fire pit, the big screen on its posts, the string lights, the dock,
## and every marker the app looks for (rooms/room.gd lists them: TVScreen, CAM_*, PRESENTER_n,
## PODIUM_n, AUDIENCE_*, TARGET_*, LIGHTS_House with LAMP_* inside).
##
## Called once by rooms/campfire/campfire_room.gd (_ready, before anything reads the room), which
## keeps the Dictionary build() returns: the materials and nodes it animates afterwards.
## There is no Blender model for this room: to move or resize something, change the numbers in
## the "Layout" block below; everything else follows from them.
##
## Axes (metres): the campfire is at the origin and the ground there is y = 0. -Z is north (the
## big screen, then the lake), +Z is south (the benches, then the main camera), +X is east.
## Markers that "face" something follow the app's rule: +Z points at what they face, except
## cameras, which look along -Z.

const WATER_SHADER := preload("res://rooms/campfire/camp_water.gdshader")
const STREAM_SHADER := preload("res://rooms/campfire/camp_stream.gdshader")
const GROUND_SHADER := preload("res://rooms/campfire/camp_ground.gdshader")
const PROP_SHADER := preload("res://rooms/campfire/camp_prop.gdshader")
## The detailed trees, grass tufts and ferns (see _build_detailed_plants).
const Trees := preload("res://rooms/campfire/campfire_trees.gd")
## The photo textures (CC0, made by textures/make_textures.py).
const TEX := "res://rooms/campfire/textures/"

# ── Layout ───────────────────────────────────────────────────
## The lake's surface (y). The ground dips below it north of shore_z().
const WATER_Y: float = -0.3
## The big screen: its middle is this far north of the fire; width x height; bottom edge height.
const SCREEN_Z: float = -6.5
const SCREEN_SIZE: Vector2 = Vector2(7.2, 4.05)
const SCREEN_BOTTOM: float = 1.5
## The two posts the screen hangs between: metres either side of the middle, and their height.
const POST_X: float = 3.85
const POST_H: float = 6.0
## The four camp chairs (the podiums): metres from the fire, and where on the circle (degrees;
## -90 = due north of the fire, so they sit on the far side facing the main camera).
const CHAIR_RADIUS: float = 2.7
const CHAIR_DEGREES: Array[float] = [-150.0, -110.0, -70.0, -30.0]
## Height of a chair's seat, where the presenter's picture stands.
const CHAIR_SEAT_Y: float = 0.42
## The chat audience's log benches: [metres from the fire, seats] per row, on an arc south of
## the fire from ROW_ARC.x to ROW_ARC.y degrees (90 = due south). 8 + 10 + 12 = 30 seats.
const ROWS: Array = [[4.6, 8], [6.1, 10], [7.6, 12]]
const ROW_ARC: Vector2 = Vector2(18.0, 162.0)
## A bench's sitting height above the ground under it.
const BENCH_Y: float = 0.42
## The tents: [x, z, turn in degrees (0 = door facing south), kind ("dome" / "tunnel"),
## main colour, second colour].
const TENTS: Array = [
	[-10.0, -1.4, 110.0, "dome", Color(0.1, 0.42, 0.4), Color(0.75, 0.78, 0.72)],
	[10.5, -1.75, -105.0, "dome", Color(0.78, 0.5, 0.08), Color(0.2, 0.2, 0.22)],
	[10.9, 4.6, -70.0, "tunnel", Color(0.3, 0.24, 0.6), Color(0.72, 0.7, 0.8)],
]
## The stream's middle line from the lake back up into the hills: x, the water's height, z.
const STREAM: Array[Vector3] = [
	Vector3(-9.0, -0.3, -10.6), Vector3(-9.6, -0.12, -8.6), Vector3(-11.6, -0.1, -5.5), Vector3(-12.7, -0.07, -1.25),
	Vector3(-14.0, -0.03, 1.5), Vector3(-15.3, 0.03, 3.2), Vector3(-19.5, 0.6, 7.5), Vector3(-26.0, 1.8, 11.5),
	Vector3(-35.0, 3.6, 15.0), Vector3(-48.0, 6.5, 18.0),
]
## The stream's water is between 2 x STREAM_NARROW and 2 x STREAM_WIDE metres across
## (stream_half_width), and STREAM_DEPTH metres deep in the middle.
const STREAM_NARROW: float = 0.5
const STREAM_WIDE: float = 1.4
const STREAM_DEPTH: float = 0.4
## The stream's own strip of ground (_build_stream) reaches this far each side of its middle.
const STREAM_BED_HALF: float = 4.1
## Uphill from the camp the stream comes down in steps: level pools this much apart in height
## (metres), each ending in a short drop (stream_steps).
const STREAM_STEP: float = 0.45
## Which of the fire ring's 11 stones is Pebble (_build_pebble): counted from due east of the
## fire round by the south, so 3 is the one on the audience's side nearest the main camera.
const PEBBLE_STONE: int = 3
## Where the things beside the fire stand (x, z).
const STICK_PILE: Vector2 = Vector2(4.2, 0.6)
const SMORES_TABLE: Vector2 = Vector2(-4.3, 0.6)
## The dock: its middle line's x, and the z of its land end and its lake end.
const DOCK_X: float = 5.7
const DOCK_Z: Vector2 = Vector2(-7.6, -12.6)
## The poles the string lights hang from (besides the screen's two posts): x, height, z.
## How many of the string light lines carry a real lamp (the first ones in _build_lights' list).
const LAMP_LINES: int = 3
const LIGHT_POLES: Array[Vector3] = [Vector3(-9.0, 3.6, 0.4), Vector3(9.4, 3.6, 0.0), Vector3(9.9, 3.6, 3.2)]
## The ground mesh: it covers GROUND_HALF metres each way from the fire, in squares this big.
const GROUND_HALF: float = 78.0
const GROUND_CELL: float = 1.5
## How many trees are tried / at most planted, and how far out the forest goes.
const TREE_TRIES: int = 2600
const TREE_MAX: int = 620
const FOREST_RADIUS: float = 66.0
## Tree sway: metres per unit of tree, so a 10 m fir's top moves 20 cm in a light breeze.
const TREE_SWAY: float = 0.02
## "Set detail: Detailed near the fire" draws the forest's trees detailed inside this radius
## (metres from the fire, in the clearing's oval) and low-poly beyond it.
const NEAR_RADIUS: float = 30.0
## Grass tufts and ferns (detailed looks only): how many at most, and how far out they grow.
const GRASS_MAX: int = 1500
const FERN_MAX: int = 320
const UNDERGROWTH_RADIUS: float = 21.0
## The close woods (_build_close_woods). The wall along the shore: half its length along x,
## the nearest its front row comes to the screen (z) and the metres between trees. CLOSE_SLIM: how wide those firs are as a
## share of their height (from, to); at most 0.3, or a 10 m fir's branches reach the screen.
const CLOSE_WALL_HALF: float = 17.0
const CLOSE_WALL_Z: float = -7.6
const CLOSE_WALL_STEP: float = 0.5
const CLOSE_SLIM: Vector2 = Vector2(0.22, 0.3)
## The horseshoe: the two walls of trees down the sides that make the clearing a cul-de-sac.
## Each starts beside the screen at CLOSE_SIDE_START (x, z; mirrored for the other side), widens
## to CLOSE_SIDE_RADIUS metres from the fire level with it, then follows that circle round
## behind the benches' ends and stops where |x| gets down to CLOSE_SIDE_OPEN, which leaves the
## mouth the main camera looks in through. CLOSE_SIDE_STEP: metres between trees along it.
const CLOSE_SIDE_START: Vector2 = Vector2(5.3, -7.2)
const CLOSE_SIDE_RADIUS: float = 9.0
const CLOSE_SIDE_OPEN: float = 6.5
const CLOSE_SIDE_STEP: float = 0.4
## The belt round the clearing: from / to as a radius in the clearing's oval, how many places
## are tried, the least metres between two trunks, and the room kept clear round each camera.
const CLOSE_RING: Vector2 = Vector2(8.4, 15.0)
const CLOSE_TRIES: int = 2400
const CLOSE_GAP: float = 1.25
const CLOSE_CAMERA_GAP: float = 1.25
## Which photo "detail" texture a shape gets when the set is drawn detailed (Buf.mat; see
## camp_prop.gdshader, which holds the matching list): 0 = none, plain colour.
const MAT_PLAIN: float = 0.0
const MAT_BARK: float = 1.0
const MAT_ROCK: float = 2.0
const MAT_PLANKS: float = 3.0
const MAT_FABRIC: float = 4.0
const MAT_BARK_OAK: float = 5.0
const MAT_BARK_BIRCH: float = 6.0
## Camera views: [name (after "CAM_"; the leading number sets the order), where it stands, what
## it looks at]. The one with "Reaction" in its name is used for react pauses.
const CAMERAS: Array = [
	["01_Campfire", Vector3(0.0, 2.3, 11.6), Vector3(0.0, 2.2, -3.0)],
	["02_Fireside_Right", Vector3(6.6, 1.3, 5.2), Vector3(-1.2, 1.5, -2.0)],
	["03_Fireside_Left", Vector3(-6.6, 1.3, 5.2), Vector3(1.2, 1.5, -2.0)],
	["04_From_The_Screen", Vector3(2.4, 2.6, -5.4), Vector3(-0.6, 0.9, 4.0)],
	["05_Tent_View", Vector3(6.3, 1.5, -3.9), Vector3(-2.0, 1.1, 1.0)],
	["06_Lake_Shore", Vector3(-10.2, 1.7, -4.2), Vector3(6.0, 1.6, -9.0)],
	["07_Drone", Vector3(0.0, 15.0, 16.0), Vector3(0.0, 0.0, -3.0)],
	["08_Marshmallows", Vector3(0.0, 0.95, 2.6), Vector3(0.0, 1.25, -2.4)],
	["09_Reaction", Vector3(0.0, 1.7, 4.6), Vector3(0.0, 1.5, -2.6)],
	["10_Lake_And_Sky", Vector3(0.0, 1.6, -9.1), Vector3(0.0, 5.5, -40.0)],
]

## The noise the ground's bumps and hills come from (made once; the same on every PC).
static var _noise: FastNoiseLite
## The stream's middle line with the bends rounded off (smooth_stream), built on first use.
static var _stream_fine: Array[Vector3] = []


# ── Where the ground is ──────────────────────────────────────
static func _setup_noise() -> void:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 4242
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.045
		_noise.fractal_octaves = 3


## The z of the lake's near shore at this x: gently wavy, curving away to the north at the sides.
static func shore_z(x: float) -> float:
	return -8.6 + 0.5 * sin(x * 0.31) + 0.35 * sin(x * 0.13 + 1.0) - 0.0016 * x * x


## The stream's middle line as many short straight pieces (a smooth curve through STREAM).
static func smooth_stream() -> Array[Vector3]:
	if _stream_fine.is_empty():
		for i in STREAM.size() - 1:
			var p0 := STREAM[maxi(i - 1, 0)]
			var p1 := STREAM[i]
			var p2 := STREAM[i + 1]
			var p3 := STREAM[mini(i + 2, STREAM.size() - 1)]
			for k in 6:
				var t := float(k) / 6.0
				_stream_fine.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
		_stream_fine.append(STREAM[STREAM.size() - 1])
	return _stream_fine


## For a point on the map: x = metres to the stream's middle line, y = the water's height there.
## Far from the stream (east of the fire, or beyond its ends) it returns a large distance.
static func stream_near(x: float, z: float) -> Vector2:
	if x > -5.0 or x < -52.0:
		return Vector2(99.0, 0.0)
	var pts := smooth_stream()
	var best := 1e9
	var water := 0.0
	var p := Vector2(x, z)
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			water = lerpf(pts[i].y, pts[i + 1].y, t)
	return Vector2(sqrt(best), stream_steps(water))


## Turns the stream's even slope into steps: above the camp's level the water lies in level
## pools about STREAM_STEP apart in height, and falls from one to the next over the last
## fifth of each stretch (a little cascade). The sine makes some pools long and some short,
## so it doesn't look like a staircase (it is small enough that the water never runs uphill).
## y = the evenly sloping height from STREAM; below 0 (the flat run past the camp) it is left
## as it is.
static func stream_steps(y: float) -> float:
	if y <= 0.0:
		return y
	var k := y / STREAM_STEP + 0.3 * sin(y * 2.9) + 0.12 * sin(y * 7.3)
	return STREAM_STEP * (floorf(k) + smoothstep(0.8, 1.0, k - floorf(k)))


## Half the width of the stream's water near a point (metres): it narrows and widens into
## pools along its way (noise), as a real brook does. ground_height() digs the bed this wide.
static func stream_half_width(x: float, z: float) -> float:
	_setup_noise()
	return lerpf(STREAM_NARROW, STREAM_WIDE, clampf(0.5 + 0.9 * _noise.get_noise_2d(x * 3.2 + 50.0, z * 3.2 - 20.0), 0.0, 1.0))


## The stream's middle line as short pieces `step` metres long (finer than smooth_stream, for
## the water's ribbon and for placing rocks): x, z from the smooth line, y = the water's height
## there with its steps (stream_near).
static func stream_fine(step: float) -> Array[Vector3]:
	var pts := smooth_stream()
	var fine: Array[Vector3] = []
	for i in pts.size() - 1:
		var gap := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		var n := maxi(1, int(ceilf(gap / step)))
		for k in n:
			var p := pts[i].lerp(pts[i + 1], float(k) / float(n))
			fine.append(Vector3(p.x, stream_near(p.x, p.z).y, p.z))
	var last := pts[pts.size() - 1]
	fine.append(Vector3(last.x, stream_steps(last.y), last.z))
	return fine


## The rocks in and beside the stream, the same every time (its own random numbers): each is
## x, z, its size (metres) and 1 if it stands in the water (0 = on the bank). Three kinds:
## a line of rocks across the top of every little cascade, boulders on the banks, and loose
## stones in the water's edge. _build_camp_props makes them; _build_stream puts foam round
## the ones in the water.
static var _stream_rocks: Array[Vector4] = []
static func stream_rocks() -> Array[Vector4]:
	if not _stream_rocks.is_empty():
		return _stream_rocks
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var pts := stream_fine(0.4)
	var since_ledge := 9.0
	for i in range(3, pts.size() - 3):
		var along := pts[i + 1] - pts[i - 1]
		var side := Vector3(along.x, 0.0, along.z).normalized().cross(Vector3.UP)
		var half := stream_half_width(pts[i].x, pts[i].z)
		since_ledge += 0.4
		# a ledge where the water starts to drop
		if pts[i + 1].y - pts[i].y > 0.02 and since_ledge > 1.6 and pts[i].x > -40.0:
			since_ledge = 0.0
			# a broken row: rocks of mixed sizes, some up or down the stream a little, with
			# gaps the water pours through
			var u := -half - 0.25
			while u < half + 0.4:
				var size := rng.randf_range(0.16, 0.36) if rng.randf() < 0.7 else rng.randf_range(0.45, 0.62)
				var shift := rng.randf_range(-0.3, 0.3)
				var back := Vector3(along.x, 0.0, along.z).normalized() * shift
				if rng.randf() < 0.72:
					_stream_rocks.append(Vector4(pts[i].x + side.x * u + back.x, pts[i].z + side.z * u + back.z, size, 1.0))
				u += size * rng.randf_range(1.5, 2.4)
		elif rng.randf() < 0.16 and pts[i].x > -40.0:
			# a loose stone at the water's edge, or (one in five) a boulder up the bank
			var bank := -1.0 if rng.randf() < 0.5 else 1.0
			if rng.randf() < 0.2:
				var u2 := bank * (half + rng.randf_range(0.5, 1.3))
				_stream_rocks.append(Vector4(pts[i].x + side.x * u2, pts[i].z + side.z * u2, rng.randf_range(0.55, 0.95), 0.0))
			else:
				var u3 := bank * half * rng.randf_range(0.5, 1.15)
				_stream_rocks.append(Vector4(pts[i].x + side.x * u3, pts[i].z + side.z * u3, rng.randf_range(0.14, 0.4), 1.0 if absf(u3) < half else 0.0))
	return _stream_rocks


## The ground's height (y) at a point: flat round the camp, a low bank under the benches so the
## back rows see over the front ones, hills with the forest on them further out, the lake's bed
## north of the shore and the stream's bed along STREAM.
static func ground_height(x: float, z: float) -> float:
	_setup_noise()
	var from_fire := Vector2(x, z).length()
	var oval := Vector2(x / 1.25, z).length()                # the clearing is wider than it is deep
	var h := _noise.get_noise_2d(x, z) * 0.14 * smoothstep(8.0, 14.0, oval)
	h += 0.22 * clampf((from_fire - 5.3) / 1.5, 0.0, 2.2) * smoothstep(0.5, 2.5, z)
	var in_lake := shore_z(x) - z                            # above 0 = north of the shore line
	var hills := 2.5 + 7.0 * (0.5 + 0.5 * _noise.get_noise_2d(x * 0.5 + 90.0, z * 0.5))
	h += hills * smoothstep(15.0, 50.0, oval) * smoothstep(2.0, -6.0, in_lake)
	h = lerpf(h, WATER_Y - 1.3, smoothstep(-0.6, 3.0, in_lake))
	# the stream: a shallow dish under the water (deepest in the middle), then a bank that
	# climbs gently from the waterline and has melted into the land around by 2.6 m out.
	# Lower ground is raised to it as well, so the water never hangs over a dip.
	var s := stream_near(x, z)
	var half := stream_half_width(x, z)
	if s.x < half + 2.6 and in_lake < 1.0:
		var bed := s.y - STREAM_DEPTH * smoothstep(half, half * 0.2, s.x)
		if s.x > half:
			bed = s.y + 0.03 + 0.22 * (s.x - half)
		elif in_lake < 0.0 and z < -7.4:
			bed = maxf(bed, WATER_Y + 0.02)       # (where the lake's sheet reaches south of the shore, z < -7.7, the bed stays above it)
		var keep := smoothstep(half + 0.5, half + 2.6, s.x)        # 0 = the stream's shape, 1 = the land's own
		h = lerpf(bed, h, maxf(keep, smoothstep(0.0, 1.0, in_lake)))
	return h


## What the ground is at a point, as the ground mesh's vertex colour (camp_ground.gdshader):
## r = trodden dirt (round the fire, under the benches), g = sand and gravel (the shore, the
## stream's bed), b = forest floor; all three 0 = grass. _build_ground colours the ground with
## it and _build_undergrowth asks it where grass and ferns may grow.
static func ground_kind(x: float, z: float) -> Color:
	var from_fire := Vector2(x, z).length()
	var oval := Vector2(x / 1.25, z).length()
	var in_lake := shore_z(x) - z
	var dirt := 1.0 - smoothstep(2.6, 4.2, from_fire)
	for row: Array in ROWS:           # trodden ground under each bench row
		dirt = maxf(dirt, (1.0 - smoothstep(0.5, 1.3, absf(from_fire - float(row[0])))) * smoothstep(-0.5, 1.0, z))
	var sand := smoothstep(-2.2, -0.4, in_lake)
	# the stream: gravel in its bed and on a narrow, ragged strip of bank (wider in places)
	_setup_noise()
	var margin := 0.1 + 0.55 * clampf(0.5 + _noise.get_noise_2d(x * 5.0 - 70.0, z * 5.0 + 30.0), 0.0, 1.0)
	var past_water := stream_near(x, z).x - stream_half_width(x, z)
	sand = maxf(sand, 1.0 - smoothstep(margin * 0.4, margin, past_water))
	var forest := smoothstep(11.5, 15.0, oval) * (1.0 - sand)
	return Color(dirt, sand, forest)


## A point on a circle round the fire, on the ground: degrees as in CHAIR_DEGREES / ROW_ARC.
static func ring_point(radius: float, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees)
	var x := radius * cos(a)
	var z := radius * sin(a)
	return Vector3(x, ground_height(x, z), z)


# ── A mesh being put together ────────────────────────────────
## Collects flat-shaded, coloured triangles and turns them into one mesh. Every shape below adds
## to one of these, so a whole group of objects is a single mesh with a single material.
class Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	## Which detail texture the shapes added from now on get (a MAT_ constant; it goes into
	## every corner's UV.x, where camp_prop.gdshader reads it). Set it before adding shapes.
	var mat: float = 0.0

	## One triangle. The normal comes from the corner order, and the material draws both sides,
	## so the order never makes a face vanish.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		tri_round(a, b, c, n, n, n, col)

	## One triangle with a normal given for each corner (for round things: a log's side is
	## shaded as a curve, not as flat strips).
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
		uvs.append_array([Vector2(mat, 0.0), Vector2(mat, 0.0), Vector2(mat, 0.0)])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, c, b, col)
		tri(a, d, c, col)

	## A box: xf places its centre and turns it, size is its full width, height and depth.
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

	## A cylinder or cone standing on xf's origin along its Y axis: r0 at the bottom, r1 at the
	## top (0 = a point), h tall. cap = the colour of the flat ends (a log's cut wood).
	func cyl(xf: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var end := col if cap.a == 0.0 else cap
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var b0 := xf * Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
			var b1 := xf * Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
			var t0 := xf * Vector3(cos(a0) * r1, h, sin(a0) * r1)
			var t1 := xf * Vector3(cos(a1) * r1, h, sin(a1) * r1)
			# the side is shaded round: each corner's normal points straight out from the axis
			# (tilted for a cone), except that a flat-sided look is kept for shapes of 5 sides
			# or fewer (thin sticks and ropes, where it can't be seen)
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

	## A cylinder from one point to another (a pole, a log, a rope).
	func rod(from: Vector3, to: Vector3, radius: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var axis := to - from
		if axis.length() < 0.001:
			return
		var up := axis.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		cyl(Transform3D(Basis(side, up, side.cross(up)), from), radius, radius, axis.length(), segs, col, cap)

	## A lumpy ball (a rock, a tree's crown): radii per axis, `lump` = how uneven (0 = smooth),
	## top and bottom colours blended by height.
	func blob(centre: Vector3, radii: Vector3, segs: int, rings: int, top: Color, bottom: Color, lump: float, rng: RandomNumberGenerator) -> void:
		var grid: Array = []
		for r in rings + 1:
			var row: Array[Vector3] = []
			var lat := PI * float(r) / float(rings)
			for s in segs:
				var lon := TAU * float(s) / float(segs)
				var k := 1.0 + (rng.randf() - 0.5) * lump if r > 0 and r < rings else 1.0
				row.append(centre + Vector3(sin(lat) * cos(lon) * radii.x, cos(lat) * radii.y, sin(lat) * sin(lon) * radii.z) * k)
			grid.append(row)
		for r in rings:
			var col := bottom.lerp(top, 1.0 - (float(r) + 0.5) / float(rings))
			for s in segs:
				var s1 := (s + 1) % segs
				quad(grid[r][s], grid[r][s1], grid[r + 1][s1], grid[r + 1][s], col)

	## Sets every corner's alpha from its height: 0 at y = 0 up to 1 at y = top (the trees'
	## sway weight, see camp_prop.gdshader).
	func alpha_by_height(top: float) -> void:
		for i in verts.size():
			var c := colors[i]
			c.a = clampf(verts[i].y / top, 0.0, 1.0)
			colors[i] = c

	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		if not verts.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## A camp_prop.gdshader material with the detail textures on it. They only show while its
## `detail` is 1: campfire_room.gd's _apply_detail() sets that on every material listed in
## out["detail_mats"], so add each new one to that list (_note_material does it).
static func _prop_material(sway: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("sway", sway)
	# the shader's sampler names and the pictures that go in them (the MAT_ numbers' order)
	var pictures := {"tex_bark": "detail_bark_pine.jpg", "tex_rock": "detail_rock.jpg", "tex_planks": "detail_planks.jpg",
		"tex_fabric": "detail_fabric.jpg", "tex_bark_oak": "detail_bark_oak.jpg", "tex_bark_birch": "detail_bark_birch.jpg"}
	for key: String in pictures:
		m.set_shader_parameter(key, load(TEX + String(pictures[key])))
	return m


## Puts a material on out["detail_mats"], the list the room script works through to set
## `detail` 0 / 1 from the Set detail choice (campfire_room.gd _apply_detail). Not for the
## detailed plants' own materials: those are only ever drawn detailed.
static func _note_material(out: Dictionary, m: ShaderMaterial) -> void:
	if not out.has("detail_mats"):
		var empty: Array[ShaderMaterial] = []
		out["detail_mats"] = empty
	(out["detail_mats"] as Array[ShaderMaterial]).append(m)


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


# ── The whole set ────────────────────────────────────────────
## Builds everything under `room`. Returns what the room script goes on using:
##   ground_mat, prop_mat, tent_mat, tree_mat (ShaderMaterial): for glow,
##   lake_mat, stream_mat (ShaderMaterial): the lake's and the stream's water,
##   ember_mat, bulb_mat (StandardMaterial3D): the fire's coals and the string lights' bulbs,
##   bulbs (MultiMeshInstance3D): the string lights,
##   screen (MeshInstance3D "TVScreen"), screen_back (MeshInstance3D): shown / hidden together,
##   fire (Marker3D "FIRE_Camp"): bottom centre of the flames,
##   close_woods (Array[Node3D]): the close woods' low-poly trees, built hidden (see _build_close_woods),
##   lowpoly_near, lowpoly_far (Array[Node3D]): the forest's low-poly trees, near and far (is_near),
##   detail_near, detail_far, close_woods_detail, undergrowth (Node3D): the detailed plants,
##     built hidden (see _build_detailed_plants),
##   detail_mats (Array[ShaderMaterial]): see _note_material.
static func build(room: Node3D) -> Dictionary:
	_setup_noise()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113              # the same forest on every PC
	var out: Dictionary = {}
	var set_root := Node3D.new()
	set_root.name = "Set"
	room.add_child(set_root)
	var markers := Node3D.new()
	markers.name = "Markers"
	room.add_child(markers)

	_build_ground(set_root, out)
	_build_water(set_root, out)
	_build_stream(set_root, out)
	_build_forest(set_root, out, rng)
	var props := Buf.new()            # everything small and solid shares this mesh
	_build_fire_pit(props, set_root, markers, out, rng)
	_build_benches(props, markers)
	_build_camp_things(props, rng)
	_build_wild(props)
	_build_screen(props, set_root, out)
	out["prop_mat"] = _prop_material()
	_note_material(out, out["prop_mat"])
	_add_mesh(set_root, "CampProps", props.to_mesh(), out["prop_mat"])
	_build_chairs(set_root, markers, out["prop_mat"])
	_build_tents(set_root, out)
	_build_lights(set_root, room, out)
	_build_markers(markers)
	return out


## The ground: a grid of squares whose corners sit at ground_height(), coloured by what the
## ground is there (see camp_ground.gdshader for what the colours mean).
static func _build_ground(parent: Node3D, out: Dictionary) -> void:
	var n := int(GROUND_HALF * 2.0 / GROUND_CELL)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			var gx := -GROUND_HALF + ix * GROUND_CELL
			var gz := -GROUND_HALF + iz * GROUND_CELL
			# (near the stream these big squares are too coarse for its bed: they duck under the
			# stream's own fine strip of ground, see _build_stream)
			heights[iz * (n + 1) + ix] = ground_height(gx, gz) - 0.6 * smoothstep(STREAM_BED_HALF - 0.2, STREAM_BED_HALF - 1.4, stream_near(gx, gz).x)
	for iz in n + 1:
		for ix in n + 1:
			var x := -GROUND_HALF + ix * GROUND_CELL
			var z := -GROUND_HALF + iz * GROUND_CELL
			var h := heights[iz * (n + 1) + ix]
			verts.append(Vector3(x, h, z))
			# the slope from the neighbours' heights
			var hl := heights[iz * (n + 1) + maxi(ix - 1, 0)]
			var hr := heights[iz * (n + 1) + mini(ix + 1, n)]
			var hu := heights[maxi(iz - 1, 0) * (n + 1) + ix]
			var hd := heights[mini(iz + 1, n) * (n + 1) + ix]
			normals.append(Vector3(hl - hr, 2.0 * GROUND_CELL, hu - hd).normalized())
			colors.append(ground_kind(x, z))
	for iz in n:
		for ix in n:
			var i := iz * (n + 1) + ix
			indices.append_array([i, i + 1, i + n + 1, i + 1, i + n + 2, i + n + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	for kind: String in ["grass", "forest", "dirt", "sand"]:
		mat.set_shader_parameter("tex_" + kind, load(TEX + "ground_%s.jpg" % kind))
	out["ground_mat"] = mat
	_note_material(out, mat)
	_add_mesh(parent, "Ground", mesh, mat, false)


## The lake (one huge flat sheet north of the camp; the ground hides it wherever the land is
## higher). The stream is built by _build_stream.
static func _build_water(parent: Node3D, out: Dictionary) -> void:
	var lake := PlaneMesh.new()
	lake.size = Vector2(1400.0, 1400.0)
	var lake_mat := ShaderMaterial.new()
	lake_mat.shader = WATER_SHADER
	lake_mat.set_shader_parameter("ripples", load(TEX + "water_normal.png"))
	out["lake_mat"] = lake_mat
	var mi := _add_mesh(parent, "Lake", lake, lake_mat, false)
	# its south edge is just short of the shore's southernmost bend (shore_z), so it never
	# shows in the stream's bed, which lies lower than the lake for its last few metres
	mi.position = Vector3(0.0, WATER_Y, -700.0 - 7.7)


## The stream: its own fine strip of ground (the bed and the banks, in the ground's material)
## and a ribbon of clear water over it (camp_stream.gdshader). Both follow the smoothed middle
## line STREAM; the heights come from ground_height(), which digs the bed.
static func _build_stream(parent: Node3D, out: Dictionary) -> void:
	# (short pieces, so the bed steps down under each little cascade as the water does)
	var pts := stream_fine(0.4)
	# the bed: corners closer together near the water, where the shape matters
	var bed_cols: PackedFloat32Array = [-STREAM_BED_HALF, -3.3, -2.6, -2.1, -1.75, -1.45, -1.2, -0.95, -0.72, -0.5, -0.3, -0.12, 0.0,
		0.12, 0.3, 0.5, 0.72, 0.95, 1.2, 1.45, 1.75, 2.1, 2.6, 3.3, STREAM_BED_HALF]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in pts.size():
		var along := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		along.y = 0.0
		var side := along.normalized().cross(Vector3.UP)
		for u in bed_cols:
			var x := pts[i].x + side.x * u
			var z := pts[i].z + side.z * u
			var h := ground_height(x, z)
			# the slope, from the heights a hand's width away
			normals.append(Vector3(ground_height(x - 0.1, z) - ground_height(x + 0.1, z), 0.2, ground_height(x, z - 0.1) - ground_height(x, z + 0.1)).normalized())
			# (the outermost corners dip, so the strip's edge hides under the big ground mesh)
			verts.append(Vector3(x, h - (0.25 if absf(u) > STREAM_BED_HALF - 0.01 else 0.0), z))
			colors.append(ground_kind(x, z))
	_strip_indices(indices, pts.size(), bed_cols.size())
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var bed := ArrayMesh.new()
	bed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_add_mesh(parent, "StreamBed", bed, out["ground_mat"], false)

	# the water: a ribbon level across, 1 cm over the water's height (clear of the lake's
	# sheet), in pieces 0.3 m long so the cascades and the foam round the rocks have a shape
	var fine := stream_fine(0.3)
	var rocks := stream_rocks()
	var water_cols: PackedFloat32Array = [-2.0, -1.6, -1.3, -1.05, -0.82, -0.6, -0.4, -0.2, 0.0, 0.2, 0.4, 0.6, 0.82, 1.05, 1.3, 1.6, 2.0]
	var w_verts := PackedVector3Array()
	var w_uvs := PackedVector2Array()
	var w_colors := PackedColorArray()
	var w_indices := PackedInt32Array()
	var run := 0.0                     # metres along the stream so far
	for i in fine.size():
		var before := fine[maxi(i - 1, 0)]
		var after := fine[mini(i + 1, fine.size() - 1)]
		if i > 0:
			run += Vector2(fine[i].x - before.x, fine[i].z - before.z).length()
		var along := after - before
		# how steeply it runs here: 1 = a drop of 1 in 3 or more (a cascade)
		var steep := clampf(along.y / maxf(Vector2(along.x, along.z).length(), 0.01) * 3.0, 0.0, 1.0)
		along.y = 0.0
		var side := along.normalized().cross(Vector3.UP)
		for u in water_cols:
			var x := fine[i].x + side.x * u
			var z := fine[i].z + side.z * u
			# how deep: down to the ground, and never drawn far past the bed's own width (a dip
			# in the land beside the stream is not a puddle)
			var deep := minf(fine[i].y - ground_height(x, z), (stream_half_width(x, z) + 0.3 - absf(u)) * 0.6)
			deep = clampf(deep / STREAM_DEPTH, 0.0, 1.0)
			deep *= smoothstep(0.3, -0.9, shore_z(x) - z)          # it melts into the lake at its mouth
			# how close a rock in the water is (foam gathers round it)
			var rocky := 0.0
			for rock in rocks:
				if rock.w > 0.5 and absf(rock.x - x) < 1.2 and absf(rock.y - z) < 1.2:
					rocky = maxf(rocky, 1.0 - smoothstep(rock.z * 0.9, rock.z * 2.4, Vector2(rock.x - x, rock.y - z).length()))
			w_verts.append(Vector3(x, fine[i].y + 0.01, z))
			w_uvs.append(Vector2(u, run))
			w_colors.append(Color(deep, steep, rocky))
	_strip_indices(w_indices, fine.size(), water_cols.size())
	var w_arrays: Array = []
	w_arrays.resize(Mesh.ARRAY_MAX)
	w_arrays[Mesh.ARRAY_VERTEX] = w_verts
	w_arrays[Mesh.ARRAY_TEX_UV] = w_uvs
	w_arrays[Mesh.ARRAY_COLOR] = w_colors
	w_arrays[Mesh.ARRAY_INDEX] = w_indices
	var water := ArrayMesh.new()
	water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, w_arrays)
	var stream_mat := ShaderMaterial.new()
	stream_mat.shader = STREAM_SHADER
	stream_mat.set_shader_parameter("ripples", load(TEX + "water_normal.png"))
	out["stream_mat"] = stream_mat
	_add_mesh(parent, "Stream", water, stream_mat, false)


## The triangles of a strip of `rows` x `cols` corners laid out row after row (_build_stream).
static func _strip_indices(indices: PackedInt32Array, rows: int, cols: int) -> void:
	for i in rows - 1:
		for j in cols - 1:
			var k := i * cols + j
			indices.append_array([k, k + cols, k + 1, k + 1, k + cols, k + cols + 1])       # facing up


## The forest: two tree shapes (a fir and a round-crowned tree), each drawn many times in one go
## (a MultiMesh), scattered on the hills round the clearing. None stand in the clearing, in the
## lake, on the stream or in the main camera's view of the lake.
static func _build_forest(parent: Node3D, out: Dictionary, rng: RandomNumberGenerator) -> void:
	# a fir, 1 unit tall: a trunk and four tiers of branches
	var fir := Buf.new()
	fir.cyl(Transform3D.IDENTITY, 0.035, 0.02, 0.5, 6, Color(0.2, 0.13, 0.08))
	var tiers := [[0.16, 0.27, 0.34], [0.36, 0.22, 0.3], [0.55, 0.16, 0.27], [0.72, 0.1, 0.28]]
	for t: Array in tiers:
		var green := Color(0.05, 0.17, 0.09).lerp(Color(0.09, 0.26, 0.12), float(t[0]))
		fir.cyl(Transform3D(Basis.IDENTITY, Vector3(0.0, float(t[0]), 0.0)), float(t[1]), 0.0, float(t[2]), 8, green)
	fir.alpha_by_height(1.0)
	# a round tree, 1 unit tall: a trunk and three lumpy balls of leaves
	var round_tree := Buf.new()
	round_tree.cyl(Transform3D.IDENTITY, 0.045, 0.03, 0.5, 6, Color(0.23, 0.16, 0.1))
	var crown_rng := RandomNumberGenerator.new()
	crown_rng.seed = 7
	round_tree.blob(Vector3(0.0, 0.66, 0.0), Vector3(0.3, 0.26, 0.3), 9, 6, Color(0.2, 0.36, 0.1), Color(0.07, 0.17, 0.06), 0.16, crown_rng)
	round_tree.blob(Vector3(0.16, 0.8, 0.06), Vector3(0.2, 0.18, 0.2), 8, 5, Color(0.24, 0.4, 0.12), Color(0.09, 0.2, 0.07), 0.16, crown_rng)
	round_tree.blob(Vector3(-0.14, 0.76, -0.1), Vector3(0.19, 0.17, 0.19), 8, 5, Color(0.18, 0.34, 0.1), Color(0.07, 0.17, 0.06), 0.16, crown_rng)
	round_tree.alpha_by_height(1.0)

	# Each kind is kept in two lots, so "Set detail: Detailed near the fire" can swap only the
	# trees within NEAR_RADIUS for detailed ones: index 0 = far, 1 = near.
	var firs_far: Array[Transform3D] = []
	var firs_near: Array[Transform3D] = []
	var round_far: Array[Transform3D] = []
	var round_near: Array[Transform3D] = []
	var spots_fir: Array = [firs_far, firs_near]
	var spots_round: Array = [round_far, round_near]
	var tints_fir: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
	var tints_round: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
	var placed := 0
	var records: Array[Dictionary] = []      # every tree, for _build_detailed_plants
	var taken: Array[Vector2] = []
	# a few picked by hand close to the camp, so the clearing has an edge
	var near: Array[Vector2] = [Vector2(-13.6, 5.0), Vector2(13.9, -4.6), Vector2(13.4, 8.6), Vector2(-12.4, 9.4),
		Vector2(-15.8, -3.4), Vector2(15.0, 1.6), Vector2(-6.5, 12.8), Vector2(7.2, 13.2), Vector2(14.6, -7.6), Vector2(-17.0, 1.0)]
	var tries := TREE_TRIES + near.size()
	for i in tries:
		var p: Vector2
		if i < near.size():
			p = near[i]
		else:
			var radius := sqrt(rng.randf()) * FOREST_RADIUS
			var ang := rng.randf() * TAU
			p = Vector2(cos(ang) * radius, sin(ang) * radius)
			if Vector2(p.x / 1.25, p.y).length() < 14.0:
				continue                                    # the clearing
			if absf(p.x) < 5.0 and p.y > 10.0 and p.y < 24.0:
				continue                                    # behind the main camera stays open
		if shore_z(p.x) - p.y > -2.0 or stream_near(p.x, p.y).x < 2.8:
			continue                                        # the lake and the stream
		var ok := true
		for q in taken:
			if q.distance_squared_to(p) < 3.2:
				ok = false
				break
		if not ok or placed >= TREE_MAX:
			continue
		placed += 1
		taken.append(p)
		var tall := rng.randf_range(5.5, 11.0)
		var wide := tall * rng.randf_range(0.85, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide, tall, wide)),
			Vector3(p.x, ground_height(p.x, p.y) - 0.15, p.y))
		var shade := rng.randf_range(0.75, 1.15)
		var lot := 1 if is_near(p) else 0
		if rng.randf() < 0.84:
			(spots_fir[lot] as Array[Transform3D]).append(xf)
			tints_fir[lot].append(Color(shade, shade, shade))
			records.append({"p": p, "xf": xf, "shade": shade, "kind": "fir"})
		else:
			records.append({"p": p, "xf": xf, "shade": shade, "kind": "round"})
			xf = xf.scaled_local(Vector3(1.15, 0.8, 1.15))
			(spots_round[lot] as Array[Transform3D]).append(xf)
			tints_round[lot].append(Color(shade, shade * 1.05, shade * 0.9))
	var tree_mat := _prop_material(TREE_SWAY)
	out["tree_mat"] = tree_mat
	var far: Array[Node3D] = [
		_add_trees(parent, "Firs", fir, firs_far, tints_fir[0], tree_mat),
		_add_trees(parent, "RoundTrees", round_tree, round_far, tints_round[0], tree_mat)]
	var near_nodes: Array[Node3D] = [
		_add_trees(parent, "FirsNear", fir, firs_near, tints_fir[1], tree_mat),
		_add_trees(parent, "RoundTreesNear", round_tree, round_near, tints_round[1], tree_mat)]
	out["lowpoly_far"] = far
	out["lowpoly_near"] = near_nodes
	out["tree_count"] = placed
	var close_records := _build_close_woods(parent, out, fir, round_tree, tree_mat)
	_build_detailed_plants(parent, out, records, close_records)


## Whether a tree at p (x, z) counts as "near the fire" for the Set detail choice.
static func is_near(p: Vector2) -> bool:
	return Vector2(p.x / 1.25, p.y).length() < NEAR_RADIUS


## One kind of tree drawn many times in one go (a MultiMesh): `spots` is where each stands and
## how big, `tints` its shade. Returns the node, so a group of trees can be shown and hidden.
static func _add_trees(parent: Node3D, node_name: String, tree: Buf, spots: Array[Transform3D], tints: PackedColorArray, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tree.to_mesh()
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


## The close woods ("camp_close_woods", Room tab > Woods close around the camp): a thick belt of
## trees right round the clearing and a wall of firs along the whole shore, so the lake can't be
## seen and the camp sits in the forest. Built once with the rest of the set and left hidden;
## campfire_room.gd's _apply_woods() shows and hides the nodes listed in out["close_woods"].
## They use the forest's two tree shapes and its material.
## Passes: 1) the shore wall, two staggered rows of tall firs and a thinner third; 1b) the
## horseshoe, a wall down each side that closes the clearing into a cul-de-sac; 2) the belt, tall trees
## scattered round the clearing; 3) young firs between them all, whose branches start at the
## ground and close the gaps between the tall trees' bare trunks.
## Its own random numbers (not the set's `rng`), so adding it changed nothing else in the set.
## Returns one record per tree (p, xf, shade, kind "fir" / "round" / "young") for
## _build_detailed_plants, which builds the same woods again out of detailed trees.
static func _build_close_woods(parent: Node3D, out: Dictionary, fir: Buf, round_tree: Buf, tree_mat: Material) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	var records: Array[Dictionary] = []
	var spots_fir: Array[Transform3D] = []
	var spots_round: Array[Transform3D] = []
	var tints_fir := PackedColorArray()
	var tints_round := PackedColorArray()
	var taken: Array[Vector2] = []
	var young: Array[Vector2] = []      # where the young firs of pass 3 go
	# 1) the wall along the shore
	var x := -CLOSE_WALL_HALF
	var row := 0
	while x <= CLOSE_WALL_HALF:
		var front := minf(CLOSE_WALL_Z, shore_z(x) + 0.75)       # never nearer the screen than CLOSE_WALL_Z
		var p := Vector2(x + rng.randf_range(-0.12, 0.12), front - 0.45 * float(row % 2) + rng.randf_range(-0.08, 0.08))
		row += 1
		x += CLOSE_WALL_STEP
		# a young fir in front of every wall tree and a tall one now and then at the water's
		# edge behind them: together they shut the gaps under and between the front rows
		young.append(Vector2(p.x + 0.25, front + 0.25))
		if row % 2 == 0:
			young.append(Vector2(p.x - 0.2, front - 0.75))
		if row % 3 == 0:
			var back := Vector2(p.x, front - 1.0)
			if _close_spot_free(back):
				var back_tall := rng.randf_range(7.0, 9.5)
				spots_fir.append(_close_tree(back, back_tall, back_tall * _close_width(back, rng)))
				tints_fir.append(Color(0.75, 0.75, 0.75))
				records.append({"p": back, "xf": spots_fir[-1], "shade": 0.75, "kind": "fir"})
		if not _close_spot_free(p):
			continue
		taken.append(p)
		var tall := rng.randf_range(7.5, 10.5)
		var shade := rng.randf_range(0.7, 1.05)
		spots_fir.append(_close_tree(p, tall, tall * _close_width(p, rng)))
		tints_fir.append(Color(shade, shade, shade))
		records.append({"p": p, "xf": spots_fir[-1], "shade": shade, "kind": "fir"})
	# 1b) the horseshoe down both sides: three staggered rows of fairly slim firs along
	#     horseshoe_line(), each row 0.7 m further out than the last, with a young fir on the inside of
	#     every other one. The tents end up among these trees (gap 1.8 m, not the belt's 3.3).
	var line := horseshoe_line()
	for side: float in [-1.0, 1.0]:
		for i in line.size():
			var on_line := line[i]
			var outward := on_line.normalized() if on_line.y > 0.0 else Vector2(1.0, 0.0)
			var p := Vector2(on_line.x, on_line.y) + outward * (0.7 * float(i % 3)) + Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
			p.x *= side
			if i % 2 == 0:
				young.append(Vector2((on_line.x - outward.x * 0.45) * side, on_line.y - outward.y * 0.45))
			if not _close_spot_free(p, 1.8):
				continue
			taken.append(p)
			var tall := rng.randf_range(6.0, 9.5)
			var shade := rng.randf_range(0.7, 1.1)
			spots_fir.append(_close_tree(p, tall, tall * minf(_close_width(p, rng), rng.randf_range(0.34, 0.46))))
			tints_fir.append(Color(shade, shade, shade))
			records.append({"p": p, "xf": spots_fir[-1], "shade": shade, "kind": "fir"})
	# 2) the belt round the clearing, from just outside the tents and benches out to where the
	#    ordinary forest starts
	for i in CLOSE_TRIES:
		var radius := lerpf(CLOSE_RING.x, CLOSE_RING.y, sqrt(rng.randf()))
		var ang := rng.randf() * TAU
		var p := Vector2(cos(ang) * radius * 1.25, sin(ang) * radius)     # the clearing's oval (see ground_height)
		if not _close_spot_free(p) or shore_z(p.x) - p.y > -0.5:
			continue
		var ok := true
		for q in taken:
			if q.distance_squared_to(p) < CLOSE_GAP * CLOSE_GAP:
				ok = false
				break
		if not ok:
			continue
		taken.append(p)
		if rng.randf() < 0.6:
			young.append(p + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7)))
		var tall := rng.randf_range(5.0, 10.0)
		var shade := rng.randf_range(0.7, 1.1)
		# on the lake's side only firs: a round tree's bare trunk would leave the water in view
		if p.y < -1.0 or rng.randf() < 0.8:
			spots_fir.append(_close_tree(p, tall, tall * _close_width(p, rng)))
			tints_fir.append(Color(shade, shade, shade))
			records.append({"p": p, "xf": spots_fir[-1], "shade": shade, "kind": "fir"})
		else:
			var round_xf := _close_tree(p, tall, tall * rng.randf_range(0.5, 0.8))
			records.append({"p": p, "xf": round_xf, "shade": shade, "kind": "round"})
			spots_round.append(round_xf.scaled_local(Vector3(1.15, 0.8, 1.15)))
			tints_round.append(Color(shade, shade * 1.05, shade * 0.9))
	# 3) the young firs: 2.2 to 3.5 m tall and sunk a little, so their lowest branches brush the ground
	for p in young:
		if not _close_spot_free(p, 1.8) or shore_z(p.x) - p.y > -0.3:
			continue
		var tall := rng.randf_range(2.2, 3.5)
		var xf := _close_tree(p, tall, tall * rng.randf_range(0.6, 0.8))
		xf.origin.y -= 0.25
		var shade := rng.randf_range(0.8, 1.15)
		spots_fir.append(xf)
		tints_fir.append(Color(shade, shade, shade))
		records.append({"p": p, "xf": xf, "shade": shade, "kind": "young"})
	var nodes: Array[Node3D] = [
		_add_trees(parent, "CloseFirs", fir, spots_fir, tints_fir, tree_mat),
		_add_trees(parent, "CloseRoundTrees", round_tree, spots_round, tints_round, tree_mat)]
	for n in nodes:
		n.visible = false
	out["close_woods"] = nodes
	out["close_tree_count"] = spots_fir.size() + spots_round.size()
	return records


# ── The detailed plants ──────────────────────────────────────
## The detailed look of the forest ("camp_detail", Room tab > Set detail): every tree of the
## forest and of the close woods once more, as a detailed tree from campfire_trees.gd standing
## on the same spot, plus grass tufts and ferns. All built hidden; campfire_room.gd's
## _apply_detail() shows the detailed lot or the low-poly lot of each group:
##   out["detail_near"]         Node3D: the forest's trees within NEAR_RADIUS of the fire
##   out["detail_far"]          Node3D: the rest of the forest
##   out["close_woods_detail"]  Node3D: the close woods (only shown while they are switched on)
##   out["undergrowth"]         Node3D: grass tufts and ferns
## `forest` / `close`: the records _build_forest and _build_close_woods made.
## Which species stands where is worked out from the spot itself (species_at), so it is the
## same on every PC and adding this changed nothing in the low-poly set.
static func _build_detailed_plants(parent: Node3D, out: Dictionary, forest: Array[Dictionary], close: Array[Dictionary]) -> void:
	var mats := Trees.materials(TREE_SWAY)
	out["plant_mats"] = mats
	var kits: Dictionary = {}                 # species -> its mesh, made the first time it is needed
	var groups: Dictionary = {"detail_near": {}, "detail_far": {}, "close_woods_detail": {}}      # group -> species -> [spots, tints]
	var counts: Dictionary = {}               # species -> how many, for the test and the log
	for is_close: bool in [false, true]:
		for rec: Dictionary in (close if is_close else forest):
			var p: Vector2 = rec["p"]
			var species := species_at(p, String(rec["kind"]), rec["xf"], is_close)
			var group: Dictionary = groups["close_woods_detail" if is_close else ("detail_near" if is_near(p) else "detail_far")]
			if not group.has(species):
				var no_spots: Array[Transform3D] = []
				group[species] = [no_spots, PackedColorArray()]
			(group[species][0] as Array[Transform3D]).append(_detailed_spot(rec["xf"], species))
			var shade: float = rec["shade"]
			# leafy trees vary in colour as well as in brightness: some yellower, some bluer
			var hue := fposmod(p.x * 0.731 + p.y * 1.377, 1.0) - 0.5
			var tint := Color(shade, shade, shade)
			if species in ["oak", "maple", "birch"]:
				tint = Color(shade * (1.0 + 0.16 * hue), shade, shade * (1.0 - 0.2 * hue))
			var tints: PackedColorArray = group[species][1]
			tints.append(tint)
			group[species][1] = tints          # (a PackedColorArray is copied when read out of an Array)
			counts[species] = int(counts.get(species, 0)) + 1
	for group_name: String in groups:
		var holder := Node3D.new()
		holder.name = group_name.to_pascal_case()        # DetailNear, DetailFar, CloseWoodsDetail
		holder.visible = false
		parent.add_child(holder)
		out[group_name] = holder
		var group: Dictionary = groups[group_name]
		for species: String in group:
			if not kits.has(species):
				kits[species] = Trees.kit(species, mats)
			_add_plants(holder, species.to_pascal_case(), kits[species], group[species][0], group[species][1], true)
	out["species_counts"] = counts
	_build_undergrowth(parent, out, mats)


## Which detailed tree stands on a low-poly tree's spot. kind = the low-poly tree there
## ("fir", "round" or "young"), xf = its place and size, is_close = it belongs to the close woods.
## The owner asked for a temperate wood where the cameras look, so near the clearing (is_near)
## and in the close woods about half the tall trees are oaks and maples, with birches, firs
## and a few pines between them; the far hillsides stay more of a fir forest. Only behind the
## screen do the close woods stay all firs: their boughs reach the ground and hide the lake,
## and a leafy crown there would push through the picture. Young firs fill in under the
## leafy trees' bare trunks everywhere else.
static func species_at(p: Vector2, kind: String, _xf: Transform3D, is_close: bool) -> String:
	if kind == "young":
		return "young_fir"
	var roll := fposmod(sin(p.x * 91.7 + p.y * 37.3) * 43758.5453, 1.0)      # 0..1, fixed for the spot
	if kind == "round":
		return "oak" if roll < 0.45 else ("maple" if roll < 0.85 else "birch")
	if is_close:
		if p.y < -1.0 and absf(p.x) < POST_X + 2.5:
			return "fir"                              # the wall behind the screen
		# the lake's side keeps more firs than the rest, so the water stays hidden
		return _pick(roll, [0.6, 0.0, 0.17, 0.17, 0.06] if p.y < -1.0 else [0.26, 0.04, 0.28, 0.28, 0.14])
	return _pick(roll, [0.28, 0.07, 0.26, 0.26, 0.13] if is_near(p) else [0.44, 0.1, 0.18, 0.17, 0.11])


## The species for a spot's `roll` (0..1) from shares in the order fir, pine, oak, maple,
## birch (they add up to 1).
static func _pick(roll: float, shares: Array) -> String:
	var names: Array[String] = ["fir", "pine", "oak", "maple", "birch"]
	var upto := 0.0
	for i in names.size():
		upto += float(shares[i])
		if roll < upto:
			return names[i]
	return "birch"


## A detailed tree's place and size from the low-poly tree's (`xf`: turned round y, `wide`
## across and `tall` high). Young firs keep it. A fir keeps it too, but is never slimmer than
## 0.3 of its height: slimmer, its boughs shrink to tufts on a pole (the low-poly firs behind
## the screen go down to CLOSE_SLIM; at 0.3 a 10 m fir's boughs reach 0.9 m, still clear of the
## screen 1.1 m in front of it). Leafy trees and pines are built to other proportions
## (campfire_trees.gd), so they are kept from getting needle-thin or wider than they are tall.
static func _detailed_spot(xf: Transform3D, species: String) -> Transform3D:
	if species == "young_fir":
		return xf
	var size := xf.basis.get_scale()
	if species == "fir":
		if size.x >= size.y * 0.3:
			return xf
		return Transform3D(xf.basis.orthonormalized().scaled(Vector3(size.y * 0.3, size.y, size.y * 0.3)), xf.origin)
	var tall := size.y * (0.85 if species != "pine" else 1.05)
	var wide := clampf(size.x, tall * 0.55, tall * 0.9)
	return Transform3D(xf.basis.orthonormalized().scaled(Vector3(wide, tall, wide)), xf.origin)


## One kind of detailed plant drawn many times in one go. Unlike _add_trees, the mesh brings
## its own materials (bark on one surface, leaf cards on the other: campfire_trees.gd kit()).
static func _add_plants(parent: Node3D, node_name: String, mesh: Mesh, spots: Array[Transform3D], tints: PackedColorArray, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Grass tufts in the clearing and ferns under the trees at its edge (out["undergrowth"], shown
## with the detailed looks only). Tufts grow where the ground is grass: not on the trodden dirt
## round the fire and under the benches, not on the sand, not where a tent or the camp's things
## stand. They cast no shadows (too small to matter, and shadows are what costs).
static func _build_undergrowth(parent: Node3D, out: Dictionary, mats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var holder := Node3D.new()
	holder.name = "Undergrowth"
	holder.visible = false
	parent.add_child(holder)
	out["undergrowth"] = holder
	var grass: Array[Transform3D] = []
	var ferns: Array[Transform3D] = []
	var grass_tints := PackedColorArray()
	var fern_tints := PackedColorArray()
	for i in 9000:
		var radius := sqrt(rng.randf()) * UNDERGROWTH_RADIUS
		var ang := rng.randf() * TAU
		var p := Vector2(cos(ang) * radius * 1.25, sin(ang) * radius)
		var roll := rng.randf()
		var size := rng.randf_range(0.5, 1.1)
		var high := rng.randf_range(0.8, 1.3)
		var turn := rng.randf() * TAU
		var shade := rng.randf_range(0.8, 1.1)
		if shore_z(p.x) - p.y > -0.6 or stream_near(p.x, p.y).x < stream_half_width(p.x, p.y) + 0.25:
			continue                                   # the lake, the stream and their banks
		if not _undergrowth_free(p):
			continue
		var kind := ground_kind(p.x, p.y)
		if kind.r > 0.25 or kind.g > 0.25:
			continue                                   # trodden dirt, sand
		var xf := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(size, size * high, size)), Vector3(p.x, ground_height(p.x, p.y) - 0.02, p.y))
		# under the trees: mostly ferns, a little thin grass; in the open: grass, in clumps
		if kind.b > 0.4:
			if roll < 0.3 and ferns.size() < FERN_MAX:
				ferns.append(xf)
				fern_tints.append(Color(shade, shade, shade))
			elif roll > 0.8 and grass.size() < GRASS_MAX:
				grass.append(xf)
				grass_tints.append(Color(shade * 0.8, shade * 0.85, shade * 0.8))
		elif grass.size() < GRASS_MAX and _noise.get_noise_2d(p.x * 6.0 + 300.0, p.y * 6.0) > -0.12:
			grass.append(xf)
			grass_tints.append(Color(shade, shade, shade))
	_add_plants(holder, "GrassTufts", Trees.kit("grass", mats), grass, grass_tints, false)
	_add_plants(holder, "Ferns", Trees.kit("fern", mats), ferns, fern_tints, false)


## Whether a tuft or fern may grow at p: not in a tent, on the s'mores table or the stick pile,
## or under the screen and its posts.
static func _undergrowth_free(p: Vector2) -> bool:
	for t: Array in TENTS:
		if p.distance_to(Vector2(float(t[0]), float(t[1]))) < 2.3:
			return false
	if p.distance_to(STICK_PILE) < 1.0 or p.distance_to(SMORES_TABLE) < 1.1:
		return false
	if absf(p.x) < POST_X + 0.4 and absf(p.y - SCREEN_Z) < 0.5:
		return false
	return true


## Where and how big one close-woods tree is: standing at p (x, z) on the ground, turned at
## random (always the same way for the same spot), `tall` metres high and `wide` across.
static func _close_tree(p: Vector2, tall: float, wide: float) -> Transform3D:
	var turn := fposmod(p.x * 12.9898 + p.y * 78.233, TAU)
	return Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(wide, tall, wide)), Vector3(p.x, ground_height(p.x, p.y) - 0.15, p.y))


## How wide a close-woods fir at p may be, as a share of its height. Behind the screen they are
## slim (CLOSE_SLIM), a little fuller just beside it, and full further out: a wide fir close
## behind the screen would push its branches through the picture.
static func _close_width(p: Vector2, rng: RandomNumberGenerator) -> float:
	if p.y < -4.5 and absf(p.x) < 5.0:
		return rng.randf_range(CLOSE_SLIM.x, CLOSE_SLIM.y)
	if p.y < -4.5 and absf(p.x) < 8.0:
		return rng.randf_range(0.34, 0.44)
	return rng.randf_range(0.5, 0.8)


## The horseshoe's line on the right-hand side (x > 0) as points CLOSE_SIDE_STEP apart, from
## beside the screen round to the mouth; the left side is the same with x turned round.
static func horseshoe_line() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	# beside the screen, widening towards the fire's level (z = 0)
	var steps := int(absf(CLOSE_SIDE_START.y) / CLOSE_SIDE_STEP)
	for i in steps:
		var t := float(i) / float(steps)
		pts.append(Vector2(lerpf(CLOSE_SIDE_START.x, CLOSE_SIDE_RADIUS, pow(t, 0.8)), lerpf(CLOSE_SIDE_START.y, 0.0, t)))
	# round the circle behind the benches' ends
	var ang := 0.0
	while CLOSE_SIDE_RADIUS * cos(ang) > CLOSE_SIDE_OPEN:
		pts.append(Vector2(cos(ang), sin(ang)) * CLOSE_SIDE_RADIUS)
		ang += CLOSE_SIDE_STEP / CLOSE_SIDE_RADIUS
	return pts


## True when a close-woods tree may stand at p (x, z): not on a tent (tent_gap metres from its
## middle), a light pole, the stream, the path to the dock, a camera (CLOSE_CAMERA_GAP metres
## round each, and for a camera that looks in at the fire from the edge, nothing within 3 m in
## front of it), and not inside the horseshoe or in its mouth, where the benches and the main
## camera's view are.
static func _close_spot_free(p: Vector2, tent_gap: float = 3.3) -> bool:
	for t: Array in TENTS:
		if p.distance_to(Vector2(float(t[0]), float(t[1]))) < tent_gap:
			return false
	for pole in LIGHT_POLES:
		if p.distance_to(Vector2(pole.x, pole.z)) < 1.0:
			return false
	if stream_near(p.x, p.y).x < 1.1:
		return false
	if absf(p.x - DOCK_X) < 0.75 and p.y < -6.0:
		return false
	for c: Array in CAMERAS:
		var at := Vector2((c[1] as Vector3).x, (c[1] as Vector3).z)
		var to_tree := p - at
		if to_tree.length() < CLOSE_CAMERA_GAP:
			return false
		var look := (Vector2((c[2] as Vector3).x, (c[2] as Vector3).z) - at).normalized()
		var from_edge := at.length() > 6.0 and look.dot(-at.normalized()) > 0.5
		if from_edge and to_tree.length() < 3.0 and look.dot(to_tree.normalized()) > 0.8:
			return false
	if p.y > -1.0 and p.length() < CLOSE_SIDE_RADIUS - 0.5:
		return false
	if absf(p.x) < CLOSE_SIDE_OPEN and p.y > 5.5:
		return false
	return true


## The fire pit: a ring of stones, the logs leaning together, the bed of coals (its own mesh and
## glowing material) and the FIRE_Camp marker at the bottom centre of the flames.
static func _build_fire_pit(props: Buf, parent: Node3D, markers: Node3D, out: Dictionary, rng: RandomNumberGenerator) -> void:
	props.mat = MAT_ROCK
	for i in 11:
		var a := TAU * float(i) / 11.0 + rng.randf_range(-0.08, 0.08)
		var size := rng.randf_range(0.16, 0.24)
		var grey := rng.randf_range(0.22, 0.38)
		if i == PEBBLE_STONE:                     # this one is Pebble: a stone like the rest, with a face
			_build_pebble(props, Vector3(cos(a) * 0.84, 0.0, sin(a) * 0.84), 0.22, grey)
			props.mat = MAT_ROCK
			continue
		props.blob(Vector3(cos(a) * 0.82, size * 0.45, sin(a) * 0.82), Vector3(size, size * 0.7, size * 0.85), 6, 4,
			Color(grey, grey, grey * 1.05), Color(grey * 0.5, grey * 0.5, grey * 0.5), 0.35, rng)
	props.mat = MAT_BARK
	for i in 6:                                   # the logs: feet on a circle, tops meeting over the middle
		var a := TAU * float(i) / 6.0 + 0.3
		var foot := Vector3(cos(a) * 0.48, 0.05, sin(a) * 0.48)
		var top := Vector3(cos(a + 2.6) * 0.1, 0.62, sin(a + 2.6) * 0.1)
		props.rod(foot, top, 0.065, 7, Color(0.1, 0.07, 0.05), Color(0.32, 0.22, 0.12))
	var coals := CylinderMesh.new()
	coals.top_radius = 0.55
	coals.bottom_radius = 0.62
	coals.height = 0.1
	coals.radial_segments = 12
	var ember := StandardMaterial3D.new()
	ember.resource_name = "Embers"
	ember.emission_enabled = true
	out["ember_mat"] = ember
	var mi := _add_mesh(parent, "Embers", coals, ember, false)
	mi.position = Vector3(0.0, 0.05, 0.0)
	out["fire"] = _marker_facing(markers, "FIRE_Camp", Vector3(0.0, 0.12, 0.0), Vector3(0.0, 0.0, 5.0))


## Pebble: the owner's own little character (drawn for them; the design is theirs), kept
## subtle: it is one of the fire ring's ordinary grey stones (number PEBBLE_STONE, the one
## nearest the main camera) with a small face and a gem on its forehead, looking out at the
## camera. Called by _build_fire_pit with that stone's place on the ground (`at`), its size
## (metres) and its grey (0..1). Everything on it is placed by two angles (radians): `yaw`
## round the stone from the face's middle (positive = the viewer's right) and `pitch` up from
## the stone's middle (PI / 2 = the very top). It uses its own random numbers.
static func _build_pebble(props: Buf, at: Vector3, size: float, grey: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var radii := Vector3(size, size * 0.74, size * 0.9)
	var c := Vector3(at.x, size * 0.4, at.z)
	var f := (Vector3(CAMERAS[0][1].x, 0.0, CAMERAS[0][1].z) - Vector3(c.x, 0.0, c.z)).normalized()
	var side := Vector3.UP.cross(f)                     # the viewer's right
	# the stone itself: rock like the others, only smooth enough for a face to sit on
	props.mat = MAT_ROCK
	props.blob(c, radii, 12, 8, Color(grey, grey, grey * 1.05), Color(grey * 0.5, grey * 0.5, grey * 0.5), 0.0, rng)
	props.mat = MAT_PLAIN
	# a point on the stone (lift 1 = on it, a little more = just above it) and its way out
	var out_of := func(yaw: float, pitch: float) -> Vector3:
		return (f * cos(yaw) + side * sin(yaw)) * cos(pitch) + Vector3.UP * sin(pitch)
	var on := func(yaw: float, pitch: float, lift: float) -> Vector3:
		return c + out_of.call(yaw, pitch) * radii * lift
	# a round or oval spot lying on the stone: w, h = half its width and height (radians)
	var spot := func(yaw: float, pitch: float, w: float, h: float, lift: float, col: Color) -> void:
		var n: Vector3 = out_of.call(yaw, pitch)
		var mid: Vector3 = on.call(yaw, pitch, lift)
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			props.tri_round(mid, on.call(yaw + w * cos(a0), pitch + h * sin(a0), lift),
				on.call(yaw + w * cos(a1), pitch + h * sin(a1), lift), n, n, n, col)
	var blush := Color(grey, grey, grey).lerp(Color(0.9, 0.55, 0.58), 0.55)      # a faint pink on the grey
	for sx: float in [-1.0, 1.0]:
		spot.call(sx * 0.5, 0.06, 0.12, 0.075, 1.015, blush)
		spot.call(sx * 0.3, 0.2, 0.095, 0.1, 1.03, Color(0.03, 0.03, 0.04))            # eye
		spot.call(sx * 0.3 - 0.035, 0.165, 0.042, 0.045, 1.045, Color(0.95, 0.95, 0.95)) # its white dot: looking down and to its right
	# the mouth: a small "v"
	var dark := Color(0.05, 0.04, 0.06)
	props.rod(on.call(-0.045, 0.13, 1.015), on.call(0.0, 0.08, 1.015), 0.003, 4, dark)
	props.rod(on.call(0.045, 0.13, 1.015), on.call(0.0, 0.08, 1.015), 0.003, 4, dark)
	# the gem on the forehead: a kite, longer below, cut with a flat middle and four slopes
	var gem_mid := 0.62
	var rim: Array[Vector3] = []
	var flat: Array[Vector3] = []
	for corner: Vector2 in [Vector2(0.0, 0.22), Vector2(0.17, 0.05), Vector2(0.0, -0.24), Vector2(-0.17, 0.05)]:
		rim.append(on.call(corner.x / cos(gem_mid), gem_mid + corner.y, 0.99))
		flat.append(on.call(corner.x * 0.45 / cos(gem_mid), gem_mid + corner.y * 0.45, 1.08))
	var slopes: Array[Color] = [Color(0.85, 0.5, 0.72), Color(0.85, 0.2, 0.5), Color(0.18, 0.18, 0.75), Color(0.35, 0.7, 0.9)]
	var gem_out: Vector3 = out_of.call(0.0, gem_mid)
	for i in 4:
		var j := (i + 1) % 4
		var n := (rim[i] + rim[j] + flat[i] + flat[j]) * 0.25 - c
		n = (n.normalized() + ((rim[i] + rim[j]) * 0.5 - (flat[i] + flat[j]) * 0.5).normalized()).normalized()
		props.tri_round(rim[i], rim[j], flat[j], n, n, n, slopes[i])
		props.tri_round(rim[i], flat[j], flat[i], n, n, n, slopes[i])
	props.tri_round(flat[0], flat[1], flat[2], gem_out, gem_out, gem_out, Color(0.3, 0.2, 0.8))
	props.tri_round(flat[0], flat[2], flat[3], gem_out, gem_out, gem_out, Color(0.3, 0.2, 0.8))


## The log benches (the chat audience's seats): each row is an arc of logs with one AUDIENCE_
## marker per seat on top, facing the fire.
static func _build_benches(props: Buf, markers: Node3D) -> void:
	props.mat = MAT_BARK
	var bark := Color(0.17, 0.11, 0.07)
	var cut := Color(0.5, 0.38, 0.22)
	var row_n := 0
	for row: Array in ROWS:
		row_n += 1
		var radius := float(row[0])
		var seats := int(row[1])
		var step := (ROW_ARC.y - ROW_ARC.x) / float(seats)
		# a log for every two seats (the last one takes what is left)
		var s := 0
		while s < seats:
			var take := mini(2, seats - s)
			var from := ring_point(radius, ROW_ARC.x + step * (float(s) + 0.08))
			var to := ring_point(radius, ROW_ARC.x + step * (float(s + take) - 0.08))
			from.y += BENCH_Y - 0.19
			to.y += BENCH_Y - 0.19
			props.rod(from, to, 0.19, 9, bark, cut)
			for end: Vector3 in [from.lerp(to, 0.15), from.lerp(to, 0.85)]:       # two stumps under each log
				props.cyl(Transform3D(Basis.IDENTITY, Vector3(end.x, ground_height(end.x, end.z) - 0.1, end.z)), 0.15, 0.14, end.y - ground_height(end.x, end.z), 7, bark, cut)
			s += take
		for i in seats:
			var at := ring_point(radius, ROW_ARC.x + step * (float(i) + 0.5))
			at.y += BENCH_Y
			_marker_facing(markers, "AUDIENCE_R%d_%02d" % [row_n, i + 1], at, Vector3.ZERO)


## The loose things round the camp: the stick pile, the s'mores table and cooler, the dock, the
## rocks along the water and the old fallen trunk over the stream.
static func _build_camp_things(props: Buf, rng: RandomNumberGenerator) -> void:
	var wood := Color(0.34, 0.24, 0.14)
	var dark_wood := Color(0.2, 0.14, 0.09)
	props.mat = MAT_BARK
	# the stick pile
	var pile_y := ground_height(STICK_PILE.x, STICK_PILE.y)
	for i in 14:
		var layer := i / 5
		var off := (float(i % 5) - 2.0) * 0.1 + rng.randf_range(-0.02, 0.02)
		var from := Vector3(STICK_PILE.x - 0.55, pile_y + 0.05 + layer * 0.085, STICK_PILE.y + off)
		var to := from + Vector3(1.1 + rng.randf_range(-0.15, 0.15), rng.randf_range(-0.01, 0.03), rng.randf_range(-0.08, 0.08))
		props.rod(from, to, 0.035, 5, dark_wood.lerp(wood, rng.randf()), Color(0.5, 0.38, 0.22))
	props.mat = MAT_PLAIN
	# the s'mores table: a folding table with the makings on it, and a cooler beside it
	var ty := ground_height(SMORES_TABLE.x, SMORES_TABLE.y)
	var table := Transform3D(Basis(Vector3.UP, deg_to_rad(20.0)), Vector3(SMORES_TABLE.x, ty, SMORES_TABLE.y))
	props.box(table * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.72, 0.0)), Vector3(1.2, 0.04, 0.6), Color(0.55, 0.57, 0.6))
	for lx: float in [-0.5, 0.5]:
		props.rod(table * Vector3(lx, 0.0, -0.22), table * Vector3(lx, 0.7, 0.22), 0.018, 5, Color(0.25, 0.26, 0.28))
		props.rod(table * Vector3(lx, 0.0, 0.22), table * Vector3(lx, 0.7, -0.22), 0.018, 5, Color(0.25, 0.26, 0.28))
	props.box(table * Transform3D(Basis.IDENTITY, Vector3(-0.35, 0.83, 0.0)), Vector3(0.26, 0.18, 0.18), Color(0.92, 0.92, 0.95))   # bag of marshmallows
	props.box(table * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.05)), Vector3(0.2, 0.12, 0.14), Color(0.6, 0.4, 0.16))        # box of crackers
	props.box(table * Transform3D(Basis.IDENTITY, Vector3(0.3, 0.76, -0.05)), Vector3(0.22, 0.03, 0.1), Color(0.2, 0.1, 0.06))      # chocolate
	props.box(table * Transform3D(Basis.IDENTITY, Vector3(1.0, 0.2, 0.1)), Vector3(0.6, 0.4, 0.38), Color(0.12, 0.3, 0.55))         # the cooler
	props.box(table * Transform3D(Basis.IDENTITY, Vector3(1.0, 0.43, 0.1)), Vector3(0.62, 0.06, 0.4), Color(0.9, 0.9, 0.92))
	props.mat = MAT_PLANKS
	# the dock: planks on posts out over the lake
	var planks := int((DOCK_Z.x - DOCK_Z.y) / 0.3)
	for i in planks:
		var z := DOCK_Z.x - 0.15 - float(i) * 0.3
		var shade := rng.randf_range(0.85, 1.1)
		props.box(Transform3D(Basis.IDENTITY, Vector3(DOCK_X, 0.2, z)), Vector3(1.3, 0.05, 0.27), Color(wood.r * shade, wood.g * shade, wood.b * shade))
	for z: float in [DOCK_Z.x - 0.6, (DOCK_Z.x + DOCK_Z.y) * 0.5, DOCK_Z.y + 0.3]:
		for sx: float in [-0.6, 0.6]:
			props.cyl(Transform3D(Basis.IDENTITY, Vector3(DOCK_X + sx, WATER_Y - 1.4, z)), 0.07, 0.07, 2.1, 6, dark_wood)
	props.mat = MAT_ROCK
	# rocks: the stream's (stream_rocks: ledges, boulders, loose stones; mossy on top in the
	# woods' damp shade) and a scatter along the lake's shore
	for rock in stream_rocks():
		var grey := rng.randf_range(0.2, 0.34)
		var moss := rng.randf_range(0.0, 0.7) * (0.4 if rock.w > 0.5 else 1.0)
		var top := Color(grey, grey, grey * 1.06).lerp(Color(0.13, 0.2, 0.07), moss)
		var sunk := 0.05 if rock.z < 0.5 else -0.1          # (boulders sit a little into the bank)
		props.blob(Vector3(rock.x, ground_height(rock.x, rock.y) + rock.z * 0.3 + sunk, rock.y),
			Vector3(rock.z, rock.z * rng.randf_range(0.5, 0.8), rock.z * rng.randf_range(0.7, 1.1)),
			9 if rock.z > 0.42 else 6, 6 if rock.z > 0.42 else 4,           # (big ones get more corners, or they look like dice)
			top, Color(grey * 0.45, grey * 0.5, grey * 0.45), 0.28 if rock.z > 0.42 else 0.4, rng)
	for i in 16:
		var x := rng.randf_range(-9.0, 14.0)
		if absf(x - DOCK_X) < 1.2:
			continue
		var size := rng.randf_range(0.14, 0.42)
		var grey := rng.randf_range(0.2, 0.36)
		var at := Vector3(x, 0.0, shore_z(x) + rng.randf_range(-0.4, 0.9))
		at.y = ground_height(at.x, at.z) + size * 0.2
		props.blob(at, Vector3(size, size * rng.randf_range(0.5, 0.8), size * rng.randf_range(0.7, 1.1)), 6, 4,
			Color(grey, grey, grey * 1.06), Color(grey * 0.45, grey * 0.5, grey * 0.45), 0.4, rng)
	# flat pebbles on the stream's bed and at its edge past the camp (too small to matter
	# further off)
	var bed_pts := stream_fine(0.5)
	for i in 100:
		var p := bed_pts[rng.randi_range(4, mini(bed_pts.size() - 1, 60))]
		var reach := stream_half_width(p.x, p.z) + 0.12
		var at := Vector3(p.x + rng.randf_range(-reach, reach), 0.0, p.z + rng.randf_range(-reach, reach))
		var size := rng.randf_range(0.05, 0.12)
		var grey := rng.randf_range(0.24, 0.46)
		at.y = ground_height(at.x, at.z) + size * 0.12
		props.blob(at, Vector3(size, size * 0.4, size * rng.randf_range(0.7, 1.2)), 6, 3,
			Color(grey * 1.05, grey, grey * 0.95), Color(grey * 0.5, grey * 0.5, grey * 0.5), 0.3, rng)
	# an old fallen trunk across the stream where it leaves the woods, mossy on top
	props.mat = MAT_BARK
	var fall := STREAM[5]
	var trunk_dir := Vector3(0.85, 0.07, 0.5).normalized()
	var trunk_from := Vector3(fall.x - 2.3, ground_height(fall.x - 2.3, fall.z - 1.35) + 0.12, fall.z - 1.35)
	var trunk_side := trunk_dir.cross(Vector3.UP).normalized()
	props.cyl(Transform3D(Basis(trunk_side, trunk_dir, trunk_side.cross(trunk_dir)), trunk_from), 0.24, 0.17, 5.2, 9, Color(0.2, 0.17, 0.11), Color(0.42, 0.33, 0.2))
	props.mat = MAT_ROCK


## Whether something wild (a rock outcrop, a stump, flowers) may stand at p (x, z): `gap` metres
## clear of every camera, and not in a tent, on the benches' side of the fire inside the
## rows, under the screen, or on the camp's things (_undergrowth_free).
static func _wild_free(p: Vector2, gap: float) -> bool:
	for c: Array in CAMERAS:
		var cam: Vector3 = c[1]
		if p.distance_to(Vector2(cam.x, cam.z)) < gap:
			return false
	for t: Array in TENTS:
		if p.distance_to(Vector2(float(t[0]), float(t[1]))) < 2.3 + gap * 0.5:
			return false
	return _undergrowth_free(p)


## What makes the land look lived in, all in the shared props mesh (so both looks of Set detail
## get it): rock outcrops on the stream's banks, the lake's shore and the clearing's edge, tree
## stumps and mushrooms, reeds and cattails at the water's edge, lily pads (some in flower) on
## the lake, and wildflowers in drifts through the grass. Called by build(). It has its own
## random numbers, so it is the same on every PC and moves nothing else.
static func _build_wild(props: Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	# -- rock outcrops: two to four big mossy boulders leaning on each other
	var outcrops: Array[Vector2] = [Vector2(-7.2, shore_z(-7.2) + 0.5), Vector2(13.2, shore_z(13.2) + 0.9),
		Vector2(15.0, -4.6), Vector2(14.0, 9.6), Vector2(-12.6, 10.4), Vector2(-17.5, -2.6)]
	var line := stream_fine(0.5)
	var k := 34
	var bank := 1.0
	while k < line.size() - 4 and line[k].x > -40.0:        # up the stream, now one bank, now the other
		var along := (line[k + 1] - line[k - 1])
		var across := Vector3(along.x, 0.0, along.z).normalized().cross(Vector3.UP)
		var off := bank * (stream_half_width(line[k].x, line[k].z) + rng.randf_range(1.5, 2.4))
		outcrops.append(Vector2(line[k].x + across.x * off, line[k].z + across.z * off))
		bank = -bank
		k += rng.randi_range(7, 12)
	props.mat = MAT_ROCK
	for spot_at in outcrops:
		if not _wild_free(spot_at, 2.6):
			continue
		for n in rng.randi_range(2, 4):
			var size := rng.randf_range(0.55, 1.25) * (1.0 if n == 0 else 0.7)
			var p := spot_at + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (0.0 if n == 0 else 1.1)
			var grey := rng.randf_range(0.2, 0.32)
			var moss := rng.randf_range(0.2, 0.75)
			props.blob(Vector3(p.x, ground_height(p.x, p.y) + size * 0.22, p.y),
				Vector3(size, size * rng.randf_range(0.55, 0.9), size * rng.randf_range(0.7, 1.0)), 10, 7,
				Color(grey, grey, grey * 1.06).lerp(Color(0.13, 0.2, 0.07), moss), Color(grey * 0.45, grey * 0.5, grey * 0.45), 0.3, rng)
	# -- stumps at the edge of the clearing, each with a few mushrooms at its foot
	var cap_red := Color(0.62, 0.12, 0.08)
	var cap_tan := Color(0.6, 0.45, 0.28)
	for spot_at: Vector2 in [Vector2(-8.6, 6.4), Vector2(9.2, 8.3), Vector2(13.4, 1.4), Vector2(-15.8, 6.0), Vector2(7.6, -5.9), Vector2(-5.4, 11.3)]:
		if not _wild_free(spot_at, 1.5):
			continue
		var y := ground_height(spot_at.x, spot_at.y)
		props.mat = MAT_BARK
		var r := rng.randf_range(0.2, 0.32)
		props.cyl(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(spot_at.x, y - 0.1, spot_at.y)), r * 1.25, r, rng.randf_range(0.35, 0.6), 9, Color(0.2, 0.15, 0.1), Color(0.5, 0.4, 0.25))
		props.mat = MAT_PLAIN
		for n in rng.randi_range(2, 5):
			var a := rng.randf() * TAU
			var m := Vector3(spot_at.x + cos(a) * (r + 0.2), 0.0, spot_at.y + sin(a) * (r + 0.2))
			m.y = ground_height(m.x, m.z)
			var tall := rng.randf_range(0.05, 0.11)
			props.rod(m, m + Vector3(0.0, tall, 0.0), 0.012, 5, Color(0.85, 0.82, 0.72))
			props.blob(m + Vector3(0.0, tall, 0.0), Vector3(0.045, 0.028, 0.045), 7, 3, cap_red if rng.randf() < 0.5 else cap_tan, Color(0.8, 0.75, 0.65), 0.0, rng)
	# -- reeds and cattails: clumps along the lake's shore and at the stream's quiet pools
	var clumps: Array[Vector2] = []
	for n in 34:
		var x := rng.randf_range(-8.5, 15.0)
		if absf(x - DOCK_X) > 1.1:
			clumps.append(Vector2(x, shore_z(x) + rng.randf_range(-0.9, 0.15)))
	for n in 30:
		var at := line[rng.randi_range(5, 30)]
		var edge := (stream_half_width(at.x, at.z) + rng.randf_range(-0.1, 0.25)) * (-1.0 if rng.randf() < 0.5 else 1.0)
		var from_mid := stream_near(at.x + edge, at.z).x
		if absf(from_mid - absf(edge)) < 0.35:        # (only where that really is the water's edge: the stream bends)
			clumps.append(Vector2(at.x + edge, at.z))
	props.mat = MAT_PLAIN
	for clump in clumps:
		for n in rng.randi_range(4, 9):
			var foot := Vector3(clump.x + rng.randf_range(-0.22, 0.22), 0.0, clump.y + rng.randf_range(-0.22, 0.22))
			foot.y = maxf(ground_height(foot.x, foot.z), WATER_Y - 0.25) - 0.05
			var tall := rng.randf_range(0.5, 0.95)
			var tip := foot + Vector3(rng.randf_range(-0.12, 0.12), tall, rng.randf_range(-0.12, 0.12))
			var green := rng.randf_range(0.8, 1.15)
			props.rod(foot, tip, 0.007, 4, Color(0.2 * green, 0.34 * green, 0.1 * green), Color(0.45 * green, 0.55 * green, 0.2 * green))
			if rng.randf() < 0.3:                      # a cattail's brown head
				props.rod(foot.lerp(tip, 0.8), foot.lerp(tip, 0.97), 0.017, 6, Color(0.15, 0.09, 0.05), Color(0.15, 0.09, 0.05))
	# -- lily pads on the lake near the shore: a round leaf with a notch, one in four in flower
	for n in 34:
		var x := rng.randf_range(-8.5, 15.0)
		var c := Vector3(x, WATER_Y + 0.012, shore_z(x) - rng.randf_range(1.3, 5.2))
		if absf(x - DOCK_X) < 1.0 and c.z > DOCK_Z.y - 0.5:
			continue
		var r := rng.randf_range(0.14, 0.3)
		var turn := rng.randf() * TAU
		var green := Color(0.1, 0.3, 0.09).lerp(Color(0.22, 0.4, 0.1), rng.randf())
		for w in 10:                                   # (wedge 0 of 11 is left out: the notch)
			var a0 := turn + TAU * float(w + 1) / 11.0
			var a1 := turn + TAU * float(w + 2) / 11.0
			props.tri_round(c, c + Vector3(cos(a0), 0.0, sin(a0)) * r, c + Vector3(cos(a1), 0.0, sin(a1)) * r, Vector3.UP, Vector3.UP, Vector3.UP, green)
		if rng.randf() < 0.26:
			var heart := c + Vector3(cos(turn) * r * 0.9, 0.03, sin(turn) * r * 0.9)
			var pink := Color(0.95, 0.6, 0.78).lerp(Color(1.0, 0.92, 0.95), rng.randf() * 0.6)
			for petal in 8:
				var a := TAU * float(petal) / 8.0
				var out_dir := Vector3(cos(a), 0.0, sin(a))
				var wide := out_dir.cross(Vector3.UP) * 0.022
				var tip := heart + out_dir * 0.085 + Vector3(0.0, 0.045 if petal % 2 == 0 else 0.015, 0.0)
				var up := (Vector3.UP + out_dir * 0.5).normalized()
				props.tri_round(heart - wide, heart + wide, tip, up, up, up, pink)
				props.tri_round(heart - wide, tip, heart + wide, -up, -up, -up, pink.darkened(0.25))
			props.blob(heart + Vector3(0.0, 0.012, 0.0), Vector3(0.018, 0.014, 0.018), 5, 3, Color(0.98, 0.8, 0.15), Color(0.9, 0.6, 0.1), 0.0, rng)
	# -- wildflowers in drifts through the open grass: each drift mostly one colour
	var petals: Array[Color] = [Color(0.95, 0.95, 0.9), Color(0.98, 0.82, 0.18), Color(0.58, 0.4, 0.85), Color(0.93, 0.5, 0.65), Color(0.35, 0.5, 0.9)]
	for n in 2600:
		var radius := sqrt(rng.randf()) * 19.0
		var ang := rng.randf() * TAU
		var p := Vector2(cos(ang) * radius * 1.25, sin(ang) * radius)
		var pick := rng.randf()
		var tall := rng.randf_range(0.14, 0.3)
		var lean := Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.04, 0.04))
		if _noise.get_noise_2d(p.x * 4.0 - 500.0, p.y * 4.0 + 200.0) < 0.12:
			continue                                   # between the drifts
		if shore_z(p.x) - p.y > -0.5 or stream_near(p.x, p.y).x < stream_half_width(p.x, p.y) + 0.3 or not _wild_free(p, 0.6):
			continue
		var kind := ground_kind(p.x, p.y)
		if kind.r > 0.2 or kind.g > 0.3 or kind.b > 0.75:
			continue                                   # trodden dirt, sand, deep forest floor
		var drift := clampf(0.5 + _noise.get_noise_2d(p.x * 1.3 + 800.0, p.y * 1.3 - 300.0), 0.0, 0.999)
		var col := petals[int(drift * float(petals.size()))] if pick < 0.8 else petals[int(pick * 977.0) % petals.size()]
		var foot := Vector3(p.x, ground_height(p.x, p.y), p.y)
		props.rod(foot, foot + lean + Vector3(0.0, tall, 0.0), 0.005, 3, Color(0.16, 0.32, 0.08))
		props.blob(foot + lean + Vector3(0.0, tall, 0.0), Vector3(0.045, 0.014, 0.045), 7, 3, col, col.darkened(0.3), 0.0, rng)
		props.blob(foot + lean + Vector3(0.0, tall + 0.012, 0.0), Vector3(0.015, 0.012, 0.015), 5, 3, Color(0.95, 0.75, 0.15), Color(0.8, 0.55, 0.1), 0.0, rng)   # its yellow heart
	props.mat = MAT_ROCK


## The big screen: a white sheet (TVScreen, where the picture goes) hung between two posts, with
## a top and a bottom bar and a dark back. The room script hides the sheet and its back when the
## screen is switched off; the posts stay, because the string lights hang from them.
static func _build_screen(props: Buf, parent: Node3D, out: Dictionary) -> void:
	props.mat = MAT_BARK
	var pole := Color(0.16, 0.12, 0.09)
	for sx: float in [-1.0, 1.0]:
		var x := POST_X * sx
		var foot := ground_height(x, SCREEN_Z)
		props.cyl(Transform3D(Basis.IDENTITY, Vector3(x, foot - 0.3, SCREEN_Z)), 0.1, 0.075, POST_H + 0.3 - foot, 8, pole)
		# a guy rope down to a peg behind each post
		props.rod(Vector3(x, POST_H - 0.3, SCREEN_Z), Vector3(x + sx * 1.6, ground_height(x + sx * 1.6, SCREEN_Z - 1.4), SCREEN_Z - 1.4), 0.012, 4, Color(0.6, 0.55, 0.45))
	var top := SCREEN_BOTTOM + SCREEN_SIZE.y
	props.rod(Vector3(-POST_X, top + 0.1, SCREEN_Z), Vector3(POST_X, top + 0.1, SCREEN_Z), 0.04, 6, pole)
	props.rod(Vector3(-POST_X, SCREEN_BOTTOM - 0.1, SCREEN_Z), Vector3(POST_X, SCREEN_BOTTOM - 0.1, SCREEN_Z), 0.04, 6, pole)
	var sheet := QuadMesh.new()
	sheet.size = SCREEN_SIZE
	var screen := MeshInstance3D.new()
	screen.name = "TVScreen"
	screen.mesh = sheet
	screen.position = Vector3(0.0, SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, SCREEN_Z)
	parent.add_child(screen)
	out["screen"] = screen
	var back := QuadMesh.new()
	back.size = SCREEN_SIZE
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.07, 0.07, 0.08)
	back_mat.roughness = 0.9
	var back_mi := _add_mesh(parent, "ScreenBack", back, back_mat, true)
	back_mi.transform = Transform3D(Basis(Vector3.UP, PI), screen.position + Vector3(0.0, 0.0, -0.03))
	out["screen_back"] = back_mi


## The four camp chairs. Each is its own mesh named PODIUM_n, so the app shows it only while that
## presenter is on set, with PRESENTER_n on its seat: the bottom centre of the presenter's picture.
static func _build_chairs(parent: Node3D, markers: Node3D, mat: Material) -> void:
	var cloths: Array[Color] = [Color(0.62, 0.2, 0.08), Color(0.1, 0.3, 0.5), Color(0.14, 0.38, 0.16), Color(0.55, 0.42, 0.08)]
	var frame := Color(0.12, 0.12, 0.13)
	for i in CHAIR_DEGREES.size():
		var at := ring_point(CHAIR_RADIUS, CHAIR_DEGREES[i])
		var b := Buf.new()
		b.mat = MAT_FABRIC
		var cloth := cloths[i]
		# local axes: +Z = the way the chair faces, y up from the ground
		b.box(Transform3D(Basis.IDENTITY, Vector3(0.0, CHAIR_SEAT_Y - 0.03, -0.12)), Vector3(0.56, 0.04, 0.5), cloth)
		b.box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, CHAIR_SEAT_Y + 0.33, -0.42)), Vector3(0.56, 0.62, 0.035), cloth.darkened(0.15))
		for sx: float in [-0.29, 0.29]:
			b.rod(Vector3(sx, 0.0, 0.12), Vector3(sx, CHAIR_SEAT_Y + 0.22, -0.4), 0.016, 5, frame)        # front foot to the back's side
			b.rod(Vector3(sx, 0.0, -0.4), Vector3(sx, CHAIR_SEAT_Y + 0.22, 0.12), 0.016, 5, frame)        # back foot to the armrest's front
			b.rod(Vector3(sx, CHAIR_SEAT_Y + 0.22, -0.4), Vector3(sx, CHAIR_SEAT_Y + 0.72, -0.5), 0.016, 5, frame)
			b.box(Transform3D(Basis.IDENTITY, Vector3(sx, CHAIR_SEAT_Y + 0.23, -0.14)), Vector3(0.05, 0.02, 0.54), cloth.darkened(0.3))
		var chair := _add_mesh(parent, "PODIUM_%d" % (i + 1), b.to_mesh(), mat)
		# the chairs face a point a little south of the fire, so they open towards the main camera
		var marker := _marker_facing(markers, "PRESENTER_%d" % (i + 1), at + Vector3(0.0, CHAIR_SEAT_Y, 0.0), Vector3(0.0, 0.0, 2.5))
		chair.transform = Transform3D(marker.transform.basis, at)


## The tents, in a mesh of their own so the room script can make them glow from inside at night
## (camp_prop.gdshader's glow).
static func _build_tents(parent: Node3D, out: Dictionary) -> void:
	var b := Buf.new()
	b.mat = MAT_FABRIC
	for t: Array in TENTS:
		var x := float(t[0])
		var z := float(t[1])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(t[2]))), Vector3(x, ground_height(x, z) - 0.03, z))
		var main: Color = t[4]
		var second: Color = t[5]
		var door := main.darkened(0.75)
		if String(t[3]) == "dome":
			# half a ball, 2.6 m across and 1.45 m high, in panels of alternating colour; the
			# three panels at the front are the door
			var segs := 12
			var rings := 5
			for r in rings:
				var lat0 := PI * 0.5 * float(r) / float(rings)
				var lat1 := PI * 0.5 * float(r + 1) / float(rings)
				for s in segs:
					var lon0 := TAU * float(s) / float(segs)
					var lon1 := TAU * float(s + 1) / float(segs)
					var col := main if s % 2 == 0 else main.lerp(second, 0.85)
					if (s == 2 or s == 3) and r < 3:
						col = door                      # (segments 2 and 3 straddle +Z, the front)
					var corners: Array[Vector3] = []
					for ll: Array in [[lat0, lon0], [lat0, lon1], [lat1, lon1], [lat1, lon0]]:
						corners.append(xf * Vector3(cos(float(ll[0])) * cos(float(ll[1])) * 1.3, sin(float(ll[0])) * 1.45, cos(float(ll[0])) * sin(float(ll[1])) * 1.3))
					b.quad(corners[0], corners[1], corners[2], corners[3], col)
		else:
			# a tunnel: half a pipe 3.6 m long and 1.4 m high, striped by its hoops, closed at
			# the back, with a dark doorway at the front
			var segs := 8
			var hoops := 4
			for hp in hoops:
				var z0 := -1.8 + 3.6 * float(hp) / float(hoops)
				var z1 := -1.8 + 3.6 * float(hp + 1) / float(hoops)
				for s in segs:
					var a0 := PI * float(s) / float(segs)
					var a1 := PI * float(s + 1) / float(segs)
					var col := main if hp % 2 == 0 else main.lerp(second, 0.85)
					b.quad(xf * Vector3(cos(a0) * 1.25, sin(a0) * 1.4, z0), xf * Vector3(cos(a1) * 1.25, sin(a1) * 1.4, z0),
						xf * Vector3(cos(a1) * 1.25, sin(a1) * 1.4, z1), xf * Vector3(cos(a0) * 1.25, sin(a0) * 1.4, z1), col)
			for s in segs:
				var a0 := PI * float(s) / float(segs)
				var a1 := PI * float(s + 1) / float(segs)
				b.tri(xf * Vector3(0.0, 0.0, -1.8), xf * Vector3(cos(a0) * 1.25, sin(a0) * 1.4, -1.8), xf * Vector3(cos(a1) * 1.25, sin(a1) * 1.4, -1.8), main.darkened(0.2))
				b.tri(xf * Vector3(0.0, 0.0, 1.8), xf * Vector3(cos(a0) * 1.25, sin(a0) * 1.4, 1.8), xf * Vector3(cos(a1) * 1.25, sin(a1) * 1.4, 1.8),
					door if s >= 2 and s <= 5 else main)
	var mat := _prop_material()
	out["tent_mat"] = mat
	_note_material(out, mat)
	_add_mesh(parent, "Tents", b.to_mesh(), mat)


## The string lights: bulbs on sagging lines from the screen's posts out to the poles by the
## tents, plus the few lamps that really light the camp (LAMP_ markers under LIGHTS_House: Room
## turns each into a light and dims them with the house lights). The tents have no lamp inside:
## their cloth glows instead (the room script, _apply_glows).
static func _build_lights(parent: Node3D, room: Node3D, out: Dictionary) -> void:
	var poles := Buf.new()
	poles.mat = MAT_BARK
	var tops: Array[Vector3] = []
	for p in LIGHT_POLES:
		var foot := ground_height(p.x, p.z)
		poles.cyl(Transform3D(Basis.IDENTITY, Vector3(p.x, foot - 0.2, p.z)), 0.05, 0.04, p.y + 0.2 - foot, 6, Color(0.16, 0.12, 0.09))
		tops.append(Vector3(p.x, p.y, p.z))
	var post_l := Vector3(-POST_X, POST_H - 0.1, SCREEN_Z)
	var post_r := Vector3(POST_X, POST_H - 0.1, SCREEN_Z)
	var lines: Array = [[post_l, tops[0]], [post_r, tops[1]], [tops[1], tops[2]], [post_l, post_r]]
	var bulbs: Array[Vector3] = []
	var house := Node3D.new()
	house.name = "LIGHTS_House"
	room.add_child(house)
	var lamp_n := 0
	for line: Array in lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var count := maxi(int(a.distance_to(b) / 0.55), 2)
		var sag := a.distance_to(b) * 0.09
		var last := a
		for i in range(1, count + 1):
			var t := float(i) / float(count)
			var p := a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
			poles.rod(last, p, 0.006, 3, Color(0.05, 0.05, 0.05))
			last = p
			if i < count:
				bulbs.append(p - Vector3(0.0, 0.06, 0.0))
		# one real light in the middle of each long line (LAMP_LINES of them in all). Few on
		# purpose: every lamp costs the graphics card on every frame, and the bulbs and the
		# tents glow by themselves anyway.
		if lamp_n < LAMP_LINES:
			lamp_n += 1
			var lamp := Marker3D.new()
			lamp.name = "LAMP_String_%d" % lamp_n
			house.add_child(lamp)
			lamp.position = a.lerp(b, 0.5) - Vector3(0.0, sag + 0.25, 0.0)
	var pole_mat := _prop_material()
	_note_material(out, pole_mat)
	_add_mesh(parent, "LightPoles", poles.to_mesh(), pole_mat)
	var bulb := SphereMesh.new()
	bulb.radius = 0.045
	bulb.height = 0.09
	bulb.radial_segments = 8
	bulb.rings = 4
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.85, 0.55)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.72, 0.38)
	bulb_mat.emission_energy_multiplier = 3.0
	out["bulb_mat"] = bulb_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = bulbs.size()
	for i in bulbs.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, bulbs[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "StringLights"
	mmi.multimesh = mm
	mmi.material_override = bulb_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	out["bulbs"] = mmi


## The camera views and the reaction targets (things chat can throw at: "campfire", "lake", "tent").
static func _build_markers(markers: Node3D) -> void:
	for c: Array in CAMERAS:
		var cam := Marker3D.new()
		cam.name = "CAM_" + String(c[0])
		markers.add_child(cam)
		cam.transform = Transform3D(Basis.IDENTITY, c[1]).looking_at(c[2], Vector3.UP)
	_marker_facing(markers, "TARGET_Campfire", Vector3(0.0, 0.7, 0.0), Vector3(0.0, 0.0, 8.0))
	_marker_facing(markers, "TARGET_Lake", Vector3(-1.0, WATER_Y + 0.1, -16.0), Vector3(0.0, 0.0, 8.0))
	_marker_facing(markers, "TARGET_Tent", Vector3(float(TENTS[1][0]), 1.2, float(TENTS[1][1])), Vector3(0.0, 0.0, 2.0))
