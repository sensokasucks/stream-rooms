extends RefCounted
## Route 22's vehicles, built from plain shapes (no models): the red woody convertible the
## co-stream guests ride in (our own design after the style of Sen's reference sheet: long, low,
## wood-grain side panels framed in pale trim, chrome bumpers, four round headlights,
## whitewalls), and the traffic: pickups, semis, motorhomes, motorcycles, classic sedans and a
## tour bus. The Drive-In parks convertibles and pickups in its lot with the same builders.
##
## Every vehicle is built in its own space: front towards -Z, ground at y = 0, centred on its
## middle. build() writes into Bufs (r22_geo.gd) by part, so a caller can give each part its own
## material (the Cruise's woody: clear-coat paint, varnished wood, chrome) or put every part into
## one Buf with the prop material (traffic, the lot), where each part's MAT_ number picks the look.
## Callers: r22_traffic.gd, r22_drivein_builder.gd, r22_pieces.gd (the wreck). The Cruise's own
## woody is no longer built here: r22_car.gd loads the Blender model models/woody.glb.
##
## On the Detailed look (Set detail) the traffic and the Drive-In's parked cars are Blender
## models instead (models/vehicles.glb, made by models/make_vehicles.py): build_model() copies
## one into a Buf, so it is still drawn by the prop material with everything else. The shapes
## built here stay the Low look, and the wreck.

const Geo := preload("res://rooms/route22/r22_geo.gd")

## Which r22_prop.gdshader look each part gets when parts share one Buf.
const PART_MAT: Dictionary = {
	"paint": 0.0, "wood": 1.0, "trim": 1.0, "chrome": 6.0, "rubber": 0.0, "white": 0.0,
	"leather": 0.0, "dark": 0.0, "glass": 7.0, "lamp_front": 5.0, "lamp_tail": 5.0, "rust": 3.0,
}
## Wheel size (metres) of the cars; trucks and buses scale it.
const WHEEL_R: float = 0.36

## The kinds of traffic and how often each turns up (shares, any scale).
const TRAFFIC_KINDS: Dictionary = {"pickup": 5.0, "classic": 4.0, "semi": 3.0, "rv": 2.0, "motorcycle": 2.0, "bus": 1.0}


## The Blender models: one mesh per kind, its surfaces named by material (see make_vehicles.py).
const MODELS := "res://rooms/route22/models/vehicles.glb"
## kind -> {"surfaces": [{"look": material name, "verts", "normals": one entry per triangle
## corner}], "front_lights", "tail_lights": [Vector3], "length": metres}; filled once by _load_models().
static var _models: Dictionary = {}


## Reads models/vehicles.glb into _models (once): every mesh's triangles by material name, and
## its lamp markers (child nodes named <kind>_LampFront_n / <kind>_LampTail_n).
static func _load_models() -> void:
	if not _models.is_empty():
		return
	var scene := load(MODELS) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var surfaces: Array = []
		for i in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(i)
			var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var verts := src_v
			var normals := src_n
			if arrays[Mesh.ARRAY_INDEX] != null:
				# a Buf has no index list: one entry per triangle corner
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				verts = PackedVector3Array()
				normals = PackedVector3Array()
				verts.resize(idx.size())
				normals.resize(idx.size())
				for k in idx.size():
					verts[k] = src_v[idx[k]]
					normals[k] = src_n[idx[k]]
			var from := mi.mesh.surface_get_material(i)
			surfaces.append({"look": String(from.resource_name) if from else "", "verts": verts, "normals": normals})
		var fronts: Array[Vector3] = []
		var tails: Array[Vector3] = []
		for c in mi.get_children():
			if c is Node3D and String(c.name).contains("_LampFront_"):
				fronts.append((c as Node3D).position)
			elif c is Node3D and String(c.name).contains("_LampTail_"):
				tails.append((c as Node3D).position)
		_models[String(mi.name)] = {"surfaces": surfaces, "front_lights": fronts, "tail_lights": tails, "length": mi.get_aabb().size.z}
	root.free()


