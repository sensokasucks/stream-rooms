extends RefCounted
## The Lakeside Campfire's detailed plants: the trees, grass tufts and ferns drawn when the
## room's "Set detail" choice is not Low-poly (campfire_room.gd, _apply_detail).
## Called by campfire_builder.gd (_build_detailed_plants), which places them with MultiMeshes
## on the same spots as the low-poly trees. Everything is static: no instance of this exists.
##
## How a tree is made (the way games of the 2000s did it, cheap to draw): a round trunk and a
## few limbs with a bark photo on them, and the leaves as flat "cards": rectangles showing a
## see-through picture of a whole bough or spray of leaves (textures/card_*.png). A fir is rings
## of drooping bough cards up its trunk; a leafy tree is clumps of leaf cards round its limbs.
## The species differ in shape as well as in leaf (the owner compared them side by side):
## the oak is low and broad on heavy spreading limbs, the maple a taller dense egg shape, the
## birch slender with hanging twigs and a white trunk, the pine a bare trunk under a flat crown.
## Every kind is built 1 unit tall, so the builder can scale it like the low-poly trees.
##
## A tree's mesh has two surfaces, each with its material already on it (so the MultiMesh that
## draws it must not be given a material_override):
##   0  trunk and limbs: camp_prop.gdshader with detail = 1 (UV.x picks the bark, MAT_ below)
##   1  the cards: camp_foliage.gdshader with the kind's card picture
## Vertex colour: rgb = shade (darker inside the crown), alpha = how far the wind moves it.
## materials() makes the materials once per room.

const PROP_SHADER := preload("res://rooms/campfire/camp_prop.gdshader")
const FOLIAGE_SHADER := preload("res://rooms/campfire/camp_foliage.gdshader")
const TEX := "res://rooms/campfire/textures/"

## The bark numbers camp_prop.gdshader knows (the same as campfire_builder.gd's MAT_ constants).
const MAT_BARK: float = 1.0
const MAT_BARK_OAK: float = 5.0
const MAT_BARK_BIRCH: float = 6.0

## The kinds kit() can make.
const KINDS: PackedStringArray = ["fir", "young_fir", "pine", "oak", "birch", "maple", "grass", "fern"]


## The triangles of one surface while it is being put together.
class Surf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	## One card: a rectangle from `base` (the picture's bottom edge, its stem end) to `tip`,
	## `width` across along `side`. All four corners get the normal `n`. shade_base / shade_tip
	## darken the two ends (1 = as photographed); the wind weight is each end's height.
	func card(base: Vector3, tip: Vector3, side: Vector3, width: float, n: Vector3, shade_base: float, shade_tip: float) -> void:
		var h := side.normalized() * width * 0.5
		var first := verts.size()
		verts.append_array([base - h, base + h, tip + h, tip - h])
		normals.append_array([n, n, n, n])
		var cb := Color(shade_base, shade_base, shade_base, clampf(base.y, 0.0, 1.0))
		var ct := Color(shade_tip, shade_tip, shade_tip, clampf(tip.y, 0.0, 1.0))
		colors.append_array([cb, cb, ct, ct])
		uvs.append_array([Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)])
		indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])

	## A round, tapering stick from one point to another (a trunk, a limb): r0 thick at `from`,
	## r1 at `to`. bark = which bark photo (a MAT_ number, stored in UV.x).
	func limb(from: Vector3, to: Vector3, r0: float, r1: float, segs: int, col: Color, bark: float) -> void:
		var axis := to - from
		if axis.length() < 0.0001:
			return
		var up := axis.normalized()
		var a := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var b := up.cross(a)
		var first := verts.size()
		for i in segs + 1:
			var ang := TAU * float(i) / float(segs)
			var out := a * cos(ang) + b * sin(ang)
			for top: bool in [false, true]:
				var at := (to + out * r1) if top else (from + out * r0)
				verts.append(at)
				normals.append(out)
				colors.append(Color(col.r, col.g, col.b, clampf(at.y, 0.0, 1.0)))
				uvs.append(Vector2(bark, 0.0))
		for i in segs:
			var k := first + i * 2
			indices.append_array([k, k + 1, k + 3, k, k + 3, k + 2])

	func arrays() -> Array:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		return arr


