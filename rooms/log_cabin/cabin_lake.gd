extends RefCounted
## Cabin: Lakeside, the outside of the Log Cabin's second scene room (rooms/cabin_lake/ uses
## log_cabin_room.gd with scene = "lake"; the plan is Sen's "Log Cabin room plan" doc, "Outdoor
## scenes": grass and pine needles, pines, birch and fir, a calm lake with the far shore and
## mountains, a dock, a canoe pulled up on the shore, reeds and lily pads, loons calling).
## Built in code when the room loads, like the rest of the cabin:
##   - the land: the flat yard round the cabin, a lawn running down in front of the deck to a
##     sandy beach, and the lake beyond. The shore curves away to both sides as two wooded arms,
##     so the lake opens out between them to the far shore; a slope with forest rises behind the
##     cabin. A small wooded island sits out on the water. One mesh, finer near the cabin,
##     coarser far out (height() for anything standing on it); three parts: grass (the yard and
##     the lawn), sand (the beach) and pine needles (the woods, giving way to treetop colours far
##     out, as in the forest room),
##   - the lake: one huge flat sheet at WATER_Y with the Lakeside Campfire's water shader
##     (camp_water.gdshader), which mirrors the sky and the far shore and mountains the sky draws
##     (camp_sky.gdshader's own horizon: this room leaves `blue_ridges` off),
##   - white pines, firs and birches (the campfire's leaf-card trees on the Detailed look, plain
##     shapes on the Simple one) and a far forest of cheap low-poly trees on the arms, the slope
##     behind and the island (both looks),
##   - a dock out into the lake with two chairs at its end, a canoe pulled up on the beach, reeds
##     along the shore, lily pads, granite boulders, and a trodden path from the deck steps to the
##     dock.
## The loons' calls are played by the room script (log_cabin_room.gd _run_loons).
## Everything is placed with fixed seeds, so every PC in a co-stream sees the same lake.
## build() hands back what Builder.build() does (the room script uses the same keys) plus:
##   lake_mat    the lake's water (the room sets its sky, light and waves for the hour and wind),
##   leaf_mats   the leaf-card materials by name (Season: the birches turn),
##   litter_mat  the pine needles' material (Season: its tint),
##   far_trees   the low-poly tree MultiMeshInstance3Ds (Season: the round ones turn).

const Builder := preload("res://rooms/log_cabin/cabin_builder.gd")
const CampBuilder := preload("res://rooms/campfire/campfire_builder.gd")
const Trees := preload("res://rooms/campfire/campfire_trees.gd")
const WATER_SHADER := preload("res://rooms/campfire/camp_water.gdshader")
const CAMP_TEX := "res://rooms/campfire/textures/"

## The middle of the flat yard round the cabin (x, z) and how far out it stays flat (metres).
## (The same yard as the forest room's, so the fireflies and the cameras fit both.)
const YARD := Vector2(-2.5, 2.0)
const YARD_R: float = 19.0
## The lake's surface (y, metres): 2.6 m below the yard, so the deck looks down onto the water.
const WATER_Y: float = Builder.GROUND_Y - 2.6
## How far the water's edge is from the yard's middle straight out in front of the deck (metres).
## To the sides it is further (shore_r()): the two arms of the shore.
const SHORE_FRONT: float = 32.0
## The island out on the lake (x, z) and its radius (metres).
const ISLAND := Vector2(-85.0, -230.0)
const ISLAND_R: float = 36.0
## The land mesh: how far out it reaches each way (metres) and how many rows and columns; the
## rows bunch up near the cabin (LAND_BUNCH): about 1.5 m apart by the beach, 17 m at the edge.
const LAND_SIZE: float = 900.0
const LAND_CELLS: int = 250
const LAND_BUNCH: float = 2.6
## The detailed trees: how many, and how far from the yard's middle they stand (metres).
const TREE_COUNT: int = 260
const TREE_RANGE := Vector2(15.0, 130.0)
## The far low-poly forest: how many trees and where (metres from the yard's middle).
const FAR_COUNT: int = 3800
const FAR_RANGE := Vector2(100.0, 520.0)
## Roughly where a seated person's eyes are on the deck: nothing in front of the deck stands
## above this, so the view down the lawn to the lake stays open.
const VIEW_Y: float = 0.9
## Which way the dock runs from the yard's middle (it starts where this line meets the beach,
## dock_root()), how long it is and how high its planks are over the water (metres).
const DOCK_DIR := Vector2(0.34, -0.94)
const DOCK_LEN: float = 15.0
const DOCK_UP: float = 0.55
## Where the trodden path starts: the foot of the deck steps (x, z).
const PATH_START := Vector2(6.8, -4.8)
const C_NEEDLES := Color(0.4, 0.3, 0.2)          # pine needles under the trees
const C_SAND := Color(0.66, 0.6, 0.48)
const C_CANOPY := Color(0.06, 0.11, 0.07)        # far slopes: the shade between the treetops
const C_GRANITE := Color(0.56, 0.54, 0.52)
const C_MOSS := Color(0.25, 0.34, 0.15)
const C_CANOE := Color(0.62, 0.16, 0.1)          # an old red canvas canoe


