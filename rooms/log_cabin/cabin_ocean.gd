extends RefCounted
## Cabin: Ocean, the outside of the Log Cabin's third scene room (rooms/cabin_ocean/ uses
## log_cabin_room.gd with scene = "ocean"; the plan is Sen's "Log Cabin room plan" doc, "Outdoor
## scenes": the cabin on a grassy bluff, dune grass, wind-bent coastal pines, a beach with rolling
## surf and open sea to the horizon, driftwood, a far lighthouse whose beam sweeps at night and in
## fog, gulls). Built in code when the room loads, like the rest of the cabin:
##   - the land: the flat yard on top of a bluff; in front of the deck the grass slopes down to
##     the bluff's edge, which drops steeply to a sandy beach and the sea (about 9 m below the
##     yard). The coast curves
##     gently back on both sides; behind the cabin the land rises with pine woods. One mesh, finer
##     near the cabin, coarser far out (height() for anything standing on it), in three parts:
##     grass (the bluff top), sand (the bluff's face, the beach and the sea bed) and pine needles
##     (the woods behind),
##   - the sea: one huge flat sheet at SEA_Y with the Lakeside Campfire's water shader
##     (camp_water.gdshader, nothing mirrored on its horizon); the sky draws a flat sea horizon
##     all round (camp_sky.gdshader `open_sea`, set by the room),
##   - the surf: a strip of painted foam along the beach (cabin_surf.gdshader): waves roll in,
##     break and wash up the sand,
##   - wooden stairs from the path down the bluff to the beach, driftwood and dark rocks on the
##     sand, dune grass along the bluff's edge and the back of the beach,
##   - coastal pines bent away from the sea by the wind and low scrub (the campfire's leaf-card
##     trees on the Detailed look, plain shapes on the Simple one), and a far forest of cheap
##     low-poly trees inland (both looks),
##   - a lighthouse on a rocky islet out to sea: white tower, red band, a lamp and two beams that
##     the room script turns (its strength follows the night and the fog), and the keeper's house,
##   - gulls (small gliding birds) that the room script flies in circles over the beach by day.
## The surf's sound, the gulls' calls and the foghorn are played by the room script
## (log_cabin_room.gd: _fill_surf, _run_gulls, _run_foghorn).
## Everything is placed with fixed seeds, so every PC in a co-stream sees the same coast.
## build() hands back what Builder.build() does (the room script uses the same keys) plus:
##   sea_mat     the sea's water (the room sets its sky, light and waves for the hour and wind),
##   surf_mat    the surf's foam (the room sets its light and its size from the wind),
##   lamp        the lighthouse lamp's glow (a MeshInstance3D; the room swells it as a beam
##               sweeps past), lamp_mat its material (the room sets its strength),
##   beam        the beams' pivot (a Node3D; the room turns it about its Y axis),
##   beam_mat    the beams' material (the room sets their strength and haze),
##   gulls       Array[Node3D]: the gulls (the room flies them),
##   leaf_mats   the leaf-card materials by name (unused here: the coast has no Season),
##   far_trees   the low-poly tree MultiMeshInstance3Ds.

const Builder := preload("res://rooms/log_cabin/cabin_builder.gd")
const CampBuilder := preload("res://rooms/campfire/campfire_builder.gd")
const Trees := preload("res://rooms/campfire/campfire_trees.gd")
const WATER_SHADER := preload("res://rooms/campfire/camp_water.gdshader")
const SURF_SHADER := preload("res://rooms/log_cabin/cabin_surf.gdshader")
const BEAM_SHADER := preload("res://rooms/log_cabin/cabin_beam.gdshader")
const CAMP_TEX := "res://rooms/campfire/textures/"