## The materials every detailed plant uses, made once per room:
##   trunk (the bark), fir, pine, leaves, leaves_birch, leaves_maple, grass, fern.
## `sway` as in campfire_builder.gd's tree material (metres per unit of tree).
static func materials(sway: float) -> Dictionary:
	var out: Dictionary = {}
	var trunk := ShaderMaterial.new()
	trunk.shader = PROP_SHADER
	trunk.set_shader_parameter("detail", 1.0)
	trunk.set_shader_parameter("sway", sway)
	trunk.set_shader_parameter("tex_bark", load(TEX + "detail_bark_pine.jpg"))
	trunk.set_shader_parameter("tex_bark_oak", load(TEX + "detail_bark_oak.jpg"))
	trunk.set_shader_parameter("tex_bark_birch", load(TEX + "detail_bark_birch.jpg"))
	out["trunk"] = trunk
	# [name, card picture, tint, sway]
	var kinds: Array = [
		["fir", "card_fir.png", Color(0.82, 0.95, 0.85), sway],
		["pine", "card_pine.png", Color(0.9, 1.0, 0.85), sway],
		["leaves", "card_oak.png", Color(1.0, 1.0, 1.0), sway],
		["leaves_birch", "card_birch.png", Color(1.0, 1.0, 1.0), sway],
		["leaves_maple", "card_maple.png", Color(1.0, 1.0, 1.0), sway],
		["grass", "card_grass.png", Color(0.8, 1.15, 0.5), 0.06],
		["fern", "card_fern.png", Color(0.85, 1.0, 0.8), 0.04],
	]
	for k: Array in kinds:
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		m.set_shader_parameter("card", load(TEX + String(k[1])))
		m.set_shader_parameter("tint", k[2])
		m.set_shader_parameter("sway", k[3])
		out[String(k[0])] = m
	return out


## The mesh of one kind of plant (see KINDS), with its materials from `mats` (materials()) on it.
## Trees are 1 unit tall; a grass tuft and a fern are in metres.
static func kit(kind: String, mats: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)                 # the same tree on every PC
	var trunk := Surf.new()
	var cards := Surf.new()
	var leaf_mat := "fir"
	match kind:
		"fir":
			_fir(trunk, cards, rng, 15, 0.13, 0.29)
		"young_fir":
			_fir(trunk, cards, rng, 7, 0.06, 0.36)
		"pine":
			_pine(trunk, cards, rng)
			leaf_mat = "pine"
		"oak":
			_leafy(trunk, cards, rng, {"bark": MAT_BARK_OAK, "trunk": 0.05, "fork": 0.24, "centre": 0.62, "radii": Vector3(0.47, 0.3, 0.47),
				"limbs": 9, "limb_r": 0.55, "rise": 0.15, "clumps": 0.75, "clump_r": 0.2,
				"cards": 150, "size": 0.25, "droop": 0.1, "col": Color(0.4, 0.36, 0.31)})
			leaf_mat = "leaves"
		"maple":
			_leafy(trunk, cards, rng, {"bark": MAT_BARK_OAK, "trunk": 0.032, "fork": 0.3, "centre": 0.66, "radii": Vector3(0.29, 0.34, 0.29),
				"limbs": 7, "limb_r": 0.4, "rise": 0.6, "clumps": 0.35, "clump_r": 0.16,
				"cards": 140, "size": 0.21, "droop": 0.0, "col": Color(0.36, 0.33, 0.3)})
			leaf_mat = "leaves_maple"
		"birch":
			_leafy(trunk, cards, rng, {"bark": MAT_BARK_BIRCH, "trunk": 0.022, "fork": 0.45, "centre": 0.7, "radii": Vector3(0.2, 0.29, 0.2),
				"limbs": 7, "limb_r": 0.36, "rise": 0.7, "clumps": 0.5, "clump_r": 0.12,
				"cards": 95, "size": 0.2, "droop": 0.6, "col": Color(0.66, 0.65, 0.61)})
			leaf_mat = "leaves_birch"
		"grass":
			for i in 3:
				var ang := PI * float(i) / 3.0 + rng.randf_range(-0.2, 0.2)
				cards.card(Vector3.ZERO, Vector3(rng.randf_range(-0.04, 0.04), 0.3, rng.randf_range(-0.04, 0.04)), Vector3(cos(ang), 0.0, sin(ang)), 0.42, Vector3.UP, 0.75, 1.0)
			leaf_mat = "grass"
		"fern":
			for i in 8:
				var ang := TAU * float(i) / 8.0 + rng.randf_range(-0.25, 0.25)
				var out_dir := Vector3(cos(ang), 0.0, sin(ang))
				var reach := rng.randf_range(0.45, 0.7)
				cards.card(out_dir * 0.03, out_dir * reach + Vector3.UP * reach * rng.randf_range(0.35, 0.6), out_dir.cross(Vector3.UP), reach * 0.3,
					(Vector3.UP + out_dir * 0.4).normalized(), 0.6, 1.0)
			leaf_mat = "fern"
	var mesh := ArrayMesh.new()
	if not trunk.verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats["trunk"])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cards.arrays())
	mesh.surface_set_material(mesh.get_surface_count() - 1, mats[leaf_mat])
	return mesh