## The cabin and the lake round it, under `room`. Returns the parts (see the file's header).
static func build(room: Node3D, view: String) -> Dictionary:
	var out := Builder.build_cabin(room, view)
	out["smoke_spots"] = Builder.SMOKE_SPOTS
	out["shelters"] = Builder.shelters()
	out["eaves"] = Builder.eaves()
	var set_root := room.get_node("Set") as Node3D
	var surf: Dictionary = out["surface_mats"]
	out["litter_mat"] = surf[Builder.S_LITTER]
	# pine needles: browner and warmer than the forest room's leaf litter
	(surf[Builder.S_LITTER] as ShaderMaterial).set_shader_parameter("photo_tint", Color(0.92, 0.78, 0.6))
	_build_land(set_root, surf)
	_build_lake(set_root, out)
	_build_shore_things(set_root, surf)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1867
	var trees := _place_trees(rng)
	var far_mat := CampBuilder._prop_material(0.05)
	var shapes := _lowpoly_shapes()
	out["far_trees"] = _build_far_forest(set_root, rng, shapes, far_mat)
	out["simple_trees"] = _build_simple_trees(set_root, trees, shapes, far_mat)
	out["detailed_plants"] = _build_detailed_plants(set_root, trees, rng)
	var leaf_mats: Dictionary = (out["detailed_plants"] as Node3D).get_meta("mats")
	out["leaf_mats"] = leaf_mats
	var tree_mats: Array = leaf_mats.values()
	tree_mats.append(far_mat)
	out["tree_mats"] = tree_mats
	return out


# ── The land ─────────────────────────────────────────────────
## Metres from the yard's middle to the water's edge in the direction of x, z: SHORE_FRONT
## straight out in front of the deck, further and further to the sides (the arms of the shore
## curve away forwards), and the land never ends behind the cabin. A gentle wobble keeps it from
## looking drawn with compasses.
static func shore_r(x: float, z: float) -> float:
	var dx := x - YARD.x
	var dz := z - YARD.y
	var r := maxf(sqrt(dx * dx + dz * dz), 0.01)
	var ahead := -dz / r                          # 1 straight out from the deck, -1 straight behind
	var open := smoothstep(-0.1, 0.85, ahead)
	var ang := atan2(dx, -dz)
	var wobble := 1.0 + 0.07 * sin(ang * 7.0 + 1.0) + 0.05 * sin(ang * 13.0 + 0.3)
	return SHORE_FRONT / maxf(open, 0.04) * wobble


## The ground's height (metres) at x, z. Flat in the yard; in front, the lawn slopes down to the
## beach and on under the water; behind, the wooded slope rises; to the sides, low wooded hills
## that come down to the water along the arms. The island rises out of the lake. Everything that
## stands on the ground asks this.
static func height(x: float, z: float) -> float:
	var dx := x - YARD.x
	var dz := z - YARD.y
	var r := sqrt(dx * dx + dz * dz)
	var ahead := -dz / maxf(r, 0.01)
	var back := smoothstep(0.15, 0.75, -ahead)
	var front := smoothstep(0.15, 0.75, ahead)
	var rise := back * (26.0 * smoothstep(YARD_R + 4.0, 190.0, r) + 30.0 * smoothstep(280.0, 700.0, r)) \
		+ (1.0 - back) * (10.0 * smoothstep(YARD_R + 6.0, 160.0, r) + 22.0 * smoothstep(300.0, 700.0, r)) * (1.0 - 0.5 * front)
	var bumps := 2.0 * sin(x * 0.043 + 1.3) * sin(z * 0.037 + 0.4) + 1.1 * sin(x * 0.11 + z * 0.07) + 0.5 * sin(z * 0.19 - x * 0.05)
	var land := Builder.GROUND_Y + rise + bumps * smoothstep(YARD_R, YARD_R + 30.0, r)
	var edge := shore_r(x, z)
	var d := r - edge                             # metres out past the water's edge (below 0 = on land)
	var h: float
	if d < 0.0:
		# from the water's edge up to the land: in front that is the lawn, which must reach the
		# yard's level by the yard's edge
		var ramp := clampf(edge - YARD_R - 1.0, 6.0, 30.0)
		h = lerpf(WATER_Y + 0.05, land, smoothstep(0.0, ramp, -d))
	else:
		h = WATER_Y + 0.05 - 3.5 * smoothstep(0.0, 25.0, d)       # a shallow shelf, then deeper
	# the island: a low wooded hump
	var isl := 1.0 - smoothstep(0.0, ISLAND_R, Vector2(x, z).distance_to(ISLAND))
	if isl > 0.0:
		h = maxf(h, WATER_Y - 2.0 + 8.0 * sqrt(isl))
	return h


## Whether x, z is on the lawn in front of the deck (kept open: no trees, no rocks).
static func on_lawn(x: float, z: float) -> bool:
	var dx := x - YARD.x
	var dz := z - YARD.y
	var r := sqrt(dx * dx + dz * dz)
	return r < 48.0 and -dz / maxf(r, 0.01) > 0.42 and r < shore_r(x, z) + 1.0


## Whether x, z is in the water (or right at its edge, `margin` metres onto the land).
static func in_water(x: float, z: float, margin: float = 0.0) -> bool:
	return height(x, z) < WATER_Y + 0.05 + margin * 0.12


