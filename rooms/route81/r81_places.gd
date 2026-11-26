extends RefCounted
## Route 81's roadside places: what people built beside the highway. Farms and their fences on
## the "field" land, and on the "lawn" land small towns, gas stations, a truck stop and an old
## closed-down station (r81_land.gd edge profiles; both are flat out to Land.FLAT_REACH, and
## everything here stands on Land.flat_height()).
##
## Used by r81_trip.gd: a stretch of field or lawn is one "feature" (r81_trip.gd feature_at(),
## the names in FEATURES) over up to seven places in a row, and build(feature, i, side) is the
## mesh for the i-th of them (0..6) on one side of the road, or null where that place has
## nothing. Meshes are built once and shared (_cache), for the Route 22 prop material
## (kit["prop"]: MAT_ numbers in UV.x; MAT_LIGHT glows at night), like r81_pieces.gd's.
##
## Positions: `u` = metres out from the paved edge (the same u as r81_land.gd), z = 0 (the
## place's start) to -Land.LENGTH. _at(side, u, y, z) turns that into the place's own metres on
## either side. A building's front is its +Z face before turning; _face(side) turns it to the
## road. Nothing longer than about 30 m along the road is one box, so the bend can curve a
## street (r22_common.gdshaderinc).
## Art: all original. Brands are made-up colour emblems without words; no real places.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Land := preload("res://rooms/route81/r81_land.gd")

## The features (r81_trip.gd feature_at picks one per stretch):
##   farm           a family farm: house, red barn, silo, round bales, a tractor
##   amish          an Amish farm: white house and barn, twin silos, a windmill pump, washing
##                  on the line, corn shocks, a horse and buggy on the lane; no wires, no lamps
##   town_cozy      a small town: a main street of brick shop fronts, a white church, houses
##                  with porches, a water tower
##   town_historic  an old county seat: a stone courthouse with a clock cupola, a stone church,
##                  a mill, and a red covered bridge over the creek
## (gas, truck_stop and old_station stand on "lot" land, which is a lawn without the street
## trees; the towns on "lawn".)
##   gas            a gas station at an exit: canopy, pumps, store and a tall pole sign
##   truck_stop     a truck stop: high canopies, a diner, parked trailers, light masts
##   old_station    a closed-down filling station from the 1930s, rusting
const FEATURES: PackedStringArray = ["farm", "amish", "town_cozy", "town_historic", "gas", "truck_stop", "old_station"]

const ASPHALT := Color(0.13, 0.13, 0.14)
const GRAVEL := Color(0.42, 0.4, 0.36)
const WHITE := Color(0.82, 0.82, 0.78)
const BARN_RED := Color(0.42, 0.09, 0.06)
const BRICK := Color(0.4, 0.17, 0.12)
const STONE := Color(0.46, 0.44, 0.4)
const ROOF_DARK := Color(0.16, 0.16, 0.18)
const ROOF_TIN := Color(0.45, 0.47, 0.48)
const LAMP_WARM := Color(1.0, 0.78, 0.45)

static var _cache: Dictionary = {}


## The mesh for place `i` (0..6) of a feature on one side (+1 right, -1 left), or null.
static func build(feature: String, i: int, side: int) -> ArrayMesh:
	var key := "%s|%d|%d" % [feature, i, side]
	if _cache.has(key):
		return _cache[key]
	var b := Geo.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match feature:
		"farm": _farm(b, i, side, rng)
		"amish": _amish(b, i, side, rng)
		"town_cozy": _town_cozy(b, i, side, rng)
		"town_historic": _town_historic(b, i, side, rng)
		"gas": _gas(b, i, side)
		"truck_stop": _truck_stop(b, i, side, rng)
		"old_station": _old_station(b, i, side, rng)
	var mesh: ArrayMesh = null if b.is_empty() else b.to_mesh()
	_cache[key] = mesh
	return mesh


# ── Where things go ──────────────────────────────────────────
## A point u metres out from the paved edge on `side`, y above the ground there (field or lawn,
## `land`), z along the place.
static func _at(side: int, land: String, u: float, y: float, z: float) -> Vector3:
	return Vector3((Land.ROAD_R + u) if side > 0 else (Land.OPP_L - u), Land.flat_height(land, u) + y, z)


## The turn (radians) that makes a building's front face the road from `side`, plus `extra`.
static func _face(side: int, extra: float = 0.0) -> float:
	return -float(side) * PI * 0.5 + extra


## A strip of paving (a street, a lane, a lot) along the road at `u`, `wide` across, from z0 to
## z1, laid just above the ground in pieces short enough for the bend.
static func _paving(b: Geo.Buf, side: int, land: String, u: float, wide: float, z0: float, z1: float, col: Color) -> void:
	b.mat = Geo.MAT_ROCK
	var z := z0
	while z > z1 + 0.01:
		var zn := maxf(z - 8.0, z1)
		b.block(_at(side, land, u, 0.04, (z + zn) * 0.5), Vector3(wide, 0.08, z - zn), col)
		z = zn
	b.mat = Geo.MAT_PAINT


## A paved lane from one spot to another (a ramp, a farm lane), in short straight pieces.
static func _lane(b: Geo.Buf, side: int, land: String, from: Vector2, to: Vector2, wide: float, col: Color) -> void:
	b.mat = Geo.MAT_ROCK
	var pieces := maxi(2, ceili(from.distance_to(to) / 8.0))
	for n in pieces:
		var a := from.lerp(to, float(n) / float(pieces))
		var c := from.lerp(to, float(n + 1) / float(pieces))
		var mid := _at(side, land, (a.x + c.x) * 0.5, 0.05, (a.y + c.y) * 0.5)
		var pa := _at(side, land, a.x, 0.05, a.y)
		var pc := _at(side, land, c.x, 0.05, c.y)
		var along := pc - pa
		along.y = 0.0
		var turn := atan2(along.x, along.z)
		b.box(Transform3D(Basis(Vector3.UP, turn), mid), Vector3(wide, 0.08, along.length() + 0.4), col)
	b.mat = Geo.MAT_PAINT