## The middle of the flat yard round the cabin (x, z) and how far out it stays flat (metres).
## (The same yard as the other scene rooms', so the cameras fit all of them.)
const YARD := Vector2(-2.5, 2.0)
const YARD_R: float = 19.0
## The sea's surface (y, metres): well below the yard, so the deck looks out over the sea.
const SEA_Y: float = Builder.GROUND_Y - 10.0
## The bluff's edge straight out in front of the deck (z, metres); edge_z() curves it back to
## the sides. The grass slopes down by EDGE_DROP metres over the last EDGE_SLOPE metres before
## the edge (so the deck can see over it down to where the waves break), then BLUFF_W metres of
## steep face drop to the beach's top (BEACH_TOP), then BEACH_W metres of sand slope into the sea.
const EDGE_FRONT: float = -32.0
const EDGE_DROP: float = 4.0
const EDGE_SLOPE: float = 20.0
const BLUFF_W: float = 6.0
const BEACH_W: float = 22.0
const BEACH_TOP: float = SEA_Y + 1.6
## The beach meets the sea this many metres out from the bluff's edge (where height() = SEA_Y).
const WATERLINE: float = BLUFF_W + BEACH_W * (BEACH_TOP - SEA_Y) / (BEACH_TOP - SEA_Y + 0.4)
## The lighthouse's islet out to sea (x, z), its radius (metres), and the tower's height.
const ISLET := Vector2(-270.0, -640.0)
const ISLET_R: float = 34.0
const TOWER_H: float = 21.0
## The land mesh: how far out it reaches each way (metres) and how many rows and columns.
const LAND_SIZE: float = 900.0
const LAND_CELLS: int = 250
const LAND_BUNCH: float = 2.6
## The detailed trees: how many, and how far from the yard's middle they stand (metres).
const TREE_COUNT: int = 190
const TREE_RANGE := Vector2(17.0, 130.0)
## The far low-poly forest: how many trees and where (metres from the yard's middle).
const FAR_COUNT: int = 2600
const FAR_RANGE := Vector2(100.0, 520.0)
## Roughly where a seated person's eyes are on the deck: nothing in front of the deck stands
## above this, so the view out to sea stays open.
const VIEW_Y: float = 0.9
## Where the trodden path starts (the foot of the deck steps) and the x where the stairs go down
## the bluff.
const PATH_START := Vector2(6.8, -4.8)
const STAIRS_X: float = 13.0
## The surf strip: from x = -SURF_HALF to SURF_HALF along the beach. Far longer than anyone
## sees clearly (round 7: at 420 m its end showed as a hard seam where the waves stopped); its
## last SURF_FADE metres at each end fade out (cabin_surf.gdshader, by UV2.y).
const SURF_HALF: float = 880.0          # (the land reaches 900 m each way: LAND_SIZE)
const SURF_FADE: float = 420.0
const C_SAND := Color(0.72, 0.66, 0.54)
const C_BLUFF := Color(0.6, 0.5, 0.38)          # the bluff's face: sandy clay
const C_GRASS_SEA := Color(0.42, 0.48, 0.28)     # wind-dried coastal grass (the Simple look)
const C_NEEDLES := Color(0.4, 0.3, 0.2)
const C_CANOPY := Color(0.06, 0.11, 0.07)
const C_DRIFT := Color(0.66, 0.62, 0.56)         # sun-bleached driftwood
const C_ROCK := Color(0.24, 0.24, 0.25)


## The cabin and the coast round it, under `room`. Returns the parts (see the file's header).
static func build(room: Node3D, view: String) -> Dictionary:
	var out := Builder.build_cabin(room, view)
	out["smoke_spots"] = Builder.SMOKE_SPOTS
	out["shelters"] = Builder.shelters()
	out["eaves"] = Builder.eaves()
	var set_root := room.get_node("Set") as Node3D
	var surf: Dictionary = out["surface_mats"]
	out["litter_mat"] = surf[Builder.S_LITTER]
	(surf[Builder.S_LITTER] as ShaderMaterial).set_shader_parameter("photo_tint", Color(0.92, 0.78, 0.6))
	# the bluff's grass: drier and paler than the forest rooms' lawn
	(surf[Builder.S_GRASS] as ShaderMaterial).set_shader_parameter("photo_tint", Color(0.74, 0.78, 0.52))
	_build_land(set_root, surf)
	_build_sea(set_root, out)
	_build_surf(set_root, out)
	_build_beach_things(set_root, surf)
	_build_lighthouse(set_root, surf, out)
	out["gulls"] = _build_gulls(set_root, surf)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1912
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
## The bluff's edge at x (its z, metres): EDGE_FRONT in front of the cabin, curving back
## towards the sea on both sides (the coast bends away), with a gentle wobble.
static func edge_z(x: float) -> float:
	return EDGE_FRONT + 3.0 * sin(x * 0.031) + 2.0 * sin(x * 0.077 + 1.0) - 0.0005 * x * x


## Metres out to sea from the bluff's edge at x, z (below 0 = on the bluff top).
static func seaward(x: float, z: float) -> float:
	return edge_z(x) - z


