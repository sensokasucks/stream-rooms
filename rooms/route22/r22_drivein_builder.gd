extends RefCounted
## Builds the Route 22 Drive-In's set (route22_room.gd calls build() when the room loads):
## a desert drive-in beside Route 22 with red rocks behind the screen.
##   - the big screen on its tower (TVScreen, facing +Z) and a low stage under it with four
##     podiums (PRESENTER_n / PODIUM_n),
##   - the 30 chat seats (AUDIENCE_nn), facing the screen:
##       1-8    blankets (front row) and lawn chairs on the grass strip before the stage,
##       9-16   four convertibles nosed up to the screen, two in each front seat,
##       17-28  four pickups backed in, tailgates down, three sitting in each bed,
##       29-30  the picnic table by the snack bar,
##   - speaker posts between the cars, the snack bar with the projection booth on its roof
##     (BEAM_Projector), lot light poles (the house lights: LIGHTS_House / LAMP_*), the ticket
##     booth, an old gas pump, a fence, the neon "ROUTE 22 DRIVE-IN" marquee by the road,
##   - Route 22 itself running past the entrance (traffic: r22_traffic.gd, laid along it),
##   - red sandstone behind the screen and round the lot (r22_geo.gd), photo-scanned boulders,
##     stones, oil drums and dead wood among it (_scans, models/), brush, ten cameras.
## Room space: the screen at the north (-Z) end facing the lot, the road along X at z = ROAD_Z.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Vehicles := preload("res://rooms/route22/r22_vehicles.gd")

const SCREEN_Z: float = -17.0
const SCREEN_SIZE: Vector2 = Vector2(15.0, 8.44)
const SCREEN_BOTTOM: float = 4.0
## The stage under the screen: its top's height and its front edge.
const STAGE_Y: float = 0.8
const STAGE_Z: float = -14.3
## The lot (packed gravel): x0, z0, x1, z1.
const LOT := Vector4(-23.0, -21.0, 23.0, 26.0)
## Route 22's middle line runs along X at this z.
const ROAD_Z: float = 33.0
## The cars: [x, colour, wood panels] for the convertibles at z = CAR_ROW_Z, x for the pickups
## at z = TRUCK_ROW_Z.
const CAR_ROW_Z: float = -1.5
const CARS: Array = [[-9.0, Color(0.2, 0.55, 0.55), false], [-3.0, Color(0.62, 0.05, 0.04), true], [3.0, Color(0.92, 0.88, 0.75), false], [9.0, Color(0.5, 0.7, 0.55), true]]
const TRUCK_ROW_Z: float = 6.5
const TRUCKS: Array = [[-9.0, Color(0.15, 0.3, 0.5)], [-3.0, Color(0.8, 0.55, 0.15)], [3.0, Color(0.3, 0.38, 0.25)], [9.0, Color(0.7, 0.68, 0.64)]]
const SNACK_BAR := Vector3(0.0, 0.0, 14.0)
const PICNIC := Vector3(8.6, 0.0, 12.6)
const LIGHT_POLES: Array[Vector3] = [Vector3(-16.0, 0.0, -9.0), Vector3(16.0, 0.0, -9.0), Vector3(-16.0, 0.0, 11.0), Vector3(16.0, 0.0, 11.0)]
const MARQUEE := Vector3(-13.0, 0.0, 28.6)
## Camera views: [name (after "CAM_"; the number sets the order), where it stands, what it looks at].
const CAMERAS: Array = [
	["01_Drive_In", Vector3(0.0, 6.4, 12.2), Vector3(0.0, 6.2, -17.0)],
	["02_Front_Row", Vector3(0.0, 1.3, -4.6), Vector3(0.0, 5.0, -17.0)],
	["03_From_The_Stage", Vector3(0.0, 3.0, -12.4), Vector3(0.0, 1.0, 8.0)],
	["04_Convertibles", Vector3(-14.5, 2.4, -4.8), Vector3(-2.0, 1.0, 0.0)],
	["05_Pickup_Beds", Vector3(14.5, 2.8, 2.6), Vector3(2.0, 1.2, 6.5)],
	["06_Snack_Bar", Vector3(9.8, 1.7, 17.6), Vector3(2.0, 1.8, 10.5)],
	["07_Marquee", Vector3(-4.0, 2.0, 38.5), Vector3(-13.0, 4.6, 28.6)],
	["08_Drone", Vector3(0.0, 26.0, 38.0), Vector3(0.0, 0.0, -8.0)],
	["09_Reaction", Vector3(0.0, 1.9, -8.6), Vector3(0.0, 1.9, -14.3)],
	["10_Red_Rocks", Vector3(0.0, 11.0, 8.0), Vector3(0.0, 14.0, -80.0)],
]