## Where the dock starts: the point on DOCK_DIR from the yard's middle where the beach meets the
## water (x, z).
static func dock_root() -> Vector2:
	var r := YARD_R
	while r < 80.0 and height(YARD.x + DOCK_DIR.x * r, YARD.y + DOCK_DIR.y * r) > WATER_Y + 0.25:
		r += 0.25
	return YARD + DOCK_DIR * r


## The trodden path from the deck steps to the dock (x, z points).
static func path_points() -> Array[Vector2]:
	var end := dock_root()
	var pts: Array[Vector2] = []
	for i in 6:
		var t := float(i) / 5.0
		# (bowed a little to the right, as feet go round the slope)
		pts.append(PATH_START.lerp(end, t) + Vector2(1.4, 0.0) * sin(t * PI))
	return pts


## Metres from x, z to the trodden path.
static func path_distance(x: float, z: float) -> float:
	var pts := path_points()
	var p := Vector2(x, z)
	var best := 1.0e9
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var ab: Vector2 = pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Metres from x, z to the dock's middle line (from the beach to its end).
static func dock_distance(x: float, z: float) -> float:
	var a := dock_root() - DOCK_DIR * 3.0
	var ab := DOCK_DIR * (DOCK_LEN + 6.0)
	var p := Vector2(x, z)
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Whether x, z is on the cabin, the den, the deck or the back stoop (nothing grows there).
static func on_cabin(x: float, z: float, margin: float) -> bool:
	return x > Builder.DEN_FAR_X - margin and x < Builder.DECK_HALF + margin and z > -Builder.DECK_DEPTH - margin - 1.2 and z < Builder.BACK_Z + 1.6 + margin


## The land: one grid, rows and columns bunched up near the cabin, in three parts: grass (the
## yard and the lawn), sand (the beach and the lake bed) and pine needles (the woods; far out the
## corner colours' alpha drops to 0 and the treetop colours show instead of the photo).
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
			var mottle := 0.5 + 0.5 * sin(x * 0.21 + sin(z * 0.17) * 2.0) * sin(z * 0.23 + x * 0.05)
			var canopy := C_CANOPY.lerp(C_CANOPY.lightened(0.22), mottle)
			var near := C_NEEDLES.lerp(C_MOSS, 0.25 * mottle)
			var yard_d := Vector2((x - YARD.x) / 1.15, z - YARD.y).length()
			var grassy := 1.0 - smoothstep(YARD_R - 5.0, YARD_R - 1.0, yard_d)
			if on_lawn(x, z):
				grassy = 1.0
			near = near.lerp(Builder.C_GRASS, grassy)
			# the beach: sand where the ground is within a metre of the water
			near = near.lerp(C_SAND, 1.0 - smoothstep(WATER_Y + 0.35, WATER_Y + 1.1, y))
			var c := near.lerp(canopy, smoothstep(70.0, 140.0, r) * smoothstep(WATER_Y + 0.6, WATER_Y + 2.5, y))
			c.a = 1.0 - smoothstep(85.0, 150.0, r)
			colors[k] = c
	var grass_idx := PackedInt32Array()
	var sand_idx := PackedInt32Array()
	var wood_idx := PackedInt32Array()
	for j in LAND_CELLS:
		for i in LAND_CELLS:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			var mid := (verts[a] + verts[d]) * 0.5
			var low := minf(minf(verts[a].y, verts[b].y), minf(verts[c].y, verts[d].y))
			# (packed arrays are copied on assignment, so append to the right one directly)
			# (corner order: the face that looks up is the front)
			if low < WATER_Y + 0.7:
				sand_idx.append_array([a, b, c, b, d, c])
			elif Vector2((mid.x - YARD.x) / 1.15, mid.z - YARD.y).length() < YARD_R - 3.0 or on_lawn(mid.x, mid.z):
				grass_idx.append_array([a, b, c, b, d, c])
			else:
				wood_idx.append_array([a, b, c, b, d, c])
	var mesh := ArrayMesh.new()
	for part: Array in [[grass_idx, Builder.S_GRASS], [sand_idx, Builder.S_SAND], [wood_idx, Builder.S_LITTER]]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = part[0]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, surf[part[1]])
	Builder._add_mesh(parent, "Land", mesh, null, true)
	# the trodden path to the dock: a strip of the dirt photo just above the ground
	var g := Builder.Buf.new()
	g.mat = Builder.S_DIRT
	var dirt := Builder.C_GRASS.darkened(0.25).lerp(Color(0.45, 0.38, 0.28), 0.6)
	var pts := path_points()
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var side := Vector2(-(b - a).y, (b - a).x).normalized() * 0.55
		var corners: Array[Vector2] = [a - side, a + side, b + side, b - side]
		var at: Array[Vector3] = []
		for q: Vector2 in corners:
			at.append(Vector3(q.x, height(q.x, q.y) + 0.03, q.y))
		g.quad(at[0], at[1], at[2], at[3], dirt)
	Builder._add_mesh(parent, "Path", g.to_mesh(surf), null, false)


