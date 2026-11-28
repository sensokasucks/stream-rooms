extends Node3D
## Route 81's distant views ("vistas"): the things you see from an overlook one to three
## kilometres off. On the valley floor: a river bend, a reservoir with its dam, a stone railway
## viaduct, a patchwork of farms, a valley town, a field of bare boulders, a water gap. On the
## nearest ridge: a ski hill, a strip mine with its culm banks, a quarry, a wind farm, a fire
## tower, and a radio mast with red warning lights on a summit.
##
## Made by route81_room.gd as a child of the far view (r81_land.gd build_backdrop), so it is
## lowered and turned with the ridges. r81_trip.gd calls show_region() whenever the region
## changes (in the middle of a tunnel, in the dark): every region shows one valley view on each
## side of the road, one thing on a ridge and a radio mast, picked from the region's number
## alone (picks()), so every PC in a co-stream sees the same.
##
## Everything is low-poly with corner colours, drawn by r81_vista.gdshader (which lights and
## hazes it like the ridges). Sizes are real metres; nothing here is ever nearer than about a
## kilometre, so shapes are kept simple. Valley views are built once round their own middle,
## for the right-hand side (the road lies towards -X), and turned half round for the left.
## Ridge things are built for the very spot of the ridge they stand on, each time.
## Art: all original, no real places or brands.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Land := preload("res://rooms/route81/r81_land.gd")

## UV.x numbers r81_vista.gdshader knows.
const K_PLAIN: float = 0.0
const K_WATER: float = 1.0
const K_LIGHT: float = 2.0
const K_BEACON: float = 3.0
const K_TREES: float = 4.0
const K_STONES: float = 5.0

## The valley views and the ridge things (see the top of the file).
const VALLEY: PackedStringArray = ["river", "farms", "town", "viaduct", "reservoir", "boulders", "gap"]
const RIDGE: PackedStringArray = ["ski", "wind", "mine", "fire_tower", "quarry"]
## Where a valley view's middle lies from the car's spot at the start of a region: metres to
## the side, and metres ahead (the far view then creeps back a little as the car drives, see
## r81_trip.gd _apply). Far enough out to clear the land beside the road (r81_land.gd REACH)
## whichever way the road has turned, and short of the first ridge's foot.
const VALLEY_OUT: float = 1650.0
const VALLEY_AHEAD: float = 500.0

const WATER := Color(0.07, 0.12, 0.15)
const CANOPY := Color(0.085, 0.16, 0.055)
const STONE := Color(0.42, 0.4, 0.36)
const CONCRETE := Color(0.55, 0.54, 0.5)
const WINDOW := Color(1.0, 0.78, 0.45)

var _kit: Dictionary
var _valley_meshes: Dictionary = {}     # view name -> its mesh (built the first time it shows)
var _nodes: Array[Node3D] = []          # what the region in view shows (freed at the next one)
var _rotors: Array[Node3D] = []         # the wind farm's rotors, turned in _process
var _region: int = -99999
var _spot: Vector3 = Vector3.INF


## kit: the room's kit; r81_land.gd add_materials() has put kit["vista"] in it.
func setup(kit: Dictionary) -> void:
	name = "Vistas"
	_kit = kit


## What region `r` shows: [[view name, side (-1 left / +1 right)], ...]: a valley view on each
## side (never the same one twice), a ridge thing, and a radio mast on the other side's ridge.
static func picks(r: int) -> Array:
	var right := posmod(r * 3 + 1, VALLEY.size())
	var left := posmod(r * 5 + 4, VALLEY.size())
	if left == right:
		left = posmod(left + 1, VALLEY.size())
	var ridge_side := 1.0 if posmod(r, 2) == 0 else -1.0
	return [[VALLEY[right], 1.0], [VALLEY[left], -1.0], [RIDGE[posmod(r, RIDGE.size())], ridge_side], ["radio", -ridge_side]]


## Shows region r's views. spot = the car's place in the far view's own metres at the start of
## the region (r81_trip.gd region_spot()); the valley views lie beside it, the ridge things on
## the ridge abreast of it. Does nothing when both are what they were.
func show_region(r: int, spot: Vector3) -> void:
	if r == _region and spot.is_equal_approx(_spot):
		return
	_region = r
	_spot = spot
	show_views(picks(r), spot)


## Shows exactly these views (show_region's list; tests call it to look at one view).
func show_views(list: Array, spot: Vector3) -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_rotors.clear()
	for pick: Array in list:
		var view := String(pick[0])
		var side := float(pick[1])
		var node: Node3D
		if VALLEY.has(view):
			if not _valley_meshes.has(view):
				var vb := Geo.Buf.new()
				call("_build_" + view, vb)
				_valley_meshes[view] = vb.to_mesh()
			var mi := _mesh_node(view, _valley_meshes[view])
			mi.position = spot + Vector3(side * VALLEY_OUT, 0.0, -VALLEY_AHEAD)
			# (built for the right-hand side; half a turn puts its road side towards the road)
			mi.rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, 0.0)
			node = mi
		else:
			# built in the far view's own metres, on the ridge abreast of the car's spot
			var rb := Geo.Buf.new()
			node = Node3D.new()
			call("_build_" + view, rb, side, spot.z - VALLEY_AHEAD, node)
			var body := _mesh_node(view, rb.to_mesh())
			node.add_child(body)
		node.name = "%s_%s" % [view, "R" if side > 0.0 else "L"]
		add_child(node)
		_nodes.append(node)