## Builds everything under `room`. Returns what route22_room.gd goes on using:
##   screen (MeshInstance3D "TVScreen"), marquee_words (Array[Label3D]: line 2 of both faces),
##   traffic_frame (Node3D laid along Route 22 for r22_traffic.gd).
static func build(room: Node3D, kit: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261116
	var set_root := Node3D.new()
	set_root.name = "Set"
	room.add_child(set_root)
	var markers := Node3D.new()
	markers.name = "Markers"
	room.add_child(markers)
	var rock := Geo.Buf.new()
	var props := Geo.Buf.new()
	var neon := Geo.Buf.new()
	var far := Geo.Buf.new()
	var labels := Node3D.new()
	labels.name = "Labels"
	set_root.add_child(labels)
	_ground(set_root, kit)
	_screen(set_root, props, out)
	_stage(set_root, markers, kit)
	_seats(props, markers, rng)
	_snack_bar(props, neon, labels, markers, kit)
	_lot_things(props, labels, room, rng)
	_marquee(props, neon, labels, kit, out)
	_rocks(rock, far, rng)
	_scans(rock, set_root, kit)
	Geo.add_mesh(set_root, "Rocks", rock, kit["rock"], true)
	Geo.add_mesh(set_root, "Props", props, kit["prop"], true)
	Geo.add_mesh(set_root, "Neon", neon, kit["neon"], false)
	Geo.add_mesh(set_root, "Far", far, kit["rock"], false)
	# brush round the lot (not on it, the road or the rocks' feet)
	var spots := PackedVector3Array()
	for i in 900:
		var p := Vector3(rng.randf_range(-170.0, 170.0), 0.0, rng.randf_range(-160.0, 120.0))
		var on_lot := p.x > LOT.x - 1.0 and p.x < LOT.z + 1.0 and p.z > LOT.y - 1.0 and p.z < LOT.w + 1.0
		if on_lot or absf(p.z - ROAD_Z) < 6.5:
			continue
		spots.append(p)
	Geo.scatter_brush(set_root, kit, spots, rng, {"creosote": 5.0, "sage": 3.0, "brittlebush": 2.0, "grass": 4.0, "cholla": 1.0, "yucca": 1.5})
	# Route 22: the road strip along X, and a frame for the traffic laid along it
	var road := MeshInstance3D.new()
	road.name = "Road"
	road.mesh = Geo.road_strip(3.9, -420.0, 420.0, 4.0)
	road.material_override = Geo.road_material(kit)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_root.add_child(road)
	road.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 0.005, ROAD_Z))
	var frame := Node3D.new()
	frame.name = "RoadFrame"
	room.add_child(frame)
	frame.transform = road.transform
	out["traffic_frame"] = frame
	_cameras(markers)
	return out


static func _ground(parent: Node3D, kit: Dictionary) -> void:
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = Geo.ground_sheet(500.0, -500.0, 500.0)
	var m := Geo.ground_material(kit)
	m.set_shader_parameter("lot_rect", LOT)
	m.set_shader_parameter("road_along_x", 1.0)
	m.set_shader_parameter("road_at", ROAD_Z)
	m.set_shader_parameter("shoulder", Geo.SHOULDER)
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g)