## The ground's height (metres) at x, z: the bluff top (flat in the yard, low dune hummocks
## beyond, rising inland behind the cabin), the bluff's steep face, the beach, the sea bed, and
## the islet the lighthouse stands on. Everything that stands on the ground asks this.
static func height(x: float, z: float) -> float:
	var dx := x - YARD.x
	var dz := z - YARD.y
	var r := sqrt(dx * dx + dz * dz)
	var ahead := -dz / maxf(r, 0.01)
	var back := smoothstep(0.15, 0.75, -ahead)
	var rise := back * (18.0 * smoothstep(YARD_R + 4.0, 190.0, r) + 24.0 * smoothstep(280.0, 700.0, r)) \
		+ (1.0 - back) * (3.0 * smoothstep(YARD_R + 6.0, 200.0, r) + 16.0 * smoothstep(300.0, 700.0, r) * smoothstep(-0.1, -0.6, ahead))
	var bumps := 0.8 * sin(x * 0.07 + 1.3) * sin(z * 0.05 + 0.4) + 0.5 * sin(x * 0.13 + z * 0.09) + 0.3 * sin(z * 0.21 - x * 0.05)
	var s := seaward(x, z)
	var top := Builder.GROUND_Y + rise + bumps * smoothstep(YARD_R, YARD_R + 20.0, r) - EDGE_DROP * smoothstep(-EDGE_SLOPE, 0.0, s)
	var h: float
	if s <= 0.0:
		h = top
	elif s < BLUFF_W:
		# the steep face: a little ragged (rain gullies), steepest near the top
		var t := s / BLUFF_W
		var ragged := 0.5 * sin(x * 0.9) * sin(x * 0.37 + 2.0) * t * (1.0 - t)
		h = lerpf(top, BEACH_TOP, pow(smoothstep(0.0, 1.0, t), 0.7)) + ragged
	elif s < BLUFF_W + BEACH_W:
		h = lerpf(BEACH_TOP, SEA_Y - 0.4, (s - BLUFF_W) / BEACH_W)
	else:
		h = SEA_Y - 0.4 - 7.0 * smoothstep(BLUFF_W + BEACH_W, 150.0, s)
	# the islet: a lumpy dome of rock
	var isl := 1.0 - smoothstep(0.0, ISLET_R, Vector2(x, z).distance_to(ISLET))
	if isl > 0.0:
		h = maxf(h, SEA_Y - 3.0 + 12.0 * sqrt(isl) + 0.6 * sin(x * 0.5) * sin(z * 0.4))
	return h


## Whether x, z is on the open grass in front of the deck (kept clear: no trees).
static func on_front(x: float, z: float) -> bool:
	var dx := x - YARD.x
	var dz := z - YARD.y
	var r := sqrt(dx * dx + dz * dz)
	return -dz / maxf(r, 0.01) > 0.35 and seaward(x, z) > -25.0


## The trodden path from the deck steps to the top of the stairs (x, z points).
static func path_points() -> Array[Vector2]:
	var end := Vector2(STAIRS_X, edge_z(STAIRS_X) + 1.5)
	var pts: Array[Vector2] = []
	for i in 5:
		var t := float(i) / 4.0
		pts.append(PATH_START.lerp(end, t) + Vector2(1.0, 0.0) * sin(t * PI))
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


## Whether x, z is on the cabin, the den, the deck or the back stoop (nothing grows there).
static func on_cabin(x: float, z: float, margin: float) -> bool:
	return x > Builder.DEN_FAR_X - margin and x < Builder.DECK_HALF + margin and z > -Builder.DECK_DEPTH - margin - 1.2 and z < Builder.BACK_Z + 1.6 + margin


## The land: one grid, rows and columns bunched up near the cabin, in three parts: grass (the
## bluff top), sand (the face, the beach, the sea bed, the islet's foot) and pine needles (the
## woods behind; far out the corner colours' alpha drops to 0 and treetop colours show).
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
			var e := 0.5
			var nrm := Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()
			var k := j * n + i
			verts[k] = Vector3(x, y, z)
			normals[k] = nrm
			var r := Vector2(x, z).distance_to(YARD)
			var s := seaward(x, z)
			var mottle := 0.5 + 0.5 * sin(x * 0.21 + sin(z * 0.17) * 2.0) * sin(z * 0.23 + x * 0.05)
			var c := C_GRASS_SEA.lerp(Builder.C_GRASS, 0.4 * mottle)
			# woods behind the cabin: needles near, treetops far
			var woods := smoothstep(30.0, 50.0, r) * smoothstep(0.0, 0.4, (z - YARD.y) / maxf(r, 0.01))
			c = c.lerp(C_NEEDLES, woods * 0.8)
			c = c.lerp(C_CANOPY.lerp(C_CANOPY.lightened(0.22), mottle), woods * smoothstep(70.0, 140.0, r))
			# the bluff's face and the beach
			c = c.lerp(C_BLUFF, smoothstep(0.5, 2.0, s))
			c = c.lerp(C_SAND, smoothstep(BLUFF_W - 1.0, BLUFF_W + 1.0, s))
			c.a = 1.0 - smoothstep(85.0, 150.0, r) * woods
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
			var r := Vector2(mid.x, mid.z).distance_to(YARD)
			# (packed arrays are copied on assignment, so append to the right one directly)
			# (corner order: the face that looks up is the front)
			if seaward(mid.x, mid.z) > 0.8 or mid.y < SEA_Y + 3.0:
				sand_idx.append_array([a, b, c, b, d, c])
			elif r > 40.0 and mid.z > YARD.y + 12.0:
				wood_idx.append_array([a, b, c, b, d, c])
			else:
				grass_idx.append_array([a, b, c, b, d, c])
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
	# the trodden path to the stairs: a strip of the dirt photo just above the ground
	var g := Builder.Buf.new()
	g.mat = Builder.S_DIRT
	var dirt := Color(0.5, 0.44, 0.34)
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