## The names of the views showing now, as "name_R" / "name_L" (for tests).
func showing() -> PackedStringArray:
	var out := PackedStringArray()
	for n in _nodes:
		out.append(String(n.name))
	return out


func _mesh_node(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _kit["vista"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the far view is turned and lowered a long way from where its meshes are built
	mi.extra_cull_margin = 16000.0
	return mi


func _process(delta: float) -> void:
	# the wind farm: a slow, steady turn (one turn in about six seconds, as the real ones do)
	for r in _rotors:
		r.rotate_object_local(Vector3.RIGHT, delta * 1.05)


# ── Small parts ──────────────────────────────────────────────
## A house or shed: walls, a pitched roof with its ridge along the long side, and a lit window
## strip on the two long walls. at = the middle of its floor; turn = radians round Y.
static func _house(b: Geo.Buf, at: Vector3, size: Vector3, turn: float, wall: Color, roof: Color, lit: bool = true) -> void:
	var xf := Transform3D(Basis(Vector3.UP, turn), at)
	b.mat = K_PLAIN
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.5, 0.0)), size, wall)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := size.y + size.z * 0.35
	var e0 := xf * Vector3(-hx, size.y, -hz)
	var e1 := xf * Vector3(hx, size.y, -hz)
	var e2 := xf * Vector3(hx, size.y, hz)
	var e3 := xf * Vector3(-hx, size.y, hz)
	var r0 := xf * Vector3(-hx, top, 0.0)
	var r1 := xf * Vector3(hx, top, 0.0)
	b.quad(e0, e1, r1, r0, roof)
	b.quad(e3, r0, r1, e2, roof)
	b.tri(e0, r0, e3, wall)
	b.tri(e1, e2, r1, wall)
	if lit:
		b.mat = K_LIGHT
		for s: float in [-1.0, 1.0]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.55, s * (hz + 0.15))), Vector3(size.x * 0.7, size.y * 0.22, 0.2), WINDOW)
		b.mat = K_PLAIN


