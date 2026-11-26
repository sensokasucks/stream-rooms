extends RefCounted
## Route 81's roadside furniture and its tunnels: the meshes that go with a place of road on top
## of its land (r81_land.gd). r81_trip.gd asks for them by name as places come into view; every
## mesh is built once and then shared by every place that needs the same one (_cache).
##
## What is here:
##   props(side, from, to)  one side's guardrail (wherever that side is an overlook, "drop") and
##                          its reflector posts, for Route 22's prop material,
##   lining(part)           the inside of the two tunnels (one per direction of the highway):
##                          tiled walls, a concrete arch and a row of lamps, for r81_tunnel.gdshader,
##   lid(part)              the mountain's top over the two roads, for r81_terrain.gdshader
##                          (the land beside the road leaves the road itself open),
##   lid_trees(part)        and the trees that stand on it,
##   frame(part)            the concrete portal round a tunnel mouth, for the prop material,
##   sign_board()           a green highway sign on two posts (its words are Label3Ds that
##                          r81_trip.gd writes).
## `part` says which piece of a tunnel a place is:
##   "in"    the mouth we drive into: open road for the first half, mountain from the middle on,
##   "tube"  all tunnel,
##   "out"   the mouth we come out of: mountain for the first half, open from the middle on.
## These must stay in step with r81_land.gd's mount() / mount_rise(): the land beside the road
## turns into the mountain at exactly the same spots.
##
## Everything long is cut into short lengths along the road (STEP), because the road's bend
## (r22_common.gdshaderinc) only moves corners: a long straight box would cut across the curve.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Land := preload("res://rooms/route81/r81_land.gd")

## Metres between cuts along the road in rails and tunnel linings (also the lamps' spacing, which
## r81_tunnel.gdshader and r81_road.gdshader both assume: one lamp every 8 m).
const STEP: float = 8.0
## The tunnel's shape inside: the walls stand this far either side of a road's middle and go
## straight up to WALL_H, then an arch (half an ellipse) rises ARCH_H more.
const HALF_W: float = 6.45
const WALL_H: float = 4.2
const ARCH_H: float = 3.9
## The middle of our road and of the other direction's road (X, metres).
const ROAD_MIDS: Array[float] = [(Land.ROAD_L + Land.ROAD_R) * 0.5, (Land.OPP_L + Land.OPP_R) * 0.5]
## Made-up place names for the green signs and the tunnels (never real towns).
const PLACES: PackedStringArray = ["Pine Hollow", "Mill Run", "Ash Gap", "Stony Fork", "Laurel Notch", "Bryce Mills",
	"Coalbrook", "Wexley", "Harlan Springs", "Dutch Corner", "Mount Arden", "Shale Creek", "Tamarack", "Kettle Run"]
const TUNNELS: PackedStringArray = ["Ash Gap", "Laurel Notch", "Stony Fork", "Blue Knob", "Kettle Run", "Mount Arden"]

static var _cache: Dictionary = {}


# ── Roadside props ───────────────────────────────────────────
## One side's guardrail and reflector posts for a place whose side goes from profile `from` to
## `to` (r81_land.gd KINDS). side: +1 = our right, -1 = the far side of the other road.
## The rail stands 2.6 m outside the paved edge wherever the ground is (or is turning into) an
## overlook; white reflector posts stand every 40 m everywhere but in a tunnel.
static func props(side: int, from: String, to: String) -> ArrayMesh:
	var key := "props|%d|%s|%s" % [side, from, to]
	if _cache.has(key):
		return _cache[key]
	var b := Geo.Buf.new()
	var edge := Land.ROAD_R if side > 0 else Land.OPP_L
	var x := edge + float(side) * 2.6
	var n := roundi(Land.LENGTH / STEP)
	for i in n:
		var zt := (float(i) + 0.5) / float(n)
		# how much of an overlook this stretch is (the same blend as the land's, r81_land.gd blend())
		var t := smoothstep(0.15, 0.85, zt)
		var drop := (1.0 - t) * (1.0 if from == "drop" else 0.0) + t * (1.0 if to == "drop" else 0.0)
		if from == "mount" or to == "mount":
			drop = 0.0
		if drop > 0.35:
			_rail(b, x, -float(i) * STEP, -float(i + 1) * STEP, float(side))
	for i in 2:
		var zt := (float(i) + 0.25) / 2.0
		if Land.mount_rise(from, to, zt) < 0.0:
			Geo.reflector_post(b, Vector3(edge + float(side) * 1.4, 0.0, -zt * Land.LENGTH), side < 0)
	var mesh := b.to_mesh()
	_cache[key] = mesh
	return mesh


