extends RefCounted
## The Route 22 Cruise's road pieces: 24 stretches of desert, each 80 m long (LENGTH), that
## r22_trip.gd strings together in a shuffled order behind and ahead of the car, forever.
## Every piece has the same road (the road itself is one long strip that never moves, see
## route22_cruise_room.gd), so any piece can follow any other; what changes is what stands
## beside it: red sandstone (road cuts, fins, an arch, a natural bridge, hoodoos, balanced
## rocks, beehive domes, a honeycomb wall, petrified dunes, a slot-canyon cut, boulders, sand
## drifts, a varnished cliff, buttes) and roadside places (a gas station, an old motel, a diner,
## a jerky stand, a ranch with a water tower and a windmill, a rusted wreck, signs, guardrails,
## culverts).
## Every piece also gets the things that run the whole way: telephone poles on the right every
## 40 m with their wires (ravens perch on some), reflector posts, brush, small rocks (some of
## them photo-scanned, see Geo.scan_rock), now and then dead wood, and far off, now and then, a
## butte. The gas station, diner and jerky stand have scanned oil drums (Geo.scan_prop).
##
## A piece's space: X across the road (0 = the middle line, +X = the car's right), Z along it
## from 0 to -LENGTH (a piece reaches ahead of its origin, the way the car drives).
## build() makes one piece of a type into a Node3D, once, when the room loads; r22_trip.gd
## moves it into place whenever its turn comes. Nothing standing comes nearer the middle than
## Geo.CLEAR (5.6 m), so the cameras on the shoulder never end up inside a sign.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Vehicles := preload("res://rooms/route22/r22_vehicles.gd")

const LENGTH: float = 80.0
## The piece types, in their number order (r22_trip.gd shuffles the numbers).
const TYPES: PackedStringArray = ["flats", "road_cut", "fins", "arch", "natural_bridge", "hoodoos", "balanced_rocks", "domes",
	"honeycomb", "petrified_dunes", "slot_cut", "boulders", "sand_drifts", "gas_station", "motel", "diner", "jerky_stand",
	"ranch", "wreck", "services", "guardrails", "culverts", "buttes", "varnish_cliff"]
## The brush mix (shares) for ordinary desert.
const BRUSH: Dictionary = {"creosote": 5.0, "sage": 3.0, "brittlebush": 2.0, "grass": 4.0, "cholla": 1.0, "yucca": 1.0}
## How many plain stretches (build_plain) there are: one more than can be in view at once, so
## r22_trip.gd can give every plain place in view its own (place k gets number k % PLAIN).
const PLAIN: int = 12
## Where the telephone poles stand (X) and how far apart (metres; must divide LENGTH).
const POLE_X: float = 11.0
const POLE_GAP: float = 40.0
const POLE_H: float = 8.0


## Builds piece `type` (an index into TYPES) under a new Node3D, returned with metadata:
##   "slots"    billboard spots [[Vector3, side], ...] (r22_billboards.gd fill),
##   "spinners" nodes r22_trip.gd turns about their Z (windmill blades),
##   "mile"     the mile marker's Label3D (r22_trip.gd writes the mile on it), or null.
## The meshes inside: Rocks (sandstone), Props, Neon, Far (the distant butte), Brush_* (the
## plants), Scan_* (photo-scanned props, _scan), Labels (sign words, Label3D, which r22_trip.gd
## bends on the CPU).
static func build(type: int, kit: Dictionary) -> Node3D:
	return _build(TYPES[type], 9100 + type * 37, kit)


## A plain stretch of desert, number i (0..PLAIN-1): nothing but what every piece has (poles,
## posts, brush, small rocks, now and then a far butte, billboard spots). r22_trip.gd puts these
## between the landmark pieces when the Landmarks and stops slider is below 100. Kind "plain".
static func build_plain(i: int, kit: Dictionary) -> Node3D:
	var root := _build("plain", 5300 + i * 41, kit)
	root.name = "Piece_plain_%d" % i
	return root