## The Detailed look's vehicle: copies a Blender model into `b` (a prop Buf). kind and opts as
## for build() ("woody" = the convertible with wood sides; "classic" + "open" = the plain
## convertible; "rusty" is not for models). paint = its own colour. rng picks the semi's
## trailer and the rider's jacket. Returns {"length", "front_lights", "tail_lights"} like
## build(); the seats are build()'s, the same on both looks. Falls back to build() if the model
## file is missing.
static func build_model(kind: String, b: Geo.Buf, paint: Color, opts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	_load_models()
	var woody := kind == "woody"
	var model := kind
	if woody or kind == "classic":
		model = "convertible" if woody or bool(opts.get("open", false)) else "classic"
	if not _models.has(model):
		return build(kind, {"all": b}, paint, opts, rng)
	# what each material name in the models is here: [MAT_ number, colour]
	var dark := Color(0.05, 0.05, 0.055)
	var bright := Color(0.8, 0.8, 0.82)
	var pale := Color(0.92, 0.9, 0.85)
	var trailer := Color(0.9, 0.9, 0.88) if rng.randf() < 0.6 else paint.lightened(0.4)
	var jacket := Color(0.15, 0.12, 0.1) if rng.randf() < 0.6 else Color(0.35, 0.25, 0.15)
	var looks: Dictionary = {
		"paint": [Geo.MAT_CAR, paint], "bed": [Geo.MAT_CAR, paint.darkened(0.3)], "helmet": [Geo.MAT_CAR, paint.lightened(0.2)],
		"wood": [Geo.MAT_WOOD, Color(0.62, 0.4, 0.22)] if woody else [Geo.MAT_CAR, paint],
		"trim": [Geo.MAT_PAINT, Color(0.88, 0.76, 0.52)] if woody else [Geo.MAT_CAR, paint],
		"chrome": [Geo.MAT_CHROME, bright], "hub": [Geo.MAT_CHROME, bright], "glass": [Geo.MAT_GLASS, Color(0.3, 0.35, 0.4)],
		"lamp_front": [Geo.MAT_LIGHT, Color(1.0, 0.95, 0.85)], "lamp_tail": [Geo.MAT_LIGHT, Color(0.9, 0.08, 0.05)],
		"amber": [Geo.MAT_LIGHT, Color(1.0, 0.55, 0.1)],
		"tyre": [Geo.MAT_RUBBER, Color(0.07, 0.07, 0.075)], "dark": [Geo.MAT_PAINT, dark], "pad": [Geo.MAT_LEATHER, dark],
		"carpet": [Geo.MAT_CLOTH, dark], "seat": [Geo.MAT_LEATHER, Color(0.08, 0.07, 0.065)],
		"whitewall": [Geo.MAT_RUBBER, pale], "white": [Geo.MAT_PAINT, pale],
		"leather": [Geo.MAT_LEATHER, Color(0.88, 0.84, 0.76)], "plate": [Geo.MAT_PAINT, Color(0.95, 0.8, 0.2)],
		# the sedan's two-tone roof and the motorhome's cab; the motorhome's slatted house; the coach's body and bright fluted skirt
		"ivory": [Geo.MAT_CAR, Color(0.92, 0.88, 0.78)], "cream": [Geo.MAT_SIDING, Color(0.92, 0.88, 0.78)],
		"coach": [Geo.MAT_CAR, Color(0.93, 0.93, 0.92)], "fluted": [Geo.MAT_SIDING, Color(0.85, 0.86, 0.88)],
		"trailer": [Geo.MAT_PANEL, trailer], "jacket": [Geo.MAT_LEATHER, jacket], "jeans": [Geo.MAT_CLOTH, Color(0.12, 0.15, 0.25)],
	}
	_copy_model(b, model, looks)
	if model == "pickup":
		_copy_model(b, "pickup_gate_down" if bool(opts.get("tailgate_down", false)) else "pickup_gate_up", looks)
	var e: Dictionary = _models[model]
	return {"length": float(e["length"]), "front_lights": e["front_lights"], "tail_lights": e["tail_lights"]}


## Appends one of _models' meshes to a Buf, each surface in its look's colour and MAT_ number.
static func _copy_model(b: Geo.Buf, model: String, looks: Dictionary) -> void:
	if not _models.has(model):
		return
	for s: Dictionary in (_models[model] as Dictionary)["surfaces"]:
		var look: Array = looks.get(String(s["look"]), [Geo.MAT_PAINT, Color(0.5, 0.5, 0.5)])
		var verts: PackedVector3Array = s["verts"]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		cols.fill(look[1] as Color)
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		uvs.fill(Vector2(float(look[0]), 0.0))
		b.verts.append_array(verts)
		b.normals.append_array(s["normals"] as PackedVector3Array)
		b.colors.append_array(cols)
		b.uvs.append_array(uvs)


## The Buf a part goes into, with its MAT_ number set: bufs[part] if the caller split that part
## out, else bufs["all"].
static func _p(bufs: Dictionary, part: String) -> Geo.Buf:
	var b: Geo.Buf = bufs[part] if bufs.has(part) else bufs["all"]
	b.mat = float(PART_MAT.get(part, 0.0))
	return b


## Builds one vehicle. kind: "woody", "classic", "pickup", "semi", "rv", "motorcycle", "bus".
## paint = the body colour. opts:
##   "no_wheels": true   leave the wheels out (r22_car.gd spins its own),
##   "tailgate_down": true  a pickup's tailgate lies open (the Drive-In's pickups),
##   "rusty": true       the wreck by the road: rust everywhere, no glass, no wheels,
##   "open": true        a "classic" without its hard top (a plain convertible).
## Returns {"length": metres, "front_lights": [Vector3], "tail_lights": [Vector3],
## "wheels": [[centre, radius]], "seats": [Vector3 on the seat surface]}.
static func build(kind: String, bufs: Dictionary, paint: Color, opts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	match kind:
		"woody":
			return _car(bufs, paint, opts, true)
		"classic":
			return _car(bufs, paint, opts, false)
		"pickup":
			return _pickup(bufs, paint, opts)
		"semi":
			return _semi(bufs, paint, opts, rng)
		"rv":
			return _rv(bufs, paint, opts)
		"motorcycle":
			return _motorcycle(bufs, paint, rng)
		"bus":
			return _bus(bufs, paint, opts)
	return {}


## A smooth body through cross-sections: sections = [[z, PackedVector2Array of (x, y) from the
## bottom middle round the right side to the top middle]]; the left side mirrors the right.
## The ends are closed with a flat cap.
static func loft(b: Geo.Buf, sections: Array, col: Color) -> void:
	var grid: Array = []
	var cols: Array = []
	for sec: Array in sections:
		var z := float(sec[0])
		var half: PackedVector2Array = sec[1]
		var ring := PackedVector3Array()
		for p in half:
			ring.append(Vector3(p.x, p.y, z))
		for i in range(half.size() - 2, 0, -1):
			ring.append(Vector3(-half[i].x, half[i].y, z))
		grid.append(ring)
		cols.append(col)
	b.surface(grid, true, cols)
	for end: int in [0, grid.size() - 1]:
		var ring: PackedVector3Array = grid[end]
		var mid := Vector3.ZERO
		for p in ring:
			mid += p
		mid /= float(ring.size())
		for i in ring.size():
			b.tri(mid, ring[i], ring[(i + 1) % ring.size()], col)


## The body cross-section of the long, low cars at a given width scale and top height.
static func _section(w: float, top: float, bottom: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, bottom), Vector2(w * 0.94, bottom), Vector2(w, bottom + 0.18), Vector2(w * 1.0, top - 0.25),
		Vector2(w * 0.96, top - 0.06), Vector2(w * 0.75, top), Vector2(0.0, top + 0.02)])