# ── The sea and the surf ─────────────────────────────────────
## The sea: one huge flat sheet at SEA_Y (the land hides it wherever it is higher), with the
## Lakeside Campfire's water shader. Nothing on its horizon to mirror (shore_amount 0). The room
## sets its sky, light and waves (log_cabin_room.gd _apply_ocean).
static func _build_sea(parent: Node3D, out: Dictionary) -> void:
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(24000.0, 24000.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("ripples", load(CAMP_TEX + "water_normal.png"))
	mat.set_shader_parameter("shore_amount", 0.0)
	mat.set_shader_parameter("flow", Vector2(0.02, 0.06))
	out["sea_mat"] = mat
	var mi := Builder._add_mesh(parent, "Sea", sheet, mat, false)
	mi.position = Vector3(YARD.x, SEA_Y, YARD.y - 6000.0)


## The surf strip along the beach: a grid from 14 m up the sand to 96 m out to sea, laid on the
## sand (just above it) and on the sea, which cabin_surf.gdshader paints foam on. UV: x = metres
## along the beach, y = metres out from the waterline; UV2.x = 0..1 from one end to the other,
## UV2.y = 1 along the middle falling to 0 over the last SURF_FADE metres (the shader fades the
## ends with it).
static func _build_surf(parent: Node3D, out: Dictionary) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var outs: Array[float] = []
	var o := -14.0
	while o <= 96.0:
		outs.append(o)
		o += 1.0 if o < 30.0 else 3.0              # (fine where the waves break and wash)
	var cols := 0
	var x := -SURF_HALF
	while x <= SURF_HALF + 0.01:
		var wz := edge_z(x) - WATERLINE
		for off: float in outs:
			var z := wz - off
			var y := maxf(height(x, z), SEA_Y) + 0.04
			verts.append(Vector3(x, y, z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(x, off))
			# UV2: x = 0..1 end to end (as before), y = 1 in the middle fading to 0 at the ends
			uv2s.append(Vector2((x + SURF_HALF) / (2.0 * SURF_HALF), clampf((SURF_HALF - absf(x)) / SURF_FADE, 0.0, 1.0)))
		if cols > 0:
			for k in outs.size() - 1:
				var a := (cols - 1) * outs.size() + k
				var b := cols * outs.size() + k
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
		cols += 1
		# 3 m apart near the cabin, wider far along the beach (where it is only a far white line)
		x += 3.0 if absf(x) < 300.0 else minf(3.0 + (absf(x) - 300.0) * 0.02, 15.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = SURF_SHADER
	mat.set_shader_parameter("noise", load(CAMP_TEX + "sky_noise.png"))
	out["surf_mat"] = mat
	Builder._add_mesh(parent, "Surf", mesh, mat, false)


# ── The stairs, driftwood, rocks ─────────────────────────────
## Wooden stairs from the top of the bluff down its face to the beach (steps on two stringers,
## posts down to the ground, a hand rail), sun-bleached driftwood logs on the sand (some with
## broken-off branches), and dark rocks at the bluff's foot and in the surf.
static func _build_beach_things(parent: Node3D, surf: Dictionary) -> void:
	var b := Builder.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1938
	# the stairs: straight down the face, from just behind the edge to the beach
	var z_top := edge_z(STAIRS_X) + 1.2
	var z_foot := edge_z(STAIRS_X) - BLUFF_W - 2.0
	var y_top := height(STAIRS_X, z_top)
	var y_foot := height(STAIRS_X, z_foot)
	var steps := int(ceil((y_top - y_foot) / 0.19))
	var wood := Builder.C_DECK.darkened(0.1)
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var y := lerpf(y_top, y_foot, t)
		var z := lerpf(z_top, z_foot, t)
		b.mat = Builder.S_DECK
		b.box(Transform3D(Basis.IDENTITY, Vector3(STAIRS_X, y, z)), Vector3(1.2, 0.05, 0.3), wood.lightened(0.05 * float(i % 3)))
	b.mat = Builder.S_TIMBER
	for sx: float in [-0.62, 0.62]:
		b.rod(Vector3(STAIRS_X + sx, y_top - 0.08, z_top), Vector3(STAIRS_X + sx, y_foot - 0.08, z_foot), 0.06, 6, wood.darkened(0.3))
		b.rod(Vector3(STAIRS_X + sx, y_top + 0.9, z_top), Vector3(STAIRS_X + sx, y_foot + 0.9, z_foot), 0.035, 6, wood)
		for k in 6:
			var t := float(k) / 5.0
			var p := Vector3(STAIRS_X + sx, lerpf(y_top, y_foot, t), lerpf(z_top, z_foot, t))
			var ground := height(p.x, p.z)
			b.rod(Vector3(p.x, minf(ground, p.y) - 0.3, p.z), p + Vector3(0.0, 0.92, 0.0), 0.05, 6, wood.darkened(0.25))
	# driftwood: logs lying on the beach, bleached grey, some with a stub of a branch
	b.mat = Builder.S_BARK
	for i in 18:
		var x := rng.randf_range(-130.0, 140.0)
		if absf(x - STAIRS_X) < 3.0:
			continue
		var s := rng.randf_range(BLUFF_W + 2.0, WATERLINE - 6.0)
		var z := edge_z(x) - s
		var turn := rng.randf_range(-0.7, 0.7) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
		var length := rng.randf_range(1.5, 6.5)
		var dir := Vector3(cos(turn), 0.0, sin(turn))
		var radius := rng.randf_range(0.09, 0.28)
		var a := Vector3(x, 0.0, z) - dir * length * 0.5
		var c := Vector3(x, 0.0, z) + dir * length * 0.5
		a.y = height(a.x, a.z) + radius * 0.7
		c.y = height(c.x, c.z) + radius * 0.6
		var col := C_DRIFT.darkened(rng.randf_range(0.0, 0.25))
		b.rod(a, c, radius, 8, col, col.darkened(0.15))
		if rng.randf() < 0.5:
			var at := a.lerp(c, rng.randf_range(0.3, 0.8))
			var side := dir.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
			b.rod(at, at + (side + Vector3.UP * 0.6).normalized() * rng.randf_range(0.5, 1.2), radius * 0.35, 6, col)
	# dark rocks: some at the foot of the bluff, a few out in the surf
	b.mat = Builder.S_STONE
	for i in 26:
		var x := rng.randf_range(-160.0, 170.0)
		if absf(x - STAIRS_X) < 4.0:
			continue
		var s := rng.randf_range(BLUFF_W - 1.0, BLUFF_W + 3.0) if i < 18 else rng.randf_range(WATERLINE + 4.0, WATERLINE + 25.0)
		var z := edge_z(x) - s
		var size := Vector3(rng.randf_range(0.8, 2.6), rng.randf_range(0.6, 1.8), rng.randf_range(0.8, 2.4))
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)),
			Vector3(x, height(x, z) + size.y * 0.25, z))
		b.soft_box(xf, size, minf(size.x, size.z) * 0.4, C_ROCK.lightened(rng.randf_range(0.0, 0.2)))
	Builder._add_mesh(parent, "BeachThings", b.to_mesh(surf), null, true)