# ── Parts ────────────────────────────────────────────────────
## A barn with a gambrel (two-slope) roof, its ridge along its long side (X before turning),
## a big door with white cross-braces on the front, and a hay door in the gable.
static func _barn(b: Geo.Buf, at: Vector3, size: Vector3, turn: float, wall: Color, roof: Color, trim: Color) -> void:
	var face := Basis(Vector3.UP, turn)
	var p := func(x: float, y: float, z: float) -> Vector3: return at + face * Vector3(x, y, z)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var eave := size.y
	var knee := eave + size.z * 0.28
	var ridge := eave + size.z * 0.44
	b.mat = Geo.MAT_WOOD
	b.box(Transform3D(face, at + Vector3(0.0, eave * 0.5, 0.0)), size, wall)
	for s: float in [-1.0, 1.0]:
		# the steep lower slope and the flat upper one
		b.quad(p.call(-hx - 0.4, eave - 0.2, s * (hz + 0.4)), p.call(hx + 0.4, eave - 0.2, s * (hz + 0.4)), p.call(hx + 0.4, knee, s * hz * 0.55), p.call(-hx - 0.4, knee, s * hz * 0.55), roof)
		b.quad(p.call(-hx - 0.4, knee, s * hz * 0.55), p.call(hx + 0.4, knee, s * hz * 0.55), p.call(hx + 0.4, ridge, 0.0), p.call(-hx - 0.4, ridge, 0.0), roof)
	for e: float in [-1.0, 1.0]:
		# the gable ends, up to the roof line
		b.quad(p.call(e * hx, eave, -hz), p.call(e * hx, eave, hz), p.call(e * hx, knee, hz * 0.55), p.call(e * hx, knee, -hz * 0.55), wall)
		b.tri(p.call(e * hx, knee, -hz * 0.55), p.call(e * hx, knee, hz * 0.55), p.call(e * hx, ridge, 0.0), wall)
	# the big sliding door and its braces, on the front
	b.mat = Geo.MAT_PAINT
	var door_w := minf(size.x * 0.3, 4.2)
	b.box(Transform3D(face, p.call(0.0, eave * 0.36, hz + 0.05)), Vector3(door_w, eave * 0.72, 0.08), wall.darkened(0.25))
	for d: float in [-1.0, 1.0]:
		b.box(Transform3D(face * Basis(Vector3.BACK, d * atan2(eave * 0.72, door_w)), p.call(0.0, eave * 0.36, hz + 0.1)), Vector3(sqrt(door_w * door_w + eave * eave * 0.52), 0.16, 0.05), trim)
	b.box(Transform3D(face, p.call(0.0, eave * 0.73, hz + 0.1)), Vector3(door_w + 0.3, 0.18, 0.05), trim)


## A silo: a tall drum with a domed cap.
static func _silo(b: Geo.Buf, at: Vector3, radius: float, height: float, col: Color, cap: Color) -> void:
	b.mat = Geo.MAT_PANEL
	b.cyl(Transform3D(Basis.IDENTITY, at), radius, radius, height, 10, col)
	b.mat = Geo.MAT_CHROME
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, height, 0.0)), radius, radius * 0.55, radius * 0.5, 10, cap)
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, height + radius * 0.5, 0.0)), radius * 0.55, 0.05, radius * 0.3, 10, cap)
	b.mat = Geo.MAT_PAINT


## A church: a nave with a pitched roof, and a square tower with a spire at its road end.
static func _church(b: Geo.Buf, at: Vector3, turn: float, wall: Color, roof: Color, spire: Color, lit: bool) -> void:
	var face := Basis(Vector3.UP, turn)
	# (the nave's ridge runs along its length, front to back, which Geo.building's pitched roof
	# does not do: walls and roof are built here)
	var p := func(x: float, y: float, z: float) -> Vector3: return at + face * Vector3(x, y, z)
	b.mat = Geo.MAT_PAINT
	b.box(Transform3D(face, at + Vector3(0.0, 3.25, 0.0)), Vector3(9.0, 6.5, 18.0), wall)
	for e: float in [-1.0, 1.0]:
		b.tri(p.call(-4.5, 6.5, e * 9.0), p.call(4.5, 6.5, e * 9.0), p.call(0.0, 10.5, e * 9.0), wall)
	b.mat = Geo.MAT_WOOD
	for s: float in [-1.0, 1.0]:
		b.quad(p.call(s * 4.9, 6.3, 9.3), p.call(s * 4.9, 6.3, -9.3), p.call(0.0, 10.5, -9.3), p.call(0.0, 10.5, 9.3), roof)
	var tower := at + face * Vector3(0.0, 0.0, 10.5)
	b.mat = Geo.MAT_PAINT
	b.box(Transform3D(face, tower + Vector3(0.0, 6.5, 0.0)), Vector3(4.2, 13.0, 4.2), wall)
	b.box(Transform3D(face, tower + Vector3(0.0, 13.3, 0.0)), Vector3(4.8, 0.6, 4.8), wall.lightened(0.1))
	b.mat = Geo.MAT_WOOD
	b.cyl(Transform3D(face * Basis(Vector3.UP, PI * 0.25), tower + Vector3(0.0, 13.6, 0.0)), 3.1, 0.05, 9.0, 4, spire)
	# the door, and tall windows down both sides
	b.mat = Geo.MAT_WOOD
	b.box(Transform3D(face, tower + face * Vector3(0.0, 1.4, 2.15)), Vector3(1.6, 2.8, 0.1), Color(0.3, 0.12, 0.08))
	b.mat = Geo.MAT_LIGHT if lit else Geo.MAT_GLASS
	for s: float in [-1.0, 1.0]:
		for n in 4:
			b.box(Transform3D(face, at + face * Vector3(s * 4.55, 3.3, -6.0 + 4.0 * float(n))), Vector3(0.1, 2.8, 1.0), LAMP_WARM if lit else Color(0.25, 0.3, 0.4))
	b.mat = Geo.MAT_PAINT