## A wheel: tyre, whitewall ring and chrome hubcap, its axle along X, centre c.
static func wheel(bufs: Dictionary, c: Vector3, r: float, width: float, whitewall: bool) -> void:
	var side := signf(c.x) if absf(c.x) > 0.01 else 1.0
	var turn := Basis(Vector3.FORWARD, PI * 0.5)       # a cylinder's Y axis turned to lie along X
	var foot := c - Vector3(width * 0.5, 0.0, 0.0)
	_p(bufs, "rubber").cyl(Transform3D(turn, foot), r, r, width, 14, Color(0.05, 0.05, 0.05))
	var face := c + Vector3(side * (width * 0.5 + 0.004), 0.0, 0.0)
	var face_turn := Basis(Vector3.FORWARD, PI * 0.5 * side)     # Y turned to point out of the wheel's side
	if whitewall:
		_p(bufs, "white").cyl(Transform3D(face_turn, face), r * 0.82, r * 0.82, 0.006, 14, Color(0.92, 0.92, 0.88))
		_p(bufs, "rubber").cyl(Transform3D(face_turn, face + Vector3(side * 0.003, 0.0, 0.0)), r * 0.6, r * 0.6, 0.006, 14, Color(0.06, 0.06, 0.06))
	_p(bufs, "chrome").cyl(Transform3D(face_turn, face + Vector3(side * 0.006, 0.0, 0.0)), r * 0.5, r * 0.3, 0.06, 12, Color(0.8, 0.8, 0.82))


## A dark wheel arch painted on the body side over a wheel (the wheel shows inside it).
static func _arch(bufs: Dictionary, c: Vector3, r: float, x: float) -> void:
	var b := _p(bufs, "dark")
	var segs := 10
	for i in segs:
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		b.tri(Vector3(x, c.y - 0.05, c.z), Vector3(x, c.y + sin(a0) * r, c.z + cos(a0) * r), Vector3(x, c.y + sin(a1) * r, c.z + cos(a1) * r), Color(0.03, 0.03, 0.03))