# ── The lake ─────────────────────────────────────────────────
## The water: one huge flat sheet at WATER_Y (the land hides it wherever it is higher), with the
## Lakeside Campfire's water shader. The room script sets its sky, light, the cabin's warm streak
## and the waves (log_cabin_room.gd _apply_time).
static func _build_lake(parent: Node3D, out: Dictionary) -> void:
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(3200.0, 1800.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("ripples", load(CAMP_TEX + "water_normal.png"))
	mat.set_shader_parameter("flow", Vector2(0.03, -0.02))
	out["lake_mat"] = mat
	var mi := Builder._add_mesh(parent, "Lake", sheet, mat, false)
	mi.position = Vector3(YARD.x, WATER_Y, YARD.y - 800.0)


# ── The dock, the canoe, the reeds, lily pads and rocks ──────
## Everything at the water's edge, in one mesh: the dock on posts (planks in the deck's wood) with
## a square end, two chairs and a ladder; the red canoe pulled up on the beach with its paddle;
## reeds and cattails in clumps along the shore; lily pads (some in flower) in the shallows; and
## granite boulders on the beach, in the water and round the yard.
static func _build_shore_things(parent: Node3D, surf: Dictionary) -> void:
	var b := Builder.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1903
	_build_dock(b)
	_build_canoe(b)
	_build_reeds_and_pads(b, rng)
	# granite boulders: some along the beach and in the shallows, some round the yard's edge
	b.mat = Builder.S_STONE
	var spots: Array[Vector2] = []
	var tries := 0
	while spots.size() < 34 and tries < 2000:
		tries += 1
		var p: Vector2
		if spots.size() < 20:
			var ang := rng.randf_range(-1.5, 1.5)           # radians either side of straight ahead
			var dir := Vector2(sin(ang), -cos(ang))
			var edge := shore_r(YARD.x + dir.x * 50.0, YARD.y + dir.y * 50.0)
			if edge > 120.0:
				continue
			p = YARD + dir * (edge + rng.randf_range(-3.0, 4.0))
		else:
			var a := rng.randf() * TAU
			p = YARD + Vector2(cos(a) * 1.15, sin(a)) * rng.randf_range(YARD_R + 2.0, 60.0)
		if on_cabin(p.x, p.y, 2.0) or on_lawn(p.x, p.y) and spots.size() >= 20 or path_distance(p.x, p.y) < 2.0 or dock_distance(p.x, p.y) < 3.5:
			continue
		spots.append(p)
	for p: Vector2 in spots:
		var size := Vector3(rng.randf_range(0.8, 2.6), rng.randf_range(0.5, 1.3), rng.randf_range(0.7, 2.2))
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
		var y := height(p.x, p.y) + size.y * 0.2
		var xf := Transform3D(basis, Vector3(p.x, y, p.y))
		var grey := C_GRANITE.darkened(rng.randf_range(0.0, 0.3))
		b.soft_box(xf, size, minf(size.x, size.z) * 0.42, grey)
		if y > WATER_Y + 1.0 and rng.randf() < 0.5:
			# a little moss on the dry ones up in the woods
			b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.34, 0.0)), Vector3(size.x * 0.8, size.y * 0.4, size.z * 0.8),
				minf(size.x, size.z) * 0.35, C_MOSS.darkened(rng.randf_range(0.0, 0.2)))
	Builder._add_mesh(parent, "ShoreThings", b.to_mesh(surf), null, true)


## The dock: planks across two stringers on pairs of posts, from the beach out over the water,
## ending in a square platform with two chairs facing the lake and a ladder down into the water.
static func _build_dock(b: Builder.Buf) -> void:
	var root := dock_root() - DOCK_DIR * 1.5             # (starts a little up the beach)
	var side := Vector2(-DOCK_DIR.y, DOCK_DIR.x)
	var y := WATER_Y + DOCK_UP
	var along := Basis.looking_at(Vector3(DOCK_DIR.x, 0.0, DOCK_DIR.y), Vector3.UP)    # -Z = out over the lake
	var at := func(s: float, t: float, h: float) -> Vector3:     # s across, t along, h up
		var q := root + DOCK_DIR * t + side * s
		return Vector3(q.x, h, q.y)
	var wood := Builder.C_DECK
	var end_t := DOCK_LEN
	# planks: 1.8 m wide along the walk, 4 m wide on the square end
	b.mat = Builder.S_DECK
	var t := 0.0
	var k := 0
	while t < end_t + 4.0:
		var wide := 1.8 if t < end_t else 4.0
		var shade := 0.9 + 0.2 * fmod(float(k) * 0.618, 1.0)
		b.box(Transform3D(along, at.call(0.0, t + 0.14, y)), Vector3(wide, 0.05, 0.26), Color(wood.r * shade, wood.g * shade, wood.b * shade))
		t += 0.3
		k += 1
	# the stringers under the planks, and the posts down into the lake bed
	b.mat = Builder.S_TIMBER
	for s: float in [-0.8, 0.8]:
		b.rod(at.call(s, 0.0, y - 0.1), at.call(s, end_t + 4.0, y - 0.1), 0.07, 6, wood.darkened(0.3))
	for s: float in [-1.9, 1.9]:
		b.rod(at.call(s, end_t, y - 0.1), at.call(s, end_t + 4.0, y - 0.1), 0.07, 6, wood.darkened(0.3))
	var post_t: Array[float] = [1.5, 5.0, 8.5, 12.0, end_t, end_t + 4.0]
	for pt: float in post_t:
		var spread := 1.9 if pt >= end_t else 0.85
		for s: float in [-spread, spread]:
			var foot: Vector3 = at.call(s, pt, 0.0)
			foot.y = height(foot.x, foot.z) - 0.4
			b.rod(foot, at.call(s, pt, y + (0.35 if pt >= end_t else 0.0)), 0.09, 8, wood.darkened(0.4))
	# two chairs on the end, facing out over the lake (the deck's Adirondack shape)
	b.mat = Builder.S_DECK
	for s: float in [-0.9, 0.9]:
		var foot: Vector3 = at.call(s, end_t + 2.2, y + 0.03)
		var xf := Transform3D(along * Basis(Vector3.UP, s * -0.25), foot)
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0.0, 0.36, 0.0)), Vector3(0.7, 0.06, 0.6), Color(0.85, 0.82, 0.74))
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20.0)), Vector3(0.0, 0.75, 0.35)), Vector3(0.7, 0.8, 0.06), Color(0.85, 0.82, 0.74))
		for sx: float in [-0.37, 0.37]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.3, 0.0)), Vector3(0.06, 0.6, 0.7), Color(0.78, 0.75, 0.67))
	# a ladder down into the water off the right side of the end
	b.mat = Builder.S_IRON
	for s: float in [1.7, 2.1]:
		var top: Vector3 = at.call(s, end_t + 3.6, y + 0.7)
		b.rod(top, Vector3(top.x, WATER_Y - 0.8, top.z) + Vector3(DOCK_DIR.x, 0.0, DOCK_DIR.y) * 0.25, 0.025, 6, Color(0.6, 0.62, 0.64))
	for r in 4:
		var h := y - 0.15 - float(r) * 0.32
		b.rod(at.call(1.7, end_t + 3.6 + 0.05 * float(r), h), at.call(2.1, end_t + 3.6 + 0.05 * float(r), h), 0.02, 5, Color(0.6, 0.62, 0.64))


