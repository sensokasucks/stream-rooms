extends RefCounted
## Cabin: Appalachian Forest, the outside of the Log Cabin's first scene room (rooms/cabin_forest/
## uses log_cabin_room.gd with scene = "forest"; the plan is Sen's "Log Cabin room plan" doc,
## "Outdoor scenes"). Built in code when the room loads, like the rest of the cabin:
##   - the land: a flat yard round the cabin, a valley falling away in front of the deck (so the
##     deck looks out over the treetops) and rising again to a ridge, a wooded slope behind the
##     cabin and hills to the sides. One mesh, finer near the cabin, coarser far out (height());
##     the far slopes are coloured as treetops, the near ground is the forest floor photo,
##   - a creek past the right side of the cabin, down into the valley (the Lakeside Campfire's
##     stream water, camp_stream.gdshader), with rocks in it,
##   - mixed hardwoods (oak, maple, tulip poplar, birch) and hemlocks, rhododendron thickets
##     along the creek and the forest edge, ferns and grass (the campfire's leaf-card trees,
##     campfire_trees.gd, on the Detailed look; plain shapes on the Simple look),
##   - a far forest of cheap low-poly trees on the slopes out to the ridges (both looks),
##   - a split-rail fence, mossy boulders and a trodden path down to the creek.
## The far blue ridges are drawn by the sky (camp_sky.gdshader `blue_ridges`, set by the room).
## Everything is placed with fixed seeds, so every PC in a co-stream sees the same forest.
## build() hands back what Builder.build() does (the room script uses the same keys) plus:
##   stream_mat  the creek's water (the room sets its light for the hour),
##   leaf_mats   the leaf-card materials by name (Season: autumn colours),
##   litter_mat  the forest floor's material (Season: its tint),
##   far_trees   the low-poly tree MultiMeshInstance3Ds (Season: their colours turn).

const Builder := preload("res://rooms/log_cabin/cabin_builder.gd")
const CampBuilder := preload("res://rooms/campfire/campfire_builder.gd")
const Trees := preload("res://rooms/campfire/campfire_trees.gd")
const STREAM_SHADER := preload("res://rooms/campfire/camp_stream.gdshader")
const CAMP_TEX := "res://rooms/campfire/textures/"

## The middle of the flat yard round the cabin (x, z) and how far out it stays flat (metres).
const YARD := Vector2(-2.5, 2.0)
const YARD_R: float = 19.0
## The creek's middle line (x, z) from up the slope behind the cabin, past its right side, down
## into the valley in front. smooth_creek() rounds it off.
const CREEK: Array[Vector2] = [Vector2(27.0, 300.0), Vector2(24.0, 160.0), Vector2(21.0, 75.0), Vector2(19.0, 32.0),
	Vector2(18.5, 8.0), Vector2(19.5, -10.0), Vector2(23.0, -28.0), Vector2(29.0, -55.0), Vector2(36.0, -95.0),
	Vector2(44.0, -150.0), Vector2(53.0, -230.0), Vector2(62.0, -320.0)]
## How deep the creek's bed is cut into the ground in the middle (metres), how wide the cut is
## (metres, the bell curve's width) and how deep the water stands over the bed.
const CREEK_DEPTH: float = 1.0
const CREEK_W: float = 1.7
const CREEK_WATER: float = 0.42
## Half the creek's water width (metres).
const CREEK_HALF: float = 1.5
## The land mesh: how far out it reaches each way (metres) and how many rows and columns.
## Its rows bunch up near the cabin (LAND_BUNCH): about 1.5 m apart by the creek, 15 m at the edge.
const LAND_SIZE: float = 800.0
const LAND_CELLS: int = 250
const LAND_BUNCH: float = 2.6
## The detailed trees: how many, and how far from the yard's middle they stand (metres).
const TREE_COUNT: int = 290
const TREE_RANGE := Vector2(15.0, 135.0)
## The far low-poly forest: how many trees and where (metres from the yard's middle).
const FAR_COUNT: int = 4000
const FAR_RANGE := Vector2(110.0, 470.0)
## Roughly where a seated person's eyes are on the deck: trees in front of the deck (down in the
## valley) must stay below this, so the view over the treetops stays open.
const VIEW_Y: float = 0.9
## The trodden path from the deck steps down to the creek (x, z points).
const PATH: Array[Vector2] = [Vector2(6.8, -4.8), Vector2(9.5, -9.0), Vector2(13.5, -12.5), Vector2(17.2, -14.0)]
## The split-rail fence along the front left of the yard (x, z from / to).
const FENCE_FROM := Vector2(-23.0, -6.0)
const FENCE_TO := Vector2(-5.0, -20.5)
const C_LITTER := Color(0.36, 0.3, 0.2)
const C_CANOPY := Color(0.07, 0.12, 0.06)       # far slopes: the shade between the treetops
const C_RAIL := Color(0.44, 0.4, 0.34)
const C_MOSS := Color(0.25, 0.34, 0.15)