## The long, low convertible (the woody: wood-panelled sides) or a classic sedan with a hard top
## and tail fins (wood = false). 5.4 m long, 2.0 m wide.
static func _car(bufs: Dictionary, paint: Color, opts: Dictionary, wood: bool) -> Dictionary:
	var rusty := bool(opts.get("rusty", false))
	var bp := _p(bufs, "rust" if rusty else "paint")
	var hood: Array = [[-2.72, _section(0.82, 0.88, 0.36)], [-2.6, _section(0.95, 0.97, 0.34)], [-2.2, _section(0.99, 1.0, 0.33)], [-1.05, _section(1.0, 1.03, 0.33)]]
	loft(bp, hood, paint)
	var tail: Array = [[1.85, _section(1.0, 1.0, 0.33)], [2.45, _section(0.99, 0.99, 0.34)], [2.72, _section(0.86, 0.9, 0.38)]]
	loft(_p(bufs, "rust" if rusty else "paint"), tail, paint)
	# the cabin: two side walls with a rounded top rail, the floor, the firewall and the back
	bp = _p(bufs, "rust" if rusty else "paint")
	for sx: float in [-1.0, 1.0]:
		bp.block(Vector3(sx * 0.96, 0.66, 0.4), Vector3(0.08, 0.66, 2.9), paint)
		bp.rod(Vector3(sx * 0.95, 0.99, -1.05), Vector3(sx * 0.95, 0.99, 1.85), 0.05, 7, paint)
	bp.block(Vector3(0.0, 0.36, 0.4), Vector3(1.9, 0.06, 2.9), paint.darkened(0.4))
	_p(bufs, "dark").block(Vector3(0.0, 0.42, 0.4), Vector3(1.86, 0.04, 2.86), Color(0.12, 0.05, 0.05))
	bp = _p(bufs, "rust" if rusty else "paint")
	bp.block(Vector3(0.0, 0.92, -0.98), Vector3(1.86, 0.22, 0.16), paint.darkened(0.15))          # the dash
	if not wood:
		# tail fins on the classic
		for sx: float in [-1.0, 1.0]:
			bp.quad(Vector3(sx * 0.93, 1.0, 1.6), Vector3(sx * 0.93, 1.0, 2.7), Vector3(sx * 0.9, 1.22, 2.66), Vector3(sx * 0.92, 1.03, 2.0), paint)
	var wheel_z: Array[float] = [-1.62, 1.62]
	for z in wheel_z:
		for sx: float in [-1.0, 1.0]:
			_arch(bufs, Vector3(0.0, WHEEL_R, z), WHEEL_R + 0.1, sx * 1.007)
	# wood panels framed in pale trim (the woody), or a chrome side strip (the classic)
	if wood and not rusty:
		var wd := _p(bufs, "wood")
		var honey := Color(0.62, 0.36, 0.17)
		var panels: Array = [[-0.95, 0.45, 0.42, 0.93], [0.45, 1.1, 0.42, 0.93], [1.1, 2.1, 0.8, 0.93], [2.1, 2.62, 0.42, 0.93]]
		for pnl: Array in panels:
			for sx: float in [-1.0, 1.0]:
				var z0 := float(pnl[0])
				var z1 := float(pnl[1])
				var y0 := float(pnl[2])
				var y1 := float(pnl[3])
				wd.block(Vector3(sx * 1.012, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(0.02, y1 - y0, z1 - z0), honey)
		var trm := _p(bufs, "trim")
		var maple := Color(0.9, 0.78, 0.55)
		for sx: float in [-1.0, 1.0]:
			trm.block(Vector3(sx * 1.024, 0.93, 0.84), Vector3(0.025, 0.06, 3.6), maple)
			trm.block(Vector3(sx * 1.024, 0.43, -0.25), Vector3(0.025, 0.06, 1.4), maple)
			trm.block(Vector3(sx * 1.024, 0.43, 2.36), Vector3(0.025, 0.06, 0.52), maple)
			for z: float in [-0.95, 0.45, 1.1, 2.1, 2.62]:
				var y0 := 0.8 if z > 1.05 and z < 2.15 else 0.42
				trm.block(Vector3(sx * 1.024, (y0 + 0.93) * 0.5, z), Vector3(0.025, 0.93 - y0, 0.06), maple)
		# the tailgate: wood framed in trim
		_p(bufs, "wood").block(Vector3(0.0, 0.67, 2.73), Vector3(1.2, 0.48, 0.02), honey)
		_p(bufs, "trim").block(Vector3(0.0, 0.92, 2.74), Vector3(1.26, 0.06, 0.02), maple)
		_p(bufs, "trim").block(Vector3(0.0, 0.43, 2.74), Vector3(1.26, 0.06, 0.02), maple)
	elif not rusty:
		for sx: float in [-1.0, 1.0]:
			_p(bufs, "chrome").block(Vector3(sx * 1.01, 0.68, 0.0), Vector3(0.015, 0.04, 5.0), Color(0.8, 0.8, 0.82))
	# chrome: bumpers, grille, the windscreen frame
	var ch := _p(bufs, "rust" if rusty else "chrome")
	var chrome := Color(0.82, 0.82, 0.84) if not rusty else Color(0.4, 0.25, 0.15)
	for z: float in [-2.8, 2.8]:
		ch.block(Vector3(0.0, 0.4, z), Vector3(1.9, 0.15, 0.1), chrome)
		for sx: float in [-1.0, 1.0]:
			ch.rod(Vector3(sx * 0.95, 0.4, z), Vector3(sx * 1.0, 0.4, z - signf(z) * 0.2), 0.075, 6, chrome)
	_p(bufs, "dark").block(Vector3(0.0, 0.6, -2.725), Vector3(0.7, 0.28, 0.02), Color(0.04, 0.04, 0.04))
	ch = _p(bufs, "rust" if rusty else "chrome")
	for i in 7:
		var x := lerpf(-0.32, 0.32, float(i) / 6.0)
		ch.block(Vector3(x, 0.6, -2.735), Vector3(0.025, 0.28, 0.02), chrome)
	ch.block(Vector3(0.0, 0.76, -2.735), Vector3(0.74, 0.03, 0.025), chrome)
	var lights: Array[Vector3] = []
	var tails: Array[Vector3] = []
	var lens_turn := Basis(Vector3.RIGHT, PI * 0.5)      # a disc's axis turned to point along +Z
	# four round headlights on the flat nose either side of the grille
	for x: float in [-0.68, -0.47, 0.47, 0.68]:
		var at := Vector3(x, 0.68, -2.72)
		ch = _p(bufs, "rust" if rusty else "chrome")
		ch.cyl(Transform3D(lens_turn, at + Vector3(0.0, 0.0, -0.07)), 0.1, 0.1, 0.07, 12, chrome)
		if not rusty:
			_p(bufs, "lamp_front").cyl(Transform3D(lens_turn, at + Vector3(0.0, 0.0, -0.082)), 0.078, 0.078, 0.015, 12, Color(1.0, 0.95, 0.82))
		lights.append(at + Vector3(0.0, 0.0, -0.2))
	for x: float in [-0.72, 0.72]:
		if not rusty:
			_p(bufs, "lamp_tail").block(Vector3(x, 0.74, 2.735), Vector3(0.2, 0.1, 0.04), Color(0.9, 0.08, 0.05))
		tails.append(Vector3(x, 0.74, 2.8))
	if not rusty:
		var g := _p(bufs, "glass")
		var fr := _p(bufs, "chrome")
		var lt := Vector3(-0.9, 1.02, -0.95)
		var rt := Vector3(0.9, 1.02, -0.95)
		var lb := Vector3(-0.86, 1.44, -0.76)
		var rb := Vector3(0.86, 1.44, -0.76)
		fr.rod(lt, lb, 0.022, 5, chrome)
		fr.rod(rt, rb, 0.022, 5, chrome)
		fr.rod(lb, rb, 0.022, 5, chrome)
		g.quad(lt + Vector3(0.03, 0.02, 0.0), rt + Vector3(-0.03, 0.02, 0.0), rb + Vector3(-0.03, -0.02, 0.0), lb + Vector3(0.03, -0.02, 0.0), Color(0.6, 0.7, 0.75))
		if not wood and not bool(opts.get("open", false)):
			# the classic's hard top: pillars and a roof over the back seat
			var p := _p(bufs, "paint")
			p.block(Vector3(0.0, 1.47, 0.5), Vector3(1.75, 0.06, 2.4), paint.lightened(0.6))
			for sx: float in [-0.86, 0.86]:
				p.rod(Vector3(sx, 1.0, 1.7), Vector3(sx, 1.45, 1.6), 0.04, 5, paint.lightened(0.6))
			_p(bufs, "glass").quad(Vector3(-0.86, 1.0, 1.75), Vector3(0.86, 1.0, 1.75), Vector3(0.86, 1.45, 1.65), Vector3(-0.86, 1.45, 1.65), Color(0.5, 0.6, 0.65))
		# the seats: two red leather benches, and the steering wheel on the left
		var lea := _p(bufs, "leather")
		var red := Color(0.55, 0.06, 0.05)
		lea.block(Vector3(0.0, 0.58, -0.22), Vector3(1.7, 0.18, 0.6), red)
		lea.box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, 0.92, 0.14)), Vector3(1.7, 0.62, 0.14), red.darkened(0.1))
		lea.block(Vector3(0.0, 0.6, 1.2), Vector3(1.72, 0.2, 0.62), red)
		lea.box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, 0.96, 1.57)), Vector3(1.72, 0.66, 0.14), red.darkened(0.1))
		var dk := _p(bufs, "dark")
		var hub := Vector3(-0.42, 1.04, -0.66)
		dk.rod(hub, Vector3(-0.42, 0.92, -0.92), 0.025, 5, Color(0.1, 0.1, 0.1))
		var ring_basis := Basis(Vector3.RIGHT, deg_to_rad(-60.0))
		var last := Vector3.ZERO
		for i in 13:
			var a := TAU * float(i) / 12.0
			var p := hub + ring_basis * Vector3(cos(a) * 0.19, 0.0, sin(a) * 0.19)
			if i > 0:
				dk.rod(last, p, 0.016, 4, Color(0.92, 0.88, 0.78))
			last = p
	# the plate: our own, ROUTE 22 (the words are a Label3D added by r22_car.gd)
	_p(bufs, "white").block(Vector3(0.0, 0.53, 2.76), Vector3(0.36, 0.18, 0.02), Color(0.95, 0.8, 0.2))
	var wheels: Array = []
	for z in wheel_z:
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * 0.9, WHEEL_R, z)
			wheels.append([c, WHEEL_R])
			if not bool(opts.get("no_wheels", false)) and not rusty:
				wheel(bufs, c, WHEEL_R, 0.22, true)
	# (front pair 1 m apart: the Drive-In's chat seats must be at least the default Seat spacing apart)
	var seats: Array[Vector3] = [Vector3(-0.5, 0.67, -0.2), Vector3(0.5, 0.67, -0.2), Vector3(-0.44, 0.7, 1.2), Vector3(0.44, 0.7, 1.2)]
	return {"length": 5.6, "front_lights": lights, "tail_lights": tails, "wheels": wheels, "seats": seats}