## The screen tower: a pale painted face on a steel frame, braced at the back, and TVScreen on it.
static func _screen(parent: Node3D, props: Geo.Buf, out: Dictionary) -> void:
	var w := SCREEN_SIZE.x + 1.6
	var top := SCREEN_BOTTOM + SCREEN_SIZE.y + 0.9
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(0.0, top * 0.5 + 0.6, SCREEN_Z - 0.35), Vector3(w, top - 1.2, 0.5), Color(0.86, 0.84, 0.8))
	props.block(Vector3(0.0, top + 0.1, SCREEN_Z - 0.3), Vector3(w + 0.4, 0.4, 0.8), Color(0.62, 0.12, 0.08))
	props.block(Vector3(0.0, 0.5, SCREEN_Z - 0.35), Vector3(w + 0.2, 1.0, 0.7), Color(0.6, 0.45, 0.35))
	props.mat = Geo.MAT_RUST
	var steel := Color(0.4, 0.38, 0.36)
	for i in 6:
		var x := lerpf(-w * 0.45, w * 0.45, float(i) / 5.0)
		props.rod(Vector3(x, 0.0, SCREEN_Z - 0.7), Vector3(x, top, SCREEN_Z - 0.7), 0.12, 6, steel)
		props.rod(Vector3(x, top * 0.8, SCREEN_Z - 0.7), Vector3(x, 0.0, SCREEN_Z - 5.5), 0.1, 6, steel)
		props.rod(Vector3(x, top * 0.4, SCREEN_Z - 0.7), Vector3(x, 0.0, SCREEN_Z - 3.5), 0.08, 5, steel)
	for y: float in [top * 0.3, top * 0.6, top * 0.9]:
		props.rod(Vector3(-w * 0.45, y, SCREEN_Z - 0.75), Vector3(w * 0.45, y, SCREEN_Z - 0.75), 0.07, 5, steel)
	props.mat = Geo.MAT_PAINT
	var sheet := QuadMesh.new()
	sheet.size = SCREEN_SIZE
	var screen := MeshInstance3D.new()
	screen.name = "TVScreen"
	screen.mesh = sheet
	screen.position = Vector3(0.0, SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, SCREEN_Z - 0.08)
	parent.add_child(screen)
	out["screen"] = screen


## The low stage under the screen, with steps, and four podiums on it (PODIUM_n, shown with
## their presenter; PRESENTER_n behind each, facing the lot).
static func _stage(parent: Node3D, markers: Node3D, kit: Dictionary) -> void:
	var b := Geo.Buf.new()
	b.mat = Geo.MAT_WOOD
	b.block(Vector3(0.0, STAGE_Y * 0.5, STAGE_Z - 1.4), Vector3(11.0, STAGE_Y, 3.2), Color(0.55, 0.38, 0.25))
	for i in 3:
		var y := STAGE_Y * float(i) / 3.0
		b.block(Vector3(0.0, y + STAGE_Y / 6.0, STAGE_Z + 0.35 + 0.35 * float(2 - i)), Vector3(3.0, STAGE_Y / 3.0, 0.35), Color(0.5, 0.35, 0.24))
	b.mat = Geo.MAT_PAINT
	b.block(Vector3(0.0, STAGE_Y - 0.06, STAGE_Z + 0.21), Vector3(11.0, 0.12, 0.02), Color(0.62, 0.12, 0.08))
	Geo.add_mesh(parent, "Stage", b, kit["prop"], true)
	var main_cam: Vector3 = CAMERAS[0][1]
	for i in 4:
		var x := lerpf(-3.4, 3.4, float(i) / 3.0)
		var at := Vector3(x, STAGE_Y, STAGE_Z - 1.0)
		var pod := Geo.Buf.new()
		pod.mat = Geo.MAT_PAINT
		# podium space: +Z = the way it faces (towards the lot)
		pod.block(Vector3(0.0, 0.52, 0.45), Vector3(0.8, 1.04, 0.45), Color(0.62, 0.08, 0.05))
		pod.block(Vector3(0.0, 1.07, 0.4), Vector3(0.9, 0.06, 0.6), Color(0.12, 0.1, 0.1))
		pod.mat = Geo.MAT_CHROME
		pod.block(Vector3(0.0, 0.85, 0.68), Vector3(0.82, 0.05, 0.02), Color(0.85, 0.85, 0.87))
		pod.block(Vector3(0.0, 0.2, 0.68), Vector3(0.82, 0.05, 0.02), Color(0.85, 0.85, 0.87))
		var marker := _facing(markers, "PRESENTER_%d" % (i + 1), at, main_cam)
		var mi := Geo.add_mesh(parent, "PODIUM_%d" % (i + 1), pod, kit["prop"], true)
		mi.transform = Transform3D(marker.transform.basis, at)