# ── The lighthouse ───────────────────────────────────────────
## The lighthouse on its islet: a tapering white tower with a red band, a dark gallery and
## railing, a glass lantern room with a dark roof, and the keeper's small white house with a red
## roof. The lamp's glow is its own unshaded billboard (out "lamp"); the two beams (long cones
## pointing opposite ways, drawn by cabin_beam.gdshader as soft shafts of light with no outline)
## hang on a pivot the room turns (out "beam", "beam_mat").
static func _build_lighthouse(parent: Node3D, surf: Dictionary, out: Dictionary) -> void:
	var b := Builder.Buf.new()
	var base := Vector3(ISLET.x, height(ISLET.x, ISLET.y) - 0.3, ISLET.y)
	var white := Color(0.92, 0.92, 0.88)
	var red := Color(0.66, 0.12, 0.1)
	b.mat = Builder.S_PLAIN
	var bands: Array = [[0.0, 0.45, white], [0.45, 0.62, red], [0.62, 1.0, white]]
	for band: Array in bands:
		var y0 := float(band[0]) * TOWER_H
		var y1 := float(band[1]) * TOWER_H
		b.cyl(Transform3D(Basis.IDENTITY, base + Vector3(0.0, y0, 0.0)), lerpf(2.6, 1.7, float(band[0])), lerpf(2.6, 1.7, float(band[1])), y1 - y0, 20, band[2])
	var top := base + Vector3(0.0, TOWER_H, 0.0)
	var dark := Color(0.12, 0.12, 0.13)
	b.mat = Builder.S_IRON
	b.cyl(Transform3D(Basis.IDENTITY, top), 2.4, 2.4, 0.25, 20, dark)                        # the gallery floor
	for k in 16:
		var a := TAU * float(k) / 16.0
		b.rod(top + Vector3(cos(a) * 2.3, 0.25, sin(a) * 2.3), top + Vector3(cos(a) * 2.3, 1.2, sin(a) * 2.3), 0.04, 4, dark)
	b.cyl(Transform3D(Basis.IDENTITY, top + Vector3(0.0, 1.15, 0.0)), 2.32, 2.32, 0.07, 20, dark)  # the rail
	b.mat = Builder.S_PLAIN
	b.cyl(Transform3D(Basis.IDENTITY, top + Vector3(0.0, 0.25, 0.0)), 1.3, 1.3, 2.0, 12, Color(0.7, 0.78, 0.8))   # lantern glass
	b.mat = Builder.S_IRON
	b.cyl(Transform3D(Basis.IDENTITY, top + Vector3(0.0, 2.25, 0.0)), 1.55, 0.15, 1.2, 12, dark)       # the roof
	# the keeper's house beside it
	b.mat = Builder.S_PLAIN
	var house := Transform3D(Basis(Vector3.UP, 0.4), base + Vector3(9.0, 0.0, 5.0))
	b.box(house * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.0)), Vector3(7.0, 3.2, 5.0), white)
	b.mat = Builder.S_ROOF
	for side: float in [-1.0, 1.0]:
		b.box(house * Transform3D(Basis(Vector3.RIGHT, side * 0.6), Vector3(0.0, 3.9, side * 1.35)), Vector3(7.4, 0.15, 3.3), red.darkened(0.3))
	Builder._add_mesh(parent, "Lighthouse", b.to_mesh(surf), null, true)
	var lamp_at := top + Vector3(0.0, 1.25, 0.0)
	# the lamp's glow: a soft round billboard, bright, added to the picture
	var glow := QuadMesh.new()
	glow.size = Vector2(9.0, 9.0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.disable_fog = true
	gm.no_depth_test = false
	var dot := GradientTexture2D.new()
	dot.width = 64
	dot.height = 64
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dg := Gradient.new()
	dg.set_color(0, Color(1.0, 0.95, 0.8))
	dg.add_point(0.15, Color(1.0, 0.85, 0.55))
	dg.set_color(dg.get_point_count() - 1, Color.BLACK)
	dot.gradient = dg
	gm.albedo_texture = dot
	glow.material = gm
	var lamp := MeshInstance3D.new()
	lamp.name = "LighthouseLamp"
	lamp.mesh = glow
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lamp)
	lamp.position = lamp_at
	out["lamp"] = lamp
	out["lamp_mat"] = gm
	# the beams: two long cones lying flat from the lamp, back to back, on a pivot
	var pivot := Node3D.new()
	pivot.name = "LighthouseBeams"
	parent.add_child(pivot)
	pivot.position = lamp_at
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = BEAM_SHADER
	# (the shader works out the shaft's brightness from these same sizes: keep them in step)
	beam_mat.set_shader_parameter("half_len", 160.0)
	beam_mat.set_shader_parameter("r_lamp", 0.5)
	beam_mat.set_shader_parameter("r_end", 18.0)
	for side: float in [1.0, -1.0]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.5
		cone.bottom_radius = 18.0
		cone.height = 320.0
		cone.radial_segments = 16
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = beam_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		# (a cylinder stands along +Y with its narrow top up: lay it along X, narrow end at the lamp)
		mi.transform = Transform3D(Basis(Vector3.BACK, side * PI * 0.5), Vector3(side * 160.0, 0.0, 0.0))
	out["beam"] = pivot
	out["beam_mat"] = beam_mat