## A pickup: hood, cab with windows, and an open bed with a tailgate. 5.4 m.
static func _pickup(bufs: Dictionary, paint: Color, opts: Dictionary) -> Dictionary:
	var p := _p(bufs, "paint")
	var r := WHEEL_R * 1.15
	p.block(Vector3(0.0, 0.88, -1.85), Vector3(1.9, 0.66, 1.7), paint)                 # the hood
	p.block(Vector3(0.0, 1.2, -0.35), Vector3(1.9, 1.3, 1.3), paint)                    # the cab
	p.block(Vector3(0.0, 1.88, -0.35), Vector3(1.85, 0.06, 1.25), paint.lightened(0.2))
	p.block(Vector3(0.0, 0.62, 1.4), Vector3(1.9, 0.2, 2.2), paint.darkened(0.3))       # the bed floor
	for sx: float in [-1.0, 1.0]:
		p.block(Vector3(sx * 0.92, 0.96, 1.4), Vector3(0.06, 0.6, 2.2), paint)
	p.block(Vector3(0.0, 0.96, 0.33), Vector3(1.9, 0.6, 0.06), paint)
	if bool(opts.get("tailgate_down", false)):
		p.block(Vector3(0.0, 0.7, 2.78), Vector3(1.8, 0.06, 0.55), paint)
	else:
		p.block(Vector3(0.0, 0.96, 2.48), Vector3(1.9, 0.6, 0.06), paint)
	var g := _p(bufs, "glass")
	g.block(Vector3(0.0, 1.55, -1.01), Vector3(1.7, 0.5, 0.02), Color(0.3, 0.35, 0.4))
	for sx: float in [-1.0, 1.0]:
		g.block(Vector3(sx * 0.955, 1.55, -0.35), Vector3(0.02, 0.45, 1.0), Color(0.3, 0.35, 0.4))
		_arch(bufs, Vector3(0.0, r, -1.75), r + 0.1, sx * 0.955)
		_arch(bufs, Vector3(0.0, r, 1.55), r + 0.1, sx * 0.955)
	var ch := _p(bufs, "chrome")
	ch.block(Vector3(0.0, 0.5, -2.75), Vector3(2.0, 0.18, 0.12), Color(0.8, 0.8, 0.82))
	ch.block(Vector3(0.0, 0.5, 2.6), Vector3(2.0, 0.16, 0.12), Color(0.7, 0.7, 0.72))
	ch.block(Vector3(0.0, 0.85, -2.71), Vector3(1.3, 0.35, 0.04), Color(0.75, 0.75, 0.77))
	var lights: Array[Vector3] = []
	for x: float in [-0.72, 0.72]:
		_p(bufs, "lamp_front").block(Vector3(x, 0.88, -2.72), Vector3(0.22, 0.18, 0.04), Color(1.0, 0.95, 0.85))
		lights.append(Vector3(x, 0.88, -2.85))
	var tails: Array[Vector3] = []
	for x: float in [-0.9, 0.9]:
		_p(bufs, "lamp_tail").block(Vector3(x, 1.0, 2.5), Vector3(0.1, 0.25, 0.05), Color(0.9, 0.08, 0.05))
		tails.append(Vector3(x, 1.0, 2.58))
	var wheels: Array = []
	for z: float in [-1.75, 1.55]:
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * 0.88, r, z)
			wheels.append([c, r])
			if not bool(opts.get("no_wheels", false)):
				wheel(bufs, c, r, 0.26, false)
	# three places to sit in the bed, facing back over the tailgate: two at the tailgate end and
	# one further in, up on a cooler (all at least 1 m apart, the default Seat spacing)
	var seats: Array[Vector3] = [Vector3(-0.5, 0.73, 2.1), Vector3(0.5, 0.73, 2.1), Vector3(0.0, 0.95, 1.0)]
	return {"length": 5.6, "front_lights": lights, "tail_lights": tails, "wheels": wheels, "seats": seats}


