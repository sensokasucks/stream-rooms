extends RefCounted
## Route 22's building kit: the mesh builder (Buf), the materials, and every shape both Route 22
## rooms are made of: red sandstone (buttes, fins, arches, hoodoos, domes, walls, boulders), the
## desert brush, and the roadside things (poles, signs, fences, buildings).
## Used by r22_drivein_builder.gd (the Drive-In lot), r22_pieces.gd (the Cruise's road pieces),
## r22_vehicles.gd and r22_billboards.gd. Nothing here keeps state: each function adds triangles
## to a Buf or returns a material. There is no Blender model; everything is built when a room
## loads, from fixed random seeds, so every PC builds the same desert. The one exception is the
## photo-scanned rocks and props in models/ (CC0 Poly Haven scans, see models/make_models.py),
## placed by scan_rock() and scan_prop().
##
## The materials (see the shaders for what each mesh attribute means):
##   rock   r22_rock.gdshader   the sandstone (layers from height, honeycomb, varnish)
##   prop   r22_prop.gdshader   everything else (vertex colour + MAT_ number in UV.x)
##   ground / road              r22_ground / r22_road.gdshader (the floor and the highway)
##   glow                       r22_glow.gdshader (glare round lights), one material per colour
##   scan                       r22_scan.gdshader (the scanned props' own photo maps)
## Every one of them goes into kit["mats"], the list r22_desert.gd writes the shared uniforms to
## each frame (bend, travel, wet, cloud shadows, detail). Make materials through these functions
## so they land in that list.

const TEX := "res://rooms/route22/textures/"
## The Lakeside Campfire's textures used here too (wood grain, cloth, the sky's noise).
const CAMP_TEX := "res://rooms/campfire/textures/"
const ROCK_SHADER := preload("res://rooms/route22/r22_rock.gdshader")
const PROP_SHADER := preload("res://rooms/route22/r22_prop.gdshader")
const GROUND_SHADER := preload("res://rooms/route22/r22_ground.gdshader")
const ROAD_SHADER := preload("res://rooms/route22/r22_road.gdshader")
const GLOW_SHADER := preload("res://rooms/route22/r22_glow.gdshader")
const SKY_NOISE := preload("res://rooms/campfire/textures/sky_noise.png")
const ROCK_NOISE := preload("res://rooms/route22/textures/rock_noise.png")

## What a prop is made of (UV.x in r22_prop.gdshader).
const MAT_PAINT: float = 0.0
const MAT_WOOD: float = 1.0
const MAT_ROCK: float = 2.0
const MAT_RUST: float = 3.0
const MAT_CLOTH: float = 4.0
const MAT_LIGHT: float = 5.0
const MAT_CHROME: float = 6.0
const MAT_GLASS: float = 7.0
const MAT_SAND: float = 8.0

## The road: lanes are 3.6 m, so the paint's edge lines sit at ±3.6 and the paved edge at ±3.75;
## gravel to ±SHOULDER. Nothing standing may come closer to the middle than CLEAR (the Cruise's
## cameras stand on the shoulder and the oncoming lane's edge).
const LANE: float = 3.6
const SHOULDER: float = 5.2
const CLEAR: float = 5.6

## The sandstone palette for tints (0.5 = the shader's own colour).
const TINT := Color(0.5, 0.5, 0.5, 0.0)
const TINT_PALE := Color(0.62, 0.58, 0.55, 0.0)
const TINT_DEEP := Color(0.46, 0.4, 0.4, 0.0)

static var _noise: FastNoiseLite


static func _n() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 2222
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.5
		_noise.fractal_octaves = 3
	return _noise