## The canoe: pulled up on the beach left of the dock, the right way up, with a paddle lying
## across it. Its hull is drawn rib by rib from one pointed end (t = -1) to the other (t = 1),
## each rib five points from gunwale to keel to gunwale (the campfire's rowing boat, longer and
## narrower, the ends swept up).
static func _build_canoe(b: Builder.Buf) -> void:
	var root := dock_root()
	var side := Vector2(-DOCK_DIR.y, DOCK_DIR.x)
	var p := root - side * 4.2 - DOCK_DIR * 1.6
	var mid := Vector3(p.x, height(p.x, p.y) + 0.02, p.y)
	var turn := Basis(Vector3.UP, atan2(DOCK_DIR.x, DOCK_DIR.y) + 1.15)
	var canoe := Transform3D(turn, mid)
	var length := 4.8
	var ribs: Array = []
	for rib in 17:
		var t := -1.0 + 2.0 * float(rib) / 16.0
		var wide := 0.44 * pow(maxf(1.0 - t * t, 0.0), 0.55)
		var rail := 0.36 + 0.22 * pow(absf(t), 5.0)
		var keel := 0.02 + 0.2 * pow(absf(t), 5.0)
		var one: Array[Vector3] = []
		for corner: Vector2 in [Vector2(-1.0, rail), Vector2(-0.75, keel + 0.1), Vector2(0.0, keel), Vector2(0.75, keel + 0.1), Vector2(1.0, rail)]:
			one.append(canoe * Vector3(corner.x * wide, corner.y, -t * length * 0.5))
		ribs.append(one)
	b.mat = Builder.S_PLAIN
	var hull_mid := canoe * Vector3(0.0, 0.32, 0.0)
	for rib in 16:
		for strake in 4:
			var a: Vector3 = ribs[rib][strake]
			var bb: Vector3 = ribs[rib][strake + 1]
			var c: Vector3 = ribs[rib + 1][strake + 1]
			var d: Vector3 = ribs[rib + 1][strake]
			var n := ((a + bb + c + d) * 0.25 - hull_mid).normalized()
			b.tri_round(a, bb, c, n, n, n, C_CANOE)
			b.tri_round(a, c, d, n, n, n, C_CANOE)
	# the wooden gunwales, two seats and a thwart, and the paddle
	b.mat = Builder.S_TIMBER
	var trim := Color(0.55, 0.38, 0.22)
	for rib in 16:
		for edge: int in [0, 4]:
			b.rod(ribs[rib][edge], ribs[rib + 1][edge], 0.025, 5, trim)
	for seat_t: float in [-0.62, 0.0, 0.66]:
		var half := 0.44 * pow(maxf(1.0 - seat_t * seat_t, 0.0), 0.55) * 0.92
		b.box(canoe * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, -seat_t * length * 0.5)), Vector3(half * 2.0, 0.03, 0.18), trim)
	var grip := canoe * Vector3(-0.15, 0.42, 1.1)
	var blade := canoe * Vector3(0.25, 0.42, -0.35)
	b.rod(grip, blade, 0.018, 6, trim.lightened(0.15))
	var dir := (blade - grip).normalized()
	b.box(Transform3D(Basis.looking_at(dir, Vector3.UP), blade + dir * 0.28), Vector3(0.17, 0.015, 0.55), trim.lightened(0.15))