## The 30 chat seats: blankets and lawn chairs, convertibles, pickup beds, the picnic table.
static func _seats(props: Geo.Buf, markers: Node3D, rng: RandomNumberGenerator) -> void:
	var look := Vector3(0.0, 0.0, SCREEN_Z)
	var n := 0
	# 1-4: blankets on the front row; 5-8: lawn chairs behind them
	var blankets: Array[Color] = [Color(0.75, 0.15, 0.12), Color(0.15, 0.4, 0.6), Color(0.85, 0.65, 0.15), Color(0.3, 0.5, 0.3)]
	for i in 4:
		var x := lerpf(-5.0, 5.0, float(i) / 3.0)
		var at := Vector3(x, 0.0, -9.6)
		props.mat = Geo.MAT_CLOTH
		props.box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), at + Vector3(0.0, 0.015, 0.0)), Vector3(1.6, 0.03, 1.3), blankets[i])
		n += 1
		_facing(markers, "AUDIENCE_%02d" % n, at + Vector3(0.0, 0.05, 0.0), look)
	for i in 4:
		var x := lerpf(-5.4, 5.4, float(i) / 3.0)
		var at := Vector3(x, 0.0, -6.8)
		_lawn_chair(props, at, Color(0.2, 0.55, 0.55) if i % 2 == 0 else Color(0.9, 0.6, 0.2))
		n += 1
		_facing(markers, "AUDIENCE_%02d" % n, at + Vector3(0.0, 0.42, 0.0), look)
	# 9-16: the convertibles, front -Z (nosed up to the screen); two in each front seat
	for c: Array in CARS:
		var at := Vector3(float(c[0]), 0.0, CAR_ROW_Z)
		var car := Geo.Buf.new()
		var info := Vehicles.build("woody" if bool(c[2]) else "classic", {"all": car}, c[1], {"open": true}, rng)
		_append(props, car, Transform3D(Basis.IDENTITY, at))
		for s: Vector3 in [info["seats"][0], info["seats"][1]]:
			n += 1
			_facing(markers, "AUDIENCE_%02d" % n, at + s, look + Vector3(at.x * 0.6, 0.0, 0.0))
	# speaker posts between the cars and the trucks (a classic drive-in's window speakers)
	for z: float in [CAR_ROW_Z, TRUCK_ROW_Z]:
		for x: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			props.mat = Geo.MAT_RUST
			props.rod(Vector3(x, 0.0, z + 0.8), Vector3(x, 1.25, z + 0.8), 0.04, 5, Color(0.45, 0.45, 0.42))
			props.mat = Geo.MAT_PAINT
			for sx: float in [-0.14, 0.14]:
				props.block(Vector3(x + sx, 1.2, z + 0.8), Vector3(0.12, 0.2, 0.1), Color(0.55, 0.58, 0.55))
	# 17-28: pickups backed in (front +Z), tailgates down, three in each bed facing the screen
	for t: Array in TRUCKS:
		var at := Vector3(float(t[0]), 0.0, TRUCK_ROW_Z)
		var truck := Geo.Buf.new()
		var info := Vehicles.build("pickup", {"all": truck}, t[1], {"tailgate_down": true}, rng)
		var xf := Transform3D(Basis(Vector3.UP, PI), at)
		_append(props, truck, xf)
		# the cooler the third one sits on (r22_vehicles.gd pickup seats)
		props.mat = Geo.MAT_PAINT
		props.box(Transform3D(xf.basis, xf * Vector3(0.0, 0.84, 1.0)), Vector3(0.7, 0.22, 0.45), Color(0.15, 0.4, 0.75))
		for s: Vector3 in info["seats"]:
			n += 1
			_facing(markers, "AUDIENCE_%02d" % n, xf * s, look + Vector3(at.x * 0.6, 0.0, 0.0))
	# 29-30: the picnic table by the snack bar, both on the bench on its far side
	props.mat = Geo.MAT_WOOD
	var wood := Color(0.55, 0.4, 0.28)
	props.block(PICNIC + Vector3(0.0, 0.74, 0.0), Vector3(2.0, 0.06, 0.8), wood)
	for sz: float in [-0.65, 0.65]:
		props.block(PICNIC + Vector3(0.0, 0.43, sz), Vector3(2.0, 0.05, 0.3), wood)
	for sx: float in [-0.8, 0.8]:
		props.box(Transform3D(Basis(Vector3.RIGHT, 0.5), PICNIC + Vector3(sx, 0.37, 0.0)), Vector3(0.06, 0.85, 0.06), wood)
		props.box(Transform3D(Basis(Vector3.RIGHT, -0.5), PICNIC + Vector3(sx, 0.37, 0.0)), Vector3(0.06, 0.85, 0.06), wood)
	# (1.1 m apart: at least the default Seat spacing, or the room drops one)
	for sx: float in [-0.55, 0.55]:
		n += 1
		_facing(markers, "AUDIENCE_%02d" % n, PICNIC + Vector3(sx, 0.46, 0.65), look)
	props.mat = Geo.MAT_PAINT