## A water tower on four legs: a drum tank with a cone top and a coloured band (no words).
static func _water_tower(b: Geo.Buf, at: Vector3, band: Color) -> void:
	var steel := Color(0.62, 0.68, 0.7)
	b.mat = Geo.MAT_PAINT
	for leg: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		b.rod(at + Vector3(leg.x * 4.5, 0.0, leg.y * 4.5), at + Vector3(leg.x * 3.0, 22.0, leg.y * 3.0), 0.3, 5, steel)
	b.rod(at, at + Vector3(0.0, 22.0, 0.0), 0.6, 6, steel)
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 19.5, 0.0)), 2.5, 5.2, 2.5, 12, steel)
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 22.0, 0.0)), 5.2, 5.2, 5.5, 12, steel)
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 24.0, 0.0)), 5.25, 5.25, 1.4, 12, band)
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 27.5, 0.0)), 5.2, 0.4, 2.2, 12, steel.darkened(0.15))


## A row of two-storey shop fronts along the road: each its own width, colour and awning, lit
## shop windows below and a few lit rooms above. from_z > to_z; the fronts face the road.
static func _shop_row(b: Geo.Buf, side: int, u: float, from_z: float, to_z: float, rng: RandomNumberGenerator, stone: bool) -> void:
	var walls: Array[Color] = [BRICK, BRICK.lightened(0.12), Color(0.5, 0.42, 0.3), Color(0.3, 0.3, 0.32), Color(0.45, 0.2, 0.16)]
	if stone:
		walls = [STONE, STONE.darkened(0.15), BRICK.darkened(0.1), Color(0.5, 0.47, 0.4)]
	var awnings: Array[Color] = [Color(0.1, 0.3, 0.2), Color(0.45, 0.08, 0.08), Color(0.1, 0.16, 0.4), Color(0.55, 0.45, 0.2)]
	var z := from_z
	while z > to_z + 4.0:
		var wide := minf(rng.randf_range(6.0, 10.0), z - to_z)
		var high := rng.randf_range(7.0, 9.5)
		var deep := 12.0
		var mid := _at(side, "lawn", u + deep * 0.5, 0.0, z - wide * 0.5)
		var turn := _face(side)
		var face := Basis(Vector3.UP, turn)
		var wall := walls[rng.randi() % walls.size()]
		b.mat = Geo.MAT_PAINT
		b.box(Transform3D(face, mid + Vector3(0.0, high * 0.5, 0.0)), Vector3(wide - 0.2, high, deep), wall)
		# a cornice along the top, the shop window, the awning over it, the rooms upstairs
		b.box(Transform3D(face, mid + face * Vector3(0.0, high + 0.2, deep * 0.5)), Vector3(wide - 0.1, 0.5, 0.4), wall.lightened(0.2))
		b.mat = Geo.MAT_LIGHT
		b.box(Transform3D(face, mid + face * Vector3(0.0, 1.7, deep * 0.5 + 0.03)), Vector3(wide * 0.7, 2.2, 0.06), LAMP_WARM)
		for n in 2:
			if rng.randf() < 0.6:
				b.box(Transform3D(face, mid + face * Vector3((float(n) - 0.5) * wide * 0.45, high * 0.68, deep * 0.5 + 0.03)), Vector3(1.0, 1.6, 0.06), LAMP_WARM * 0.8)
		b.mat = Geo.MAT_CLOTH
		b.box(Transform3D(face * Basis(Vector3.RIGHT, 0.35), mid + face * Vector3(0.0, 3.1, deep * 0.5 + 0.7)), Vector3(wide * 0.8, 0.08, 1.6), awnings[rng.randi() % awnings.size()])
		b.mat = Geo.MAT_PAINT
		z -= wide


## A house with a pitched roof and a front porch, lit rooms at night.
static func _porch_house(b: Geo.Buf, at: Vector3, turn: float, wall: Color, roof: Color, rng: RandomNumberGenerator, lit: bool = true) -> void:
	var size := Vector3(rng.randf_range(8.0, 11.0), rng.randf_range(5.5, 7.0), rng.randf_range(7.0, 9.0))
	Geo.building(b, at, size, turn, wall, roof, true, 2, lit)
	var face := Basis(Vector3.UP, turn)
	b.mat = Geo.MAT_WOOD
	b.box(Transform3D(face, at + face * Vector3(0.0, 0.25, size.z * 0.5 + 1.1)), Vector3(size.x * 0.8, 0.5, 2.2), Color(0.5, 0.5, 0.48))
	b.box(Transform3D(face * Basis(Vector3.RIGHT, 0.2), at + face * Vector3(0.0, 3.0, size.z * 0.5 + 1.1)), Vector3(size.x * 0.85, 0.1, 2.5), roof)
	for s: float in [-1.0, 1.0]:
		b.box(Transform3D(face, at + face * Vector3(s * size.x * 0.38, 1.6, size.z * 0.5 + 2.05)), Vector3(0.14, 2.7, 0.14), WHITE)
	b.mat = Geo.MAT_PAINT


## A tall sign on a pole, the kind that shows over the trees from the highway: a coloured panel
## with a plain emblem (a disc or a bar, no words), lit from inside, and a price board under it.
static func _pole_sign(b: Geo.Buf, at: Vector3, turn: float, height: float, field: Color, emblem: Color, round_emblem: bool) -> void:
	var face := Basis(Vector3.UP, turn)
	b.mat = Geo.MAT_PAINT
	b.cyl(Transform3D(Basis.IDENTITY, at), 0.35, 0.28, height, 8, Color(0.5, 0.5, 0.52))
	b.mat = Geo.MAT_LIGHT
	var mid := at + Vector3(0.0, height + 1.9, 0.0)
	b.box(Transform3D(face, mid), Vector3(6.4, 3.8, 0.5), field)
	for s: float in [-1.0, 1.0]:
		if round_emblem:
			b.cyl(Transform3D(face * Basis(Vector3.RIGHT, s * PI * 0.5), mid + face * Vector3(0.0, 0.0, s * 0.2)), 1.4, 1.4, 0.08, 16, emblem)
		else:
			b.box(Transform3D(face * Basis(Vector3.BACK, 0.35), mid + face * Vector3(0.0, 0.0, s * 0.28)), Vector3(5.0, 0.9, 0.04), emblem)
	b.box(Transform3D(face, at + Vector3(0.0, height - 2.2, 0.0)), Vector3(4.2, 2.2, 0.4), Color(0.9, 0.9, 0.85))
	b.mat = Geo.MAT_PAINT