## A semi: a long-nosed tractor with a sleeper, pulling a 13 m box trailer. About 19 m.
static func _semi(bufs: Dictionary, paint: Color, _opts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var p := _p(bufs, "paint")
	var r := WHEEL_R * 1.4
	p.block(Vector3(0.0, 1.3, -7.8), Vector3(2.3, 1.2, 2.2), paint)                      # the hood
	p.block(Vector3(0.0, 2.1, -5.8), Vector3(2.4, 2.8, 1.9), paint)                      # the cab and sleeper
	_p(bufs, "glass").block(Vector3(0.0, 2.75, -6.76), Vector3(2.2, 0.8, 0.03), Color(0.25, 0.3, 0.35))
	var ch := _p(bufs, "chrome")
	ch.block(Vector3(0.0, 1.2, -8.92), Vector3(1.4, 1.0, 0.05), Color(0.82, 0.82, 0.84))
	ch.block(Vector3(0.0, 0.6, -9.0), Vector3(2.5, 0.3, 0.15), Color(0.82, 0.82, 0.84))
	for sx: float in [-1.0, 1.0]:
		ch.rod(Vector3(sx * 1.1, 1.5, -5.0), Vector3(sx * 1.1, 4.1, -5.0), 0.08, 6, Color(0.82, 0.82, 0.84))
	var trailer := Color(0.9, 0.9, 0.88) if rng.randf() < 0.6 else paint.lightened(0.4)
	p = _p(bufs, "paint")
	p.block(Vector3(0.0, 2.45, 2.1), Vector3(2.5, 2.7, 13.2), trailer)
	p.block(Vector3(0.0, 1.5, 2.1), Vector3(2.48, 0.12, 13.2), trailer.darkened(0.4))
	var lights: Array[Vector3] = []
	for x: float in [-0.95, 0.95]:
		_p(bufs, "lamp_front").block(Vector3(x, 1.25, -8.93), Vector3(0.3, 0.2, 0.04), Color(1.0, 0.95, 0.85))
		lights.append(Vector3(x, 1.25, -9.1))
	for x: float in [-0.7, -0.35, 0.0, 0.35, 0.7]:
		_p(bufs, "lamp_tail").block(Vector3(x, 4.15, -6.77), Vector3(0.08, 0.06, 0.04), Color(1.0, 0.55, 0.1))
	var tails: Array[Vector3] = []
	for x: float in [-1.1, 1.1]:
		_p(bufs, "lamp_tail").block(Vector3(x, 1.1, 8.72), Vector3(0.2, 0.15, 0.04), Color(0.9, 0.08, 0.05))
		tails.append(Vector3(x, 1.1, 8.8))
	var wheels: Array = []
	for z: float in [-7.8, -5.0, -4.0, 6.6, 7.7]:
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * 1.0, r, z)
			wheels.append([c, r])
			wheel(bufs, c, r, 0.4, false)
	return {"length": 18.5, "front_lights": lights, "tail_lights": tails, "wheels": wheels, "seats": []}