# ── A mesh being put together ────────────────────────────────
## Collects triangles and turns them into one mesh (the Lakeside Campfire's Buf, plus smooth
## surfaces from a grid of points). Every shape below adds to one of these, so a whole group of
## objects is a single mesh with a single material.
class Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	## UV.x of the shapes added from now on: a MAT_ number for props, the layer tilt for rock.
	var mat: float = 0.0
	## UV.y of the shapes added from now on: honeycomb weathering for rock (unused by props).
	var uv_y: float = 0.0

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		tri_round(a, b, c, n, n, n, col, col, col)

	## One triangle with its own normal and colour at each corner.
	func tri_round(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		if (c - a).cross(b - a).dot(na + nb + nc) < 0.0:
			var keep := b
			b = c
			c = keep
			var keep_n := nb
			nb = nc
			nc = keep_n
			var keep_c := cb
			cb = cc
			cc = keep_c
		verts.append_array([a, b, c])
		normals.append_array([na, nb, nc])
		colors.append_array([ca, cb, cc])
		var uv := Vector2(mat, uv_y)
		uvs.append_array([uv, uv, uv])

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
		quad(p[0], p[1], p[3], p[2], col)
		quad(p[4], p[6], p[7], p[5], col)
		quad(p[0], p[4], p[5], p[1], col)
		quad(p[2], p[3], p[7], p[6], col)
		quad(p[0], p[2], p[6], p[4], col)
		quad(p[1], p[5], p[7], p[3], col)

	## A box from its centre and size, not turned.
	func block(centre: Vector3, size: Vector3, col: Color) -> void:
		box(Transform3D(Basis.IDENTITY, centre), size, col)

	## A cylinder or cone standing on xf's origin along its Y axis: r0 at the bottom, r1 at the top.
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
				tri_round(b0, t1, t0, n0, n1, n0, col, col, col)
				tri_round(b0, b1, t1, n0, n1, n1, col, col, col)
			else:
				quad(b0, t0, t1, b1, col)
			if r0 > 0.0:
				tri(xf * Vector3.ZERO, b0, b1, end)
			if r1 > 0.0:
				tri(xf * Vector3(0.0, h, 0.0), t1, t0, end)

	## A cylinder from one point to another (a pole, a pipe, a wire).
	func rod(from: Vector3, to: Vector3, radius: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var axis := to - from
		if axis.length() < 0.001:
			return
		var up := axis.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		cyl(Transform3D(Basis(side, up, side.cross(up)), from), radius, radius, axis.length(), segs, col, cap)

	## A lumpy ball (a boulder, a bush): radii per axis, `lump` = how uneven, colours top / bottom.
	func blob(centre: Vector3, radii: Vector3, segs: int, rings: int, top: Color, bottom: Color, lump: float, rng: RandomNumberGenerator) -> void:
		var grid: Array = []
		for r in rings + 1:
			var row := PackedVector3Array()
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

	## A smooth surface through a grid of points: grid[row][column] (rows of equal length).
	## loop = the columns close into a ring (a rock's sides). Each corner's normal is the average
	## of the faces round it, so the surface shades smoothly. cols[row] = the colour of each row.
	func surface(grid: Array, loop: bool, cols: Array) -> void:
		var rows := grid.size()
		if rows < 2:
			return
		var w: int = (grid[0] as PackedVector3Array).size()
		var spans := w if loop else w - 1
		var acc: Array = []
		for r in rows:
			var nrow := PackedVector3Array()
			nrow.resize(w)
			acc.append(nrow)
		for r in rows - 1:
			for s in spans:
				var s1 := (s + 1) % w
				var a: Vector3 = grid[r][s]
				var b: Vector3 = grid[r][s1]
				var c: Vector3 = grid[r + 1][s1]
				var d: Vector3 = grid[r + 1][s]
				var fn := (b - a).cross(d - a) + (c - b).cross(d - b)
				for at: Vector2i in [Vector2i(r, s), Vector2i(r, s1), Vector2i(r + 1, s1), Vector2i(r + 1, s)]:
					acc[at.x][at.y] += fn
		for r in rows - 1:
			for s in spans:
				var s1 := (s + 1) % w
				var a: Vector3 = grid[r][s]
				var b: Vector3 = grid[r][s1]
				var c: Vector3 = grid[r + 1][s1]
				var d: Vector3 = grid[r + 1][s]
				var na: Vector3 = (acc[r][s] as Vector3).normalized()
				var nb: Vector3 = (acc[r][s1] as Vector3).normalized()
				var nc: Vector3 = (acc[r + 1][s1] as Vector3).normalized()
				var nd: Vector3 = (acc[r + 1][s] as Vector3).normalized()
				var c0: Color = cols[r]
				var c1: Color = cols[r + 1]
				tri_round(a, b, c, na, nb, nc, c0, c0, c1)
				tri_round(a, c, d, na, nc, nd, c0, c1, c1)

	## Sets every corner's alpha from its height: 0 at y = base up to 1 at y = top (the sway weight).
	func alpha_by_height(base: float, top: float) -> void:
		for i in verts.size():
			var c := colors[i]
			c.a = clampf((verts[i].y - base) / maxf(top - base, 0.01), 0.0, 1.0)
			colors[i] = c

	func is_empty() -> bool:
		return verts.is_empty()

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


# ── Materials ────────────────────────────────────────────────
## A new kit: the shared materials both rooms build with.
##   kit["mats"]        every material r22_desert.gd writes the shared uniforms to each frame,
##   kit["rock"]        the sandstone,
##   kit["prop"]        signs, poles, buildings, vehicles (its lights glow at night),
##   kit["neon"]        the same look for neon signs (they glow only with the Neon tick box on),
##   kit["brush"]       the desert plants (they sway),
##   kit["roads"]       the road materials (mirage, reflectors),
##   kit["glows"] / kit["neon_glows"]   the glare squares (see glow_material),
##   kit["pictures"]    the billboard pictures (r22_billboards.gd adds them; lit at night),
##   kit["brush_mm"]    every brush MultiMesh (scatter_brush adds them; r22_desert.gd thins them
##                      out by the Plant life slider).
static func new_kit() -> Dictionary:
	var mats: Array[ShaderMaterial] = []
	var glows: Array[ShaderMaterial] = []
	var neon_glows: Array[ShaderMaterial] = []
	var roads: Array[ShaderMaterial] = []
	var pictures: Array[ShaderMaterial] = []
	var brush_mm: Array[MultiMesh] = []
	var kit: Dictionary = {"mats": mats, "glows": glows, "neon_glows": neon_glows, "roads": roads, "pictures": pictures, "glow_by_color": {}, "brush_mm": brush_mm}
	kit["rock"] = rock_material(kit)
	kit["prop"] = prop_material(kit, 0.0)
	kit["neon"] = prop_material(kit, 0.0)
	kit["brush"] = prop_material(kit, 0.16)
	return kit


static func _note(kit: Dictionary, m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("cloud_noise", SKY_NOISE)
	m.set_shader_parameter("rock_noise", ROCK_NOISE)
	(kit["mats"] as Array[ShaderMaterial]).append(m)
	return m


static func rock_material(kit: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("tex_detail", load(TEX + "detail_sandstone.jpg"))
	m.set_shader_parameter("tex_detail_nor", load(TEX + "detail_sandstone_nor.jpg"))
	return _note(kit, m)


## sway: metres the brush tips move in a light breeze (0 for solid props).
static func prop_material(kit: Dictionary, sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("tex_wood", load(TEX + "detail_planks_weathered.jpg"))
	m.set_shader_parameter("tex_rust", load(TEX + "prop_rust.jpg"))
	m.set_shader_parameter("tex_rock", load(TEX + "detail_sandstone.jpg"))
	m.set_shader_parameter("tex_fabric", load(CAMP_TEX + "detail_fabric.jpg"))
	m.set_shader_parameter("tex_sand", load(TEX + "ground_sand.jpg"))
	return _note(kit, m)


static func ground_material(kit: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("tex_desert", load(TEX + "ground_desert.jpg"))
	m.set_shader_parameter("tex_sand", load(TEX + "ground_sand.jpg"))
	m.set_shader_parameter("tex_desert_nor", load(TEX + "ground_desert_nor.jpg"))
	m.set_shader_parameter("tex_sand_nor", load(TEX + "ground_sand_nor.jpg"))
	return _note(kit, m)


static func road_material(kit: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	m.set_shader_parameter("tex_asphalt", load(TEX + "road_asphalt.jpg"))
	m.set_shader_parameter("tex_asphalt_nor", load(TEX + "road_asphalt_nor.jpg"))
	(kit["roads"] as Array[ShaderMaterial]).append(m)
	return _note(kit, m)


## The glare material for one light colour (shared by every light of that colour and size).
## neon = a sign's light (listed in kit["neon_glows"]: the Neon tick box switches them), else a
## vehicle's or a lamp's (kit["glows"]: they follow the hour only).
static func glow_material(kit: Dictionary, col: Color, size: float, neon: bool = false) -> ShaderMaterial:
	var key := "%s/%.2f/%s" % [col.to_html(), size, neon]
	var known: Dictionary = kit["glow_by_color"]
	if known.has(key):
		return known[key]
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("color", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("strength", 0.0)
	_note(kit, m)
	(kit["neon_glows" if neon else "glows"] as Array[ShaderMaterial]).append(m)
	known[key] = m
	return m


## A glare square at `at` (in parent's space) in the colour and size given (see glow_material).
static func add_glow(kit: Dictionary, parent: Node3D, at: Vector3, col: Color, size: float, neon: bool = false) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Glare"
	mi.mesh = q
	mi.material_override = glow_material(kit, col, size, neon)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size * 2.0 + 30.0         # (the shader moves it: keep it from being culled early)
	parent.add_child(mi)
	mi.position = at
	return mi


static func add_mesh(parent: Node3D, node_name: String, b: Buf, mat: Material, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = b.to_mesh()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the bend moves the mesh sideways and up by up to tens of metres far out: don't cull early
	mi.extra_cull_margin = 40.0
	parent.add_child(mi)
	return mi


## A sign's words: a Label3D standing on the sign's face (+Z = the way it reads). Lit = drawn
## shining (neon), for night signs. Sizes in metres per pixel of font size (pixel_size).
static func add_words(parent: Node3D, text: String, at: Vector3, facing_y: float, height: float, col: Color, lit: bool = false) -> Label3D:
	var l := Label3D.new()
	l.name = "Words"
	l.text = text
	l.font_size = 64
	l.pixel_size = height / 64.0
	l.outline_size = 0
	l.modulate = col
	l.shaded = not lit
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = at
	l.rotation = Vector3(0.0, facing_y, 0.0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l


# ── Sandstone ────────────────────────────────────────────────
## A rock built as rings stacked up a profile: profile = [[height, radius], ...] from the
## bottom up (start below ground so it sits in the sand), squash = the X and Z stretch of each
## ring, lump = how much noise roughens the outline, salt moves the noise. A flat (slightly
## lumpy) cap closes the top. Buttes, mesas, hoodoos, domes, fins and pillars all come from this.
static func column(b: Buf, base: Vector3, profile: Array, squash: Vector2, segs: int, lump: float, salt: float, col: Color, turn: float = 0.0) -> void:
	var n := _n()
	var grid: Array = []
	var cols: Array = []
	var top_y := 0.0
	var top_r := 0.0
	for p: Array in profile:
		var h := float(p[0])
		var r := float(p[1])
		var row := PackedVector3Array()
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var dir := Vector3(cos(a), 0.0, sin(a))
			# the noise is read on the unit ring (so bigger rocks get bigger lumps), plus height
			var k := 1.0 + lump * n.get_noise_3d(dir.x * 1.6 + salt, h * 0.08 + salt * 0.37, dir.z * 1.6)
			var local := Vector3(dir.x * r * squash.x * k, h, dir.z * r * squash.y * k)
			row.append(base + local.rotated(Vector3.UP, turn))
		grid.append(row)
		cols.append(col)
		top_y = h
		top_r = r
	b.surface(grid, true, cols)
	if top_r > 0.01:
		var last: PackedVector3Array = grid[grid.size() - 1]
		var mid := base + Vector3(0.0, top_y + 0.02 * top_r, 0.0)
		for s in segs:
			b.tri(mid, last[s], last[(s + 1) % segs], col)


## A butte or mesa: a talus skirt, steep layered cliffs, a flat cap rock. size: x = width,
## y = height, z = depth (metres).
static func butte(b: Buf, base: Vector3, size: Vector3, salt: float, segs: int = 22, turn: float = 0.0) -> void:
	var r := 0.5
	var h := size.y
	var prof: Array = [[-1.5, r * 1.45], [0.0, r * 1.4], [h * 0.12, r * 1.2], [h * 0.2, r * 1.02], [h * 0.45, r * 0.98],
		[h * 0.7, r * 0.97], [h * 0.9, r * 0.95], [h * 0.97, r * 0.97], [h, r * 0.9]]
	column(b, base, prof, Vector2(size.x, size.z), segs, 0.13, salt, Color(0.5, 0.5, 0.5, 0.55), turn)


## A fin: a long thin wall of rock standing on edge with a ragged top.
static func fin(b: Buf, base: Vector3, length: float, height: float, thick: float, salt: float, turn: float = 0.0) -> void:
	var prof: Array = [[-1.0, 0.56], [0.0, 0.55], [height * 0.25, 0.5], [height * 0.55, 0.44], [height * 0.8, 0.36], [height * 0.95, 0.24], [height, 0.1]]
	column(b, base, prof, Vector2(thick * 2.0, length * 2.0 * 0.5), 18, 0.28, salt, Color(0.5, 0.5, 0.5, 0.3), turn)


## A hoodoo: a slim, waisted pillar of soft rock with a wider, paler cap rock balanced on top.
static func hoodoo(b: Buf, base: Vector3, height: float, radius: float, salt: float) -> void:
	var prof: Array = [[-0.5, radius * 1.6], [0.0, radius * 1.5], [height * 0.25, radius * 1.05], [height * 0.55, radius * 0.75],
		[height * 0.78, radius * 0.6], [height * 0.86, radius * 0.7]]
	column(b, base, prof, Vector2.ONE, 12, 0.22, salt, TINT)
	var cap: Array = [[0.0, radius * 0.7], [radius * 0.25, radius * 1.25], [radius * 0.7, radius * 1.15], [radius * 0.85, radius * 0.6]]
	column(b, base + Vector3(0.0, height * 0.86, 0.0), cap, Vector2(1.0, 0.9), 12, 0.25, salt + 3.0, TINT_PALE)


## A balanced rock: a stubby pedestal with a big boulder perched on a small neck.
static func balanced_rock(b: Buf, base: Vector3, size: float, salt: float, rng: RandomNumberGenerator) -> void:
	var prof: Array = [[-0.5, size * 0.55], [0.0, size * 0.5], [size * 0.5, size * 0.38], [size * 0.85, size * 0.22], [size * 0.95, size * 0.16]]
	column(b, base, prof, Vector2(1.0, 0.8), 12, 0.2, salt, TINT)
	var ball: Array = [[0.0, size * 0.15], [size * 0.2, size * 0.55], [size * 0.55, size * 0.75], [size * 0.9, size * 0.65], [size * 1.15, size * 0.3]]
	column(b, base + Vector3(rng.randf_range(-0.1, 0.1) * size, size * 0.92, 0.0), ball, Vector2(1.2, 0.9), 14, 0.18, salt + 5.0, TINT_PALE, rng.randf() * TAU)


## A beehive dome: a rounded hump of cross-bedded sandstone.
static func dome(b: Buf, base: Vector3, radius: float, height: float, salt: float) -> void:
	var prof: Array = [[-0.6, radius * 1.02]]
	for i in 8:
		var t := float(i) / 7.0
		prof.append([height * t, radius * sqrt(maxf(1.0 - t * t, 0.0)) * (1.0 - 0.15 * t) + 0.05])
	var old_tilt := b.mat
	b.mat = 0.9            # strongly tilted, curving layers (cross-bedding)
	column(b, base, prof, Vector2(1.0, 0.85), 18, 0.08, salt, TINT_PALE)
	b.mat = old_tilt


## A boulder: a lumpy rounded rock half sunk in the sand.
static func boulder(b: Buf, base: Vector3, size: float, salt: float, turn: float) -> void:
	var prof: Array = [[-size * 0.3, size * 0.8], [0.0, size * 0.95], [size * 0.35, size * 0.9], [size * 0.7, size * 0.6], [size * 0.85, size * 0.25]]
	column(b, base, prof, Vector2(1.0, 0.75), 9, 0.25, salt, TINT, turn)


# ── Photo-scanned models (models/, made by make_models.py from CC0 Poly Haven scans) ──
const MODELS := "res://rooms/route22/models/"
const SCAN_SHADER := preload("res://rooms/route22/r22_scan.gdshader")
## The scanned rocks (rock_<name>.obj), for scan_rock(); sizes in models/models.json.
const SCAN_ROCKS: Array[String] = ["boulder_a", "boulder_b", "boulder_c", "boulder_d", "boulder_e", "pile", "stones"]
## The loaded model meshes by file name, so each .obj is read once however many times it is
## placed (both rooms, every road piece).
static var _scan_cache: Dictionary = {}


static func _scan_mesh(file: String) -> Mesh:
	if not _scan_cache.has(file):
		_scan_cache[file] = load(MODELS + file + ".obj") as Mesh
	return _scan_cache[file] as Mesh


## Copies a scanned rock (rock_<name>.obj, one of SCAN_ROCKS) into a rock Buf, so it is drawn by
## the same sandstone shader as the formations round it and costs no extra draw call. at = where
## it stands (its foot, sunk `sink` x its height into the sand), scale = metres per model metre
## (per axis: a flatter or longer rock from the same scan), turn = radians about Y. The Buf's
## current mat / uv_y (layer tilt, honeycomb) apply, and `varnish` goes into COLOR.a.
static func scan_rock(b: Buf, name: String, at: Vector3, scale: Vector3, turn: float, varnish: float = 0.3, sink: float = 0.12, col: Color = TINT) -> void:
	var mesh := _scan_mesh("rock_" + name)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var basis := Basis(Vector3.UP, turn) * Basis.from_scale(scale)
	var nbasis := basis.inverse().transposed()
	var height := 0.0
	for v: Vector3 in src_v:
		height = maxf(height, v.y)
	var xf := Transform3D(basis, at - Vector3(0.0, height * scale.y * sink, 0.0))
	var c := Color(col.r, col.g, col.b, varnish)
	var uv := Vector2(b.mat, b.uv_y)
	var count := idx.size() if not idx.is_empty() else src_v.size()
	for i in count:
		var k := idx[i] if not idx.is_empty() else i
		b.verts.append(xf * src_v[k])
		b.normals.append((nbasis * src_n[k]).normalized())
		b.colors.append(c)
		b.uvs.append(uv)


## A scanned prop with its photo textures (prop_<name>.obj + _diff/_nor/_arm.jpg): barrel,
## barrel_rusty, dead_trunk or dry_branches. Its own MeshInstance3D under `parent`, drawn by
## r22_scan.gdshader; one material per model, shared by every copy (kit["scan_mats"]) and listed
## in kit["mats"] so it bends and gets wet with the rest. at = its foot, scale = uniform size,
## turn = radians about Y, tint multiplies the photo.
static func scan_prop(parent: Node3D, kit: Dictionary, name: String, at: Vector3, scale: float, turn: float, tint: Color = Color.WHITE) -> MeshInstance3D:
	var mesh := _scan_mesh("prop_" + name)
	if mesh == null:
		return null
	if not kit.has("scan_mats"):
		kit["scan_mats"] = {}
	var mats: Dictionary = kit["scan_mats"]
	var key := name + str(tint)
	if not mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SCAN_SHADER
		m.set_shader_parameter("tex_albedo", load(MODELS + "prop_" + name + "_diff.jpg"))
		m.set_shader_parameter("tex_normal", load(MODELS + "prop_" + name + "_nor.jpg"))
		m.set_shader_parameter("tex_arm", load(MODELS + "prop_" + name + "_arm.jpg"))
		m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		mats[key] = _note(kit, m)
	var mi := MeshInstance3D.new()
	mi.name = "Scan_" + name
	mi.mesh = mesh
	mi.material_override = mats[key]
	mi.extra_cull_margin = 40.0
	parent.add_child(mi)
	mi.transform = Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * scale), at)
	return mi


## A loop of rock: a thick, lumpy tube swept along an arc from one foot to the other (an arch,
## or a flatter natural bridge). span = foot to foot (metres, along X before `turn`), rise =
## how high the inside of the opening is, thick = the tube's radius.
static func arch(b: Buf, base: Vector3, span: float, rise: float, thick: float, salt: float, turn: float) -> void:
	var n := _n()
	var steps := 22
	var segs := 12
	var grid: Array = []
	var cols: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := PI * t
		var centre := Vector3(-cos(a) * span * 0.5, sin(a) * (rise + thick * 0.6) - 0.6, 0.0)
		var along := Vector3(sin(a) * span * 0.5, cos(a) * (rise + thick * 0.6), 0.0).normalized()
		var side := Vector3(0.0, 0.0, 1.0)
		var up := side.cross(along).normalized()
		# thicker at the feet, thinnest at the crown
		var r := thick * (1.0 + 0.6 * pow(absf(cos(a)), 3.0))
		var row := PackedVector3Array()
		for s in segs:
			var c := TAU * float(s) / float(segs)
			var off := (up * cos(c) * 1.15 + side * sin(c) * 0.8) * r
			off *= 1.0 + 0.22 * n.get_noise_3d(t * 6.0 + salt, c, salt)
			row.append(base + (centre + off).rotated(Vector3.UP, turn))
		grid.append(row)
		cols.append(Color(0.5, 0.5, 0.5, 0.4))
	b.surface(grid, true, cols)
	# the rock mass round the feet and over the crown, so it reads as part of a fin
	for sx: float in [-1.0, 1.0]:
		var foot := base + Vector3(sx * span * 0.5, 0.0, 0.0).rotated(Vector3.UP, turn)
		var prof: Array = [[-0.5, thick * 2.2], [rise * 0.3, thick * 2.0], [rise * 0.7, thick * 1.6], [rise * 1.0, thick * 1.0]]
		column(b, foot, prof, Vector2(1.2, 0.8), 12, 0.2, salt + sx, TINT, turn)


## A cliff wall beside the road (a road cut, a slot canyon's side, a honeycomb or varnished face):
## a smooth grid that runs along Z from z0 to z1 at x = face (side = +1 for a wall on the right,
## facing the road at -X; -1 on the left), rising to `height` and then running back flat for
## `depth` metres, with its ends sloping down into the ground. wave = metres the face wanders.
## tilt (the layers' tilt) and honey (honeycomb) go into the mesh for the rock shader.
static func wall(b: Buf, z0: float, z1: float, face: float, side: float, height: float, depth: float, wave: float, salt: float, varnish: float, tilt: float, honey: float) -> void:
	var n := _n()
	var old_mat := b.mat
	var old_y := b.uv_y
	b.mat = tilt
	b.uv_y = honey
	var steps := maxi(int(absf(z1 - z0) / 2.0), 4)
	# the profile up the face and back over the top: [metres back from the face, height share]
	var prof: Array = [[-0.6, -0.08], [-0.2, 0.0], [0.0, 0.12], [0.15, 0.3], [0.1, 0.48], [0.3, 0.66], [0.25, 0.82], [0.6, 0.95], [1.4, 1.0], [depth * 0.5, 0.98], [depth, 0.9]]
	var grid: Array = []
	var cols: Array = []
	for pi in prof.size():
		var row := PackedVector3Array()
		var p: Array = prof[pi]
		for i in steps + 1:
			var t := float(i) / float(steps)
			var z := lerpf(z0, z1, t)
			# the ends ease down into the ground over the first and last fifth
			var ends := smoothstep(0.0, 0.2, t) * smoothstep(1.0, 0.8, t)
			var h := height * ends * (0.85 + 0.3 * (n.get_noise_2d(z * 0.03 + salt, salt) * 0.5 + 0.5))
			var back := float(p[0]) + wave * n.get_noise_2d(z * 0.09 + salt, float(pi) * 0.7 + salt)
			if float(p[0]) < 0.0:
				back = float(p[0])
			var y := float(p[1]) * h
			row.append(Vector3(face + side * back, y, z))
		grid.append(row)
		cols.append(Color(0.5, 0.5, 0.5, varnish))
	b.surface(grid, false, cols)
	b.mat = old_mat
	b.uv_y = old_y


# ── Brush ────────────────────────────────────────────────────
## The desert plants, one mesh each, scattered by MultiMesh (r22_pieces.gd / the Drive-In).
## Alpha = sway weight (0 at the foot). Kinds: "creosote", "sage", "brittlebush", "cholla",
## "yucca", "grass".
static func brush_mesh(kind: String) -> ArrayMesh:
	var b := Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"creosote":
			# a loose vase of thin dark stems with small olive leaf clumps at their tips
			for i in 9:
				var a := TAU * float(i) / 9.0 + rng.randf() * 0.4
				var lean := rng.randf_range(0.25, 0.55)
				var top := Vector3(cos(a) * lean, rng.randf_range(0.9, 1.5), sin(a) * lean)
				b.rod(Vector3(cos(a) * 0.05, 0.0, sin(a) * 0.05), top, 0.018, 4, Color(0.25, 0.2, 0.15))
				b.blob(top, Vector3(0.22, 0.16, 0.22), 6, 4, Color(0.42, 0.45, 0.2), Color(0.3, 0.33, 0.15), 0.5, rng)
			b.alpha_by_height(0.0, 1.4)
		"sage":
			# a low silvery mound
			for i in 4:
				var off := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
				b.blob(off + Vector3(0.0, 0.3, 0.0), Vector3(0.45, 0.35, 0.45), 7, 4, Color(0.62, 0.64, 0.52), Color(0.4, 0.4, 0.33), 0.45, rng)
			b.alpha_by_height(0.0, 0.8)
		"brittlebush":
			# a round grey-green ball with yellow flowers on top
			b.blob(Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.38, 0.5), 8, 5, Color(0.6, 0.65, 0.5), Color(0.38, 0.42, 0.3), 0.35, rng)
			for i in 14:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.1, 0.45)
				b.blob(Vector3(cos(a) * r, 0.7 + rng.randf() * 0.12, sin(a) * r), Vector3(0.06, 0.04, 0.06), 5, 3, Color(1.0, 0.82, 0.15), Color(0.9, 0.7, 0.1), 0.2, rng)
			b.alpha_by_height(0.0, 0.85)
		"cholla":
			# a cactus trunk with jointed, fuzzy pale arms (stiff: no sway)
			var pale := Color(0.72, 0.7, 0.45, 0.0)
			b.rod(Vector3.ZERO, Vector3(0.0, 0.9, 0.0), 0.08, 6, Color(0.4, 0.38, 0.25, 0.0))
			for i in 6:
				var a := TAU * float(i) / 6.0 + rng.randf()
				var from := Vector3(0.0, 0.6 + rng.randf() * 0.4, 0.0)
				var mid := from + Vector3(cos(a) * 0.25, 0.2, sin(a) * 0.25)
				var tip := mid + Vector3(cos(a) * 0.1, 0.3, sin(a) * 0.1)
				b.rod(from, mid, 0.07, 6, pale)
				b.rod(mid, tip, 0.065, 6, pale)
		"yucca":
			# a short shaggy trunk and a starburst of stiff dark blades
			b.rod(Vector3.ZERO, Vector3(0.0, 0.5, 0.0), 0.12, 6, Color(0.35, 0.3, 0.22))
			for i in 26:
				var a := rng.randf() * TAU
				var up := rng.randf_range(0.3, 1.0)
				var dir := Vector3(cos(a) * (1.0 - up * 0.6), up, sin(a) * (1.0 - up * 0.6)).normalized()
				var foot := Vector3(0.0, 0.5, 0.0)
				var tip := foot + dir * rng.randf_range(0.5, 0.8)
				var side := dir.cross(Vector3.UP).normalized() * 0.03
				b.tri(foot - side, foot + side, tip, Color(0.25, 0.36, 0.2))
			b.alpha_by_height(0.4, 1.3)
		_:
			# a tuft of dry grass: thin pale blades
			for i in 18:
				var a := rng.randf() * TAU
				var tip := Vector3(cos(a) * rng.randf_range(0.05, 0.25), rng.randf_range(0.25, 0.5), sin(a) * rng.randf_range(0.05, 0.25))
				var side := Vector3(-sin(a), 0.0, cos(a)) * 0.015
				b.tri(-side, side, tip, Color(0.78, 0.66, 0.42))
			b.alpha_by_height(0.0, 0.45)
	return b.to_mesh()


## Scatters the brush kinds over the spots: spots[i] = Vector3(x, 0, z) local. Returns the
## MultiMesh nodes (one per kind). Each spot gets a random kind (by `shares`), turn and size.
static func scatter_brush(parent: Node3D, kit: Dictionary, spots: PackedVector3Array, rng: RandomNumberGenerator, shares: Dictionary) -> Array[MultiMeshInstance3D]:
	var by_kind: Dictionary = {}
	var total := 0.0
	for k: String in shares:
		total += float(shares[k])
	for p in spots:
		var roll := rng.randf() * total
		var pick := ""
		for k: String in shares:
			roll -= float(shares[k])
			if roll <= 0.0:
				pick = k
				break
		if pick == "":
			pick = String(shares.keys()[0])
		if not by_kind.has(pick):
			by_kind[pick] = [] as Array[Transform3D]
		var s := rng.randf_range(0.6, 1.35)
		(by_kind[pick] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s)), p))
	var out: Array[MultiMeshInstance3D] = []
	for k: String in by_kind:
		var list: Array[Transform3D] = by_kind[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = brush_mesh(k)
		mm.instance_count = list.size()
		# listed for the Plant life slider (r22_desert.gd _apply_plants draws only the first part;
		# the spots come in random order, so any first part is an even thinning)
		(kit["brush_mm"] as Array[MultiMesh]).append(mm)
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			var shade := rng.randf_range(0.85, 1.1)
			mm.set_instance_color(i, Color(shade, shade, shade * rng.randf_range(0.92, 1.05), 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Brush_" + k
		mmi.multimesh = mm
		mmi.material_override = kit["brush"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k in ["creosote", "yucca", "cholla"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 40.0
		parent.add_child(mmi)
		out.append(mmi)
	return out


# ── Roadside things ──────────────────────────────────────────
## A wooden telephone pole at `at` (its foot) with a cross-arm and glass insulators; returns the
## points the wires hang from (left, middle, right insulator tops).
static func telephone_pole(b: Buf, at: Vector3, height: float) -> Array[Vector3]:
	b.mat = MAT_WOOD
	var wood := Color(0.36, 0.28, 0.2)
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, -0.5, 0.0)), 0.15, 0.12, height + 0.5, 7, wood)
	b.block(at + Vector3(0.0, height - 0.35, 0.0), Vector3(0.1, 0.12, 2.2), wood)
	var tops: Array[Vector3] = []
	b.mat = MAT_GLASS
	for z: float in [-0.95, 0.0, 0.95]:
		var p := at + Vector3(0.0, height - 0.28, z)
		b.cyl(Transform3D(Basis.IDENTITY, p), 0.045, 0.03, 0.12, 6, Color(0.4, 0.65, 0.6))
		tops.append(p + Vector3(0.0, 0.12, 0.0))
	b.mat = MAT_PAINT
	return tops


## A sagging wire between two points (thin; drawn in a few straight bits).
static func wire(b: Buf, a: Vector3, c: Vector3, sag: float) -> void:
	b.mat = MAT_PAINT
	var steps := 8
	var last := a
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(c, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
		b.rod(last, p, 0.012, 3, Color(0.08, 0.08, 0.08))
		last = p


## A sign on one or two posts: the panel's centre at `at`, size (w, h), facing +Z turned by
## `turn`, in `col` with a `rim` border. Words are added by the caller (add_words).
static func sign_board(b: Buf, at: Vector3, size: Vector2, turn: float, col: Color, rim: Color, posts: int = 1) -> void:
	var basis := Basis(Vector3.UP, turn)
	b.mat = MAT_PAINT
	b.box(Transform3D(basis, at), Vector3(size.x, size.y, 0.05), col)
	b.box(Transform3D(basis, at - basis.z * 0.01), Vector3(size.x + 0.08, size.y + 0.08, 0.04), rim)
	b.mat = MAT_RUST
	var grey := Color(0.45, 0.45, 0.47)
	if posts <= 1:
		b.rod(Vector3(at.x, -0.4, at.z) - basis.z * 0.06, Vector3(at.x, at.y + size.y * 0.3, at.z) - basis.z * 0.06, 0.04, 5, grey)
	else:
		for sx: float in [-0.35, 0.35]:
			var p := at + basis.x * size.x * sx - basis.z * 0.06
			b.rod(Vector3(p.x, -0.4, p.z), Vector3(p.x, at.y + size.y * 0.3, p.z), 0.045, 5, grey)
	b.mat = MAT_PAINT


## A white reflector post (delineator) with an amber reflector that catches headlights.
static func reflector_post(b: Buf, at: Vector3, amber: bool) -> void:
	b.mat = MAT_PAINT
	b.block(at + Vector3(0.0, 0.55, 0.0), Vector3(0.08, 1.2, 0.08), Color(0.85, 0.85, 0.82))
	b.mat = MAT_LIGHT
	b.block(at + Vector3(0.0, 1.0, 0.0), Vector3(0.09, 0.14, 0.09), Color(1.0, 0.6, 0.1) if amber else Color(0.9, 0.9, 0.85))
	b.mat = MAT_PAINT


## A barbed-wire fence along Z from z0 to z1 at x: leaning wooden posts every 4 m, three strands.
static func fence(b: Buf, x: float, z0: float, z1: float, rng: RandomNumberGenerator) -> void:
	var posts: Array[Vector3] = []
	var z := z0
	while (z1 - z) * signf(z1 - z0) >= -0.01:
		var lean := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var foot := Vector3(x + rng.randf_range(-0.1, 0.1), 0.0, z)
		b.mat = MAT_WOOD
		b.rod(foot + Vector3(0.0, -0.3, 0.0), foot + Vector3(0.0, 1.25, 0.0) + lean, 0.05, 5, Color(0.42, 0.36, 0.3))
		posts.append(foot + lean * 0.8)
		z += 4.0 * signf(z1 - z0)
	b.mat = MAT_RUST
	for i in posts.size() - 1:
		for y: float in [0.45, 0.8, 1.12]:
			b.rod(posts[i] + Vector3(0.0, y, 0.0), posts[i + 1] + Vector3(0.0, y - 0.03, 0.0), 0.006, 3, Color(0.35, 0.3, 0.27))
	b.mat = MAT_PAINT


## A metal guardrail along Z from z0 to z1 at x, rail facing the road (side = +1 right, -1 left).
static func guardrail(b: Buf, x: float, z0: float, z1: float, side: float) -> void:
	b.mat = MAT_CHROME
	var steel := Color(0.55, 0.56, 0.58)
	b.block(Vector3(x, 0.62, (z0 + z1) * 0.5), Vector3(0.06, 0.32, absf(z1 - z0)), steel)
	b.mat = MAT_RUST
	var z := minf(z0, z1)
	while z <= maxf(z0, z1):
		b.block(Vector3(x + side * 0.12, 0.35, z), Vector3(0.15, 0.95, 0.12), Color(0.45, 0.43, 0.42))
		z += 3.8
	b.mat = MAT_PAINT


## A small building: walls, a flat or pitched roof, a door and windows on the side facing +Z
## (before `turn`). Windows are MAT_LIGHT so they glow at night like lit rooms.
static func building(b: Buf, at: Vector3, size: Vector3, turn: float, wall_col: Color, roof_col: Color, pitched: bool, windows: int, lit_windows: bool) -> void:
	var basis := Basis(Vector3.UP, turn)
	b.mat = MAT_PAINT
	b.box(Transform3D(basis, at + Vector3(0.0, size.y * 0.5, 0.0)), size, wall_col)
	b.mat = MAT_WOOD
	if pitched:
		var h := size.y
		var w := size.x * 0.5 + 0.3
		var d := size.z * 0.5 + 0.3
		var ridge := h + size.z * 0.3
		var p := func(x: float, y: float, z: float) -> Vector3: return at + basis * Vector3(x, y, z)
		b.quad(p.call(-w, h, d), p.call(w, h, d), p.call(w, ridge, 0.0), p.call(-w, ridge, 0.0), roof_col)
		b.quad(p.call(-w, h, -d), p.call(w, h, -d), p.call(w, ridge, 0.0), p.call(-w, ridge, 0.0), roof_col)
		b.tri(p.call(-size.x * 0.5, h, size.z * 0.5), p.call(-size.x * 0.5, h, -size.z * 0.5), p.call(-size.x * 0.5, ridge, 0.0), wall_col)
		b.tri(p.call(size.x * 0.5, h, size.z * 0.5), p.call(size.x * 0.5, h, -size.z * 0.5), p.call(size.x * 0.5, ridge, 0.0), wall_col)
	else:
		b.box(Transform3D(basis, at + Vector3(0.0, size.y + 0.1, 0.0)), Vector3(size.x + 0.5, 0.2, size.z + 0.5), roof_col)
	# the door and windows on the front
	var front := at + basis * Vector3(0.0, 0.0, size.z * 0.5 + 0.02)
	b.mat = MAT_WOOD
	b.box(Transform3D(basis, front + basis * Vector3(-size.x * 0.3, 1.0, 0.0)), Vector3(0.9, 2.0, 0.06), wall_col.darkened(0.45))
	b.mat = MAT_LIGHT if lit_windows else MAT_GLASS
	for i in windows:
		var x := lerpf(-size.x * 0.05, size.x * 0.4, float(i) / maxf(float(windows - 1), 1.0)) if windows > 1 else size.x * 0.15
		b.box(Transform3D(basis, front + basis * Vector3(x, 1.5, 0.0)), Vector3(0.9, 0.8, 0.05), Color(1.0, 0.78, 0.45) if lit_windows else Color(0.3, 0.35, 0.4))
	b.mat = MAT_PAINT


## A simple long road strip mesh (for r22_road.gdshader): `half` metres either side of its own
## X = 0, from z0 to z1, cut every `step` metres along so the bend can curve it.
static func road_strip(half: float, z0: float, z1: float, step: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(absf(z1 - z0) / step)
	st.set_normal(Vector3.UP)
	for i in n:
		var za := z0 + (z1 - z0) * float(i) / float(n)
		var zb := z0 + (z1 - z0) * float(i + 1) / float(n)
		for xs: Array in [[-half, 0.0], [0.0, half]]:
			var xa := float(xs[0])
			var xb := float(xs[1])
			st.add_vertex(Vector3(xa, 0.0, za))
			st.add_vertex(Vector3(xb, 0.0, za))
			st.add_vertex(Vector3(xb, 0.0, zb))
			st.add_vertex(Vector3(xa, 0.0, za))
			st.add_vertex(Vector3(xb, 0.0, zb))
			st.add_vertex(Vector3(xa, 0.0, zb))
	# (r22_road.gdshader draws both sides, so the winding doesn't matter)
	return st.commit()


## A flat ground sheet: `half` metres either side in X and Z ranges, with finer cells near the
## middle (where the bend is small and the camera close) and coarser ones far out.
static func ground_sheet(x_half: float, z0: float, z1: float) -> ArrayMesh:
	var xs: Array[float] = []
	var x := -x_half
	while x < x_half:
		xs.append(x)
		x += 4.0 if absf(x) < 40.0 else 20.0
	xs.append(x_half)
	var zs: Array[float] = []
	var z := z0
	while z < z1:
		zs.append(z)
		z += 4.0 if absf(z) < 60.0 else 10.0
	zs.append(z1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var a := Vector3(xs[i], -0.03, zs[j])
			var b := Vector3(xs[i + 1], -0.03, zs[j])
			var c := Vector3(xs[i + 1], -0.03, zs[j + 1])
			var d := Vector3(xs[i], -0.03, zs[j + 1])
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(a)
			st.add_vertex(d)
			st.add_vertex(c)
	return st.commit()