## A fir / spruce: rings ("whorls") of bough cards up the trunk, long and hanging at the
## bottom, short and nearly level at the top, and three upright cards for the tip.
## first = the height of the lowest ring, reach = how long its boughs are.
static func _fir(trunk: Surf, cards: Surf, rng: RandomNumberGenerator, whorls: int, first: float, reach: float) -> void:
	trunk.limb(Vector3.ZERO, Vector3(0.0, 0.97, 0.0), 0.024, 0.003, 7, Color(0.34, 0.26, 0.2), MAT_BARK)
	for w in whorls:
		var t := float(w) / float(whorls - 1)
		var y := lerpf(first, 0.9, t)
		var length := reach * pow(1.0 - t, 0.8) + 0.06
		var boughs := 6 if t < 0.8 else 5
		var turn := rng.randf() * TAU
		for i in boughs:
			var ang := turn + TAU * float(i) / float(boughs) + rng.randf_range(-0.2, 0.2)
			var out_dir := Vector3(cos(ang), 0.0, sin(ang))
			# the boughs hang all the way up: each ring covers the trunk down to the ring below
			var droop := lerpf(0.65, 0.4, t) + rng.randf_range(-0.08, 0.12)
			var dir := (out_dir * cos(droop) - Vector3.UP * sin(droop)).normalized()
			var base := Vector3(0.0, y + rng.randf_range(-0.015, 0.015), 0.0)
			var l := length * rng.randf_range(0.85, 1.1)
			var side := dir.cross(Vector3.UP).normalized().rotated(dir, rng.randf_range(-0.45, 0.45))
			var n := (out_dir * 0.55 + Vector3.UP * 0.85).normalized()
			cards.card(base, base + dir * l, side, l * 0.8, n, 0.5, 1.0)
			if i % 2 == 0:
				# a second card on edge through the same bough, so it has a body from every side
				cards.card(base, base + dir * l * 0.92, dir.cross(side), l * 0.6, (out_dir + Vector3.UP * 0.3).normalized(), 0.45, 0.9)
	for i in 3:
		var ang := PI * float(i) / 3.0
		cards.card(Vector3(0.0, 0.8, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(cos(ang), 0.0, sin(ang)), 0.16, Vector3.UP, 0.7, 1.0)


## A Scots-type pine: a tall bare trunk under a broad, rather flat crown of rising limbs, each
## ending in tufts of long needles.
static func _pine(trunk: Surf, cards: Surf, rng: RandomNumberGenerator) -> void:
	var bark := Color(0.4, 0.27, 0.19)
	trunk.limb(Vector3.ZERO, Vector3(0.0, 0.5, 0.0), 0.03, 0.021, 8, bark, MAT_BARK)
	trunk.limb(Vector3(0.0, 0.5, 0.0), Vector3(0.02, 0.92, 0.01), 0.021, 0.006, 7, bark.lightened(0.12), MAT_BARK)
	var crown := Vector3(0.0, 0.76, 0.0)
	var ends: Array[Vector3] = [Vector3(0.02, 0.94, 0.01)]
	var dirs: Array[Vector3] = [Vector3.UP]
	var limbs := 13
	for i in limbs:
		var t := float(i) / float(limbs - 1)
		var y := lerpf(0.5, 0.88, t)
		var ang := float(i) * 2.4 + rng.randf_range(-0.3, 0.3)          # round the trunk by the golden angle
		var out_dir := Vector3(cos(ang), 0.0, sin(ang))
		var dir := (out_dir + Vector3.UP * rng.randf_range(0.2, 0.6)).normalized()
		var length := lerpf(0.36, 0.16, t) * rng.randf_range(0.85, 1.15)
		var from := Vector3(0.0, y, 0.0)
		trunk.limb(from, from + dir * length, 0.011, 0.003, 5, bark.lightened(0.1), MAT_BARK)
		# needles at the limb's end, two thirds along it and a third along it
		for share: float in [1.0, 0.66, 0.36]:
			ends.append(from + dir * length * share)
			dirs.append((dir + Vector3.UP * (1.0 - share)).normalized())
	for e in ends.size():
		for k in 3:
			var dir := (dirs[e] + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.2, 0.7), rng.randf_range(-0.7, 0.7))).normalized()
			var size := rng.randf_range(0.17, 0.25)
			var base := ends[e] - dir * size * 0.3
			var side := dir.cross(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)).normalized()
			var n := ((ends[e] - crown).normalized() + Vector3.UP * 0.5).normalized()
			cards.card(base, base + dir * size, side, size, n, 0.6, 1.0)
			cards.card(base, base + dir * size, dir.cross(side), size, n, 0.55, 0.95)