## Reeds and cattails in clumps along the shore to both sides (never in front of the dock or the
## lawn's middle), and lily pads in the shallows, one in four in flower (the campfire's shapes).
static func _build_reeds_and_pads(b: Builder.Buf, rng: RandomNumberGenerator) -> void:
	b.mat = Builder.S_PLAIN
	# a long leaf: a flat strip from `foot` narrowing to a point at `tip`, bending over on the way
	var blade := func(foot: Vector3, tip: Vector3, flat: Vector3, width: float, bend: Vector3, low: Color, high: Color) -> void:
		var mid := foot.lerp(tip, 0.55) + bend
		var half_w := flat * width * 0.5
		var n := flat.cross(tip - foot).normalized()
		b.tri_round(foot - half_w, foot + half_w, mid + half_w * 0.8, n, n, n, low)
		b.tri_round(foot - half_w, mid + half_w * 0.8, mid - half_w * 0.8, n, n, n, low)
		b.tri_round(mid - half_w * 0.8, mid + half_w * 0.8, tip, n, n, n, high)
	var clumps: Array[Vector2] = []
	var tries := 0
	while clumps.size() < 46 and tries < 3000:
		tries += 1
		var ang := rng.randf_range(-1.45, 1.45)
		if absf(ang) < 0.32:
			continue                                     # the lawn's middle: the view stays open
		var dir := Vector2(sin(ang), -cos(ang))
		var edge := shore_r(YARD.x + dir.x * 50.0, YARD.y + dir.y * 50.0)
		if edge > 110.0:
			continue
		var p := YARD + dir * (edge + rng.randf_range(-0.6, 1.4))
		if dock_distance(p.x, p.y) < 5.0:
			continue
		clumps.append(p)
	for clump in clumps:
		for n in rng.randi_range(9, 16):
			var ang := rng.randf() * TAU
			var out_dir := Vector3(cos(ang), 0.0, sin(ang))
			var foot := Vector3(clump.x + out_dir.x * rng.randf_range(0.0, 0.35), 0.0, clump.y + out_dir.z * rng.randf_range(0.0, 0.35))
			foot.y = maxf(height(foot.x, foot.z), WATER_Y - 0.3) - 0.05
			var tall := rng.randf_range(0.6, 1.3)
			var green := rng.randf_range(0.8, 1.15)
			blade.call(foot, foot + out_dir * tall * rng.randf_range(0.2, 0.45) + Vector3(0.0, tall, 0.0), out_dir.cross(Vector3.UP),
				rng.randf_range(0.025, 0.045), out_dir * -0.06 * tall + Vector3(0.0, tall * 0.12, 0.0),
				Color(0.14 * green, 0.27 * green, 0.08 * green), Color(0.36 * green, 0.5 * green, 0.16 * green))
		for n in rng.randi_range(0, 3):                # cattails: a thin stalk with a brown head
			var foot := Vector3(clump.x + rng.randf_range(-0.2, 0.2), 0.0, clump.y + rng.randf_range(-0.2, 0.2))
			foot.y = maxf(height(foot.x, foot.z), WATER_Y - 0.3) - 0.05
			var tip := foot + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(1.0, 1.5), rng.randf_range(-0.08, 0.08))
			b.rod(foot, tip, 0.006, 4, Color(0.25, 0.36, 0.12))
			b.rod(foot.lerp(tip, 0.8), foot.lerp(tip, 0.95), 0.02, 7, Color(0.17, 0.1, 0.05), Color(0.17, 0.1, 0.05))
	# lily pads: in patches a few metres out from the shore
	var pads := 0
	tries = 0
	while pads < 70 and tries < 4000:
		tries += 1
		var ang := rng.randf_range(-1.3, 1.3)
		if absf(ang) < 0.22:
			continue
		var dir := Vector2(sin(ang), -cos(ang))
		var edge := shore_r(YARD.x + dir.x * 50.0, YARD.y + dir.y * 50.0)
		if edge > 100.0:
			continue
		var centre := YARD + dir * (edge + rng.randf_range(2.0, 9.0))
		if dock_distance(centre.x, centre.y) < 4.0 or not in_water(centre.x, centre.y):
			continue
		for _pad in rng.randi_range(3, 7):
			var q := centre + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
			var c := Vector3(q.x, WATER_Y + 0.012, q.y)
			var r := rng.randf_range(0.15, 0.32)
			var turn := rng.randf() * TAU
			var green := Color(0.1, 0.3, 0.09).lerp(Color(0.22, 0.4, 0.1), rng.randf())
			for w in 10:                                 # (wedge 0 of 11 is left out: the notch)
				var a0 := turn + TAU * float(w + 1) / 11.0
				var a1 := turn + TAU * float(w + 2) / 11.0
				b.tri_round(c, c + Vector3(cos(a0), 0.0, sin(a0)) * r, c + Vector3(cos(a1), 0.0, sin(a1)) * r, Vector3.UP, Vector3.UP, Vector3.UP, green)
			if rng.randf() < 0.25:
				var heart := c + Vector3(cos(turn) * r * 0.9, 0.03, sin(turn) * r * 0.9)
				var petal_col := Color(0.97, 0.95, 0.9).lerp(Color(0.95, 0.7, 0.82), rng.randf() * 0.5)
				for petal in 8:
					var a := TAU * float(petal) / 8.0
					var out_dir := Vector3(cos(a), 0.0, sin(a))
					var wide := out_dir.cross(Vector3.UP) * 0.024
					var tip := heart + out_dir * 0.09 + Vector3(0.0, 0.045 if petal % 2 == 0 else 0.015, 0.0)
					var up := (Vector3.UP + out_dir * 0.5).normalized()
					b.tri_round(heart - wide, heart + wide, tip, up, up, up, petal_col)
			pads += 1