## A motorhome: a cream box with a brown stripe, a cab over the windscreen.
static func _rv(bufs: Dictionary, paint: Color, _opts: Dictionary) -> Dictionary:
	var p := _p(bufs, "paint")
	var r := WHEEL_R * 1.25
	var cream := Color(0.92, 0.88, 0.78)
	p.block(Vector3(0.0, 1.95, 0.3), Vector3(2.5, 2.9, 8.0), cream)
	p.block(Vector3(0.0, 1.0, -4.2), Vector3(2.4, 1.1, 1.2), cream)
	for y: float in [1.5, 1.75]:
		p.block(Vector3(0.0, y, 0.3), Vector3(2.52, 0.12, 8.0), paint)
	var g := _p(bufs, "glass")
	g.block(Vector3(0.0, 1.95, -3.71), Vector3(2.3, 0.8, 0.03), Color(0.25, 0.3, 0.35))
	for sx: float in [-1.0, 1.0]:
		for z: float in [-1.5, 0.5, 2.6]:
			g.block(Vector3(sx * 1.26, 2.5, z), Vector3(0.02, 0.6, 1.2), Color(0.25, 0.3, 0.35))
	var lights: Array[Vector3] = []
	for x: float in [-0.9, 0.9]:
		_p(bufs, "lamp_front").block(Vector3(x, 1.0, -4.82), Vector3(0.28, 0.2, 0.04), Color(1.0, 0.95, 0.85))
		lights.append(Vector3(x, 1.0, -4.95))
	var tails: Array[Vector3] = []
	for x: float in [-1.15, 1.15]:
		_p(bufs, "lamp_tail").block(Vector3(x, 1.0, 4.31), Vector3(0.15, 0.3, 0.04), Color(0.9, 0.08, 0.05))
		tails.append(Vector3(x, 1.0, 4.4))
	_p(bufs, "chrome").block(Vector3(0.0, 0.5, -4.85), Vector3(2.4, 0.2, 0.12), Color(0.75, 0.75, 0.77))
	var wheels: Array = []
	for z: float in [-3.2, 2.6]:
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * 1.0, r, z)
			wheels.append([c, r])
			wheel(bufs, c, r, 0.3, false)
	return {"length": 9.0, "front_lights": lights, "tail_lights": tails, "wheels": wheels, "seats": []}