## A pump island canopy: posts, a flat roof with a colour band round its edge, light panels
## under it, and `pumps` pumps in a row along the road. at = the middle of its floor.
static func _canopy(b: Geo.Buf, at: Vector3, size: Vector3, band: Color, pumps: int, rusty: bool) -> void:
	b.mat = Geo.MAT_RUST if rusty else Geo.MAT_PAINT
	var post := Color(0.4, 0.3, 0.24) if rusty else Color(0.8, 0.8, 0.78)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.block(at + Vector3(sx * size.x * 0.32, size.y * 0.5, sz * size.z * 0.36), Vector3(0.4, size.y, 0.4), post)
	b.block(at + Vector3(0.0, size.y + 0.45, 0.0), Vector3(size.x, 0.9, size.z), post if rusty else Color(0.85, 0.85, 0.82))
	b.block(at + Vector3(0.0, size.y + 0.45, 0.0), Vector3(size.x + 0.1, 0.4, size.z + 0.1), band)
	if not rusty:
		b.mat = Geo.MAT_LIGHT
		b.block(at + Vector3(0.0, size.y - 0.03, 0.0), Vector3(size.x * 0.7, 0.06, size.z * 0.7), Color(1.0, 0.97, 0.9))
	for n in pumps:
		var z := (float(n) - float(pumps - 1) * 0.5) * (size.z * 0.7 / maxf(float(pumps - 1), 1.0))
		b.mat = Geo.MAT_ROCK
		b.block(at + Vector3(0.0, 0.1, z), Vector3(1.2, 0.2, 2.6), Color(0.6, 0.59, 0.56))
		b.mat = Geo.MAT_RUST if rusty else Geo.MAT_PAINT
		b.block(at + Vector3(0.0, 1.0, z), Vector3(0.7, 1.7, 1.0), Color(0.45, 0.25, 0.18) if rusty else band.lerp(Color.WHITE, 0.6))
		if not rusty:
			b.mat = Geo.MAT_LIGHT
			b.block(at + Vector3(0.0, 1.55, z), Vector3(0.74, 0.35, 0.8), Color(0.9, 0.95, 1.0))
	b.mat = Geo.MAT_PAINT


## A lot light: a mast with a lamp head (glows at night).
static func _lot_light(b: Geo.Buf, at: Vector3, height: float) -> void:
	b.mat = Geo.MAT_PAINT
	b.cyl(Transform3D(Basis.IDENTITY, at), 0.12, 0.08, height, 6, Color(0.45, 0.46, 0.48))
	b.mat = Geo.MAT_LIGHT
	b.block(at + Vector3(0.0, height, 0.0), Vector3(1.1, 0.2, 0.5), Color(1.0, 0.95, 0.85))
	b.mat = Geo.MAT_PAINT


## A wire fence along the whole place at the field's edge (every field place has one), or the
## Amish farms' white board fence.
static func _field_fence(b: Geo.Buf, side: int, rng: RandomNumberGenerator, boards: bool) -> void:
	var x := _at(side, "field", 13.0, 0.0, 0.0).x
	var y := Land.flat_height("field", 13.0)
	if not boards:
		var fence := Geo.Buf.new()
		Geo.fence(fence, x, 0.0, -Land.LENGTH, rng)
		# (Geo.fence stands on y = 0: lift it onto the field)
		for n in fence.verts.size():
			fence.verts[n].y += y
		b.verts.append_array(fence.verts)
		b.normals.append_array(fence.normals)
		b.colors.append_array(fence.colors)
		b.uvs.append_array(fence.uvs)
		return
	b.mat = Geo.MAT_PAINT
	var z := 0.0
	while z > -Land.LENGTH + 0.01:
		b.block(Vector3(x, y + 0.6, z), Vector3(0.12, 1.3, 0.12), WHITE)
		for rail: float in [0.45, 0.8, 1.15]:
			b.block(Vector3(x, y + rail, z - 2.0), Vector3(0.05, 0.12, 4.0), WHITE)
		z -= 4.0


# ── Farms ────────────────────────────────────────────────────
static func _farm(b: Geo.Buf, i: int, side: int, rng: RandomNumberGenerator) -> void:
	_field_fence(b, side, rng, false)
	if i == 1 or i == 4:
		# the farmstead, back from the road at the end of its lane
		var u := 78.0 + 20.0 * float(i % 2)
		_lane(b, side, "field", Vector2(13.0, -40.0), Vector2(u - 12.0, -40.0), 3.2, GRAVEL)
		Geo.building(b, _at(side, "field", u, -0.3, -28.0), Vector3(11.0, 6.5, 8.0), _face(side), WHITE, ROOF_DARK, true, 3, true)
		_barn(b, _at(side, "field", u + 16.0, -0.3, -54.0), Vector3(18.0, 6.5, 11.0), _face(side, 0.2), BARN_RED, ROOF_TIN, WHITE)
		_silo(b, _at(side, "field", u + 30.0, -0.3, -47.0), 2.6, 15.0, Color(0.55, 0.57, 0.6), Color(0.7, 0.72, 0.74))
		# a machine shed, a tractor in front of it
		Geo.building(b, _at(side, "field", u + 2.0, -0.3, -70.0), Vector3(12.0, 4.2, 7.0), _face(side), ROOF_TIN, ROOF_TIN.darkened(0.2), true, 0, false)
		var tractor := _at(side, "field", u - 8.0, 0.0, -66.0)
		b.mat = Geo.MAT_CAR
		b.block(tractor + Vector3(0.0, 1.2, 0.0), Vector3(1.3, 0.9, 3.0), Color(0.1, 0.35, 0.12))
		b.block(tractor + Vector3(0.0, 2.0, -0.7), Vector3(1.2, 1.3, 1.2), Color(0.1, 0.35, 0.12))
		b.mat = Geo.MAT_RUBBER
		for wx: float in [-0.85, 0.85]:
			b.cyl(Transform3D(Basis(Vector3.BACK, PI * 0.5), tractor + Vector3(wx + 0.2, 0.85, -0.8)), 0.85, 0.85, 0.4, 10, Color(0.06, 0.06, 0.06))
			b.cyl(Transform3D(Basis(Vector3.BACK, PI * 0.5), tractor + Vector3(wx + 0.15, 0.5, 1.1)), 0.5, 0.5, 0.3, 8, Color(0.06, 0.06, 0.06))
		b.mat = Geo.MAT_PAINT
	elif i == 2 or i == 5:
		# round hay bales left in the mown field
		b.mat = Geo.MAT_CLOTH
		for n in 9:
			var at := _at(side, "field", rng.randf_range(24.0, 120.0), 0.75, rng.randf_range(-76.0, -4.0))
			var along := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, rng.randf() * PI)
			b.rod(at - along * 0.75, at + along * 0.75, 0.75, 9, Color(0.55, 0.47, 0.24), Color(0.48, 0.4, 0.2))
		b.mat = Geo.MAT_PAINT