## The creek's middle line as short pieces (a smooth curve through CREEK), built on first use.
static var _creek_fine: Array[Vector2] = []


## The cabin and this forest round it, under `room`. Returns the parts (see the file's header).
static func build(room: Node3D, view: String) -> Dictionary:
	var out := Builder.build_cabin(room, view)
	out["smoke_spots"] = Builder.SMOKE_SPOTS
	out["shelters"] = Builder.shelters()
	out["eaves"] = Builder.eaves()
	var set_root := room.get_node("Set") as Node3D
	var surf: Dictionary = out["surface_mats"]
	out["litter_mat"] = surf[Builder.S_LITTER]
	_build_land(set_root, surf)
	_build_creek(set_root, out)
	_build_rocks_and_fence(set_root, surf)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1776
	var trees := _place_trees(rng)
	var far_mat := CampBuilder._prop_material(0.05)
	var shapes := _lowpoly_shapes()
	var far := _build_far_forest(set_root, rng, shapes, far_mat)
	out["far_trees"] = far
	out["simple_trees"] = _build_simple_trees(set_root, trees, shapes, far_mat)
	out["detailed_plants"] = _build_detailed_plants(set_root, trees, rng)
	var leaf_mats: Dictionary = (out["detailed_plants"] as Node3D).get_meta("mats")
	out["leaf_mats"] = leaf_mats
	var tree_mats: Array = leaf_mats.values()
	tree_mats.append_array(((out["detailed_plants"] as Node3D).get_meta("evergreen_mats") as Dictionary).values())
	tree_mats.append(far_mat)
	out["tree_mats"] = tree_mats
	return out


# ── The land ─────────────────────────────────────────────────
## The ground's height (metres) at x, z before the creek is cut in: flat in the yard, then the
## valley in front (-Z, the deck's view) and the slope behind and the hills to the sides, with
## gentle bumps beyond the yard. Everything else that stands on the ground asks height().
static func raw_height(x: float, z: float) -> float:
	var dx := x - YARD.x
	var dz := z - YARD.y
	var r := sqrt(dx * dx + dz * dz)
	var ahead := -dz / maxf(r, 0.01)              # 1 straight out from the deck, -1 straight behind
	var front := smoothstep(0.15, 0.75, ahead)
	var back := smoothstep(0.15, 0.75, -ahead)
	var flank := 1.0 - front - back
	# (the far side of the valley climbs only a little: seen from the deck it must stay under
	# the sky's blue ridges, camp_sky.gdshader, which are the real mountains)
	var valley := -34.0 * smoothstep(YARD_R, 115.0, r) + 46.0 * smoothstep(200.0, 560.0, r)
	var slope := 26.0 * smoothstep(YARD_R + 4.0, 190.0, r) + 20.0 * smoothstep(280.0, 660.0, r)
	var hills := 9.0 * smoothstep(YARD_R + 6.0, 200.0, r) + 25.0 * smoothstep(300.0, 660.0, r)
	var h := front * valley + back * slope + flank * hills
	var bumps := 2.2 * sin(x * 0.043 + 1.3) * sin(z * 0.037 + 0.4) + 1.2 * sin(x * 0.11 + z * 0.07) + 0.6 * sin(z * 0.19 - x * 0.05)
	return Builder.GROUND_Y + h + bumps * smoothstep(YARD_R, YARD_R + 30.0, r)


## The ground's height at x, z with the creek's bed cut in.
static func height(x: float, z: float) -> float:
	var d := creek_distance(x, z)
	return raw_height(x, z) - CREEK_DEPTH * exp(-(d * d) / (CREEK_W * CREEK_W))