# ── Gulls ────────────────────────────────────────────────────
## Six gulls: a white body and grey wings held out flat in a slight W, as one small mesh each.
## The room script flies them in slow circles over the beach and the water by day.
static func _build_gulls(parent: Node3D, surf: Dictionary) -> Array[Node3D]:
	var b := Builder.Buf.new()
	b.mat = Builder.S_PLAIN
	var body := Color(0.95, 0.95, 0.93)
	var wing := Color(0.66, 0.68, 0.7)
	b.rod(Vector3(0.0, 0.0, 0.32), Vector3(0.0, 0.0, -0.3), 0.07, 6, body)              # body, head at -Z
	b.rod(Vector3(0.0, 0.0, -0.3), Vector3(0.0, -0.01, -0.4), 0.025, 4, Color(0.9, 0.7, 0.2))   # beak
	for side: float in [-1.0, 1.0]:
		var root_a := Vector3(side * 0.05, 0.0, -0.12)
		var root_b := Vector3(side * 0.05, 0.0, 0.12)
		var elbow := Vector3(side * 0.45, 0.07, -0.05)
		var tip := Vector3(side * 0.85, -0.02, 0.12)
		b.tri(root_a, elbow, root_b, wing)
		b.tri(root_b, elbow, tip, wing)
		b.tri(elbow, tip + Vector3(0.0, 0.0, -0.05), tip, Color(0.15, 0.15, 0.16))       # black wing tips
	var mesh := b.to_mesh(surf)
	var holder := Node3D.new()
	holder.name = "Gulls"
	parent.add_child(holder)
	var list: Array[Node3D] = []
	for i in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		list.append(mi)
	return list