## A motorcycle and its rider (helmet, jacket), 2.2 m.
static func _motorcycle(bufs: Dictionary, paint: Color, rng: RandomNumberGenerator) -> Dictionary:
	var p := _p(bufs, "paint")
	p.blob(Vector3(0.0, 0.85, -0.15), Vector3(0.22, 0.2, 0.45), 8, 4, paint, paint.darkened(0.3), 0.1, rng)     # the tank
	p.block(Vector3(0.0, 0.8, 0.35), Vector3(0.3, 0.12, 0.6), Color(0.08, 0.06, 0.05))                       # the seat
	var ch := _p(bufs, "chrome")
	ch.rod(Vector3(0.0, 0.36, -0.78), Vector3(0.0, 1.05, -0.5), 0.03, 5, Color(0.8, 0.8, 0.82))
	ch.rod(Vector3(-0.35, 1.08, -0.5), Vector3(0.35, 1.08, -0.5), 0.02, 5, Color(0.8, 0.8, 0.82))
	ch.rod(Vector3(0.12, 0.45, 0.1), Vector3(0.14, 0.5, 0.9), 0.04, 6, Color(0.8, 0.8, 0.82))
	var rider := Color(0.15, 0.12, 0.1) if rng.randf() < 0.6 else Color(0.35, 0.25, 0.15)
	var cl := _p(bufs, "dark")
	cl.blob(Vector3(0.0, 1.3, 0.2), Vector3(0.24, 0.35, 0.18), 8, 5, rider, rider.darkened(0.2), 0.08, rng)
	cl.blob(Vector3(0.0, 1.78, 0.12), Vector3(0.14, 0.15, 0.15), 8, 5, paint.lightened(0.2), paint, 0.02, rng)
	for sx: float in [-0.25, 0.25]:
		cl.rod(Vector3(sx * 0.8, 1.4, 0.05), Vector3(sx * 1.4, 1.1, -0.45), 0.05, 5, rider)
		cl.rod(Vector3(sx * 0.6, 0.95, 0.3), Vector3(sx * 1.0, 0.45, 0.0), 0.06, 5, Color(0.12, 0.15, 0.25))
	var wheels: Array = []
	for z: float in [-0.75, 0.8]:
		var c := Vector3(0.0, 0.34, z)
		wheels.append([c, 0.34])
		wheel(bufs, c, 0.34, 0.12, false)
	_p(bufs, "lamp_front").block(Vector3(0.0, 0.95, -0.72), Vector3(0.14, 0.14, 0.05), Color(1.0, 0.95, 0.85))
	_p(bufs, "lamp_tail").block(Vector3(0.0, 0.75, 1.0), Vector3(0.1, 0.06, 0.04), Color(0.9, 0.08, 0.05))
	var lights: Array[Vector3] = [Vector3(0.0, 0.95, -0.85)]
	var tails: Array[Vector3] = [Vector3(0.0, 0.75, 1.05)]
	return {"length": 2.4, "front_lights": lights, "tail_lights": tails, "wheels": wheels, "seats": []}


## A tour bus: a long box with a band of dark windows and a coloured stripe. 12 m.
static func _bus(bufs: Dictionary, paint: Color, _opts: Dictionary) -> Dictionary:
	var p := _p(bufs, "paint")
	var r := WHEEL_R * 1.4
	p.block(Vector3(0.0, 2.0, 0.0), Vector3(2.55, 3.2, 12.0), Color(0.93, 0.93, 0.92))
	p.block(Vector3(0.0, 1.05, 0.0), Vector3(2.57, 0.35, 12.0), paint)
	p.block(Vector3(0.0, 3.3, 0.0), Vector3(2.5, 0.3, 11.8), paint.darkened(0.2))
	var g := _p(bufs, "glass")
	g.block(Vector3(0.0, 2.3, 0.3), Vector3(2.58, 1.0, 10.8), Color(0.2, 0.24, 0.3))
	g.block(Vector3(0.0, 2.2, -6.01), Vector3(2.3, 1.6, 0.03), Color(0.2, 0.24, 0.3))
	var lights: Array[Vector3] = []
	for x: float in [-0.95, 0.95]:
		_p(bufs, "lamp_front").block(Vector3(x, 0.9, -6.02), Vector3(0.35, 0.18, 0.04), Color(1.0, 0.95, 0.85))
		lights.append(Vector3(x, 0.9, -6.15))
	var tails: Array[Vector3] = []
	for x: float in [-1.1, 1.1]:
		_p(bufs, "lamp_tail").block(Vector3(x, 1.0, 6.01), Vector3(0.2, 0.4, 0.04), Color(0.9, 0.08, 0.05))
		tails.append(Vector3(x, 1.0, 6.1))
	var wheels: Array = []
	for z: float in [-4.2, 3.4, 4.5]:
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * 1.05, r, z)
			wheels.append([c, r])
			wheel(bufs, c, r, 0.35, false)
	return {"length": 12.5, "front_lights": lights, "tail_lights": tails, "wheels": wheels, "seats": []}