static func _amish(b: Geo.Buf, i: int, side: int, rng: RandomNumberGenerator) -> void:
	_field_fence(b, side, rng, true)
	if i == 1 or i == 4:
		var u := 70.0
		_lane(b, side, "field", Vector2(13.0, -40.0), Vector2(u - 12.0, -40.0), 3.0, GRAVEL)
		# the house: big, plain and white, with a second house built on for the grandparents
		Geo.building(b, _at(side, "field", u, -0.3, -26.0), Vector3(13.0, 7.5, 9.0), _face(side), WHITE, ROOF_DARK, true, 3, false)
		Geo.building(b, _at(side, "field", u + 3.0, -0.3, -14.0), Vector3(8.0, 5.5, 7.0), _face(side), WHITE, ROOF_DARK, true, 2, false)
		# a lamp-lit window or two: no electric light here
		b.mat = Geo.MAT_LIGHT
		b.box(Transform3D(Basis(Vector3.UP, _face(side)), _at(side, "field", u - 4.6, 1.3, -24.0)), Vector3(0.7, 0.7, 0.08), Color(0.9, 0.55, 0.2) * 0.6)
		b.mat = Geo.MAT_PAINT
		# the white bank barn and its two silos
		_barn(b, _at(side, "field", u + 24.0, -0.3, -56.0), Vector3(24.0, 8.0, 13.0), _face(side, -0.15), WHITE, ROOF_DARK, WHITE.darkened(0.3))
		_silo(b, _at(side, "field", u + 43.0, -0.3, -50.0), 2.8, 17.0, Color(0.6, 0.6, 0.58), Color(0.72, 0.73, 0.74))
		_silo(b, _at(side, "field", u + 44.0, -0.3, -58.0), 2.4, 14.0, Color(0.56, 0.56, 0.54), Color(0.72, 0.73, 0.74))
		# the windmill pump
		var wm := _at(side, "field", u - 14.0, 0.0, -12.0)
		b.mat = Geo.MAT_RUST
		for leg: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
			b.rod(wm + Vector3(leg.x * 1.4, 0.0, leg.y * 1.4), wm + Vector3(leg.x * 0.2, 10.0, leg.y * 0.2), 0.06, 4, Color(0.5, 0.5, 0.5))
		b.mat = Geo.MAT_CHROME
		b.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), wm + Vector3(0.0, 10.3, -0.5)), 1.5, 1.5, 0.06, 14, Color(0.62, 0.63, 0.64))
		b.block(wm + Vector3(0.0, 10.3, 1.4), Vector3(0.05, 0.9, 1.3), Color(0.62, 0.63, 0.64))
		# washing on the line: dark plain colours
		var l0 := _at(side, "field", u - 6.0, 2.0, -34.0)
		var l1 := _at(side, "field", u - 6.0, 2.0, -46.0)
		b.mat = Geo.MAT_WOOD
		for post: Vector3 in [l0, l1]:
			b.rod(post - Vector3(0.0, 2.0, 0.0), post + Vector3(0.0, 0.2, 0.0), 0.07, 5, Color(0.4, 0.33, 0.26))
		b.mat = Geo.MAT_CLOTH
		var cloths: Array[Color] = [Color(0.1, 0.14, 0.35), Color(0.25, 0.1, 0.3), Color(0.05, 0.05, 0.06), Color(0.1, 0.3, 0.22), Color(0.8, 0.8, 0.78)]
		for n in 8:
			b.block(l0.lerp(l1, (float(n) + 0.5) / 8.0) + Vector3(0.0, -0.55, 0.0), Vector3(0.04, 1.0, 1.0), cloths[n % cloths.size()])
		b.mat = Geo.MAT_PAINT
	elif i == 2 or i == 5:
		# corn shocks stood up in rows, and a buggy coming down the lane behind its horse
		b.mat = Geo.MAT_CLOTH
		for row in 4:
			for n in 9:
				b.cyl(Transform3D(Basis.IDENTITY, _at(side, "field", 26.0 + 9.0 * float(row), 0.0, -6.0 - 8.0 * float(n))), 0.75, 0.12, 1.9, 7, Color(0.5, 0.42, 0.2))
		_lane(b, side, "field", Vector2(17.0, -2.0), Vector2(17.0, -78.0), 2.6, GRAVEL)
		var bg := _at(side, "field", 17.0, 0.0, -44.0)
		b.mat = Geo.MAT_LEATHER
		b.block(bg + Vector3(0.0, 1.35, 0.0), Vector3(1.3, 1.25, 1.7), Color(0.04, 0.04, 0.05))
		b.block(bg + Vector3(0.0, 2.02, 0.0), Vector3(1.4, 0.1, 1.9), Color(0.03, 0.03, 0.04))
		b.mat = Geo.MAT_RUBBER
		for wx: float in [-0.75, 0.75]:
			for wz: float in [-0.65, 0.65]:
				b.cyl(Transform3D(Basis(Vector3.BACK, PI * 0.5), bg + Vector3(wx + 0.03, 0.6, wz)), 0.6, 0.6, 0.06, 12, Color(0.05, 0.05, 0.05))
		# the horse: a bay, in the shafts ahead of the buggy
		b.mat = Geo.MAT_LEATHER
		var bay := Color(0.26, 0.13, 0.07)
		var hz := -2.9
		b.block(bg + Vector3(0.0, 1.25, hz), Vector3(0.55, 0.7, 1.7), bay)
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.7), bg + Vector3(0.0, 1.85, hz - 0.95)), Vector3(0.3, 0.9, 0.4), bay)
		b.block(bg + Vector3(0.0, 2.2, hz - 1.4), Vector3(0.25, 0.3, 0.6), bay)
		for lx: float in [-0.18, 0.18]:
			for lz: float in [-0.65, 0.65]:
				b.block(bg + Vector3(lx, 0.45, hz + lz), Vector3(0.12, 0.95, 0.14), bay.darkened(0.3))
		b.mat = Geo.MAT_WOOD
		for sx: float in [-0.4, 0.4]:
			b.rod(bg + Vector3(sx, 1.0, -0.8), bg + Vector3(sx, 1.15, hz - 0.5), 0.03, 4, Color(0.1, 0.08, 0.06))
		b.mat = Geo.MAT_PAINT