## A folding lawn chair: aluminium tubes and striped webbing, facing -Z (the screen).
static func _lawn_chair(b: Geo.Buf, at: Vector3, col: Color) -> void:
	b.mat = Geo.MAT_CHROME
	var tube := Color(0.75, 0.76, 0.78)
	for sx: float in [-0.27, 0.27]:
		b.rod(at + Vector3(sx, 0.0, -0.25), at + Vector3(sx, 0.42, -0.2), 0.015, 4, tube)
		b.rod(at + Vector3(sx, 0.0, 0.25), at + Vector3(sx, 0.42, 0.2), 0.015, 4, tube)
		b.rod(at + Vector3(sx, 0.42, 0.2), at + Vector3(sx, 0.95, 0.32), 0.015, 4, tube)
	b.mat = Geo.MAT_CLOTH
	b.block(at + Vector3(0.0, 0.4, 0.0), Vector3(0.54, 0.03, 0.45), col)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.22), at + Vector3(0.0, 0.68, 0.26)), Vector3(0.54, 0.5, 0.03), col.darkened(0.15))
	b.mat = Geo.MAT_PAINT


## Copies a vehicle's Buf into the props Buf, placed by xf.
static func _append(into: Geo.Buf, from: Geo.Buf, xf: Transform3D) -> void:
	for i in from.verts.size():
		into.verts.append(xf * from.verts[i])
		into.normals.append(xf.basis * from.normals[i])
	into.colors.append_array(from.colors)
	into.uvs.append_array(from.uvs)


## The snack bar, with the projection booth on its roof (BEAM_Projector at its window), a neon
## "SNACKS" sign, and a counter window.
static func _snack_bar(props: Geo.Buf, neon: Geo.Buf, labels: Node3D, markers: Node3D, kit: Dictionary) -> void:
	Geo.building(props, SNACK_BAR, Vector3(9.0, 3.4, 6.0), PI, Color(0.92, 0.88, 0.78), Color(0.62, 0.12, 0.08), false, 3, true)
	props.mat = Geo.MAT_PAINT
	var booth := SNACK_BAR + Vector3(0.0, 3.6, -0.6)
	props.block(booth + Vector3(0.0, 1.1, 0.0), Vector3(3.2, 2.2, 3.0), Color(0.88, 0.84, 0.74))
	props.block(booth + Vector3(0.0, 2.3, 0.0), Vector3(3.6, 0.2, 3.4), Color(0.62, 0.12, 0.08))
	props.mat = Geo.MAT_GLASS
	props.block(booth + Vector3(0.0, 1.2, -1.51), Vector3(1.2, 0.6, 0.02), Color(0.2, 0.22, 0.25))
	var beam := Marker3D.new()
	beam.name = "BEAM_Projector"
	markers.add_child(beam)
	beam.transform = Transform3D(Basis.IDENTITY, booth + Vector3(0.0, 1.2, -1.6)).looking_at(Vector3(0.0, SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, SCREEN_Z), Vector3.UP)
	# the neon SNACKS sign over the counter, facing the lot
	neon.mat = Geo.MAT_LIGHT
	neon.block(SNACK_BAR + Vector3(0.0, 2.9, -3.05), Vector3(4.0, 0.7, 0.04), Color(1.0, 0.3, 0.2))
	Geo.add_words(labels, "SNACKS", SNACK_BAR + Vector3(0.0, 2.9, -3.1), PI, 0.55, Color(4.0, 3.4, 2.6), true)
	Geo.add_glow(kit, labels, SNACK_BAR + Vector3(0.0, 2.9, -3.3), Color(2.0, 0.6, 0.3), 4.0, true)
	props.mat = Geo.MAT_PAINT