## STEP metres of W-beam guardrail: the steel rail facing the road and two posts behind it.
static func _rail(b: Geo.Buf, x: float, z0: float, z1: float, side: float) -> void:
	b.mat = Geo.MAT_CHROME
	b.block(Vector3(x, 0.62, (z0 + z1) * 0.5), Vector3(0.06, 0.32, absf(z1 - z0)), Color(0.55, 0.56, 0.58))
	b.mat = Geo.MAT_RUST
	for z: float in [z0, (z0 + z1) * 0.5]:
		b.block(Vector3(x + side * 0.12, 0.35, z), Vector3(0.15, 0.95, 0.12), Color(0.45, 0.43, 0.42))
	b.mat = Geo.MAT_PAINT


# ── Tunnels ──────────────────────────────────────────────────
## The stretch of a place (along Z, metres; [start, end], start > end) that is under the mountain.
static func _covered(part: String) -> Vector2:
	match part:
		"in": return Vector2(-Land.LENGTH * 0.5, -Land.LENGTH)
		"out": return Vector2(0.0, -Land.LENGTH * 0.5)
	return Vector2(0.0, -Land.LENGTH)


## Height of the tunnel's inside at `x` metres from the road's middle (0 outside the walls).
static func arch_y(x: float) -> float:
	if absf(x) >= HALF_W:
		return 0.0
	return WALL_H + ARCH_H * sqrt(1.0 - (x / HALF_W) * (x / HALF_W))


## The inside of both tunnels for one place. Corners carry what r81_tunnel.gdshader reads:
## UV.x = 0 wall tiles / 1 concrete arch / 2 lamp, UV.y = height above the road.
static func lining(part: String) -> ArrayMesh:
	var key := "lining|" + part
	if _cache.has(key):
		return _cache[key]
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var span := _covered(part)
	var n := roundi((span.x - span.y) / STEP)
	# the outline across the tunnel, from the foot of one wall over the arch to the other:
	# [x from the middle, height, kind]
	var outline: Array = [[-HALF_W, 0.0, 0.0], [-HALF_W, WALL_H, 0.0]]
	for i in range(1, 12):
		var a := PI * float(i) / 12.0
		outline.append([-HALF_W * cos(a), WALL_H + ARCH_H * sin(a), 1.0])
	outline.append([HALF_W, WALL_H, 0.0])
	outline.append([HALF_W, 0.0, 0.0])
	for mid in ROAD_MIDS:
		for i in n:
			var z0 := span.x - float(i) * STEP
			var z1 := z0 - STEP
			for j in outline.size() - 1:
				var p: Array = outline[j]
				var q: Array = outline[j + 1]
				# a span is wall when both its ends are wall corners, else arch
				var kind := 0.0 if float(p[2]) < 0.5 and float(q[2]) < 0.5 else 1.0
				_quad(pos, uv, Vector3(mid + float(p[0]), float(p[1]), z0), Vector3(mid + float(q[0]), float(q[1]), z0),
					Vector3(mid + float(q[0]), float(q[1]), z1), Vector3(mid + float(p[0]), float(p[1]), z1), kind, float(p[1]), float(q[1]))
			# the lamps: two rows of light boxes under the arch, in the middle of each STEP (where
			# the shader's light pools are brightest)
			var zl := z0 - STEP * 0.5
			for lx: float in [-2.2, 2.2]:
				var ly := arch_y(lx) - 0.12
				_quad(pos, uv, Vector3(mid + lx - 0.3, ly, zl + 0.9), Vector3(mid + lx + 0.3, ly, zl + 0.9),
					Vector3(mid + lx + 0.3, ly, zl - 0.9), Vector3(mid + lx - 0.3, ly, zl - 0.9), 2.0, ly, ly)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = mesh
	return mesh