# ── Towns ────────────────────────────────────────────────────
static func _town_cozy(b: Geo.Buf, i: int, side: int, rng: RandomNumberGenerator) -> void:
	var house_cols: Array[Color] = [WHITE, Color(0.7, 0.66, 0.5), Color(0.45, 0.52, 0.56), Color(0.62, 0.42, 0.36), Color(0.5, 0.58, 0.46)]
	# main street runs the whole town, a back street behind the first line of trees
	if i >= 1 and i <= 5:
		_paving(b, side, "lawn", 44.0, 7.0, 0.0, -Land.LENGTH, ASPHALT)
		_paving(b, side, "lawn", 100.0, 5.5, 0.0, -Land.LENGTH, ASPHALT)
	if i >= 2 and i <= 4:
		# shop fronts on the far side of main street, looking at the highway
		_shop_row(b, side, 50.0, -2.0, -78.0, rng, false)
		for n in 3:
			_lot_light(b, _at(side, "lawn", 39.0, 0.0, -14.0 - 26.0 * float(n)), 5.0)
	if i == 1 or i == 5:
		_church(b, _at(side, "lawn", 62.0, 0.0, -40.0), _face(side), WHITE, ROOF_DARK, ROOF_DARK, true)
	if i == 3:
		_water_tower(b, _at(side, "lawn", 172.0, 0.0, -40.0), Color(0.12, 0.3, 0.5))
	# houses with porches: on the back street, and at the town's two ends on main street too
	var us: Array[float] = [112.0, 124.0]
	if i == 0 or i == 6:
		us = [60.0, 112.0]
	for u in us:
		var z := -8.0
		while z > -74.0:
			if rng.randf() < 0.85:
				_porch_house(b, _at(side, "lawn", u + rng.randf_range(-2.0, 2.0), 0.0, z - 6.0), _face(side, rng.randf_range(-0.08, 0.08)),
					house_cols[rng.randi() % house_cols.size()], ROOF_DARK * rng.randf_range(0.8, 1.6), rng, rng.randf() < 0.7)
			z -= rng.randf_range(15.0, 20.0)