## The creek's middle line as short pieces about 3 m long (a smooth curve through CREEK).
static func smooth_creek() -> Array[Vector2]:
	if _creek_fine.is_empty():
		for i in CREEK.size() - 1:
			var p0: Vector2 = CREEK[maxi(i - 1, 0)]
			var p1: Vector2 = CREEK[i]
			var p2: Vector2 = CREEK[i + 1]
			var p3: Vector2 = CREEK[mini(i + 2, CREEK.size() - 1)]
			var steps := maxi(int(p1.distance_to(p2) / 3.0), 1)
			for s in steps:
				var t := float(s) / float(steps)
				_creek_fine.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
		_creek_fine.append(CREEK[CREEK.size() - 1])
	return _creek_fine


## Metres from x, z to the creek's middle line (a large number when far away).
static func creek_distance(x: float, z: float) -> float:
	if x < 10.0 or x > 75.0:
		return 1000.0                               # the creek never leaves this band
	var p := Vector2(x, z)
	var best := 1.0e9
	var pts := smooth_creek()
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if minf(a.y, b.y) > z + 20.0 or maxf(a.y, b.y) < z - 20.0:
			continue
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_squared_to(a + ab * t))
	return sqrt(best) if best < 1.0e8 else 1000.0


## Metres from x, z to the trodden path down to the creek.
static func path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1.0e9
	for i in PATH.size() - 1:
		var a: Vector2 = PATH[i]
		var ab: Vector2 = PATH[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Whether x, z is on the cabin, the den, the deck or the back stoop (nothing grows there).
static func on_cabin(x: float, z: float, margin: float) -> bool:
	return x > Builder.DEN_FAR_X - margin and x < Builder.DECK_HALF + margin and z > -Builder.DECK_DEPTH - margin - 1.2 and z < Builder.BACK_Z + 1.6 + margin


## The land: one grid, rows and columns bunched up near the cabin. Two parts: the mown yard
## (the campfire's grass photo, S_GRASS) and the forest floor (S_LITTER, a leaf-litter photo near
## by, giving way to treetop colours far out, where the corner colours' alpha drops to 0).
static func _build_land(parent: Node3D, surf: Dictionary) -> void:
	var n := LAND_CELLS + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var coords := PackedFloat32Array()
	coords.resize(n)
	for i in n:
		var u := float(i) / float(LAND_CELLS) * 2.0 - 1.0
		coords[i] = signf(u) * pow(absf(u), LAND_BUNCH) * LAND_SIZE
	for j in n:
		for i in n:
			var x := coords[i] + YARD.x
			var z := coords[j] + YARD.y
			var y := height(x, z)
			var e := 0.6
			var nrm := Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()
			var k := j * n + i
			verts[k] = Vector3(x, y, z)
			normals[k] = nrm
			var r := Vector2(x, z).distance_to(YARD)
			# far out: treetops, mottled light and dark (the low-poly forest stands on them too)
			var mottle := 0.5 + 0.5 * sin(x * 0.21 + sin(z * 0.17) * 2.0) * sin(z * 0.23 + x * 0.05)
			var canopy := C_CANOPY.lerp(C_CANOPY.lightened(0.25), mottle)
			var near := C_LITTER.lerp(C_MOSS, 0.35 * mottle)
			# the mown yard (the Simple look shows these colours; Detailed shows the grass photo)
			var yard_d := Vector2((x - YARD.x) / 1.15, z - YARD.y).length()
			near = near.lerp(Builder.C_GRASS, 1.0 - smoothstep(YARD_R - 5.0, YARD_R - 1.0, yard_d))
			var c := near.lerp(canopy, smoothstep(70.0, 140.0, r))
			c.a = 1.0 - smoothstep(85.0, 150.0, r)
			colors[k] = c
	var yard_idx := PackedInt32Array()
	var wood_idx := PackedInt32Array()
	for j in LAND_CELLS:
		for i in LAND_CELLS:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			var mid := (verts[a] + verts[d]) * 0.5
			var in_yard := Vector2((mid.x - YARD.x) / 1.15, mid.z - YARD.y).length() < YARD_R - 3.0 and creek_distance(mid.x, mid.z) > 3.5
			# (packed arrays are copied on assignment, so append to the right one directly)
			# (corner order: the face that looks up is the front)
			if in_yard:
				yard_idx.append_array([a, b, c, b, d, c])
			else:
				wood_idx.append_array([a, b, c, b, d, c])
	var mesh := ArrayMesh.new()
	for part: Array in [[yard_idx, Builder.S_GRASS], [wood_idx, Builder.S_LITTER]]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = part[0]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, surf[part[1]])
	Builder._add_mesh(parent, "Land", mesh, null, true)
	# the trodden path down to the creek: a strip of the dirt photo just above the ground
	var g := Builder.Buf.new()
	g.mat = Builder.S_DIRT
	var dirt := Builder.C_GRASS.darkened(0.25).lerp(Color(0.45, 0.38, 0.28), 0.6)
	for i in PATH.size() - 1:
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var side := Vector2(-(b - a).y, (b - a).x).normalized() * 0.6
		var corners: Array[Vector2] = [a - side, a + side, b + side, b - side]
		var pts: Array[Vector3] = []
		for q: Vector2 in corners:
			pts.append(Vector3(q.x, height(q.x, q.y) + 0.03, q.y))
		g.quad(pts[0], pts[1], pts[2], pts[3], dirt)
	Builder._add_mesh(parent, "Path", g.to_mesh(surf), null, false)