## Two triangles a-b-c-d for the lining. a and d are at height ya, b and c at yb.
static func _quad(pos: PackedVector3Array, uv: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, kind: float, ya: float, yb: float) -> void:
	pos.append_array([a, b, c, a, c, d])
	uv.append_array([Vector2(kind, ya), Vector2(kind, yb), Vector2(kind, yb), Vector2(kind, ya), Vector2(kind, yb), Vector2(kind, ya)])


## The mountain's top over both roads for one place: a strip of forest floor as wide as the
## tunnel, at the height the land beside it has (Land.mount_height), so the hill is whole when
## seen from outside or from the drone camera. For r81_terrain.gdshader (corner colour = forest,
## depth 0: a mountain never sinks into the valley).
static func lid(part: String) -> ArrayMesh:
	var key := "lid|" + part
	if _cache.has(key):
		return _cache[key]
	var from := "cut" if part == "in" else "mount"
	var to := "cut" if part == "out" else "mount"
	var b := Geo.Buf.new()
	var forest := Color(0.0, 0.0, 1.0)
	var rows: Array = []          # [z, height] where this place is mountain
	for zt in Land._rows(from, to):
		var rise := Land.mount_rise(from, to, zt)
		if rise >= 0.0:
			rows.append([-zt * Land.LENGTH, Land.mount_height(rise, Land.TRENCH)])
	var half := (Land.ROAD_R - Land.ROAD_L) * 0.5 + Land.TRENCH
	for mid in ROAD_MIDS:
		for i in rows.size() - 1:
			var z0 := float(rows[i][0])
			var z1 := float(rows[i + 1][0])
			var y0 := float(rows[i][1])
			var y1 := float(rows[i + 1][1])
			b.quad(Vector3(mid - half, y0, z0), Vector3(mid + half, y0, z0), Vector3(mid + half, y1, z1), Vector3(mid - half, y1, z1), forest)
	var mesh := b.to_mesh()
	_cache[key] = mesh
	return mesh


## The trees on the mountain over the two roads and the rock between them (the land's own trees,
## r81_land.gd _trees, only stand outside the roads). Scattered from a fixed seed over the
## stretch that is mountain, leaving the first metres behind the mouth bare so no crown hangs
## over the portal. Returns {tree kind: MultiMesh} for r81_tree.gdshader.
static func lid_trees(part: String) -> Dictionary:
	var key := "lid_trees|" + part
	if _cache.has(key):
		return _cache[key]
	var from := "cut" if part == "in" else "mount"
	var to := "cut" if part == "out" else "mount"
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100 + key.hash() % 1000
	var lists := {}
	for kind in Land.TREES:
		lists[kind] = []
	var x0 := Land.OPP_L - Land.TRENCH
	var x1 := Land.ROAD_R + Land.TRENCH
	for i in roundi((x1 - x0) * Land.LENGTH * 0.03):
		var x := rng.randf_range(x0, x1)
		var zt := rng.randf()
		var size := rng.randf_range(1.2, 2.0)
		var turn := rng.randf() * TAU
		var pick := rng.randf()
		var rise := Land.mount_rise(from, to, zt)
		if rise < 0.12:
			continue
		var kind := "pine" if pick > 0.85 else ("oak" if pick < 0.5 else "maple")
		var xf := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(x, Land.mount_height(rise, Land.TRENCH) - 0.5, -zt * Land.LENGTH))
		(lists[kind] as Array).append([xf, Color(0.0, pick, 0.0, 0.0)])
	var out := Land.tree_batches(lists)
	_cache[key] = out
	return out