# ── Trees ────────────────────────────────────────────────────
## Where the detailed trees stand: [foot, height, kind, lean]. Kinds: pine (coastal pines, bent
## inland by the wind: the further towards the bluff, the harder) and scrub (low, wide bushes).
## None on the open grass in front of the deck, the path, the bluff's face or the beach.
static func _place_trees(rng: RandomNumberGenerator) -> Array:
	var trees: Array = []
	var taken: Array[Vector2] = []
	var tries := 0
	while trees.size() < TREE_COUNT and tries < 9000:
		tries += 1
		var r := lerpf(TREE_RANGE.x, TREE_RANGE.y, pow(rng.randf(), 1.3))
		var a := rng.randf() * TAU
		var p := YARD + Vector2(cos(a) * r * 1.15, sin(a) * r)
		var s := seaward(p.x, p.y)
		if on_cabin(p.x, p.y, 3.0) or on_front(p.x, p.y) or path_distance(p.x, p.y) < 2.5 or s > -3.0:
			continue
		var too_close := false
		for q: Vector2 in taken:
			if q.distance_squared_to(p) < 12.0:
				too_close = true
				break
		if too_close:
			continue
		var y := height(p.x, p.y)
		var kind := "pine"
		var tall := rng.randf_range(9.0, 16.0)
		if rng.randf() < 0.28:
			kind = "scrub"
			tall = rng.randf_range(1.5, 3.2)
		var ahead := (YARD.y - p.y) / maxf(p.distance_to(YARD), 0.01)
		if ahead > 0.35 and y + tall * 0.95 > VIEW_Y:
			continue                                     # it would stand in the deck's view
		# near the bluff the wind bends them hard; inland less
		var lean := lerpf(0.32, 0.08, smoothstep(-40.0, -100.0, s)) * rng.randf_range(0.7, 1.1)
		taken.append(p)
		trees.append([Vector3(p.x, y, p.y), tall, kind, lean])
	return trees


## A tree's turn and lean: a random turn about its trunk, then tilted towards +Z (inland, away
## from the sea) by `lean` radians.
static func _lean_basis(turn: float, lean: float) -> Basis:
	return Basis(Vector3.RIGHT, lean) * Basis(Vector3.UP, turn)


## The two cheap tree shapes (the Lakeside Campfire's low-poly ones, 1 unit tall): a fir (the
## pines) and a round leafy tree (the scrub). [fir Buf, round Buf]
static func _lowpoly_shapes() -> Array:
	var fir := CampBuilder.Buf.new()
	fir.cyl(Transform3D.IDENTITY, 0.035, 0.02, 0.55, 6, Color(0.22, 0.14, 0.08))
	for t: Array in [[0.4, 0.3, 0.22], [0.55, 0.26, 0.2], [0.7, 0.18, 0.22]]:
		var green := Color(0.05, 0.14, 0.08).lerp(Color(0.08, 0.2, 0.1), float(t[0]))
		fir.cyl(Transform3D(Basis.IDENTITY, Vector3(0.0, float(t[0]), 0.0)), float(t[1]), 0.04, float(t[2]), 8, green)
	fir.alpha_by_height(1.0)
	var round_tree := CampBuilder.Buf.new()
	round_tree.cyl(Transform3D.IDENTITY, 0.04, 0.03, 0.3, 6, Color(0.25, 0.18, 0.1))
	var crown := RandomNumberGenerator.new()
	crown.seed = 13
	round_tree.blob(Vector3(0.0, 0.5, 0.0), Vector3(0.4, 0.32, 0.4), 9, 6, Color(0.2, 0.32, 0.12), Color(0.08, 0.15, 0.06), 0.18, crown)
	round_tree.alpha_by_height(1.0)
	return [fir, round_tree]


## The far forest inland and along the coast: low-poly pines (most) and round bushy trees, never
## on the bluff's face, the beach or the open grass in front. Returns its MultiMeshInstance3Ds.
static func _build_far_forest(parent: Node3D, rng: RandomNumberGenerator, shapes: Array, mat: Material) -> Array[Node3D]:
	var firs: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var fir_tints := PackedColorArray()
	var round_tints := PackedColorArray()
	var tries := 0
	while firs.size() + rounds.size() < FAR_COUNT and tries < FAR_COUNT * 6:
		tries += 1
		var r := lerpf(FAR_RANGE.x, FAR_RANGE.y, sqrt(rng.randf()))
		var a := rng.randf() * TAU
		var p := YARD + Vector2(cos(a), sin(a)) * r
		var s := seaward(p.x, p.y)
		if s > -8.0:
			continue                                     # the bluff, the beach and the sea
		var y := height(p.x, p.y)
		var tall := rng.randf_range(10.0, 16.0) * (1.0 + r / 1500.0)
		var wide := tall * rng.randf_range(0.9, 1.3)
		var shade := rng.randf_range(0.6, 1.0)
		var lean := lerpf(0.3, 0.05, smoothstep(-20.0, -120.0, s))
		if rng.randf() < 0.75:
			firs.append(Transform3D(_lean_basis(rng.randf() * TAU, lean).scaled(Vector3(wide * 0.7, tall, wide * 0.7)), Vector3(p.x, y - 0.3, p.y)))
			fir_tints.append(Color(shade, shade, shade))
		else:
			rounds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide * 0.9, tall * 0.6, wide * 0.9)), Vector3(p.x, y - 0.3, p.y)))
			round_tints.append(Color(shade, shade * 1.04, shade * 0.9))
	var out: Array[Node3D] = [
		CampBuilder._add_trees(parent, "FarPines", shapes[0], firs, fir_tints, mat),
		CampBuilder._add_trees(parent, "FarRoundTrees", shapes[1], rounds, round_tints, mat)]
	return out