# ── The creek ────────────────────────────────────────────────
## The creek's water: a ribbon along its middle line, five corners across, laid out the way
## camp_stream.gdshader reads it (UV.x metres across, UV.y metres along, falling downstream,
## COLOR.r depth, COLOR.g how steeply it runs). The water's surface is level across and follows the land along.
static func _build_creek(parent: Node3D, out: Dictionary) -> void:
	var pts := smooth_creek()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var across: Array[float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
	var along := 0.0
	var rows := 0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var ahead: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-ahead.y, ahead.x)
		if i > 0:
			along += p.distance_to(pts[i - 1])
		var y := raw_height(p.x, p.y) - CREEK_DEPTH + CREEK_WATER
		var drop := 0.0
		if i > 0:
			var prev: Vector2 = pts[i - 1]
			drop = clampf((raw_height(prev.x, prev.y) - raw_height(p.x, p.y)) / maxf(p.distance_to(prev), 0.1) * 4.0, 0.0, 1.0)
		for a: float in across:
			var q := p + side * a * CREEK_HALF
			verts.append(Vector3(q.x, y, q.y))
			normals.append(Vector3.UP)
			# (camp_stream.gdshader runs its ripples towards smaller UV.y, its "metres from the
			# lake": our points start up the hill, so UV.y counts down the creek, or the water
			# flowed uphill)
			uvs.append(Vector2(a * CREEK_HALF, -along))
			colors.append(Color(1.0 - absf(a) * absf(a), drop, 0.0))
		if i > 0:
			for c in across.size() - 1:
				var a0 := (rows - 1) * across.size() + c
				var b0 := rows * across.size() + c
				idx.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
		rows += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = STREAM_SHADER
	mat.set_shader_parameter("ripples", load(CAMP_TEX + "water_normal.png"))
	mat.set_shader_parameter("speed", 1.2)
	out["stream_mat"] = mat
	Builder._add_mesh(parent, "Creek", mesh, mat, false)