static func _build(kind: String, salt: int, kit: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Piece_" + kind
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var rock := Geo.Buf.new()
	var props := Geo.Buf.new()
	var neon := Geo.Buf.new()
	var far := Geo.Buf.new()
	var labels := Node3D.new()
	labels.name = "Labels"
	root.add_child(labels)
	var boards := Node3D.new()
	boards.name = "Boards"
	root.add_child(boards)
	var p := {"root": root, "kit": kit, "rock": rock, "props": props, "neon": neon, "far": far, "labels": labels,
		"rng": rng, "keep_out": [] as Array[Rect2], "slots": [], "spinners": [] as Array[Node3D], "mile": null,
		"brush": 1.0, "glows": [] as Array}
	# the piece's own features first (they claim their ground: keep_out), then the common things
	match kind:
		"flats": _flats(p)
		"road_cut": _road_cut(p)
		"fins": _fins(p)
		"arch": _arch(p)
		"natural_bridge": _natural_bridge(p)
		"hoodoos": _hoodoos(p)
		"balanced_rocks": _balanced(p)
		"domes": _domes(p)
		"honeycomb": _honeycomb(p)
		"petrified_dunes": _dunes(p)
		"slot_cut": _slot_cut(p)
		"boulders": _boulders(p, 40)
		"sand_drifts": _sand_drifts(p)
		"gas_station": _gas_station(p)
		"motel": _motel(p)
		"diner": _diner(p)
		"jerky_stand": _jerky(p)
		"ranch": _ranch(p)
		"wreck": _wreck(p)
		"services": _services(p)
		"guardrails": _guardrails(p)
		"culverts": _culverts(p)
		"buttes": _buttes(p)
		"varnish_cliff": _varnish_cliff(p)
		"plain": p["brush"] = 1.1
	_common(p)
	if not rock.is_empty():
		_finish(Geo.add_mesh(root, "Rocks", rock, kit["rock"], true), 300.0)
	if not props.is_empty():
		_finish(Geo.add_mesh(root, "Props", props, kit["prop"], true), 300.0)
	if not neon.is_empty():
		var nm := Geo.add_mesh(root, "Neon", neon, kit["neon"], false)
		_finish(nm, 300.0)
	if not far.is_empty():
		var fm := Geo.add_mesh(root, "Far", far, kit["rock"], false)
		_finish(fm, 420.0)
	for g: Array in p["glows"]:
		Geo.add_glow(kit, root, g[0], g[1], float(g[2]), bool(g[3]))
	var spots := _brush_spots(p)
	for mmi in Geo.scatter_brush(root, kit, spots, rng, BRUSH):
		_finish(mmi, 220.0)
	root.set_meta("slots", p["slots"])
	root.set_meta("spinners", p["spinners"])
	root.set_meta("mile", p["mile"])
	root.set_meta("kind", kind)
	return root


## Fades a mesh out past `reach` metres from the camera (the far end of the road, behind and
## ahead), so pieces never pop in or out at the ends of the conveyor.
static func _finish(gi: GeometryInstance3D, reach: float) -> void:
	gi.visibility_range_end = reach
	gi.visibility_range_end_margin = 50.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## True if a spot is clear of the piece's features (and the road).
static func _free(p: Dictionary, at: Vector2, gap: float) -> bool:
	if absf(at.x) < Geo.CLEAR + gap:
		return false
	for r: Rect2 in p["keep_out"]:
		if r.grow(gap).has_point(at):
			return false
	return true


## Claims ground for a feature (brush and small rocks keep off it): centre and size in X / Z.
static func _claim(p: Dictionary, centre: Vector2, size: Vector2) -> void:
	(p["keep_out"] as Array[Rect2]).append(Rect2(centre - size * 0.5, size))


## A billboard spot: foot position and side (+1 right, -1 left), if the ground is free.
static func _slot(p: Dictionary, x: float, z: float) -> void:
	if _free(p, Vector2(x, z), 3.0):
		(p["slots"] as Array).append([Vector3(x, 0.0, z), signf(x)])
		_claim(p, Vector2(x, z), Vector2(10.0, 6.0))


## Words on a sign: a Label3D under Labels.
static func _words(p: Dictionary, text: String, at: Vector3, turn: float, height: float, col: Color, lit: bool = false) -> Label3D:
	return Geo.add_words(p["labels"], text, at, turn, height, col, lit)


## The things every piece has: poles and wires, reflector posts, small rocks, the far butte,
## billboard spots, and the brush (spots made in _brush_spots).
static func _common(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var rng: RandomNumberGenerator = p["rng"]
	# telephone poles on the right (POLE_GAP apart, so they line up across pieces) and the wires
	# from each to the next one, which is the next piece's first pole
	var z := -10.0
	while z > -LENGTH:
		var tops := Geo.telephone_pole(props, Vector3(POLE_X, 0.0, z), POLE_H)
		for t in tops:
			var to := t + Vector3(0.0, 0.0, -POLE_GAP)
			Geo.wire(props, t, to, 0.9)
		# a raven or two on the wires now and then
		if rng.randf() < 0.45:
			for i in rng.randi_range(1, 3):
				var along := rng.randf_range(0.2, 0.8)
				var t: Vector3 = tops[rng.randi() % tops.size()]
				var at := t.lerp(t + Vector3(0.0, 0.0, -POLE_GAP), along) - Vector3(0.0, 0.9 * 4.0 * along * (1.0 - along) - 0.12, 0.0)
				props.mat = Geo.MAT_PAINT
				props.blob(at, Vector3(0.07, 0.1, 0.16), 6, 4, Color(0.05, 0.05, 0.06), Color(0.03, 0.03, 0.04), 0.1, rng)
				props.blob(at + Vector3(0.0, 0.1, -0.12), Vector3(0.05, 0.05, 0.06), 5, 3, Color(0.05, 0.05, 0.06), Color(0.04, 0.04, 0.05), 0.1, rng)
		z -= POLE_GAP
	# reflector posts on both shoulders every 40 m
	for side: float in [-1.0, 1.0]:
		for zz: float in [-20.0, -60.0]:
			if _free(p, Vector2(side * 6.0, zz), -0.5):
				Geo.reflector_post(props, Vector3(side * 5.9, 0.0, zz), side > 0.0)
	# small rocks scattered about
	var rock: Geo.Buf = p["rock"]
	for i in 10:
		var at := Vector2(rng.randf_range(8.0, 60.0) * (-1.0 if rng.randf() < 0.5 else 1.0), rng.randf_range(-LENGTH, 0.0))
		if _free(p, at, 1.0):
			Geo.boulder(rock, Vector3(at.x, 0.0, at.y), rng.randf_range(0.4, 1.4), rng.randf() * 50.0, rng.randf() * TAU)
	# photo-scanned rocks (models/, CC0 Poly Haven scans) among them, a litter of scanned stones
	# near the shoulders and, now and then, a dead quiver-tree trunk or a heap of dry branches.
	# Their own random numbers, so the rest of the piece (billboard spots, brush) stays as it was.
	var srng := RandomNumberGenerator.new()
	srng.seed = rng.seed + 5
	for i in 4:
		var at := Vector2(srng.randf_range(7.5, 45.0) * (-1.0 if srng.randf() < 0.5 else 1.0), srng.randf_range(-LENGTH, 0.0))
		if _free(p, at, 1.0):
			var s := srng.randf_range(0.5, 1.6)
			Geo.scan_rock(rock, Geo.SCAN_ROCKS[srng.randi() % 5], Vector3(at.x, 0.0, at.y), Vector3(s, s * srng.randf_range(0.8, 1.25), s), srng.randf() * TAU)
	for i in 2:
		var at := Vector2(srng.randf_range(6.6, 14.0) * (-1.0 if srng.randf() < 0.5 else 1.0), srng.randf_range(-LENGTH, 0.0))
		if _free(p, at, 0.3):
			var s := srng.randf_range(2.5, 4.0)
			Geo.scan_rock(rock, "stones" if srng.randf() < 0.6 else "pile", Vector3(at.x, 0.0, at.y), Vector3(s, s, s), srng.randf() * TAU, 0.1, 0.05)
	if srng.randf() < 0.35:
		var at := Vector2(srng.randf_range(9.0, 30.0) * (-1.0 if srng.randf() < 0.5 else 1.0), srng.randf_range(-LENGTH, 0.0))
		if _free(p, at, 1.0):
			var trunk := srng.randf() < 0.5
			_scan(p, "dead_trunk" if trunk else "dry_branches", Vector3(at.x, 0.0, at.y), srng.randf_range(1.2, 1.8) if trunk else srng.randf_range(1.0, 1.6), srng.randf() * TAU)
			_claim(p, at, Vector2(2.0, 2.0))
	# a far butte or mesa on one side, now and then
	if rng.randf() < 0.55:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var at := Vector3(side * rng.randf_range(150.0, 260.0), 0.0, rng.randf_range(-LENGTH, 0.0))
		var size := Vector3(rng.randf_range(40.0, 110.0), rng.randf_range(22.0, 55.0), rng.randf_range(30.0, 70.0))
		Geo.butte(p["far"], at, size, rng.randf() * 90.0, 26, rng.randf() * TAU)
	# billboard spots: one each side, where the piece left room
	_slot(p, rng.randf_range(16.0, 24.0), rng.randf_range(-70.0, -15.0))
	_slot(p, -rng.randf_range(16.0, 24.0), rng.randf_range(-70.0, -15.0))


## A photo-scanned prop (Geo.scan_prop: barrel, barrel_rusty, dead_trunk, dry_branches) in the
## piece, fading out with the rest at the far ends of the road. at = its foot, in the piece's space.
static func _scan(p: Dictionary, name: String, at: Vector3, scale: float, turn: float) -> void:
	var mi := Geo.scan_prop(p["root"], p["kit"], name, at, scale, turn)
	if mi:
		_finish(mi, 220.0)


## Where the brush grows: thick near the road, thinning out to 140 m, none on claimed ground.
static func _brush_spots(p: Dictionary) -> PackedVector3Array:
	var rng: RandomNumberGenerator = p["rng"]
	var out := PackedVector3Array()
	var count := int(260.0 * float(p["brush"]))
	for i in count:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (6.2 + pow(rng.randf(), 1.8) * 140.0)
		var at := Vector2(x, rng.randf_range(-LENGTH, 0.0))
		if _free(p, at, 0.5):
			out.append(Vector3(at.x, 0.0, at.y))
	return out


# ── The pieces ───────────────────────────────────────────────
static func _flats(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	# a Route 22 shield on the right and the mile marker
	Geo.sign_board(props, Vector3(6.6, 2.3, -30.0), Vector2(0.75, 0.75), 0.0, Color(0.95, 0.95, 0.93), Color(0.1, 0.1, 0.1))
	_words(p, "ROUTE\n22", Vector3(6.6, 2.3, -29.96), 0.0, 0.2, Color(0.08, 0.08, 0.08))
	_mile_marker(p, Vector3(6.4, 0.0, -62.0))
	_claim(p, Vector2(6.6, -30.0), Vector2(2.0, 2.0))
	p["brush"] = 1.3


static func _mile_marker(p: Dictionary, at: Vector3) -> void:
	var props: Geo.Buf = p["props"]
	props.mat = Geo.MAT_PAINT
	props.block(at + Vector3(0.0, 0.6, 0.0), Vector3(0.08, 1.3, 0.04), Color(0.6, 0.6, 0.62))
	props.block(at + Vector3(0.0, 1.15, 0.0), Vector3(0.3, 0.5, 0.03), Color(0.1, 0.42, 0.25))
	var l := _words(p, "MILE\n0", at + Vector3(0.0, 1.15, 0.02), 0.0, 0.08, Color(0.95, 0.95, 0.95))
	p["mile"] = l


static func _road_cut(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	var tilt := rng.randf_range(0.5, 0.9) * (-1.0 if rng.randf() < 0.5 else 1.0)
	Geo.wall(p["rock"], -2.0, -78.0, 8.0, 1.0, rng.randf_range(9.0, 12.0), 30.0, 1.0, 11.0, 0.35, tilt, 0.2)
	Geo.wall(p["rock"], -2.0, -78.0, -8.0, -1.0, rng.randf_range(8.0, 11.0), 30.0, 1.0, 23.0, 0.35, tilt, 0.2)
	_claim(p, Vector2(22.0, -40.0), Vector2(30.0, 80.0))
	_claim(p, Vector2(-22.0, -40.0), Vector2(30.0, 80.0))
	# talus at the foot of the cut
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		Geo.boulder(p["rock"], Vector3(side * rng.randf_range(7.0, 8.0), 0.0, rng.randf_range(-70.0, -10.0)), rng.randf_range(0.3, 0.8), float(i), rng.randf() * TAU)


static func _fins(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	for i in 6:
		var at := Vector3(-rng.randf_range(18.0, 70.0), 0.0, rng.randf_range(-75.0, -5.0))
		Geo.fin(p["rock"], at, rng.randf_range(14.0, 26.0), rng.randf_range(8.0, 16.0), rng.randf_range(1.4, 2.6), rng.randf() * 40.0, rng.randf_range(-0.3, 0.3))
		_claim(p, Vector2(at.x, at.z), Vector2(8.0, 30.0))
	for i in 2:
		var at := Vector3(rng.randf_range(30.0, 60.0), 0.0, rng.randf_range(-70.0, -10.0))
		Geo.fin(p["rock"], at, rng.randf_range(12.0, 20.0), rng.randf_range(6.0, 11.0), 1.5, rng.randf() * 40.0, rng.randf_range(-0.4, 0.4))
		_claim(p, Vector2(at.x, at.z), Vector2(8.0, 24.0))


static func _arch(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	Geo.arch(p["rock"], Vector3(32.0, 0.0, -42.0), 18.0, 11.0, 2.4, 3.0, 0.25)
	_claim(p, Vector2(32.0, -42.0), Vector2(30.0, 24.0))
	# a brown viewpoint sign
	var props: Geo.Buf = p["props"]
	Geo.sign_board(props, Vector3(7.0, 1.9, -12.0), Vector2(2.2, 0.8), 0.0, Color(0.4, 0.25, 0.15), Color(0.85, 0.8, 0.7), 2)
	_words(p, "STONE ARCH\nVIEWPOINT", Vector3(7.0, 1.9, -11.96), 0.0, 0.22, Color(0.95, 0.9, 0.8))
	_claim(p, Vector2(7.0, -12.0), Vector2(3.0, 2.0))
	for i in 5:
		Geo.boulder(p["rock"], Vector3(rng.randf_range(22.0, 44.0), 0.0, rng.randf_range(-55.0, -30.0)), rng.randf_range(0.6, 1.6), float(i) + 3.0, rng.randf() * TAU)


static func _natural_bridge(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	# a flat, wide natural bridge over a side wash on the left
	Geo.arch(p["rock"], Vector3(-36.0, 0.0, -40.0), 26.0, 6.0, 2.8, 17.0, PI * 0.5)
	_claim(p, Vector2(-36.0, -40.0), Vector2(24.0, 36.0))
	# the wash crossing the road: a band of pale sand, and the road's concrete bridge rails
	props.mat = Geo.MAT_SAND
	for side: float in [-1.0, 1.0]:
		props.quad(Vector3(side * 5.0, 0.01, -34.0), Vector3(side * 60.0, 0.01, -30.0), Vector3(side * 60.0, 0.01, -48.0), Vector3(side * 5.0, 0.01, -46.0), Color(0.82, 0.62, 0.45))
	props.mat = Geo.MAT_PAINT
	for side: float in [-1.0, 1.0]:
		props.block(Vector3(side * 5.0, 0.55, -40.0), Vector3(0.3, 0.7, 16.0), Color(0.72, 0.7, 0.66))
		for z: float in [-32.5, -47.5]:
			props.block(Vector3(side * 5.0, 0.7, z), Vector3(0.4, 1.0, 0.5), Color(0.68, 0.66, 0.62))
	Geo.sign_board(props, Vector3(6.3, 1.8, -22.0), Vector2(1.6, 0.6), 0.0, Color(0.95, 0.85, 0.15), Color(0.1, 0.1, 0.1))
	_words(p, "DRY WASH", Vector3(6.3, 1.8, -21.96), 0.0, 0.22, Color(0.08, 0.08, 0.08))
	_claim(p, Vector2(0.0, -40.0), Vector2(14.0, 18.0))


static func _hoodoos(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	for i in 11:
		var side := -1.0 if i % 3 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(14.0, 45.0), 0.0, rng.randf_range(-75.0, -5.0))
		if not _free(p, Vector2(at.x, at.z), 1.0):
			continue
		var h := rng.randf_range(4.0, 11.0)
		Geo.hoodoo(p["rock"], at, h, h * rng.randf_range(0.12, 0.18), rng.randf() * 30.0)
		_claim(p, Vector2(at.x, at.z), Vector2(4.0, 4.0))


static func _balanced(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	for at: Vector3 in [Vector3(16.0, 0.0, -30.0), Vector3(-22.0, 0.0, -55.0), Vector3(34.0, 0.0, -66.0)]:
		Geo.balanced_rock(p["rock"], at, rng.randf_range(3.0, 5.5), rng.randf() * 30.0, rng)
		_claim(p, Vector2(at.x, at.z), Vector2(8.0, 8.0))
	_boulders(p, 18)


static func _domes(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	for i in 7:
		var side := 1.0 if i < 5 else -1.0
		var at := Vector3(side * rng.randf_range(16.0, 60.0), 0.0, rng.randf_range(-75.0, -5.0))
		if not _free(p, Vector2(at.x, at.z), 2.0):
			continue
		var r := rng.randf_range(6.0, 12.0)
		Geo.dome(p["rock"], at, r, r * rng.randf_range(0.8, 1.2), rng.randf() * 30.0)
		_claim(p, Vector2(at.x, at.z), Vector2(r * 2.0, r * 2.0))


static func _honeycomb(p: Dictionary) -> void:
	Geo.wall(p["rock"], -4.0, -76.0, 9.5, 1.0, 11.0, 26.0, 2.2, 41.0, 0.15, 0.2, 1.0)
	_claim(p, Vector2(24.0, -40.0), Vector2(30.0, 80.0))
	_boulders(p, 8)


static func _dunes(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(18.0, 50.0), 0.0, rng.randf_range(-75.0, -5.0))
		if not _free(p, Vector2(at.x, at.z), 2.0):
			continue
		var r := rng.randf_range(9.0, 16.0)
		var b: Geo.Buf = p["rock"]
		b.mat = rng.randf_range(0.8, 1.0) * side        # strongly tilted layers: cross-bedding
		Geo.column(b, at, [[-0.6, r], [r * 0.15, r * 0.95], [r * 0.3, r * 0.8], [r * 0.42, r * 0.55], [r * 0.5, r * 0.2]], Vector2(1.4, 0.8), 20, 0.12, rng.randf() * 20.0, Geo.TINT_PALE, rng.randf() * TAU)
		b.mat = 0.0
		_claim(p, Vector2(at.x, at.z), Vector2(r * 2.6, r * 2.0))


static func _slot_cut(p: Dictionary) -> void:
	Geo.wall(p["rock"], -6.0, -74.0, 6.6, 1.0, 17.0, 20.0, 1.4, 61.0, 0.25, 0.15, 0.4)
	Geo.wall(p["rock"], -6.0, -74.0, -6.6, -1.0, 16.0, 20.0, 1.4, 67.0, 0.25, 0.15, 0.4)
	_claim(p, Vector2(18.0, -40.0), Vector2(26.0, 80.0))
	_claim(p, Vector2(-18.0, -40.0), Vector2(26.0, 80.0))
	p["brush"] = 0.5


static func _boulders(p: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	for i in count:
		var at := Vector2(rng.randf_range(9.0, 60.0) * (-1.0 if rng.randf() < 0.5 else 1.0), rng.randf_range(-LENGTH, 0.0))
		if _free(p, at, 1.0):
			var s := rng.randf_range(0.8, 3.2)
			if i % 2 == 0:
				Geo.boulder(p["rock"], Vector3(at.x, 0.0, at.y), s, rng.randf() * 50.0, rng.randf() * TAU)
			else:
				# every other one a photo-scanned boulder (the scans are about 2.5 m across at 1)
				Geo.scan_rock(p["rock"], Geo.SCAN_ROCKS[i % 5], Vector3(at.x, 0.0, at.y), Vector3.ONE * s * 0.8, rng.randf() * TAU)
			_claim(p, at, Vector2(s * 2.0, s * 2.0))


static func _sand_drifts(p: Dictionary) -> void:
	var rng: RandomNumberGenerator = p["rng"]
	var props: Geo.Buf = p["props"]
	props.mat = Geo.MAT_SAND
	for i in 14:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var at := Vector3(side * rng.randf_range(7.0, 50.0), -0.2, rng.randf_range(-75.0, -5.0))
		var r := rng.randf_range(2.0, 7.0)
		props.blob(at, Vector3(r * 1.6, r * 0.22, r), 12, 5, Color(0.82, 0.5, 0.32), Color(0.75, 0.45, 0.3), 0.1, rng)
	props.mat = Geo.MAT_PAINT
	p["brush"] = 0.6


static func _gas_station(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var neon: Geo.Buf = p["neon"]
	var x := 22.0
	var z := -40.0
	# the canopy on four posts, two pumps under it, the shop behind, a tall sign by the road
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(x, 4.6, z), Vector3(8.0, 0.6, 12.0), Color(0.92, 0.9, 0.86))
	props.block(Vector3(x, 4.25, z), Vector3(8.1, 0.12, 12.1), Color(0.75, 0.1, 0.08))
	for sx: float in [-3.4, 3.4]:
		for sz: float in [-5.2, 5.2]:
			props.block(Vector3(x + sx, 2.1, z + sz), Vector3(0.3, 4.2, 0.3), Color(0.88, 0.86, 0.82))
	for sz: float in [-2.5, 2.5]:
		props.block(Vector3(x, 0.15, z + sz), Vector3(1.6, 0.3, 1.0), Color(0.6, 0.58, 0.55))
		props.block(Vector3(x, 1.05, z + sz), Vector3(0.6, 1.6, 0.45), Color(0.8, 0.12, 0.1))
		props.mat = Geo.MAT_LIGHT
		props.block(Vector3(x - 0.31, 1.45, z + sz), Vector3(0.02, 0.4, 0.3), Color(0.9, 0.95, 0.8))
		props.mat = Geo.MAT_PAINT
	Geo.building(props, Vector3(x + 9.0, 0.0, z), Vector3(7.0, 3.4, 9.0), -PI * 0.5, Color(0.88, 0.84, 0.74), Color(0.5, 0.15, 0.1), false, 3, true)
	props.mat = Geo.MAT_RUST
	props.cyl(Transform3D(Basis.IDENTITY, Vector3(8.5, -0.3, z + 8.0)), 0.18, 0.15, 9.0, 8, Color(0.5, 0.5, 0.52))
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(8.5, 8.8, z + 8.0), Vector3(0.4, 2.4, 3.2), Color(0.12, 0.12, 0.14))
	neon.mat = Geo.MAT_LIGHT
	neon.block(Vector3(8.29, 8.8, z + 8.0), Vector3(0.02, 2.2, 3.0), Color(1.0, 0.35, 0.15))
	_words(p, "GAS", Vector3(8.27, 9.2, z + 8.0), -PI * 0.5, 0.9, Color(4.0, 3.6, 2.8), true)
	_words(p, "EAT · COLD POP", Vector3(8.27, 8.25, z + 8.0), -PI * 0.5, 0.3, Color(3.0, 3.0, 3.0), true)
	(p["glows"] as Array).append([Vector3(8.0, 8.8, z + 8.0), Color(2.0, 0.6, 0.25), 4.0, true])
	(p["glows"] as Array).append([Vector3(x, 4.0, z), Color(1.6, 1.5, 1.3), 3.0, false])
	# oil drums by the shop's corner (photo-scanned)
	_scan(p, "barrel", Vector3(x + 5.0, 0.0, z - 5.2), 1.0, 0.3)
	_scan(p, "barrel_rusty", Vector3(x + 5.7, 0.0, z - 5.9), 1.0, 1.9)
	_scan(p, "barrel_rusty", Vector3(x + 5.1, 0.0, z - 6.3), 1.0, 4.0)
	_claim(p, Vector2(x + 3.0, z), Vector2(26.0, 24.0))


static func _motel(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var neon: Geo.Buf = p["neon"]
	var x := -26.0
	var z := -42.0
	# an L of rooms, doors facing the road, a few windows still lit, the old sign by the road
	for i in 6:
		Geo.building(props, Vector3(x - 2.0, 0.0, z - 15.0 + float(i) * 5.0), Vector3(6.0, 3.0, 5.0), PI * 0.5, Color(0.85, 0.75, 0.6), Color(0.45, 0.22, 0.15), false, 1, i % 3 == 1)
	Geo.building(props, Vector3(x + 6.0, 0.0, z + 18.0), Vector3(8.0, 3.4, 6.0), 0.0, Color(0.8, 0.7, 0.58), Color(0.45, 0.22, 0.15), false, 2, true)
	props.mat = Geo.MAT_RUST
	props.rod(Vector3(-8.5, -0.3, z + 20.0), Vector3(-8.5, 7.6, z + 20.0), 0.16, 7, Color(0.5, 0.48, 0.45))
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(-8.5, 7.0, z + 20.0), Vector3(0.35, 1.8, 4.2), Color(0.12, 0.25, 0.3))
	neon.mat = Geo.MAT_LIGHT
	neon.block(Vector3(-8.3, 7.0, z + 20.0), Vector3(0.02, 1.6, 4.0), Color(0.2, 0.9, 0.85))
	_words(p, "MOTEL", Vector3(-8.29, 7.25, z + 20.0), PI * 0.5, 0.8, Color(1.2, 4.0, 3.8), true)
	_words(p, "VACANCY", Vector3(-8.29, 6.45, z + 20.0), PI * 0.5, 0.35, Color(4.0, 1.0, 1.6), true)
	(p["glows"] as Array).append([Vector3(-8.0, 7.0, z + 20.0), Color(0.4, 1.8, 1.7), 4.5, true])
	_claim(p, Vector2(x, z), Vector2(18.0, 44.0))


static func _diner(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var neon: Geo.Buf = p["neon"]
	var x := 21.0
	var z := -36.0
	# a long, low streamlined diner: steel sides with a blue band, big lit windows
	props.mat = Geo.MAT_CHROME
	props.block(Vector3(x, 1.7, z), Vector3(5.0, 3.0, 16.0), Color(0.75, 0.76, 0.78))
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(x - 0.02, 1.0, z), Vector3(5.06, 0.35, 16.06), Color(0.15, 0.35, 0.65))
	props.block(Vector3(x, 3.35, z), Vector3(5.4, 0.3, 16.4), Color(0.85, 0.85, 0.82))
	props.mat = Geo.MAT_LIGHT
	for i in 5:
		props.block(Vector3(x - 2.52, 2.1, z - 6.0 + float(i) * 3.0), Vector3(0.04, 1.0, 2.2), Color(1.0, 0.85, 0.55))
	props.mat = Geo.MAT_RUST
	props.rod(Vector3(9.0, -0.3, z + 10.0), Vector3(9.0, 7.0, z + 10.0), 0.14, 7, Color(0.5, 0.5, 0.52))
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(9.0, 6.4, z + 10.0), Vector3(0.3, 1.6, 3.0), Color(0.9, 0.85, 0.75))
	neon.mat = Geo.MAT_LIGHT
	neon.block(Vector3(8.84, 6.4, z + 10.0), Vector3(0.02, 1.4, 2.8), Color(1.0, 0.25, 0.2))
	_words(p, "EAT", Vector3(8.83, 6.45, z + 10.0), -PI * 0.5, 1.0, Color(4.0, 0.9, 0.7), true)
	(p["glows"] as Array).append([Vector3(8.6, 6.4, z + 10.0), Color(2.0, 0.4, 0.3), 3.5, true])
	# a rusty drum out back for the trash (photo-scanned)
	_scan(p, "barrel_rusty", Vector3(x + 3.2, 0.0, z - 7.0), 1.0, 0.8)
	_claim(p, Vector2(x, z + 2.0), Vector2(16.0, 30.0))


static func _jerky(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var x := -12.0
	var z := -38.0
	# a plank shack with an awning, a hand-painted sign and two flags
	Geo.building(props, Vector3(x - 2.0, 0.0, z), Vector3(4.0, 2.6, 5.0), PI * 0.5, Color(0.6, 0.45, 0.3), Color(0.45, 0.35, 0.25), true, 1, false)
	props.mat = Geo.MAT_CLOTH
	props.quad(Vector3(x, 2.4, z - 2.4), Vector3(x, 2.4, z + 2.4), Vector3(x + 2.0, 1.9, z + 2.4), Vector3(x + 2.0, 1.9, z - 2.4), Color(0.85, 0.2, 0.15))
	props.mat = Geo.MAT_WOOD
	for sz: float in [-2.4, 2.4]:
		props.rod(Vector3(x + 2.0, 0.0, z + sz), Vector3(x + 2.0, 1.9, z + sz), 0.05, 5, Color(0.5, 0.4, 0.3))
	Geo.sign_board(props, Vector3(-7.0, 1.6, z + 12.0), Vector2(3.0, 1.2), PI * 0.5, Color(0.92, 0.88, 0.75), Color(0.5, 0.35, 0.2), 2)
	_words(p, "JERKY\nCOLD DRINKS", Vector3(-6.96, 1.6, z + 12.0), PI * 0.5, 0.3, Color(0.7, 0.1, 0.08))
	props.mat = Geo.MAT_CLOTH
	for i in 2:
		var fz := z - 6.0 - float(i) * 3.0
		props.rod(Vector3(-8.0, 0.0, fz), Vector3(-8.0, 3.2, fz), 0.03, 4, Color(0.6, 0.6, 0.6))
		props.quad(Vector3(-8.0, 3.1, fz), Vector3(-8.0, 3.1, fz - 1.1), Vector3(-8.0, 2.4, fz - 1.0), Vector3(-8.0, 2.4, fz), Color(0.95, 0.75, 0.1) if i == 0 else Color(0.1, 0.4, 0.75))
	props.mat = Geo.MAT_PAINT
	# a rusty water drum beside the shack (photo-scanned)
	_scan(p, "barrel_rusty", Vector3(x + 0.6, 0.0, z + 3.3), 1.0, 2.2)
	_claim(p, Vector2(x - 1.0, z), Vector2(10.0, 30.0))


static func _ranch(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var rng: RandomNumberGenerator = p["rng"]
	# a cattle guard across the road: steel bars flush with it, a fence running off each side
	props.mat = Geo.MAT_RUST
	for i in 9:
		props.block(Vector3(0.0, 0.02, -20.0 + float(i) * 0.3), Vector3(7.4, 0.04, 0.08), Color(0.35, 0.33, 0.3))
	for side: float in [-1.0, 1.0]:
		props.block(Vector3(side * 4.0, 0.4, -18.8), Vector3(0.12, 0.8, 0.12), Color(0.85, 0.85, 0.8))
		Geo.fence(props, side * 7.0, -18.8, -78.0, rng)
		Geo.fence(props, side * 7.0, -18.8, -2.0, rng)
	# the water tower on four legs
	var t := Vector3(-30.0, 0.0, -45.0)
	props.mat = Geo.MAT_WOOD
	for sx: float in [-1.6, 1.6]:
		for sz: float in [-1.6, 1.6]:
			props.rod(t + Vector3(sx * 1.3, 0.0, sz * 1.3), t + Vector3(sx * 0.9, 8.0, sz * 0.9), 0.14, 6, Color(0.42, 0.34, 0.26))
	props.mat = Geo.MAT_RUST
	props.cyl(Transform3D(Basis.IDENTITY, t + Vector3(0.0, 8.0, 0.0)), 2.6, 2.6, 4.0, 16, Color(0.55, 0.52, 0.48))
	props.cyl(Transform3D(Basis.IDENTITY, t + Vector3(0.0, 12.0, 0.0)), 2.8, 0.2, 1.5, 16, Color(0.45, 0.4, 0.36))
	_claim(p, Vector2(t.x, t.z), Vector2(8.0, 8.0))
	# the windmill pump: a lattice tower, a tail vane, and blades that turn (a spinner)
	var w := Vector3(26.0, 0.0, -55.0)
	props.mat = Geo.MAT_RUST
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			props.rod(w + Vector3(sx * 1.6, 0.0, sz * 1.6), w + Vector3(sx * 0.25, 10.0, sz * 0.25), 0.05, 4, Color(0.5, 0.48, 0.45))
	for h: float in [2.5, 5.0, 7.5]:
		var r := lerpf(1.6, 0.25, h / 10.0)
		for i in 4:
			var a := Vector3(r if i < 2 else -r, h, r if i % 3 == 0 else -r)
			var c := Vector3(-a.z, h, a.x)
			props.rod(w + a, w + c, 0.025, 3, Color(0.5, 0.48, 0.45))
	props.quad(w + Vector3(0.0, 10.2, 0.6), w + Vector3(0.0, 10.2, 2.6), w + Vector3(0.0, 11.0, 2.6), w + Vector3(0.0, 10.6, 0.6), Color(0.6, 0.55, 0.5))
	var blades := Geo.Buf.new()
	blades.mat = Geo.MAT_RUST
	for i in 16:
		var a := TAU * float(i) / 16.0
		blades.quad(Vector3(cos(a) * 0.3, sin(a) * 0.3, 0.0), Vector3(cos(a) * 1.7, sin(a) * 1.7, 0.0), Vector3(cos(a + 0.2) * 1.7, sin(a + 0.2) * 1.7, 0.1), Vector3(cos(a + 0.2) * 0.3, sin(a + 0.2) * 0.3, 0.05), Color(0.6, 0.57, 0.52))
	var spinner := Node3D.new()
	spinner.name = "WindmillBlades"
	(p["root"] as Node3D).add_child(spinner)
	spinner.position = w + Vector3(0.0, 10.4, -0.4)
	spinner.rotation = Vector3(0.0, 0.4, 0.0)
	Geo.add_mesh(spinner, "Blades", blades, (p["kit"] as Dictionary)["prop"], true)
	(p["spinners"] as Array[Node3D]).append(spinner)
	_claim(p, Vector2(w.x, w.z), Vector2(6.0, 6.0))
	props.mat = Geo.MAT_PAINT


static func _wreck(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var rng: RandomNumberGenerator = p["rng"]
	# a rusted old sedan sunk in the dirt, a mailbox on a post, a cow skull on a fence post
	var car := Geo.Buf.new()
	Vehicles.build("classic", {"all": car}, Color(0.45, 0.25, 0.15), {"rusty": true}, rng)
	var xf := Transform3D(Basis(Vector3.UP, 1.1) * Basis(Vector3.FORWARD, 0.08), Vector3(-17.0, -0.25, -44.0))
	for i in car.verts.size():
		car.verts[i] = xf * car.verts[i]
		car.normals[i] = xf.basis * car.normals[i]
	props.verts.append_array(car.verts)
	props.normals.append_array(car.normals)
	props.colors.append_array(car.colors)
	props.uvs.append_array(car.uvs)
	_claim(p, Vector2(-17.0, -44.0), Vector2(8.0, 8.0))
	Geo.fence(props, 8.0, -4.0, -76.0, rng)
	props.mat = Geo.MAT_PAINT
	var skull := Vector3(8.0, 1.3, -28.0)
	props.blob(skull, Vector3(0.12, 0.1, 0.18), 7, 4, Color(0.92, 0.9, 0.84), Color(0.8, 0.78, 0.72), 0.15, rng)
	for sx: float in [-1.0, 1.0]:
		props.rod(skull + Vector3(sx * 0.1, 0.06, 0.05), skull + Vector3(sx * 0.42, 0.22, 0.1), 0.025, 4, Color(0.9, 0.88, 0.8))
	props.mat = Geo.MAT_WOOD
	props.rod(Vector3(-6.5, 0.0, -60.0), Vector3(-6.5, 1.1, -60.0), 0.05, 5, Color(0.45, 0.38, 0.3))
	props.mat = Geo.MAT_RUST
	props.block(Vector3(-6.5, 1.25, -60.0), Vector3(0.25, 0.25, 0.5), Color(0.3, 0.32, 0.36))
	props.mat = Geo.MAT_PAINT


static func _services(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	Geo.sign_board(props, Vector3(7.5, 3.2, -30.0), Vector2(3.6, 1.6), 0.0, Color(0.08, 0.42, 0.22), Color(0.95, 0.95, 0.95), 2)
	_words(p, "NEXT SERVICES\n42 MI", Vector3(7.5, 3.2, -29.96), 0.0, 0.42, Color(0.97, 0.97, 0.97))
	Geo.sign_board(props, Vector3(6.4, 2.0, -58.0), Vector2(0.8, 1.05), 0.0, Color(0.95, 0.95, 0.93), Color(0.1, 0.1, 0.1))
	_words(p, "SPEED\nLIMIT\n55", Vector3(6.4, 2.0, -57.96), 0.0, 0.17, Color(0.06, 0.06, 0.06))
	Geo.sign_board(props, Vector3(-6.6, 2.3, -45.0), Vector2(0.75, 0.75), PI, Color(0.95, 0.95, 0.93), Color(0.1, 0.1, 0.1))
	_words(p, "ROUTE\n22", Vector3(-6.6, 2.3, -45.04), PI, 0.2, Color(0.08, 0.08, 0.08))
	_claim(p, Vector2(7.5, -30.0), Vector2(5.0, 2.0))
	_claim(p, Vector2(6.4, -58.0), Vector2(2.0, 2.0))
	_claim(p, Vector2(-6.6, -45.0), Vector2(2.0, 2.0))
	_mile_marker(p, Vector3(-6.4, 0.0, -12.0))


static func _guardrails(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	# a long bend: guardrails on both shoulders, chevrons on the outside, a curve sign
	for side: float in [-1.0, 1.0]:
		Geo.guardrail(props, side * 5.7, -2.0, -78.0, side)
	for i in 4:
		var z := -20.0 - float(i) * 14.0
		Geo.sign_board(props, Vector3(6.6, 1.4, z), Vector2(0.6, 0.75), 0.0, Color(0.95, 0.8, 0.1), Color(0.1, 0.1, 0.1))
		_words(p, "<", Vector3(6.6, 1.4, z + 0.04), 0.0, 0.5, Color(0.06, 0.06, 0.06))
	_claim(p, Vector2(6.6, -40.0), Vector2(2.0, 80.0))
	_claim(p, Vector2(-6.0, -40.0), Vector2(1.5, 80.0))


static func _culverts(p: Dictionary) -> void:
	var props: Geo.Buf = p["props"]
	var rng: RandomNumberGenerator = p["rng"]
	# two corrugated pipes under the road, their mouths in a shallow gully each side
	props.mat = Geo.MAT_RUST
	for z: float in [-25.0, -60.0]:
		for side: float in [-1.0, 1.0]:
			var turn := Basis(Vector3.FORWARD, -PI * 0.5 * side)
			props.cyl(Transform3D(turn, Vector3(side * 5.4, 0.3, z)), 0.55, 0.55, 1.2, 12, Color(0.55, 0.53, 0.5))
			props.cyl(Transform3D(turn, Vector3(side * 5.5, 0.3, z)), 0.42, 0.42, 1.2, 12, Color(0.05, 0.05, 0.05))
		props.mat = Geo.MAT_SAND
		for side: float in [-1.0, 1.0]:
			props.quad(Vector3(side * 6.0, 0.02, z - 2.0), Vector3(side * 40.0, 0.02, z - 3.0 + rng.randf() * 4.0), Vector3(side * 40.0, 0.02, z + 3.0), Vector3(side * 6.0, 0.02, z + 2.0), Color(0.78, 0.58, 0.42))
		props.mat = Geo.MAT_RUST
	props.mat = Geo.MAT_PAINT
	_claim(p, Vector2(0.0, -25.0), Vector2(14.0, 3.0))
	_claim(p, Vector2(0.0, -60.0), Vector2(14.0, 3.0))


static func _buttes(p: Dictionary) -> void:
	Geo.butte(p["rock"], Vector3(75.0, 0.0, -45.0), Vector3(36.0, 34.0, 28.0), 7.0, 26, 0.3)
	Geo.butte(p["rock"], Vector3(-110.0, 0.0, -30.0), Vector3(70.0, 28.0, 40.0), 19.0, 28, -0.2)
	_claim(p, Vector2(75.0, -45.0), Vector2(50.0, 40.0))
	_claim(p, Vector2(-110.0, -30.0), Vector2(90.0, 60.0))
	_boulders(p, 12)


static func _varnish_cliff(p: Dictionary) -> void:
	Geo.wall(p["rock"], -2.0, -78.0, -13.0, -1.0, 22.0, 40.0, 2.5, 83.0, 1.0, 0.1, 0.25)
	_claim(p, Vector2(-32.0, -40.0), Vector2(40.0, 80.0))
	_boulders(p, 10)