## A clump of tree tops: a few low lumps round `at`, about `radius` across.
static func _wood(b: Geo.Buf, at: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	b.mat = K_TREES
	var lumps := maxi(2, roundi(radius / 14.0))
	for i in lumps:
		var off := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * radius * 0.6
		var r := rng.randf_range(9.0, 15.0)
		b.blob(at + off + Vector3(0.0, r * 0.55, 0.0), Vector3(r, r * 0.8, r), 6, 3, CANOPY * 1.5, CANOPY * 0.8, 0.3, rng)
	b.mat = K_PLAIN


## A flat ribbon (a river, a road, a railway bed) through `points`, `width` across, at height y.
static func _ribbon(b: Geo.Buf, points: PackedVector3Array, width: float, y: float, col: Color) -> void:
	for i in points.size() - 1:
		var a := points[i]
		var c := points[i + 1]
		var along := (c - a).normalized()
		var before := (a - points[maxi(i - 1, 0)]).normalized() if i > 0 else along
		var after := (points[mini(i + 2, points.size() - 1)] - c).normalized() if i + 2 < points.size() else along
		var sa := Vector3.UP.cross((along + before).normalized()).normalized() * width * 0.5
		var sc := Vector3.UP.cross((along + after).normalized()).normalized() * width * 0.5
		var up := Vector3(0.0, y, 0.0)
		b.quad(a - sa + up, a + sa + up, c + sc + up, c - sc + up, col)


## A flat patch with an uneven round outline (a lake, a clearing): radii along X and Z.
static func _patch(b: Geo.Buf, at: Vector3, radii: Vector2, col: Color, rng: RandomNumberGenerator, lump: float = 0.25) -> PackedVector3Array:
	var rim := PackedVector3Array()
	var n := 18
	for i in n:
		var ang := TAU * float(i) / float(n)
		var k := 1.0 + rng.randf_range(-lump, lump)
		rim.append(at + Vector3(cos(ang) * radii.x * k, 0.0, sin(ang) * radii.y * k))
	for i in n:
		b.tri(at, rim[i], rim[(i + 1) % n], col)
	return rim


# ── Valley views (built round their own middle; the road lies towards -X) ──
## A river winding down the valley, with gravel bars, wooded banks and a road bridge.
func _build_river(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8101
	var pts := PackedVector3Array()
	for i in 41:
		var z := lerpf(-3200.0, 3200.0, float(i) / 40.0)
		pts.append(Vector3(170.0 * sin(z / 620.0) + 90.0 * sin(z / 250.0 + 1.0), 0.0, z))
	b.mat = K_WATER
	_ribbon(b, pts, 95.0, 1.5, WATER)
	b.mat = K_PLAIN
	for i in range(2, 40, 3):
		# a pale gravel bar on the inside of a bend, trees on the outside
		var p := pts[i]
		var inside := -signf(cos(p.z / 620.0))
		_patch(b, p + Vector3(inside * 52.0, 2.2, 0.0), Vector2(26.0, 70.0), Color(0.55, 0.5, 0.4), rng)
		_wood(b, p + Vector3(-inside * 85.0, 0.0, 0.0), 45.0, rng)
	# a two-lane bridge on four piers, and the road to it
	var at := pts[22]
	b.block(at + Vector3(0.0, 13.0, 0.0), Vector3(190.0, 2.0, 11.0), CONCRETE)
	for x: float in [-60.0, -20.0, 20.0, 60.0]:
		b.block(at + Vector3(x, 6.0, 0.0), Vector3(4.0, 12.0, 9.0), CONCRETE * 0.85)
	_ribbon(b, PackedVector3Array([at + Vector3(-520.0, 0.0, 30.0), at + Vector3(-95.0, 0.0, 0.0)]), 9.0, 1.0, Color(0.2, 0.2, 0.21))
	_ribbon(b, PackedVector3Array([at + Vector3(95.0, 0.0, 0.0), at + Vector3(560.0, 0.0, -60.0)]), 9.0, 1.0, Color(0.2, 0.2, 0.21))


## A quilt of fields with hedgerows, lanes and four farmsteads (house, barn, silo).
func _build_farms(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8102
	var crops: Array[Color] = [Color(0.3, 0.4, 0.13), Color(0.5, 0.45, 0.2), Color(0.22, 0.34, 0.1), Color(0.33, 0.24, 0.15),
		Color(0.42, 0.44, 0.16), Color(0.26, 0.38, 0.14)]
	var z := -620.0
	while z < 620.0:
		var deep := rng.randf_range(130.0, 230.0)
		var x := -330.0
		while x < 330.0:
			var wide := rng.randf_range(110.0, 220.0)
			b.block(Vector3(x + wide * 0.5, 0.6, z + deep * 0.5), Vector3(wide - 6.0, 1.2, deep - 6.0), crops[rng.randi() % crops.size()] * rng.randf_range(0.85, 1.1))
			if rng.randf() < 0.3:
				_wood(b, Vector3(x + wide, 0.0, z + deep * rng.randf()), 30.0, rng)
			x += wide
		z += deep
	_ribbon(b, PackedVector3Array([Vector3(-420.0, 0.0, -80.0), Vector3(0.0, 0.0, -40.0), Vector3(420.0, 0.0, 60.0)]), 7.0, 1.6, Color(0.36, 0.33, 0.28))
	for at: Vector3 in [Vector3(-200.0, 1.2, -70.0), Vector3(130.0, 1.2, -10.0), Vector3(-40.0, 1.2, 330.0), Vector3(210.0, 1.2, -400.0)]:
		var turn := rng.randf_range(-0.4, 0.4)
		_house(b, at, Vector3(14.0, 7.0, 9.0), turn, Color(0.8, 0.8, 0.76), Color(0.22, 0.22, 0.24))
		# the barn: red, bigger than the house, and a silo with a pale cap beside it
		_house(b, at + Vector3(34.0, 0.0, 22.0), Vector3(26.0, 9.0, 14.0), turn + 1.2, Color(0.45, 0.1, 0.07), Color(0.3, 0.3, 0.32), false)
		b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(52.0, 0.0, 6.0)), 4.0, 4.0, 19.0, 8, Color(0.6, 0.6, 0.58))
		b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(52.0, 19.0, 6.0)), 4.0, 0.5, 3.0, 8, Color(0.75, 0.76, 0.78))
		_wood(b, at + Vector3(-22.0, 0.0, -14.0), 22.0, rng)