# ── Rocks and the fence ──────────────────────────────────────
## Mossy boulders round the yard and in the creek, stepping stones where the path meets it, and
## a split-rail fence (rails laid zigzag, four high, stacked at the corners on a flat stone and held
## by crossed stakes) along the front left of the yard.
static func _build_rocks_and_fence(parent: Node3D, surf: Dictionary) -> void:
	var b := Builder.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1863
	b.mat = Builder.S_STONE
	var spots: Array[Vector2] = []
	var tries := 0
	while spots.size() < 22 and tries < 400:
		tries += 1
		var r := rng.randf_range(YARD_R - 6.0, 75.0)
		var a := rng.randf() * TAU
		var p := YARD + Vector2(cos(a), sin(a)) * r
		if on_cabin(p.x, p.y, 2.0) or path_distance(p.x, p.y) < 1.8 or creek_distance(p.x, p.y) < 2.6:
			continue
		spots.append(p)
	# a few in the creek and its banks
	for p: Vector2 in [Vector2(19.8, 18.0), Vector2(17.6, -2.0), Vector2(21.0, -20.5), Vector2(25.5, -40.0), Vector2(31.0, -66.0)]:
		spots.append(p)
	for p: Vector2 in spots:
		var size := Vector3(rng.randf_range(0.9, 2.4), rng.randf_range(0.6, 1.4), rng.randf_range(0.8, 2.0))
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
		var y := height(p.x, p.y) + size.y * 0.25
		var xf := Transform3D(basis, Vector3(p.x, y, p.y))
		var grey := Builder.C_STONE.darkened(rng.randf_range(0.0, 0.25))
		b.soft_box(xf, size, minf(size.x, size.z) * 0.4, grey)
		# moss over the top: a flatter, slightly smaller cap poking out of the rock's top
		b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.32, 0.0)), Vector3(size.x * 0.86, size.y * 0.45, size.z * 0.86),
			minf(size.x, size.z) * 0.35, C_MOSS.darkened(rng.randf_range(0.0, 0.2)))
	# stepping stones across the creek at the end of the path
	var end: Vector2 = PATH[PATH.size() - 1]
	for k in 4:
		var q := end + Vector2(0.9 + float(k) * 0.95, -0.5 - float(k) * 0.35)
		b.soft_box(Transform3D(Basis(Vector3.UP, float(k)), Vector3(q.x, raw_height(q.x, q.y) - CREEK_DEPTH + CREEK_WATER + 0.06, q.y)),
			Vector3(0.75, 0.3, 0.6), 0.14, Builder.C_STONE.darkened(0.1))
	# the fence: a "worm" fence, sections laid zigzag (each rail from one corner to the next),
	# four rails high. At each corner the rails of the two sections lie on one another, the
	# bottom ones on a flat stone, and a pair of stakes driven in crosswise holds the stack, so
	# nothing hangs in the air (round 7: the rails floated with no corners, like a wavy pipe).
	b.mat = Builder.S_TIMBER
	var run := FENCE_TO - FENCE_FROM
	var count := int(run.length() / 3.0)
	var side := Vector2(-run.y, run.x).normalized()
	var along := Vector3(run.x, 0.0, run.y).normalized()
	var across := Vector3(side.x, 0.0, side.y)
	var corners: Array[Vector3] = []
	for i in count + 1:
		var p := FENCE_FROM + run * float(i) / float(count) + side * (0.45 if i % 2 == 0 else -0.45)
		corners.append(Vector3(p.x, height(p.x, p.y), p.y))
	const RAIL_R := 0.07
	for i in count:
		for level in 4:
			# odd sections sit one rail-radius higher, so at each corner a rail of one section lies
			# on a rail of the next, alternating up the stack
			var lift := 0.14 + float(level) * 0.26 + (RAIL_R if i % 2 == 1 else 0.0)
			var col := C_RAIL.darkened(rng.randf_range(0.0, 0.2))
			# (the rails run a little past the corners, as split rails do)
			var a := corners[i] - along * 0.25
			var c := corners[i + 1] + along * 0.25
			b.rod(Vector3(a.x, corners[i].y + lift, a.z), Vector3(c.x, corners[i + 1].y + lift, c.z), RAIL_R, 7, col)
	b.mat = Builder.S_STONE
	for q: Vector3 in corners:
		b.soft_box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q + Vector3(0.0, 0.02, 0.0)), Vector3(0.5, 0.16, 0.45), 0.06, Builder.C_STONE.darkened(0.15))
	b.mat = Builder.S_TIMBER
	for q: Vector3 in corners:
		# two stakes, one each side of the stack, leaning in to cross about 0.3 m above the top
		# rail (they clear the rails: 0.1 m out at the top rail's height)
		for sd: float in [-1.0, 1.0]:
			var foot := q + across * (sd * 0.5) + Vector3(0.0, -0.1, 0.0)
			var top := q + across * (-sd * 0.08) + Vector3(0.0, 1.6, 0.0)
			b.rod(foot, top, 0.055, 6, C_RAIL.darkened(0.12))
	Builder._add_mesh(parent, "RocksAndFence", b.to_mesh(surf), null, true)