# ── Trees ────────────────────────────────────────────────────
## Where the detailed trees stand: [foot, height, kind]. Kinds: pine (tall white pines), fir and
## birch (more birches near the water). None on the lawn, the path, the beach or in the water;
## nothing in front of the deck that would rise into the view.
static func _place_trees(rng: RandomNumberGenerator) -> Array:
	var trees: Array = []
	var taken: Array[Vector2] = []
	var tries := 0
	while trees.size() < TREE_COUNT and tries < 9000:
		tries += 1
		var r := lerpf(TREE_RANGE.x, TREE_RANGE.y, pow(rng.randf(), 1.4))
		var a := rng.randf() * TAU
		var p := YARD + Vector2(cos(a) * r * 1.15, sin(a) * r)
		if on_cabin(p.x, p.y, 3.0) or on_lawn(p.x, p.y) or path_distance(p.x, p.y) < 2.5 or dock_distance(p.x, p.y) < 3.0:
			continue
		var y := height(p.x, p.y)
		if y < WATER_Y + 0.9:
			continue                                     # the beach and the water
		var too_close := false
		for q: Vector2 in taken:
			if q.distance_squared_to(p) < 10.0:
				too_close = true
				break
		if too_close:
			continue
		var by_water := y < WATER_Y + 3.0
		var roll := rng.randf()
		var kind := "pine"
		var tall := rng.randf_range(16.0, 26.0)
		if roll < (0.45 if by_water else 0.22):
			kind = "birch"
			tall = rng.randf_range(9.0, 14.0)
		elif roll < 0.6:
			kind = "fir"
			tall = rng.randf_range(11.0, 18.0)
		var ahead := (YARD.y - p.y) / maxf(p.distance_to(YARD), 0.01)
		if ahead > 0.45 and y + tall * 0.95 > VIEW_Y:
			continue                                     # it would stand in the deck's view
		taken.append(p)
		trees.append([Vector3(p.x, y, p.y), tall, kind])
	return trees


## The two cheap tree shapes (the Lakeside Campfire's low-poly ones, 1 unit tall): a fir (the
## pines and firs) and a round leafy tree (the birches). [fir Buf, round Buf]
static func _lowpoly_shapes() -> Array:
	var fir := CampBuilder.Buf.new()
	fir.cyl(Transform3D.IDENTITY, 0.035, 0.02, 0.5, 6, Color(0.2, 0.13, 0.08))
	for t: Array in [[0.16, 0.27, 0.34], [0.36, 0.22, 0.3], [0.55, 0.16, 0.27], [0.72, 0.1, 0.28]]:
		var green := Color(0.04, 0.13, 0.08).lerp(Color(0.07, 0.2, 0.11), float(t[0]))
		fir.cyl(Transform3D(Basis.IDENTITY, Vector3(0.0, float(t[0]), 0.0)), float(t[1]), 0.0, float(t[2]), 8, green)
	fir.alpha_by_height(1.0)
	var round_tree := CampBuilder.Buf.new()
	round_tree.cyl(Transform3D.IDENTITY, 0.04, 0.03, 0.5, 6, Color(0.75, 0.72, 0.66))    # (pale birch trunks)
	var crown := RandomNumberGenerator.new()
	crown.seed = 12
	round_tree.blob(Vector3(0.0, 0.68, 0.0), Vector3(0.26, 0.26, 0.26), 9, 6, Color(0.24, 0.38, 0.12), Color(0.08, 0.17, 0.06), 0.16, crown)
	round_tree.blob(Vector3(0.13, 0.82, 0.05), Vector3(0.17, 0.17, 0.17), 8, 5, Color(0.27, 0.42, 0.14), Color(0.1, 0.2, 0.07), 0.16, crown)
	round_tree.alpha_by_height(1.0)
	return [fir, round_tree]


## The far forest on the arms of the shore, the slope behind and the island: low-poly firs
## (most) and birches. Returns its two MultiMeshInstance3Ds (the Season turns the round ones).
static func _build_far_forest(parent: Node3D, rng: RandomNumberGenerator, shapes: Array, mat: Material) -> Array[Node3D]:
	var firs: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var fir_tints := PackedColorArray()
	var round_tints := PackedColorArray()
	var tries := 0
	while firs.size() + rounds.size() < FAR_COUNT and tries < FAR_COUNT * 6:
		tries += 1
		var p: Vector2
		var r: float
		if rng.randf() < 0.04:
			# the island
			var a := rng.randf() * TAU
			p = ISLAND + Vector2(cos(a), sin(a)) * ISLAND_R * sqrt(rng.randf()) * 0.75
			r = p.distance_to(YARD)
		else:
			r = lerpf(FAR_RANGE.x, FAR_RANGE.y, sqrt(rng.randf()))
			var a := rng.randf() * TAU
			p = YARD + Vector2(cos(a), sin(a)) * r
		var y := height(p.x, p.y)
		if y < WATER_Y + 0.8:
			continue                                     # the lake and its beaches
		var tall := rng.randf_range(12.0, 20.0) * (1.0 + r / 1500.0)
		var ahead := (YARD.y - p.y) / maxf(r, 0.01)
		if ahead > 0.45 and y + tall > VIEW_Y and r < 90.0:
			continue
		var wide := tall * rng.randf_range(0.9, 1.3)
		var shade := rng.randf_range(0.6, 1.0)
		if rng.randf() < 0.72:
			firs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide * 0.6, tall, wide * 0.6)), Vector3(p.x, y - 0.3, p.y)))
			fir_tints.append(Color(shade, shade, shade))
		else:
			rounds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide * 0.9, tall * 0.75, wide * 0.9)), Vector3(p.x, y - 0.3, p.y)))
			round_tints.append(Color(shade, shade * 1.04, shade * 0.9))
	var out: Array[Node3D] = [
		CampBuilder._add_trees(parent, "FarFirs", shapes[0], firs, fir_tints, mat),
		CampBuilder._add_trees(parent, "FarRoundTrees", shapes[1], rounds, round_tints, mat)]
	return out