## A valley town: a grid of streets, houses, a few taller blocks downtown, church spires, a
## water tower and a brick stack. Its windows and street lamps glow at night.
func _build_town(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8103
	var walls: Array[Color] = [Color(0.42, 0.18, 0.13), Color(0.7, 0.68, 0.62), Color(0.5, 0.3, 0.2), Color(0.6, 0.58, 0.5), Color(0.36, 0.34, 0.33)]
	var street := Color(0.17, 0.17, 0.18)
	var cell := 78.0
	for i in 9:
		_ribbon(b, PackedVector3Array([Vector3(-312.0, 0.0, (float(i) - 4.0) * cell), Vector3(312.0, 0.0, (float(i) - 4.0) * cell)]), 9.0, 1.0, street)
		_ribbon(b, PackedVector3Array([Vector3((float(i) - 4.0) * cell, 0.0, -312.0), Vector3((float(i) - 4.0) * cell, 0.0, 312.0)]), 9.0, 1.0, street)
	for ix in 8:
		for iz in 8:
			var mid := Vector3((float(ix) - 3.5) * cell, 0.0, (float(iz) - 3.5) * cell)
			var downtown := absi(ix * 2 - 7) <= 1 and absi(iz * 2 - 7) <= 3
			if downtown:
				# brick and stone blocks, three to nine floors, lit floors as window bands
				var high := rng.randf_range(12.0, 36.0)
				var size := Vector3(rng.randf_range(28.0, 50.0), high, rng.randf_range(28.0, 50.0))
				b.mat = K_PLAIN
				b.block(mid + Vector3(0.0, high * 0.5, 0.0), size, walls[rng.randi() % walls.size()])
				b.mat = K_LIGHT
				var floors := int(high / 7.0)
				for f in floors:
					if rng.randf() < 0.7:
						b.block(mid + Vector3(0.0, 5.0 + 7.0 * float(f), 0.0), Vector3(size.x + 0.5, 1.6, size.z + 0.5), WINDOW * rng.randf_range(0.6, 1.0))
				b.mat = K_PLAIN
			else:
				for h in 3:
					if rng.randf() < 0.2:
						_wood(b, mid + Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(-22.0, 22.0)), 16.0, rng)
						continue
					var at := mid + Vector3((float(h) - 1.0) * 21.0 + rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-18.0, 18.0))
					_house(b, at, Vector3(rng.randf_range(9.0, 13.0), rng.randf_range(6.0, 8.0), rng.randf_range(8.0, 11.0)), float(rng.randi() % 2) * PI * 0.5,
						walls[rng.randi() % walls.size()], Color(0.2, 0.2, 0.22) * rng.randf_range(0.8, 1.4), rng.randf() < 0.6)
			# a street lamp at the block's corner
			b.mat = K_LIGHT
			b.block(mid + Vector3(cell * 0.5 - 6.0, 8.0, cell * 0.5 - 6.0), Vector3(1.6, 1.0, 1.6), Color(1.0, 0.72, 0.35))
			b.mat = K_PLAIN
	# three churches: a nave and a spire
	for at: Vector3 in [Vector3(-175.0, 0.0, -120.0), Vector3(150.0, 0.0, 190.0), Vector3(-60.0, 0.0, 260.0)]:
		_house(b, at, Vector3(26.0, 11.0, 12.0), 0.0, Color(0.72, 0.7, 0.65), Color(0.25, 0.25, 0.28))
		b.block(at + Vector3(-15.0, 11.0, 0.0), Vector3(7.0, 22.0, 7.0), Color(0.72, 0.7, 0.65))
		b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(-15.0, 22.0, 0.0)), 5.0, 0.0, 17.0, 4, Color(0.22, 0.3, 0.27))
	# the water tower on its legs, and an old mill's stack
	var wt := Vector3(250.0, 0.0, -230.0)
	for leg: Vector2 in [Vector2(-5.0, -5.0), Vector2(5.0, -5.0), Vector2(5.0, 5.0), Vector2(-5.0, 5.0)]:
		b.rod(wt + Vector3(leg.x, 0.0, leg.y), wt + Vector3(leg.x * 0.6, 26.0, leg.y * 0.6), 0.6, 4, Color(0.5, 0.55, 0.58))
	b.cyl(Transform3D(Basis.IDENTITY, wt + Vector3(0.0, 25.0, 0.0)), 7.5, 7.5, 9.0, 10, Color(0.62, 0.7, 0.74))
	b.cyl(Transform3D(Basis.IDENTITY, wt + Vector3(0.0, 34.0, 0.0)), 7.5, 1.0, 3.0, 10, Color(0.5, 0.58, 0.62))
	b.cyl(Transform3D(Basis.IDENTITY, Vector3(-250.0, 0.0, 120.0)), 3.2, 2.2, 48.0, 8, Color(0.45, 0.22, 0.16))
	b.block(Vector3(-225.0, 7.0, 135.0), Vector3(60.0, 14.0, 32.0), Color(0.4, 0.2, 0.15))