# ── Trees ────────────────────────────────────────────────────
## Where the detailed trees stand: [foot, height, kind]. Kinds: oak, maple, poplar (tall and
## narrow), birch, hemlock (dark, drooping, more of them by the creek) and rhodo (a rhododendron
## thicket: a low wide bush, along the creek and the forest's edge). Trees in front of the deck
## stand only where the valley has dropped far enough that their tops stay below the view.
static func _place_trees(rng: RandomNumberGenerator) -> Array:
	var trees: Array = []
	var taken: Array[Vector2] = []
	var tries := 0
	while trees.size() < TREE_COUNT and tries < 8000:
		tries += 1
		var r := lerpf(TREE_RANGE.x, TREE_RANGE.y, pow(rng.randf(), 1.4))
		var a := rng.randf() * TAU
		var p := YARD + Vector2(cos(a) * r * 1.15, sin(a) * r)
		if on_cabin(p.x, p.y, 3.0) or path_distance(p.x, p.y) < 2.5:
			continue
		var by_creek := creek_distance(p.x, p.y)
		if by_creek < 3.0:
			continue
		var too_close := false
		for q: Vector2 in taken:
			if q.distance_squared_to(p) < 10.0:
				too_close = true
				break
		if too_close:
			continue
		var roll := rng.randf()
		var hem := 0.55 if by_creek < 15.0 else 0.3
		var kind := "hemlock"
		var tall := rng.randf_range(12.0, 19.0)
		if roll > hem:
			var t := (roll - hem) / (1.0 - hem)
			if t < 0.3:
				kind = "oak"
				tall = rng.randf_range(11.0, 17.0)
			elif t < 0.55:
				kind = "maple"
				tall = rng.randf_range(10.0, 15.0)
			elif t < 0.8:
				kind = "poplar"
				tall = rng.randf_range(17.0, 25.0)
			else:
				kind = "birch"
				tall = rng.randf_range(9.0, 14.0)
		var y := height(p.x, p.y)
		var ahead := (YARD.y - p.y) / maxf(p.distance_to(YARD), 0.01)
		if ahead > 0.45 and y + tall * 0.95 > VIEW_Y:
			continue                                    # it would stand in the deck's view
		taken.append(p)
		trees.append([Vector3(p.x, y, p.y), tall, kind])
	# rhododendron: low thickets along the creek and round the yard's edge
	var bushes := 0
	tries = 0
	while bushes < 80 and tries < 4000:
		tries += 1
		var p: Vector2
		if rng.randf() < 0.55:
			var pts := smooth_creek()
			var c: Vector2 = pts[rng.randi_range(0, pts.size() - 1)]
			p = c + Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-4.0, 4.0))
		else:
			var a := rng.randf() * TAU
			p = YARD + Vector2(cos(a) * 1.15, sin(a)) * rng.randf_range(YARD_R - 1.0, YARD_R + 14.0)
		if p.distance_to(YARD) > 120.0 or on_cabin(p.x, p.y, 2.5) or path_distance(p.x, p.y) < 2.0 or creek_distance(p.x, p.y) < 2.4:
			continue
		var y := height(p.x, p.y)
		var ahead := (YARD.y - p.y) / maxf(p.distance_to(YARD), 0.01)
		if ahead > 0.45 and y + 2.5 > VIEW_Y - 1.0 and p.distance_to(YARD) < 30.0:
			continue
		trees.append([Vector3(p.x, y, p.y), rng.randf_range(1.8, 3.2), "rhodo"])
		bushes += 1
	return trees


## The two cheap tree shapes (the Lakeside Campfire's low-poly ones, 1 unit tall): a fir (for the
## hemlocks) and a round leafy tree (the hardwoods). [fir Buf, round Buf]
static func _lowpoly_shapes() -> Array:
	var fir := CampBuilder.Buf.new()
	fir.cyl(Transform3D.IDENTITY, 0.035, 0.02, 0.5, 6, Color(0.2, 0.13, 0.08))
	for t: Array in [[0.16, 0.27, 0.34], [0.36, 0.22, 0.3], [0.55, 0.16, 0.27], [0.72, 0.1, 0.28]]:
		var green := Color(0.04, 0.13, 0.08).lerp(Color(0.07, 0.2, 0.11), float(t[0]))
		fir.cyl(Transform3D(Basis.IDENTITY, Vector3(0.0, float(t[0]), 0.0)), float(t[1]), 0.0, float(t[2]), 8, green)
	fir.alpha_by_height(1.0)
	var round_tree := CampBuilder.Buf.new()
	round_tree.cyl(Transform3D.IDENTITY, 0.045, 0.03, 0.5, 6, Color(0.23, 0.16, 0.1))
	var crown := RandomNumberGenerator.new()
	crown.seed = 11
	round_tree.blob(Vector3(0.0, 0.66, 0.0), Vector3(0.3, 0.26, 0.3), 9, 6, Color(0.2, 0.34, 0.1), Color(0.07, 0.16, 0.06), 0.16, crown)
	round_tree.blob(Vector3(0.16, 0.8, 0.06), Vector3(0.2, 0.18, 0.2), 8, 5, Color(0.24, 0.38, 0.12), Color(0.09, 0.19, 0.07), 0.16, crown)
	round_tree.blob(Vector3(-0.14, 0.76, -0.1), Vector3(0.19, 0.17, 0.19), 8, 5, Color(0.18, 0.32, 0.1), Color(0.07, 0.16, 0.06), 0.16, crown)
	round_tree.alpha_by_height(1.0)
	return [fir, round_tree]