## Lot light poles (the house lights), the ticket booth and its gate, an old gas pump, the fence
## along the road, telephone poles across the road, a Route 22 shield.
static func _lot_things(props: Geo.Buf, labels: Node3D, room: Node3D, rng: RandomNumberGenerator) -> void:
	var house := Node3D.new()
	house.name = "LIGHTS_House"
	room.add_child(house)
	var n := 0
	for p in LIGHT_POLES:
		props.mat = Geo.MAT_RUST
		props.rod(p + Vector3(0.0, -0.3, 0.0), p + Vector3(0.0, 7.5, 0.0), 0.1, 6, Color(0.45, 0.45, 0.47))
		var toward := Vector3(-signf(p.x), 0.0, 0.0) * 1.0
		props.rod(p + Vector3(0.0, 7.3, 0.0), p + Vector3(0.0, 7.3, 0.0) + toward, 0.05, 5, Color(0.45, 0.45, 0.47))
		props.mat = Geo.MAT_LIGHT
		props.block(p + Vector3(0.0, 7.2, 0.0) + toward, Vector3(0.5, 0.15, 0.3), Color(1.0, 0.85, 0.6))
		n += 1
		var lamp := Marker3D.new()
		lamp.name = "LAMP_Lot_%d" % n
		house.add_child(lamp)
		lamp.position = p + Vector3(0.0, 6.8, 0.0) + toward
	# the ticket booth at the entrance, with its gate arm, and the old gas pump beside it
	Geo.building(props, Vector3(-17.0, 0.0, 22.5), Vector3(2.4, 2.6, 2.4), PI * 0.5, Color(0.92, 0.88, 0.78), Color(0.62, 0.12, 0.08), true, 1, true)
	props.mat = Geo.MAT_PAINT
	props.block(Vector3(-15.5, 1.0, 22.5), Vector3(0.2, 2.0, 0.2), Color(0.85, 0.85, 0.82))
	for i in 6:
		props.block(Vector3(-15.5 + 0.5 + float(i) * 0.6, 1.9, 22.5), Vector3(0.6, 0.12, 0.08), Color(0.85, 0.1, 0.08) if i % 2 == 0 else Color(0.95, 0.95, 0.92))
	props.block(Vector3(-20.0, 0.9, 24.6), Vector3(0.6, 1.8, 0.45), Color(0.8, 0.12, 0.1))
	props.mat = Geo.MAT_GLASS
	props.block(Vector3(-20.0, 2.0, 24.6), Vector3(0.35, 0.4, 0.35), Color(0.9, 0.9, 0.85))
	props.mat = Geo.MAT_PAINT
	# the fence along the road, leaving the entrance open, and down the sides
	Geo.fence(props, -23.5, -21.0, 26.0, rng)
	Geo.fence(props, 23.5, -21.0, 26.0, rng)
	var f := Geo.Buf.new()
	Geo.fence(f, 0.0, -23.5, -18.0, rng)
	Geo.fence(f, 0.0, -10.0, 23.5, rng)
	_append(props, f, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 0.0, 26.5)))
	# telephone poles across the road, and a Route 22 shield by it
	var x := -120.0
	while x < 120.0:
		var tops := Geo.telephone_pole(props, Vector3(x, 0.0, ROAD_Z + 8.0), 8.0)
		for t in tops:
			Geo.wire(props, t, t + Vector3(40.0, 0.0, 0.0), 0.9)
		x += 40.0
	Geo.sign_board(props, Vector3(8.0, 2.3, ROAD_Z - 5.6), Vector2(0.75, 0.75), PI, Color(0.95, 0.95, 0.93), Color(0.1, 0.1, 0.1))
	Geo.add_words(labels, "ROUTE\n22", Vector3(8.0, 2.3, ROAD_Z - 5.64), PI, 0.2, Color(0.08, 0.08, 0.08))