static func _town_historic(b: Geo.Buf, i: int, side: int, rng: RandomNumberGenerator) -> void:
	if i >= 1 and i <= 5:
		_paving(b, side, "lawn", 44.0, 6.5, 0.0, -Land.LENGTH, Color(0.2, 0.19, 0.18))
	match i:
		1:
			# the mill: tall, stone below and red boards above, its wheel on the creek side
			var at := _at(side, "lawn", 62.0, 0.0, -44.0)
			Geo.building(b, at, Vector3(14.0, 6.0, 10.0), _face(side), STONE, ROOF_DARK, false, 2, true)
			_barn(b, at + Vector3(0.0, 6.0, 0.0), Vector3(14.0, 5.0, 10.0), _face(side), BARN_RED.darkened(0.15), ROOF_DARK, WHITE)
			b.mat = Geo.MAT_WOOD
			b.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.0, 3.4, -5.6 - 0.6)), 3.4, 3.4, 1.2, 14, Color(0.25, 0.2, 0.15))
			b.mat = Geo.MAT_PAINT
		2, 4:
			_shop_row(b, side, 50.0, -2.0, -78.0, rng, true)
			for n in 3:
				# old iron lamp posts with a round globe
				var lp := _at(side, "lawn", 39.5, 0.0, -14.0 - 26.0 * float(n))
				b.mat = Geo.MAT_PAINT
				b.cyl(Transform3D(Basis.IDENTITY, lp), 0.09, 0.06, 3.6, 6, Color(0.06, 0.07, 0.06))
				b.mat = Geo.MAT_LIGHT
				b.blob(lp + Vector3(0.0, 3.8, 0.0), Vector3(0.3, 0.3, 0.3), 6, 4, LAMP_WARM, LAMP_WARM, 0.0, rng)
				b.mat = Geo.MAT_PAINT
		3:
			# the courthouse on its square: stone, a columned porch, a clock cupola on the roof
			var at := _at(side, "lawn", 70.0, 0.0, -40.0)
			var turn := _face(side)
			var face := Basis(Vector3.UP, turn)
			Geo.building(b, at, Vector3(26.0, 10.0, 18.0), turn, STONE.lightened(0.1), ROOF_DARK, false, 4, true)
			b.mat = Geo.MAT_ROCK
			b.box(Transform3D(face, at + face * Vector3(0.0, 0.5, 11.0)), Vector3(14.0, 1.0, 4.0), STONE.lightened(0.2))
			for n in 6:
				b.cyl(Transform3D(Basis.IDENTITY, at + face * Vector3(-6.0 + 2.4 * float(n), 1.0, 12.0)), 0.45, 0.4, 7.5, 8, WHITE)
			b.box(Transform3D(face, at + face * Vector3(0.0, 9.2, 11.0)), Vector3(14.6, 1.4, 4.4), STONE.lightened(0.2))
			b.mat = Geo.MAT_PAINT
			b.box(Transform3D(face, at + Vector3(0.0, 12.5, 0.0)), Vector3(6.0, 5.0, 6.0), WHITE)
			b.mat = Geo.MAT_LIGHT
			for dial in 4:
				var fb := face * Basis(Vector3.UP, PI * 0.5 * float(dial))
				b.cyl(Transform3D(fb * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.0, 13.0, 0.0) + fb * Vector3(0.0, 0.0, 3.02)), 1.5, 1.5, 0.06, 14, Color(0.95, 0.9, 0.75))
			b.mat = Geo.MAT_CHROME
			b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 15.0, 0.0)), 3.6, 0.3, 3.6, 10, Color(0.3, 0.42, 0.36))
			b.mat = Geo.MAT_PAINT
		5:
			# the covered bridge: main street crosses the creek through a long red shed
			var creek_z := -40.0
			b.mat = Geo.MAT_GLASS
			var u := 16.0
			while u < 200.0:
				b.block(_at(side, "lawn", u + 4.0, 0.03, creek_z + 3.0 * sin(u / 18.0)), Vector3(8.2, 0.06, 7.0), Color(0.1, 0.18, 0.22))
				u += 8.0
			b.mat = Geo.MAT_ROCK
			for end: float in [-1.0, 1.0]:
				b.block(_at(side, "lawn", 44.0, 0.6, creek_z + end * 7.5), Vector3(7.5, 1.4, 2.0), STONE)
			var mid := _at(side, "lawn", 44.0, 1.1, creek_z)
			b.mat = Geo.MAT_WOOD
			for sx: float in [-1.0, 1.0]:
				b.block(mid + Vector3(sx * 2.9, 2.0, 0.0), Vector3(0.25, 4.0, 17.0), BARN_RED)
			b.block(mid + Vector3(0.0, 0.1, 0.0), Vector3(5.8, 0.25, 17.0), Color(0.3, 0.24, 0.18))
			for sx: float in [-1.0, 1.0]:
				b.quad(mid + Vector3(sx * 3.4, 3.9, 8.9), mid + Vector3(sx * 3.4, 3.9, -8.9), mid + Vector3(0.0, 5.6, -8.9), mid + Vector3(0.0, 5.6, 8.9), ROOF_DARK)
			for end: float in [-1.0, 1.0]:
				# the gable over each portal, with a white trim board
				b.tri(mid + Vector3(-3.0, 4.0, end * 8.5), mid + Vector3(3.0, 4.0, end * 8.5), mid + Vector3(0.0, 5.5, end * 8.5), BARN_RED)
				b.block(mid + Vector3(0.0, 3.9, end * 8.55), Vector3(6.0, 0.25, 0.08), WHITE)
			b.mat = Geo.MAT_PAINT
	if i == 2:
		_church(b, _at(side, "lawn", 114.0, 0.0, -40.0), _face(side), STONE, ROOF_DARK, Color(0.25, 0.36, 0.3), true)
	# stone and brick houses behind
	if i != 3:
		var z := -8.0
		while z > -74.0:
			if rng.randf() < 0.75 and not (i == 2 and z < -24.0 and z > -60.0) and not (i == 5 and absf(z + 40.0) < 14.0):
				_porch_house(b, _at(side, "lawn", 118.0 + rng.randf_range(-3.0, 3.0), 0.0, z - 6.0), _face(side, rng.randf_range(-0.08, 0.08)),
					[STONE, BRICK, WHITE, BRICK.darkened(0.15)][rng.randi() % 4], ROOF_DARK * rng.randf_range(0.8, 1.5), rng, rng.randf() < 0.7)
			z -= rng.randf_range(15.0, 20.0)


# ── Gas ──────────────────────────────────────────────────────
## The ramps: place `first` has the lane off the shoulder to the lot, place `last` the lane
## back on. lot_u = how far out the lot's road-side edge is.
static func _ramps(b: Geo.Buf, i: int, side: int, first: int, last: int, lot_u: float) -> void:
	if i == first:
		_lane(b, side, "lawn", Vector2(-0.5, -4.0), Vector2(lot_u + 3.0, -80.0), 6.5, ASPHALT)
	elif i == last:
		_lane(b, side, "lawn", Vector2(lot_u + 3.0, 0.0), Vector2(-0.5, -76.0), 6.5, ASPHALT)


static func _gas(b: Geo.Buf, i: int, side: int) -> void:
	_ramps(b, i, side, 1, 3, 20.0)
	if i != 2:
		return
	var band := Color(0.75, 0.1, 0.08)
	_paving(b, side, "lawn", 44.0, 48.0, 0.0, -Land.LENGTH, ASPHALT)
	_canopy(b, _at(side, "lawn", 36.0, 0.05, -40.0), Vector3(9.0, 5.2, 24.0), band, 4, false)
	# the store behind the pumps: glass front, lit inside
	var at := _at(side, "lawn", 58.0, 0.0, -40.0)
	Geo.building(b, at, Vector3(22.0, 4.2, 11.0), _face(side), Color(0.75, 0.74, 0.7), Color(0.3, 0.3, 0.32), false, 0, false)
	var face := Basis(Vector3.UP, _face(side))
	b.mat = Geo.MAT_LIGHT
	b.box(Transform3D(face, at + face * Vector3(1.5, 1.6, 5.56)), Vector3(15.0, 2.4, 0.06), Color(1.0, 0.95, 0.85))
	b.mat = Geo.MAT_PAINT
	b.box(Transform3D(face, at + face * Vector3(0.0, 4.0, 5.6)), Vector3(22.2, 0.9, 0.2), band)
	_pole_sign(b, _at(side, "lawn", 24.0, 0.0, -8.0), _face(side, PI * 0.5), 24.0, Color(0.95, 0.93, 0.85), band, true)
	for z: float in [-6.0, -74.0]:
		_lot_light(b, _at(side, "lawn", 46.0, 0.0, z), 8.0)