## The far forest on the slopes out to the ridges: low-poly firs and round trees (both looks, as
## they are cheap). Returns its two MultiMeshInstance3Ds (the Season turns the round ones).
static func _build_far_forest(parent: Node3D, rng: RandomNumberGenerator, shapes: Array, mat: Material) -> Array[Node3D]:
	var firs: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var fir_tints := PackedColorArray()
	var round_tints := PackedColorArray()
	var tries := 0
	while firs.size() + rounds.size() < FAR_COUNT and tries < FAR_COUNT * 4:
		tries += 1
		var r := lerpf(FAR_RANGE.x, FAR_RANGE.y, sqrt(rng.randf()))
		var a := rng.randf() * TAU
		var p := YARD + Vector2(cos(a), sin(a)) * r
		if creek_distance(p.x, p.y) < 4.0:
			continue
		var y := height(p.x, p.y)
		var ahead := (YARD.y - p.y) / maxf(r, 0.01)
		var tall := rng.randf_range(11.0, 17.0) * (1.0 + r / 1500.0)      # far ones a little bigger, so they read
		if ahead > 0.45 and y + tall > VIEW_Y and r < 200.0:
			continue
		var wide := tall * rng.randf_range(1.4, 1.9)       # wide, so the crowns close up into a canopy
		var shade := rng.randf_range(0.6, 1.0)
		if rng.randf() < 0.35:
			firs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide * 0.75, tall, wide * 0.75)), Vector3(p.x, y - 0.3, p.y)))
			fir_tints.append(Color(shade, shade, shade))
		else:
			rounds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide * 1.1, tall * 0.8, wide * 1.1)), Vector3(p.x, y - 0.3, p.y)))
			round_tints.append(Color(shade, shade * 1.04, shade * 0.9))
	var out: Array[Node3D] = [
		CampBuilder._add_trees(parent, "FarHemlocks", shapes[0], firs, fir_tints, mat),
		CampBuilder._add_trees(parent, "FarRoundTrees", shapes[1], rounds, round_tints, mat)]
	return out


## The Simple look's near trees: the same spots as the detailed ones, drawn with the low-poly
## shapes (hemlocks as firs, the rest as round trees, rhododendrons as low round bushes).
static func _build_simple_trees(parent: Node3D, trees: Array, shapes: Array, mat: Material) -> Node3D:
	var holder := Node3D.new()
	holder.name = "SimpleTrees"
	parent.add_child(holder)
	var firs: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var fir_tints := PackedColorArray()
	var round_tints := PackedColorArray()
	for one: Array in trees:
		var foot: Vector3 = one[0]
		var tall := float(one[1])
		var kind := String(one[2])
		var turn := Basis(Vector3.UP, fmod(foot.x * 1.7 + foot.z * 0.9, TAU))
		var shade := 0.8 + 0.3 * fmod(absf(foot.x * 0.37 + foot.z * 0.21), 1.0)
		if kind == "hemlock":
			firs.append(Transform3D(turn.scaled(Vector3(tall * 0.42, tall, tall * 0.42)), foot))
			fir_tints.append(Color(shade, shade, shade))
		else:
			var wide := tall * (2.0 if kind == "rhodo" else 0.6 if kind == "poplar" else 0.85)
			rounds.append(Transform3D(turn.scaled(Vector3(wide, tall, wide)), foot - Vector3(0.0, 0.1 if kind != "rhodo" else 0.6 * tall, 0.0)))
			var dark := 0.65 if kind == "rhodo" else 1.0
			round_tints.append(Color(shade * dark, shade * dark * 1.04, shade * dark * 0.9))
	CampBuilder._add_trees(holder, "Hemlocks", shapes[0], firs, fir_tints, mat)
	CampBuilder._add_trees(holder, "RoundTrees", shapes[1], rounds, round_tints, mat)
	return holder