## The marquee by the road: a tall double-sided sign on two posts with a neon border and arrow,
## "ROUTE 22 DRIVE-IN" in neon and a second line from the Marquee text setting on both faces.
static func _marquee(props: Geo.Buf, neon: Geo.Buf, labels: Node3D, kit: Dictionary, out: Dictionary) -> void:
	var c := MARQUEE
	props.mat = Geo.MAT_RUST
	for sx: float in [-2.6, 2.6]:
		props.rod(c + Vector3(sx, -0.3, 0.0), c + Vector3(sx, 7.6, 0.0), 0.16, 7, Color(0.5, 0.48, 0.45))
	props.mat = Geo.MAT_PAINT
	props.block(c + Vector3(0.0, 6.0, 0.0), Vector3(7.0, 2.2, 0.5), Color(0.12, 0.2, 0.3))
	props.block(c + Vector3(0.0, 3.9, 0.0), Vector3(6.4, 1.4, 0.35), Color(0.94, 0.92, 0.85))
	neon.mat = Geo.MAT_LIGHT
	for sz: float in [-0.27, 0.27]:
		neon.block(c + Vector3(0.0, 7.12, sz), Vector3(7.0, 0.06, 0.03), Color(1.0, 0.3, 0.6))
		neon.block(c + Vector3(0.0, 4.88, sz), Vector3(7.0, 0.06, 0.03), Color(1.0, 0.3, 0.6))
	# the arrow on top, pointing in at the entrance
	for i in 6:
		neon.block(c + Vector3(-2.0 + float(i) * 0.9, 8.1, 0.0), Vector3(0.5, 0.18, 0.18), Color(1.0, 0.75, 0.2))
	neon.block(c + Vector3(3.6, 8.1, 0.0), Vector3(0.3, 0.6, 0.18), Color(1.0, 0.75, 0.2))
	props.mat = Geo.MAT_RUST
	props.rod(c + Vector3(-2.2, 7.1, 0.0), c + Vector3(-2.2, 8.0, 0.0), 0.05, 4, Color(0.5, 0.48, 0.45))
	props.rod(c + Vector3(2.2, 7.1, 0.0), c + Vector3(2.2, 8.0, 0.0), 0.05, 4, Color(0.5, 0.48, 0.45))
	props.mat = Geo.MAT_PAINT
	var line2: Array[Label3D] = []
	for face: float in [1.0, -1.0]:
		var turn := 0.0 if face > 0.0 else PI
		Geo.add_words(labels, "ROUTE 22", c + Vector3(0.0, 6.5, 0.27 * face), turn, 0.75, Color(1.0, 3.6, 3.4), true)
		Geo.add_words(labels, "DRIVE-IN", c + Vector3(0.0, 5.55, 0.27 * face), turn, 0.6, Color(4.0, 1.2, 2.2), true)
		var l := Geo.add_words(labels, "", c + Vector3(0.0, 3.9, 0.19 * face), turn, 0.42, Color(0.08, 0.08, 0.1))
		l.width = 600.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line2.append(l)
		Geo.add_glow(kit, labels, c + Vector3(0.0, 6.1, 0.6 * face), Color(1.6, 0.6, 1.2), 7.0, true)
	out["marquee_words"] = line2


## Red sandstone behind the screen and round the lot: a big butte, fins, an arch, hoodoos, domes,
## a varnished cliff further back, boulders; buttes far out on every side.
static func _rocks(rock: Geo.Buf, far: Geo.Buf, rng: RandomNumberGenerator) -> void:
	Geo.butte(rock, Vector3(-34.0, 0.0, -78.0), Vector3(62.0, 40.0, 40.0), 3.0, 30, 0.2)
	Geo.butte(rock, Vector3(42.0, 0.0, -95.0), Vector3(48.0, 30.0, 34.0), 11.0, 28, -0.3)
	Geo.fin(rock, Vector3(22.0, 0.0, -48.0), 26.0, 14.0, 2.4, 5.0, 0.25)
	Geo.fin(rock, Vector3(34.0, 0.0, -40.0), 18.0, 10.0, 2.0, 9.0, 0.4)
	Geo.fin(rock, Vector3(-14.0, 0.0, -44.0), 16.0, 11.0, 2.0, 13.0, -0.3)
	Geo.arch(rock, Vector3(62.0, 0.0, -60.0), 20.0, 12.0, 2.6, 21.0, 0.5)
	for i in 6:
		var at := Vector3(rng.randf_range(-60.0, -30.0), 0.0, rng.randf_range(-40.0, 0.0))
		var h := rng.randf_range(4.0, 9.0)
		Geo.hoodoo(rock, at, h, h * 0.15, float(i) * 3.0)
	for i in 4:
		var r := rng.randf_range(6.0, 11.0)
		Geo.dome(rock, Vector3(rng.randf_range(32.0, 70.0), 0.0, rng.randf_range(-20.0, 20.0)), r, r * 0.9, float(i) * 7.0)
	Geo.balanced_rock(rock, Vector3(-42.0, 0.0, 14.0), 4.5, 2.0, rng)
	Geo.wall(rock, -150.0, -20.0, -60.0, -1.0, 26.0, 40.0, 3.0, 31.0, 1.0, 0.3, 0.3)
	for i in 30:
		var at := Vector3(rng.randf_range(-70.0, 70.0), 0.0, rng.randf_range(-70.0, -24.0))
		Geo.boulder(rock, at, rng.randf_range(0.5, 2.5), float(i), rng.randf() * TAU)
	for i in 10:
		var a := TAU * float(i) / 10.0 + rng.randf() * 0.4
		var d := rng.randf_range(220.0, 330.0)
		Geo.butte(far, Vector3(sin(a) * d, 0.0, -cos(a) * d), Vector3(rng.randf_range(50.0, 120.0), rng.randf_range(25.0, 60.0), rng.randf_range(40.0, 80.0)), float(i) * 13.0, 26, rng.randf() * TAU)