## A leafy tree. p:
##   bark (MAT_ number), col (the bark's colour), trunk (its radius at the foot),
##   fork (the height where the limbs start to leave the trunk),
##   centre (the crown's middle height), radii (the crown's half sizes),
##   limbs (how many), limb_r (a limb's thickness at its start, as a share of the trunk's),
##   rise (0 = the limbs spread out sideways, an oak; 1 = they sweep upwards, a maple or birch),
##   cards (how many leaf cards), size (a card's length),
##   clumps (the share of the cards bunched round the limbs' ends, which gives the crown lumps
##     and gaps; the rest fill the crown's egg shape), clump_r (a bunch's radius),
##   droop (0 = leaves point outwards, 1 = they hang, as a birch's do).
static func _leafy(trunk: Surf, cards: Surf, rng: RandomNumberGenerator, p: Dictionary) -> void:
	var bark: float = p["bark"]
	var col: Color = p["col"]
	var radii: Vector3 = p["radii"]
	var centre := Vector3(0.0, float(p["centre"]), 0.0)
	var r: float = p["trunk"]
	var fork := Vector3(rng.randf_range(-0.01, 0.01), float(p["fork"]), rng.randf_range(-0.01, 0.01))
	var top := centre + Vector3(0.0, radii.y * 0.55, 0.0)
	trunk.limb(Vector3.ZERO, fork, r, r * 0.72, 8, col, bark)
	trunk.limb(fork, top, r * 0.72, r * 0.1, 6, col, bark)
	var limb_count: int = p["limbs"]
	var limb_r: float = r * float(p["limb_r"])
	var rise: float = p["rise"]
	var tips: Array[Vector3] = [top]
	for i in limb_count:
		var t := float(i) / float(limb_count - 1)
		var ang := float(i) * 2.4 + rng.randf_range(-0.3, 0.3)
		var out_dir := Vector3(cos(ang), 0.0, sin(ang))
		# the lowest limbs leave the trunk at the fork, below the leaves, where they can be seen
		var from := fork.lerp(top, t * 0.6)
		var reach := lerpf(1.0, 0.6, t) * rng.randf_range(0.8, 1.0)
		var to := Vector3(out_dir.x * radii.x * reach, 0.0, out_dir.z * radii.z * reach)
		to.y = from.y + (centre.y + radii.y * 0.5 - from.y) * lerpf(0.25, 0.8, rise) * rng.randf_range(0.7, 1.1)
		# a bend half way, so a limb is not a straight stick
		var elbow := from.lerp(to, 0.5) + Vector3(0.0, (to.y - from.y) * lerpf(-0.15, 0.2, rise) + 0.02, 0.0)
		trunk.limb(from, elbow, limb_r * lerpf(1.0, 0.6, t), limb_r * 0.55, 5, col, bark)
		trunk.limb(elbow, to, limb_r * 0.55, limb_r * 0.12, 5, col, bark)
		tips.append(to)
		tips.append(elbow.lerp(to, 0.4) + Vector3(0.0, radii.y * 0.25, 0.0))
	var count: int = p["cards"]
	var size: float = p["size"]
	var droop: float = p["droop"]
	var clumped := int(float(count) * float(p["clumps"]))
	var clump_r: float = p["clump_r"]
	for i in count:
		var u := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.75, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var depth := lerpf(0.5, 1.0, pow(rng.randf(), 0.45))
		var at: Vector3
		if i < clumped:
			# round a limb's end
			at = tips[i % tips.size()] + u * clump_r * depth
		else:
			# anywhere in the crown: most of them near its outside, where the leaves are
			at = centre + Vector3(u.x * radii.x, u.y * radii.y, u.z * radii.z) * depth
		var from_centre := (at - centre) / radii
		var dir := (u + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) - Vector3.UP * droop * 1.6).normalized()
		var l := size * rng.randf_range(0.8, 1.2)
		var side := dir.cross(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)).normalized()
		var n := (from_centre.normalized() + u * 0.5 + Vector3.UP * 0.35).normalized()
		# darker deep in the crown and underneath, as real crowns are
		var shade := lerpf(0.5, 1.0, clampf(from_centre.length(), 0.0, 1.0)) * lerpf(0.72, 1.0, clampf(from_centre.y * 0.5 + 0.5, 0.0, 1.0))
		cards.card(at - dir * l * 0.5, at + dir * l * 0.5, side, l, n, shade * 0.85, shade)