## The Detailed look's plants (hidden until the room script shows them): the campfire's
## leaf-card trees on the tree spots (hemlocks are its fir, darker; poplars its maple, tall and
## narrow; rhododendrons its oak, low, wide and dark), young hemlocks and ferns at the trees'
## feet, and grass tufts in the yard. One MultiMesh per kind of card tree (campfire_trees.gd
## kit(), which brings its own materials, handed on through the node's "mats" meta).
static func _build_detailed_plants(parent: Node3D, trees: Array, rng: RandomNumberGenerator) -> Node3D:
	var holder := Node3D.new()
	holder.name = "DetailedPlants"
	holder.visible = false
	parent.add_child(holder)
	var mats := Trees.materials(0.05)
	holder.set_meta("mats", mats)
	# rhododendron is evergreen: its bushes (the oak's shape) get their own leaf materials, which
	# the Season leaves alone (kept on the node's "evergreen_mats" meta for the weather's wind)
	var evergreen := Trees.materials(0.05)
	holder.set_meta("evergreen_mats", evergreen)
	var spots: Dictionary = {}      # kit kind -> [[Transform3D, shade], ...]
	for one: Array in trees:
		var foot: Vector3 = one[0]
		var tall := float(one[1])
		var kind := String(one[2])
		var turn := Basis(Vector3.UP, rng.randf() * TAU)
		var shade := rng.randf_range(0.82, 1.06)
		match kind:
			"hemlock":
				_spot(spots, "fir", Transform3D(turn.scaled(Vector3(tall * 0.48, tall * 1.1, tall * 0.48)), foot - Vector3(0.0, 0.05, 0.0)), shade * 0.68)
			"poplar":
				_spot(spots, "maple", Transform3D(turn.scaled(Vector3(tall * 0.42, tall * 1.1, tall * 0.42)), foot - Vector3(0.0, 0.05, 0.0)), shade)
			"rhodo":
				_spot(spots, "rhodo", Transform3D(turn.scaled(Vector3(tall * 1.5, tall, tall * 1.5)), foot - Vector3(0.0, tall * 0.35, 0.0)), shade * 0.6)
			"birch":
				_spot(spots, "birch", Transform3D(turn.scaled(Vector3(tall * 0.55, tall * 1.1, tall * 0.55)), foot - Vector3(0.0, 0.05, 0.0)), shade)
			_:
				_spot(spots, kind, Transform3D(turn.scaled(Vector3(tall * 0.75, tall * 1.1, tall * 0.75)), foot - Vector3(0.0, 0.05, 0.0)), shade)
		if kind == "rhodo":
			continue
		if foot.distance_to(Vector3(YARD.x, foot.y, YARD.y)) < 60.0:
			if rng.randf() < 0.4:
				var off := Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
				var yt := rng.randf_range(2.5, 5.5)
				_spot(spots, "young_fir", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(yt * 0.45, yt, yt * 0.45)),
					Vector3(foot.x + off.x, height(foot.x + off.x, foot.z + off.z), foot.z + off.z)), 0.75)
			for f in 3:
				var off := Vector3(rng.randf_range(-2.5, 2.5), 0.0, rng.randf_range(-2.5, 2.5))
				var fs := rng.randf_range(0.7, 1.4)
				_spot(spots, "fern", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs, fs)),
					Vector3(foot.x + off.x, height(foot.x + off.x, foot.z + off.z) - 0.02, foot.z + off.z)), 1.0)
	# grass tufts in the yard (off the cabin, the path and the creek)
	var left := 1300
	var tries := 0
	while left > 0 and tries < 10000:
		tries += 1
		var p := YARD + Vector2(rng.randf_range(-1.0, 1.0) * YARD_R * 1.15, rng.randf_range(-1.0, 1.0) * YARD_R)
		if Vector2((p.x - YARD.x) / 1.15, p.y - YARD.y).length() > YARD_R - 2.0:
			continue
		if on_cabin(p.x, p.y, 0.8) or path_distance(p.x, p.y) < 0.9 or creek_distance(p.x, p.y) < 2.2:
			continue
		var sz := rng.randf_range(0.5, 1.1)
		_spot(spots, "grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.8, 1.3), sz)),
			Vector3(p.x, height(p.x, p.y) - 0.02, p.y)), 0.82 + 0.24 * rng.randf())
		left -= 1
	for kind: String in spots:
		var list: Array = spots[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Trees.kit("oak", evergreen) if kind == "rhodo" else Trees.kit(kind, mats)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			var s := float(list[i][1])
			mm.set_instance_color(i, Color(s, s, s))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind.to_pascal_case()
		mmi.multimesh = mm
		var small := kind == "grass" or kind == "fern"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if small:
			mmi.visibility_range_end = 60.0
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mmi)
	return holder


static func _spot(spots: Dictionary, kind: String, xf: Transform3D, shade: float) -> void:
	if not spots.has(kind):
		spots[kind] = []
	(spots[kind] as Array).append([xf, shade])