## The Simple look's near trees: the same spots as the detailed ones, drawn with the low-poly
## shapes (pines leaning, scrub as low round bushes).
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
		var turn := fmod(foot.x * 1.7 + foot.z * 0.9, TAU)
		var shade := 0.8 + 0.3 * fmod(absf(foot.x * 0.37 + foot.z * 0.21), 1.0)
		if String(one[2]) == "scrub":
			rounds.append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(tall * 1.4, tall, tall * 1.4)), foot - Vector3(0.0, 0.1, 0.0)))
			round_tints.append(Color(shade, shade * 1.04, shade * 0.9))
		else:
			firs.append(Transform3D(_lean_basis(turn, float(one[3])).scaled(Vector3(tall * 0.5, tall, tall * 0.5)), foot))
			fir_tints.append(Color(shade, shade, shade))
	CampBuilder._add_trees(holder, "Pines", shapes[0], firs, fir_tints, mat)
	CampBuilder._add_trees(holder, "RoundTrees", shapes[1], rounds, round_tints, mat)
	return holder


## The Detailed look's plants (hidden until the room script shows them): the campfire's
## leaf-card pines (leaning) and low oaks as scrub on the tree spots, and dune grass: tall pale
## tufts along the bluff's edge, over the bluff top and at the back of the beach, plus grass in
## the yard. One MultiMesh per kind (campfire_trees.gd kit(); its materials go on the node's
## "mats" meta).
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
		var turn := rng.randf() * TAU
		var shade := rng.randf_range(0.82, 1.06)
		if String(one[2]) == "scrub":
			_spot(spots, "oak", Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(tall * 1.5, tall, tall * 1.5)), foot - Vector3(0.0, tall * 0.3, 0.0)), shade * 0.7)
		else:
			_spot(spots, "pine", Transform3D(_lean_basis(turn, float(one[3])).scaled(Vector3(tall * 0.65, tall, tall * 0.65)), foot - Vector3(0.0, 0.05, 0.0)), shade)
	# dune grass: tall, pale tufts. Thickest along the bluff's edge, scattered over the top, and in
	# a band at the back of the beach (Color > 1 tints the grass card paler and yellower)
	var left := 2600
	var tries := 0
	while left > 0 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-90.0, 90.0)
		var s: float
		var pick := rng.randf()
		if pick < 0.45:
			s = rng.randf_range(-6.0, 0.3)
		elif pick < 0.75:
			s = rng.randf_range(BLUFF_W + 0.5, BLUFF_W + 8.0)
		else:
			s = rng.randf_range(-24.0, -6.0)
		var z := edge_z(x) - s
		if on_cabin(x, z, 1.0) or path_distance(x, z) < 1.0 or absf(x - STAIRS_X) < 1.5 and s > -2.0:
			continue
		var sz := rng.randf_range(0.8, 1.5)
		var pale := rng.randf_range(0.0, 1.0)
		_spot(spots, "grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(1.3, 2.0), sz)),
			Vector3(x, height(x, z) - 0.02, z)), Color(1.15, 1.08, 0.7).lerp(Color(0.95, 1.0, 0.75), pale))
		left -= 1
	# short grass in the yard
	left = 700
	tries = 0
	while left > 0 and tries < 6000:
		tries += 1
		var p := YARD + Vector2(rng.randf_range(-1.0, 1.0) * YARD_R * 1.15, rng.randf_range(-1.0, 1.0) * YARD_R)
		if Vector2((p.x - YARD.x) / 1.15, p.y - YARD.y).length() > YARD_R - 2.0 or on_cabin(p.x, p.y, 0.8) or path_distance(p.x, p.y) < 0.9:
			continue
		var sz := rng.randf_range(0.5, 1.0)
		_spot(spots, "grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz, sz)),
			Vector3(p.x, height(p.x, p.y) - 0.02, p.y)), Color(0.95, 0.95, 0.8))
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
			var shade: Variant = list[i][1]
			if shade is Color:
				mm.set_instance_color(i, shade)
			else:
				var s := float(shade)
				mm.set_instance_color(i, Color(s, s, s))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind.to_pascal_case()
		mmi.multimesh = mm
		var small := kind == "grass"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if small:
			mmi.visibility_range_end = 70.0
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mmi)
	return holder


static func _spot(spots: Dictionary, kind: String, xf: Transform3D, shade: Variant) -> void:
	if not spots.has(kind):
		spots[kind] = []
	(spots[kind] as Array).append([xf, shade])