## The concrete portal round both tunnel mouths of an "in" or "out" place: a flat wall with the
## tunnel's arch cut out of it, a little in front of the rock, with a ledge on top.
## For the prop material. The tunnel's name goes on it as a Label3D (r81_trip.gd).
static func frame(part: String) -> ArrayMesh:
	var key := "frame|" + part
	if _cache.has(key):
		return _cache[key]
	var b := Geo.Buf.new()
	b.mat = Geo.MAT_PAINT
	var concrete := Color(0.58, 0.57, 0.54)
	var dark := Color(0.42, 0.41, 0.39)
	# which way is outside: we drive towards -Z, so the way in faces +Z and the way out faces -Z
	var out := 1.0 if part == "in" else -1.0
	var z := -Land.LENGTH * 0.5 + out * 0.35
	var top := Land.TUNNEL_H + 1.0
	var wide := HALF_W + 1.6
	for mid in ROAD_MIDS:
		var cuts := 28
		for i in cuts:
			var x0 := lerpf(-wide, wide, float(i) / float(cuts))
			var x1 := lerpf(-wide, wide, float(i + 1) / float(cuts))
			b.quad(Vector3(mid + x0, arch_y(x0), z), Vector3(mid + x1, arch_y(x1), z), Vector3(mid + x1, top, z), Vector3(mid + x0, top, z), concrete)
		# the ledge on top, back to the rock, and a darker band along the wall's top edge
		b.quad(Vector3(mid - wide, top, z), Vector3(mid + wide, top, z), Vector3(mid + wide, top, z - out * 1.6), Vector3(mid - wide, top, z - out * 1.6), dark)
		b.block(Vector3(mid, top - 0.25, z + out * 0.06), Vector3(wide * 2.0 + 0.3, 0.5, 0.12), dark)
		# the wall's two ends, back to the rock
		for sx: float in [-1.0, 1.0]:
			b.quad(Vector3(mid + sx * wide, 0.0, z), Vector3(mid + sx * wide, top, z), Vector3(mid + sx * wide, top, z - out * 1.6), Vector3(mid + sx * wide, 0.0, z - out * 1.6), dark)
	var mesh := b.to_mesh()
	_cache[key] = mesh
	return mesh


# ── Signs ────────────────────────────────────────────────────
## Where a green sign's panel is (its middle; X is on our right-hand verge) and its size.
const SIGN_AT := Vector3(Land.ROAD_R + 2.6, 3.3, -40.0)
const SIGN_SIZE := Vector2(4.2, 1.9)


## A green highway sign on two posts, facing the traffic that comes towards it (+Z). For the
## prop material. Its words are written by r81_trip.gd (sign_words()).
static func sign_board() -> ArrayMesh:
	if _cache.has("sign"):
		return _cache["sign"]
	var b := Geo.Buf.new()
	Geo.sign_board(b, SIGN_AT, SIGN_SIZE, 0.0, Color(0.03, 0.3, 0.17), Color(0.9, 0.9, 0.88), 2)
	var mesh := b.to_mesh()
	_cache["sign"] = mesh
	return mesh


## What the sign at place k says: two made-up places and how many miles off they are.
static func sign_words(k: int) -> String:
	var a := posmod(k * 7 + 3, PLACES.size())
	var c := posmod(a + 1 + posmod(k, 5), PLACES.size())
	var near := 2 + posmod(k * 5, 9)
	return "%s  %d\n%s  %d" % [PLACES[a], near, PLACES[c], near + 6 + posmod(k * 3, 17)]