## The Simple look's near trees: the same spots as the detailed ones, drawn with the low-poly
## shapes (pines and firs as firs, birches as round trees).
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
		if kind == "birch":
			rounds.append(Transform3D(turn.scaled(Vector3(tall * 0.6, tall, tall * 0.6)), foot - Vector3(0.0, 0.1, 0.0)))
			round_tints.append(Color(shade, shade * 1.04, shade * 0.9))
		else:
			var slim := 0.36 if kind == "pine" else 0.42
			firs.append(Transform3D(turn.scaled(Vector3(tall * slim, tall, tall * slim)), foot))
			fir_tints.append(Color(shade, shade, shade))
	CampBuilder._add_trees(holder, "Firs", shapes[0], firs, fir_tints, mat)
	CampBuilder._add_trees(holder, "RoundTrees", shapes[1], rounds, round_tints, mat)
	return holder


## The Detailed look's plants (hidden until the room script shows them): the campfire's
## leaf-card pines, firs and birches on the tree spots, young firs and a few ferns at their feet,
## and grass tufts in the yard and on the lawn. One MultiMesh per kind (campfire_trees.gd kit(),
## which brings its own materials, handed on through the node's "mats" meta).
static func _build_detailed_plants(parent: Node3D, trees: Array, rng: RandomNumberGenerator) -> Node3D:
	var holder := Node3D.new()
	holder.name = "DetailedPlants"
	holder.visible = false
	parent.add_child(holder)
	var mats := Trees.materials(0.05)
	holder.set_meta("mats", mats)
	var spots: Dictionary = {}      # kit kind -> [[Transform3D, shade], ...]
	for one: Array in trees:
		var foot: Vector3 = one[0]
		var tall := float(one[1])
		var kind := String(one[2])
		var turn := Basis(Vector3.UP, rng.randf() * TAU)
		var shade := rng.randf_range(0.82, 1.06)
		match kind:
			"pine":
				_spot(spots, "pine", Transform3D(turn.scaled(Vector3(tall * 0.55, tall * 1.05, tall * 0.55)), foot - Vector3(0.0, 0.05, 0.0)), shade)
			"fir":
				_spot(spots, "fir", Transform3D(turn.scaled(Vector3(tall * 0.48, tall * 1.1, tall * 0.48)), foot - Vector3(0.0, 0.05, 0.0)), shade * 0.85)
			_:
				_spot(spots, "birch", Transform3D(turn.scaled(Vector3(tall * 0.55, tall * 1.1, tall * 0.55)), foot - Vector3(0.0, 0.05, 0.0)), shade)
		if foot.distance_to(Vector3(YARD.x, foot.y, YARD.y)) < 60.0:
			if rng.randf() < 0.35:
				var off := Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
				if not in_water(foot.x + off.x, foot.z + off.z, 4.0):
					var yt := rng.randf_range(2.5, 5.0)
					_spot(spots, "young_fir", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(yt * 0.45, yt, yt * 0.45)),
						Vector3(foot.x + off.x, height(foot.x + off.x, foot.z + off.z), foot.z + off.z)), 0.8)
			if rng.randf() < 0.5:
				var off := Vector3(rng.randf_range(-2.5, 2.5), 0.0, rng.randf_range(-2.5, 2.5))
				var fs := rng.randf_range(0.6, 1.2)
				_spot(spots, "fern", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs, fs)),
					Vector3(foot.x + off.x, height(foot.x + off.x, foot.z + off.z) - 0.02, foot.z + off.z)), 1.0)
	# grass tufts in the yard and on the lawn (off the cabin, the path, the beach)
	var left := 1600
	var tries := 0
	while left > 0 and tries < 14000:
		tries += 1
		var p := YARD + Vector2(rng.randf_range(-1.0, 1.0) * YARD_R * 1.15, rng.randf_range(-1.75, 1.0) * YARD_R)
		var in_yard := Vector2((p.x - YARD.x) / 1.15, p.y - YARD.y).length() < YARD_R - 2.0
		if not in_yard and not on_lawn(p.x, p.y):
			continue
		if on_cabin(p.x, p.y, 0.8) or path_distance(p.x, p.y) < 0.9 or height(p.x, p.y) < WATER_Y + 1.0:
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
		mm.mesh = Trees.kit(kind, mats)
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