## The photo-scanned models (models/, CC0 Poly Haven scans; Geo.scan_rock / scan_prop): boulders
## among the sandstone behind the screen and outside the fence, stone litter along the fence,
## oil drums by the snack bar and the gas pump, and dead wood out in the brush. Their own random
## numbers, so the rest of the set (and the brush) is laid out as before.
static func _scans(rock: Geo.Buf, parent: Node3D, kit: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2222
	# boulders behind the screen, among the procedural ones (scale 1 = about 2.5 m across)
	for i in 36:
		var at := Vector3(rng.randf_range(-70.0, 70.0), 0.0, rng.randf_range(-70.0, -24.0))
		var s := rng.randf_range(0.4, 1.8)
		Geo.scan_rock(rock, Geo.SCAN_ROCKS[i % 5], at, Vector3(s, s * rng.randf_range(0.8, 1.3), s), rng.randf() * TAU)
	# smaller ones outside the side fences (the lot is x -23..23, the fence at +-23.5)
	for i in 18:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(26.0, 45.0), 0.0, rng.randf_range(-20.0, 24.0))
		var s := rng.randf_range(0.3, 1.0)
		Geo.scan_rock(rock, Geo.SCAN_ROCKS[i % 5], at, Vector3(s, s, s), rng.randf() * TAU)
	# stone litter along the outside of the fences
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(24.5, 27.0), 0.0, rng.randf_range(-19.0, 25.0))
		var s := rng.randf_range(2.5, 4.0)
		Geo.scan_rock(rock, "stones" if i % 3 else "pile", at, Vector3(s, s, s), rng.randf() * TAU, 0.1, 0.05)
	# oil drums: behind the snack bar's east corner (seen from the Snack Bar camera) and by the
	# old gas pump at the entrance
	var sb := SNACK_BAR
	Geo.scan_prop(parent, kit, "barrel", sb + Vector3(5.2, 0.0, 1.6), 1.0, 0.4)
	Geo.scan_prop(parent, kit, "barrel_rusty", sb + Vector3(5.4, 0.0, 2.5), 1.0, 2.1)
	Geo.scan_prop(parent, kit, "barrel", sb + Vector3(-5.3, 0.0, 2.2), 1.0, 1.2)
	Geo.scan_prop(parent, kit, "barrel_rusty", Vector3(-21.0, 0.0, 25.3), 1.0, 0.9)
	# dead wood out in the brush beyond the fences
	Geo.scan_prop(parent, kit, "dead_trunk", Vector3(-28.0, 0.0, 6.0), 1.6, 0.5)
	Geo.scan_prop(parent, kit, "dead_trunk", Vector3(31.0, 0.0, -14.0), 1.3, 2.4)
	Geo.scan_prop(parent, kit, "dry_branches", Vector3(-26.5, 0.0, -6.0), 1.4, 1.0)
	Geo.scan_prop(parent, kit, "dry_branches", Vector3(27.5, 0.0, 17.0), 1.2, 3.6)
	Geo.scan_prop(parent, kit, "dry_branches", Vector3(-31.0, 0.0, 19.0), 1.6, 5.1)


static func _cameras(markers: Node3D) -> void:
	for c: Array in CAMERAS:
		var cam := Marker3D.new()
		cam.name = "CAM_" + String(c[0])
		markers.add_child(cam)
		cam.transform = Transform3D(Basis.IDENTITY, c[1]).looking_at(c[2], Vector3.UP)
	# reaction targets (!tomato stage / snacks / marquee; "screen" is every room's own already)
	_facing(markers, "TARGET_Stage", Vector3(0.0, STAGE_Y + 1.2, STAGE_Z - 0.4), Vector3(0.0, 0.0, 10.0))
	_facing(markers, "TARGET_Snacks", SNACK_BAR + Vector3(0.0, 2.0, -3.2), Vector3(0.0, 0.0, 0.0))
	_facing(markers, "TARGET_Marquee", MARQUEE + Vector3(0.0, 6.0, 0.5), Vector3(0.0, 0.0, 0.0))


## A marker at `at` whose +Z axis points (level) at `toward`.
static func _facing(parent: Node3D, node_name: String, at: Vector3, toward: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	parent.add_child(m)
	var dir := toward - at
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	m.transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), at)
	return m