## A long stone railway viaduct on tall round arches over a creek, with a freight train on it.
## It runs along the valley, so the road sees it broadside.
func _build_viaduct(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8104
	var spans := 10
	var span := 58.0
	var pier := 9.0
	var high := 66.0           # the deck's underside above the ground
	var thick := 10.0          # the viaduct's width
	var x0 := 120.0
	var length := float(spans) * span
	var radius := (span - pier) * 0.5
	var spring := high - 6.0 - radius    # where the arches start
	for i in spans + 1:
		var z := -length * 0.5 + float(i) * span
		b.block(Vector3(x0, spring * 0.5, z), Vector3(thick, spring, pier), STONE)
		# a stepped footing
		b.block(Vector3(x0, 3.0, z), Vector3(thick + 4.0, 6.0, pier + 4.0), STONE * 0.9)
	for i in spans:
		var zc := -length * 0.5 + (float(i) + 0.5) * span
		# the arch: its wall above the curve on both faces, and the curve's underside
		var steps := 10
		for s in steps:
			var a0 := PI * float(s) / float(steps)
			var a1 := PI * float(s + 1) / float(steps)
			var p0 := Vector2(zc - cos(a0) * radius, spring + sin(a0) * radius)
			var p1 := Vector2(zc - cos(a1) * radius, spring + sin(a1) * radius)
			for face: float in [-1.0, 1.0]:
				var x := x0 + face * thick * 0.5
				b.quad(Vector3(x, p0.y, p0.x), Vector3(x, high, p0.x), Vector3(x, high, p1.x), Vector3(x, p1.y, p1.x), STONE)
			b.quad(Vector3(x0 - thick * 0.5, p0.y, p0.x), Vector3(x0 + thick * 0.5, p0.y, p0.x), Vector3(x0 + thick * 0.5, p1.y, p1.x), Vector3(x0 - thick * 0.5, p1.y, p1.x), STONE * 0.7)
		# the wall over the pier between two arches
		for face: float in [-1.0, 1.0]:
			var x := x0 + face * thick * 0.5
			for end: float in [-1.0, 1.0]:
				var z := zc + end * span * 0.5
				b.quad(Vector3(x, spring, z), Vector3(x, high, z), Vector3(x, high, z - end * pier * 0.5), Vector3(x, spring, z - end * pier * 0.5), STONE)
	# the deck with its parapet, and the banks it runs onto at both ends
	b.block(Vector3(x0, high + 1.5, 0.0), Vector3(thick + 1.5, 3.0, length + pier), STONE * 1.1)
	for end: float in [-1.0, 1.0]:
		var z := end * (length * 0.5 + pier * 0.5)
		b.mat = K_TREES
		b.quad(Vector3(x0 - 80.0, 0.0, z), Vector3(x0 + 80.0, 0.0, z), Vector3(x0 + 14.0, high + 3.0, z + end * 40.0), Vector3(x0 - 14.0, high + 3.0, z + end * 40.0), CANOPY)
		b.quad(Vector3(x0 - 14.0, high + 3.0, z + end * 40.0), Vector3(x0 + 14.0, high + 3.0, z + end * 40.0), Vector3(x0 + 60.0, high + 3.0, z + end * 900.0), Vector3(x0 - 60.0, high + 3.0, z + end * 900.0), CANOPY)
		for sx: float in [-1.0, 1.0]:
			b.quad(Vector3(x0 + sx * 80.0, 0.0, z), Vector3(x0 + sx * 14.0, high + 3.0, z + end * 40.0), Vector3(x0 + sx * 60.0, high + 3.0, z + end * 900.0), Vector3(x0 + sx * 330.0, 0.0, z + end * 900.0), CANOPY * 0.85)
		b.mat = K_PLAIN
	# the train: two engines and a string of cars
	var z_car := -length * 0.3
	for i in 16:
		var long := 21.0 if i < 2 else 16.0
		var col: Color = Color(0.12, 0.2, 0.36) if i < 2 else [Color(0.4, 0.16, 0.1), Color(0.2, 0.2, 0.2), Color(0.38, 0.33, 0.2), Color(0.16, 0.26, 0.2)][rng.randi() % 4]
		b.block(Vector3(x0, high + 5.3, z_car + long * 0.5), Vector3(3.2, 4.6, long - 1.2), col)
		z_car += long
	# the creek under the middle arches, crossing the valley
	b.mat = K_WATER
	var creek := PackedVector3Array()
	for i in 13:
		var x := lerpf(-650.0, 650.0, float(i) / 12.0)
		creek.append(Vector3(x, 0.0, 30.0 + 45.0 * sin(x / 150.0)))
	_ribbon(b, creek, 22.0, 1.2, WATER)
	b.mat = K_PLAIN
	for i in 10:
		_wood(b, creek[1 + i] + Vector3(0.0, 0.0, 40.0 if i % 2 == 0 else -40.0), 28.0, rng)


## A reservoir behind a concrete dam: the lake stands 18 m above the valley floor between
## wooded banks, the dam closes its downstream end and a white spillway runs down its face.
func _build_reservoir(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8105
	var level := 18.0
	b.mat = K_WATER
	var rim := _patch(b, Vector3(0.0, level, 60.0), Vector2(300.0, 520.0), WATER, rng, 0.18)
	# the banks: a wooded skirt from the water's edge down to the floor
	b.mat = K_TREES
	for i in rim.size():
		var a := rim[i]
		var c := rim[(i + 1) % rim.size()]
		var mid := Vector3(0.0, level, 60.0)
		var a_out := a + (a - mid).normalized() * 120.0
		var c_out := c + (c - mid).normalized() * 120.0
		a_out.y = 0.0
		c_out.y = 0.0
		b.quad(a + Vector3(0.0, 4.0, 0.0), c + Vector3(0.0, 4.0, 0.0), c_out, a_out, CANOPY)
		b.quad(a, c, c + Vector3(0.0, 4.0, 0.0), a + Vector3(0.0, 4.0, 0.0), CANOPY * 0.7)
	# the dam across the downstream (-Z) end, facing down the valley
	b.mat = K_PLAIN
	var z := -470.0
	b.quad(Vector3(-190.0, level + 5.0, z), Vector3(190.0, level + 5.0, z), Vector3(190.0, 0.0, z - 30.0), Vector3(-190.0, 0.0, z - 30.0), CONCRETE)
	b.block(Vector3(0.0, level + 4.0, z + 4.0), Vector3(380.0, 3.0, 8.0), CONCRETE * 1.1)
	b.quad(Vector3(-22.0, level + 3.0, z - 0.6), Vector3(22.0, level + 3.0, z - 0.6), Vector3(22.0, 0.3, z - 31.0), Vector3(-22.0, 0.3, z - 31.0), Color(0.8, 0.82, 0.84))
	b.block(Vector3(120.0, level + 9.0, z + 4.0), Vector3(12.0, 8.0, 10.0), CONCRETE * 0.9)
	# the river it lets go, running on down the valley
	b.mat = K_WATER
	_ribbon(b, PackedVector3Array([Vector3(0.0, 0.0, z - 30.0), Vector3(30.0, 0.0, z - 400.0), Vector3(-40.0, 0.0, z - 900.0), Vector3(20.0, 0.0, z - 1800.0)]), 40.0, 1.2, WATER)
	b.mat = K_PLAIN


## A boulder field: a long clearing of bare pale stones in the forest, left by the ice age,
## with single boulders and a few stunted trees along its edge.
func _build_boulders(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8106
	b.mat = K_STONES
	_patch(b, Vector3(0.0, 2.0, 0.0), Vector2(190.0, 430.0), Color(0.5, 0.46, 0.43), rng, 0.2)
	for i in 70:
		var at := Vector3(rng.randf_range(-170.0, 170.0), 2.0, rng.randf_range(-400.0, 400.0))
		var r := rng.randf_range(2.5, 6.0)
		b.blob(at, Vector3(r, r * 0.6, r), 5, 3, Color(0.56, 0.52, 0.48), Color(0.38, 0.35, 0.33), 0.5, rng)
	b.mat = K_PLAIN
	for i in 26:
		var ang := rng.randf() * TAU
		_wood(b, Vector3(cos(ang) * 215.0, 0.0, sin(ang) * 460.0), 24.0, rng)


## A water gap: a low wooded ridge across the view with a notch cut clean through it, bare
## rock on the notch's two faces, and the river that cut it coming through.
func _build_gap(b: Geo.Buf) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8107
	var high := 190.0
	var x0 := 230.0
	for end: float in [-1.0, 1.0]:
		# one half of the ridge: a tent from the notch (150 m from the middle) out to 1700 m,
		# its crest dropping to nothing at the far end and steeply at the notch
		var grid: Array = []
		for across: Array in [[-320.0, 0.0], [-130.0, 0.72], [0.0, 1.0], [130.0, 0.72], [320.0, 0.0]]:
			var row := PackedVector3Array()
			for j in 13:
				var t := float(j) / 12.0
				var z := end * lerpf(150.0, 1700.0, t)
				var h := high * smoothstep(0.0, 0.07, t) * (1.0 - smoothstep(0.6, 1.0, t)) * (0.85 + 0.15 * sin(t * 9.0 + end))
				row.append(Vector3(x0 + float(across[0]), h * float(across[1]), z))
			grid.append(row)
		b.mat = K_TREES
		b.surface(grid, false, [CANOPY, CANOPY, CANOPY * 1.15, CANOPY, CANOPY])
		# the notch's rock face
		b.mat = K_PLAIN
		var zf := end * 150.0
		var zr := end * 258.0
		b.tri(Vector3(x0 - 230.0, 0.0, zf), Vector3(x0, high * 0.9, zr), Vector3(x0 + 230.0, 0.0, zf), Color(0.4, 0.37, 0.34))
	# the river through the notch, then away down the valley on the road's side
	b.mat = K_WATER
	_ribbon(b, PackedVector3Array([Vector3(900.0, 0.0, 60.0), Vector3(520.0, 0.0, -20.0), Vector3(230.0, 0.0, 10.0), Vector3(-60.0, 0.0, 0.0),
		Vector3(-240.0, 0.0, -160.0), Vector3(-300.0, 0.0, -600.0), Vector3(-230.0, 0.0, -1300.0), Vector3(-320.0, 0.0, -2600.0)]), 80.0, 1.4, WATER)
	b.mat = K_PLAIN
	# a railway hugging the river through the gap
	_ribbon(b, PackedVector3Array([Vector3(900.0, 0.0, 130.0), Vector3(520.0, 0.0, 60.0), Vector3(230.0, 0.0, 85.0), Vector3(-80.0, 0.0, 90.0),
		Vector3(-330.0, 0.0, -120.0)]), 8.0, 3.0, Color(0.3, 0.28, 0.26))


# ── Ridge things (built in the far view's own metres) ────────
## A patch of the nearest ridge's road-side slope, lifted `lift` metres off it, as a grid:
## rows from `a0` to `a1` across the slope (0 = crest, 1 = the foot on the road's side), columns
## along the ridge from z0 to z1. cols.call(row share 0..1, column share 0..1) -> Color.
func _drape(b: Geo.Buf, side: float, z0: float, z1: float, a0: float, a1: float, rows: int, columns: int, lift: float, cols: Callable) -> void:
	for r in rows:
		for c in columns:
			var pts: Array[Vector3] = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
				var rt := float(r + corner.x) / float(rows)
				var ct := float(c + corner.y) / float(columns)
				pts.append(Land.ridge_point(side, 0, lerpf(z0, z1, ct), -side * lerpf(a0, a1, rt)) + Vector3(0.0, lift, 0.0))
			b.quad(pts[0], pts[1], pts[2], pts[3], cols.call((float(r) + 0.5) / float(rows), (float(c) + 0.5) / float(columns)))


## The point on the nearest ridge's crest at z.
func _crest(side: float, z: float) -> Vector3:
	return Land.ridge_point(side, 0, z, 0.0)


## A ski hill: five grassy trails fanning down from the crest to a lodge at the foot, and a
## lift line of towers up the middle. (Summer and fall: no snow.)
func _build_ski(b: Geo.Buf, side: float, z: float, _node: Node3D) -> void:
	var grass := Color(0.27, 0.38, 0.14)
	for t in 5:
		var top_z := z + (float(t) - 2.0) * 70.0
		var foot_z := z + (float(t) - 2.0) * 260.0
		var steps := 10
		for s in steps:
			var pts: Array[Vector3] = []
			for corner: Vector2 in [Vector2(0.0, -1.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, -1.0)]:
				var st := (float(s) + corner.x) / float(steps)
				var wide := lerpf(22.0, 45.0, st)
				# a trail bows a little on its way down
				var zz := lerpf(top_z, foot_z, st) + 60.0 * sin(st * PI) * (1.0 if t % 2 == 0 else -1.0) + corner.y * wide
				pts.append(Land.ridge_point(side, 0, zz, -side * lerpf(0.04, 0.92, st)) + Vector3(0.0, 10.0, 0.0))
			b.quad(pts[0], pts[1], pts[2], pts[3], grass * (0.9 + 0.1 * float(t % 2)))
	for i in 9:
		var at := Land.ridge_point(side, 0, z + 20.0, -side * lerpf(0.06, 0.9, float(i) / 8.0)) + Vector3(0.0, 8.0, 0.0)
		b.block(at + Vector3(0.0, 9.0, 0.0), Vector3(1.6, 18.0, 1.6), Color(0.3, 0.32, 0.33))
		b.block(at + Vector3(0.0, 18.0, 0.0), Vector3(1.2, 1.0, 8.0), Color(0.3, 0.32, 0.33))
	var foot := Land.ridge_point(side, 0, z, -side * 0.97)
	_house(b, foot + Vector3(-side * 40.0, 10.0, 0.0), Vector3(22.0, 12.0, 60.0), 0.0, Color(0.4, 0.26, 0.16), Color(0.22, 0.25, 0.22))
	b.block(foot + Vector3(-side * 110.0, 9.0, 0.0), Vector3(90.0, 0.6, 170.0), Color(0.22, 0.22, 0.23))


## A wind farm: seven white turbines along the crest. The rotors are nodes of their own
## (turned in _process).
func _build_wind(b: Geo.Buf, side: float, z: float, node: Node3D) -> void:
	var white := Color(0.82, 0.83, 0.84)
	var blades := Geo.Buf.new()
	for i in 3:
		var spoke := Basis(Vector3.RIGHT, TAU * float(i) / 3.0)
		blades.box(Transform3D(spoke, spoke * Vector3(0.0, 22.0, 0.0)), Vector3(0.8, 44.0, 3.4), white)
	blades.cyl(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.5, 0.0, 0.0)), 2.4, 0.6, 4.0, 6, white)
	var rotor_mesh := blades.to_mesh()
	for i in 7:
		var at := _crest(side, z + (float(i) - 3.0) * 430.0)
		b.cyl(Transform3D(Basis.IDENTITY, at), 2.6, 1.5, 92.0, 8, white)
		b.block(at + Vector3(-side * 1.0, 93.0, 0.0), Vector3(9.0, 3.6, 3.6), white)
		# the rotor faces the road's side of the ridge (its axle along X)
		var rotor := _mesh_node("Rotor_%d" % i, rotor_mesh)
		rotor.position = at + Vector3(-side * 6.5, 93.0, 0.0)
		rotor.rotation = Vector3(float(i) * 0.9, 0.0, 0.0)
		node.add_child(rotor)
		_rotors.append(rotor)
		# a red light on every nacelle
		b.mat = K_BEACON
		b.block(at + Vector3(0.0, 96.5, 0.0), Vector3(3.5, 3.5, 3.5), Color(0.6, 0.05, 0.04))
		b.mat = K_PLAIN


## A strip mine: bare benches of black coal and grey-brown spoil stepped up the slope, culm
## banks (waste heaps) at its foot, and a dragline's boom.
func _build_mine(b: Geo.Buf, side: float, z: float, _node: Node3D) -> void:
	_drape(b, side, z - 420.0, z + 420.0, 0.3, 0.86, 9, 8, 9.0, func(rt: float, ct: float) -> Color:
		var band := int(rt * 9.0)
		var col := Color(0.09, 0.09, 0.1) if band % 3 == 0 else (Color(0.3, 0.27, 0.23) if band % 3 == 1 else Color(0.2, 0.19, 0.18))
		return col * (0.85 + 0.3 * absf(sin(ct * 23.0 + float(band)))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8110
	for i in 4:
		var at := Land.ridge_point(side, 0, z + (float(i) - 1.5) * 190.0, -side * 0.97) + Vector3(-side * rng.randf_range(40.0, 120.0), 0.0, 0.0)
		at.y = 0.0
		var r := rng.randf_range(55.0, 95.0)
		b.cyl(Transform3D(Basis.IDENTITY, at), r, r * 0.12, r * 0.62, 9, Color(0.1, 0.1, 0.11), Color(0.13, 0.13, 0.14))
	var dl := Land.ridge_point(side, 0, z + 60.0, -side * 0.6) + Vector3(0.0, 12.0, 0.0)
	b.block(dl + Vector3(0.0, 7.0, 0.0), Vector3(16.0, 12.0, 18.0), Color(0.6, 0.45, 0.1))
	b.rod(dl + Vector3(0.0, 12.0, 0.0), dl + Vector3(-side * 20.0, 62.0, -70.0), 1.2, 4, Color(0.6, 0.45, 0.1))


## A fire lookout tower on the crest: four braced legs, a cab with windows all round and a
## pitched roof, in a small clearing.
func _build_fire_tower(b: Geo.Buf, side: float, z: float, _node: Node3D) -> void:
	var at := _crest(side, z) + Vector3(0.0, 6.0, 0.0)
	var steel := Color(0.4, 0.42, 0.42)
	var high := 46.0
	for leg: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		b.rod(at + Vector3(leg.x * 8.0, -8.0, leg.y * 8.0), at + Vector3(leg.x * 3.2, high, leg.y * 3.2), 0.7, 4, steel)
	for level in 4:
		var y := high * (float(level) + 0.5) / 4.5
		var half := lerpf(8.0, 3.2, y / high)
		b.block(at + Vector3(0.0, y, 0.0), Vector3(half * 2.0, 0.6, half * 2.0), steel)
	b.block(at + Vector3(0.0, high + 2.6, 0.0), Vector3(8.4, 5.2, 8.4), Color(0.7, 0.72, 0.68))
	b.mat = K_LIGHT
	b.block(at + Vector3(0.0, high + 3.2, 0.0), Vector3(8.7, 2.0, 8.7), Color(0.9, 0.75, 0.5))
	b.mat = K_PLAIN
	b.cyl(Transform3D(Basis(Vector3.UP, PI * 0.25), at + Vector3(0.0, high + 5.2, 0.0)), 7.2, 0.3, 3.4, 4, Color(0.3, 0.12, 0.1))


## A quarry: pale stone benches cut into the slope like giant steps, a green pond on its floor
## and the crusher's sheds at the foot.
func _build_quarry(b: Geo.Buf, side: float, z: float, _node: Node3D) -> void:
	_drape(b, side, z - 260.0, z + 260.0, 0.42, 0.9, 8, 6, 8.0, func(rt: float, ct: float) -> Color:
		var band := int(rt * 8.0)
		var col := Color(0.62, 0.6, 0.55) if band % 2 == 0 else Color(0.36, 0.35, 0.33)
		return col * (0.9 + 0.2 * absf(sin(ct * 17.0 + float(band) * 2.0))))
	var foot := Land.ridge_point(side, 0, z, -side * 0.93) + Vector3(0.0, 11.0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8111
	b.mat = K_WATER
	_patch(b, foot, Vector2(60.0, 130.0), Color(0.08, 0.3, 0.26), rng, 0.15)
	b.mat = K_PLAIN
	var yard := Land.ridge_point(side, 0, z + 330.0, -side * 0.99)
	yard.y = 0.0
	_house(b, yard + Vector3(-side * 50.0, 0.0, 0.0), Vector3(20.0, 24.0, 44.0), 0.0, Color(0.5, 0.5, 0.48), Color(0.35, 0.36, 0.37), false)
	b.rod(yard + Vector3(-side * 50.0, 20.0, 20.0), yard + Vector3(-side * 80.0, 2.0, 100.0), 2.0, 4, Color(0.4, 0.4, 0.38))
	b.cyl(Transform3D(Basis.IDENTITY, yard + Vector3(-side * 85.0, 0.0, 130.0)), 34.0, 3.0, 20.0, 8, Color(0.6, 0.58, 0.53))


## A radio mast on the crest: a thin red-and-white lattice held by guy wires, with three red
## warning lights (they glow at night, r81_vista.gdshader).
func _build_radio(b: Geo.Buf, side: float, z: float, _node: Node3D) -> void:
	# (stands on the highest spot of the crest within a kilometre either way)
	var at := _crest(side, z)
	for i in 9:
		var p := _crest(side, z + (float(i) - 4.0) * 250.0)
		if p.y > at.y:
			at = p
	var high := 150.0
	var bands := 10
	for i in bands:
		var col := Color(0.75, 0.12, 0.08) if i % 2 == 0 else Color(0.85, 0.85, 0.83)
		b.block(at + Vector3(0.0, high * (float(i) + 0.5) / float(bands), 0.0), Vector3(3.2, high / float(bands), 3.2), col)
	for i in 3:
		var ang := TAU * float(i) / 3.0 + 0.4
		for y: float in [high * 0.5, high * 0.95]:
			b.rod(at + Vector3(0.0, y, 0.0), at + Vector3(cos(ang) * 95.0, 0.0, sin(ang) * 95.0), 0.35, 3, Color(0.3, 0.3, 0.32))
	b.block(at + Vector3(5.0, 3.0, 4.0), Vector3(7.0, 6.0, 9.0), Color(0.6, 0.6, 0.58))
	b.mat = K_BEACON
	for y: float in [high * 0.34, high * 0.67, high + 3.0]:
		b.block(at + Vector3(0.0, y, 0.0), Vector3(6.0, 6.0, 6.0), Color(0.6, 0.05, 0.04))
	b.mat = K_PLAIN