static func _truck_stop(b: Geo.Buf, i: int, side: int, rng: RandomNumberGenerator) -> void:
	_ramps(b, i, side, 1, 4, 20.0)
	if i != 2 and i != 3:
		return
	var band := Color(0.1, 0.25, 0.55)
	_paving(b, side, "lawn", 74.0, 108.0, 0.0, -Land.LENGTH, ASPHALT)
	if i == 2:
		# the truck pumps under a high canopy, the diner beyond, the sign you see for miles
		_canopy(b, _at(side, "lawn", 44.0, 0.05, -34.0), Vector3(22.0, 6.5, 14.0), band, 3, false)
		var at := _at(side, "lawn", 84.0, 0.0, -34.0)
		Geo.building(b, at, Vector3(30.0, 4.6, 14.0), _face(side), Color(0.72, 0.72, 0.7), Color(0.25, 0.26, 0.28), false, 0, false)
		var face := Basis(Vector3.UP, _face(side))
		b.mat = Geo.MAT_CHROME
		b.box(Transform3D(face, at + face * Vector3(0.0, 3.4, 7.05)), Vector3(30.2, 0.8, 0.12), Color(0.7, 0.71, 0.73))
		b.mat = Geo.MAT_LIGHT
		b.box(Transform3D(face, at + face * Vector3(0.0, 1.7, 7.06)), Vector3(24.0, 1.8, 0.06), Color(1.0, 0.9, 0.7))
		b.mat = Geo.MAT_PAINT
		_pole_sign(b, _at(side, "lawn", 24.0, 0.0, -70.0), _face(side, PI * 0.5), 30.0, band, Color(1.0, 0.85, 0.2), false)
	else:
		# the lot: trailers parked in a row, nose out
		var cols: Array[Color] = [Color(0.8, 0.8, 0.78), Color(0.5, 0.12, 0.1), Color(0.15, 0.25, 0.4), Color(0.75, 0.6, 0.2), Color(0.3, 0.32, 0.33)]
		for n in 7:
			if rng.randf() < 0.25:
				continue
			var at := _at(side, "lawn", 98.0, 0.0, -8.0 - 10.0 * float(n))
			b.mat = Geo.MAT_PANEL
			b.block(at + Vector3(0.0, 2.6, 0.0), Vector3(14.0, 2.9, 2.6), cols[rng.randi() % cols.size()])
			b.mat = Geo.MAT_RUBBER
			for wx: float in [-5.5, -4.3]:
				b.block(at + Vector3(float(side) * wx * -1.0, 0.55, 0.0), Vector3(1.0, 1.1, 2.5), Color(0.05, 0.05, 0.05))
			b.mat = Geo.MAT_RUST
			b.block(at + Vector3(float(side) * 4.5 * -1.0, 0.6, 0.0), Vector3(0.2, 1.2, 1.2), Color(0.3, 0.3, 0.3))
			b.mat = Geo.MAT_PAINT
	for z: float in [-10.0, -70.0]:
		for u: float in [30.0, 70.0, 118.0]:
			_lot_light(b, _at(side, "lawn", u, 0.0, z), 11.0)


static func _old_station(b: Geo.Buf, i: int, side: int, rng: RandomNumberGenerator) -> void:
	if i != 3:
		return
	# a cracked gravel lot straight off the shoulder, as it was before the interstate's fences
	_paving(b, side, "lawn", 22.0, 30.0, -8.0, -72.0, GRAVEL.darkened(0.15))
	var at := _at(side, "lawn", 30.0, 0.0, -42.0)
	var turn := _face(side)
	var face := Basis(Vector3.UP, turn)
	# the little office with its hipped roof reaching out over the pumps on two posts
	Geo.building(b, at, Vector3(7.0, 3.4, 5.5), turn, Color(0.62, 0.6, 0.5), Color(0.35, 0.16, 0.1), false, 0, false)
	b.mat = Geo.MAT_WOOD
	var roof := Color(0.35, 0.16, 0.1)
	b.cyl(Transform3D(face * Basis(Vector3.UP, PI * 0.25), at + face * Vector3(0.0, 3.4, 3.2)), 8.6, 1.0, 2.2, 4, roof)
	b.mat = Geo.MAT_RUST
	for sx: float in [-2.6, 2.6]:
		b.box(Transform3D(face, at + face * Vector3(sx, 1.7, 7.6)), Vector3(0.3, 3.4, 0.3), Color(0.5, 0.48, 0.42))
	# two tall old pumps with round tops, rusted
	for sx: float in [-1.0, 1.0]:
		var pump := at + face * Vector3(sx, 0.0, 7.6)
		b.block(pump + Vector3(0.0, 0.9, 0.0), Vector3(0.5, 1.8, 0.4), Color(0.45, 0.2, 0.12))
		b.cyl(Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), pump + Vector3(0.0, 2.15, 0.0)), 0.33, 0.33, 0.12, 10, Color(0.75, 0.72, 0.62))
	# boarded windows, a leaning sign whose face has faded to nothing, a drum and an old tyre
	b.mat = Geo.MAT_WOOD
	for sx: float in [-1.6, 1.8]:
		b.box(Transform3D(face, at + face * Vector3(sx, 1.7, 2.78)), Vector3(1.3, 1.2, 0.06), Color(0.38, 0.32, 0.25))
	b.mat = Geo.MAT_RUST
	var sign_at := _at(side, "lawn", 14.0, 0.0, -20.0)
	b.rod(sign_at, sign_at + Vector3(0.5, 6.0, 0.2), 0.09, 6, Color(0.4, 0.3, 0.25))
	b.cyl(Transform3D(Basis(Vector3.BACK, PI * 0.5 + 0.08), sign_at + Vector3(0.62, 7.2, 0.24)), 1.3, 1.3, 0.12, 14, Color(0.6, 0.55, 0.45))
	b.cyl(Transform3D(Basis.IDENTITY, at + face * Vector3(4.6, 0.0, 3.4)), 0.3, 0.3, 0.9, 8, Color(0.35, 0.22, 0.15))
	b.mat = Geo.MAT_RUBBER
	b.cyl(Transform3D(Basis.IDENTITY, at + face * Vector3(-4.4, 0.0, 3.6) + Vector3(rng.randf_range(-0.3, 0.3), 0.0, 0.0)), 0.4, 0.4, 0.22, 10, Color(0.05, 0.05, 0.05))
	b.mat = Geo.MAT_PAINT
