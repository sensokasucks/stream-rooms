extends Node3D
## The Cruise rooms' dashboard bobbleheads: a small copy of every presenter who is riding in the
## woody, standing on the dash top on a little base and spring, nodding with the road.
## Both Cruises make one (route22_cruise_room.gd, route81_room.gd), add it to the car
## (r22_car.gd, so it is in the car's space: +X = the passenger's side, -Z = the hood) and call
## tick() every frame.
##
## A bobblehead shows the presenter's own picture: it wears the very material of the picture on
## the seat (core/presenters/presenter.gd get_picture()), so the live feed, the chroma key and
## the zoom are the same and cost nothing extra. It shows only while its presenter is on.
##
## Settings (AppState.DEFAULTS, shared in a co-stream through NetSession.SHARED_BASE; the
## controls are controls() below, under "Dashboard bobbleheads" on the Room tab):
##   r22_bobbles          on / off for all four
##   r22_bobble_size      how big they are (1 = about 17 cm tall)
##   r22_bobble_wobble    how much they nod (0 = they stand still)
##   r22_bobble_<n>_x     presenter n's bobblehead: across the dash, metres from the middle
##   r22_bobble_<n>_z     forward (+, toward the windscreen) or back (toward the riders), metres
##   r22_bobble_<n>_y     lifted above the dash top, metres
##   r22_bobble_<n>_turn  turned on its base, degrees (0 = facing the hood like the riders;
##                        180 = facing the riders)
## The presenter shader draws both faces of a picture, so a bobblehead turned away from a
## camera still shows its picture, mirrored.

const Geo := preload("res://rooms/route22/r22_geo.gd")
## The dash top in the car's space, metres: its height and the line the bobbleheads stand on at
## "forward" 0. Must stay in step with the woody's DashPad in models/make_woody.py (the model's
## y is -z here).
const DASH_Y: float = 1.0
const DASH_Z: float = -0.74
## A bobblehead's picture at size 1, metres (width is set from the room's presenter picture so
## the feed is cropped the same way), and its base.
const HEAD_H: float = 0.15
const BASE_R: float = 0.026
const BASE_H: float = 0.012
const SPRING_H: float = 0.018
## The head's spring: how stiffly it comes back upright (1/s²) and how fast its nodding dies
## away (1/s). About two nods a second, a few seconds to settle.
const STIFF: float = 160.0
const DAMP: float = 2.2
## How far a head may lean, radians.
const MAX_LEAN: float = 0.5

## One entry per presenter: {"root": Node3D on the dash, "head": Node3D on the spring's top,
## "pic": MeshInstance3D, "lean": Vector2 (radians: x = nod, y = side to side), "vel": Vector2}
var _bobs: Array[Dictionary] = []
var _room: Node                   # the Room, to find RoomHost's "Presenters" node in
var _aspect: float = 1.04         # the presenter picture's width / height
var _time: float = 0.0
var _seed: float = 0.0


## room: the Room this car is in; presenter_size: its Room.presenter_size (the picture's shape).
func setup(room: Node, presenter_size: Vector2) -> void:
	name = "Bobbleheads"
	_room = room
	_aspect = presenter_size.x / maxf(presenter_size.y, 0.01)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.06, 0.06, 0.065)
	base_mat.roughness = 0.45
	var spring_mat := StandardMaterial3D.new()
	spring_mat.albedo_color = Color(0.75, 0.76, 0.78)
	spring_mat.metallic = 0.9
	spring_mat.roughness = 0.3
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var root := Node3D.new()
		root.name = "Bobble%d" % n
		add_child(root)
		var base := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = BASE_R * 0.9
		disc.bottom_radius = BASE_R
		disc.height = BASE_H
		disc.radial_segments = 16
		base.mesh = disc
		base.material_override = base_mat
		base.position.y = BASE_H * 0.5
		root.add_child(base)
		var spring := MeshInstance3D.new()
		var coil := CylinderMesh.new()
		coil.top_radius = 0.005
		coil.bottom_radius = 0.005
		coil.height = SPRING_H
		coil.radial_segments = 8
		spring.mesh = coil
		spring.material_override = spring_mat
		spring.position.y = BASE_H + SPRING_H * 0.5
		root.add_child(spring)
		# the head leans about the spring's top
		var head := Node3D.new()
		head.name = "Head"
		head.position.y = BASE_H + SPRING_H
		root.add_child(head)
		var pic := MeshInstance3D.new()
		pic.name = "Picture"
		var quad := QuadMesh.new()
		quad.size = Vector2(HEAD_H * _aspect, HEAD_H)
		pic.mesh = quad
		pic.position.y = HEAD_H * 0.5
		# (the presenter's picture faces +Z in its own space and the riders face the hood)
		pic.rotation.y = PI
		pic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(pic)
		_bobs.append({"root": root, "head": head, "pic": pic, "lean": Vector2.ZERO, "vel": Vector2.ZERO})
	_seed = randf() * 100.0
	EventBus.setting_changed.connect(_on_setting_changed)
	_place()


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_setting_changed):
		EventBus.setting_changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("r22_bobble"):
		_place()


## Puts every bobblehead where its sliders say (called at setup and when one of them changes).
func _place() -> void:
	var grow := clampf(float(AppState.get_setting("r22_bobble_size")), 0.3, 4.0)
	for i in _bobs.size():
		var root: Node3D = _bobs[i]["root"]
		var key := "r22_bobble_%d_" % (i + 1)
		root.position = Vector3(float(AppState.get_setting(key + "x")), DASH_Y + float(AppState.get_setting(key + "y")),
			DASH_Z - float(AppState.get_setting(key + "z")))
		root.rotation.y = deg_to_rad(float(AppState.get_setting(key + "turn")))
		root.scale = Vector3.ONE * grow


## The Presenter node of podium n (RoomHost adds the "Presenters" stage to the room after the
## room is built, so it is looked up as needed), or null.
func _presenter(n: int) -> Presenter:
	var stage := _room.get_node_or_null("Presenters") as PresenterStage if _room else null
	return stage.get_presenter(n) if stage else null


## Every frame, from the room. speed: the car's, metres a second; bend / hill: the road's
## (r22_trip.gd / r81_trip.gd `bend`, `hill`), whose changes push the heads over.
func tick(delta: float, speed: float, bend: float, hill: float) -> void:
	_time += delta
	var on := bool(AppState.get_setting("r22_bobbles"))
	var wobble := clampf(float(AppState.get_setting("r22_bobble_wobble")), 0.0, 3.0)
	var moving := clampf(speed / 14.0, 0.0, 1.5)
	var step := minf(delta, 0.05)
	for i in _bobs.size():
		var bob := _bobs[i]
		var root: Node3D = bob["root"]
		var presenter := _presenter(i + 1) if on else null
		root.visible = presenter != null and presenter.visible
		if not root.visible:
			continue
		var pic: MeshInstance3D = bob["pic"]
		var source := presenter.get_picture()
		if source and pic.material_override != source.material_override:
			pic.material_override = source.material_override
		# The road shakes each head a little differently (two slow waves, each head its own
		# pace), and a bend or a dip leans them all; the spring brings them back.
		var pace := 1.0 + 0.17 * float(i)
		var push := Vector2(sin(_time * 5.3 * pace + _seed + float(i) * 2.1) + 0.6 * sin(_time * 11.7 * pace + float(i)),
			sin(_time * 4.1 * pace + _seed * 1.7 + float(i) * 1.3) + 0.6 * sin(_time * 9.3 * pace + 2.0 + float(i)))
		push *= 9.0 * moving * wobble
		push.y += clampf(bend * 2000.0, -1.0, 1.0) * 8.0 * moving * wobble
		push.x += clampf(hill * 8000.0, -1.0, 1.0) * 6.0 * moving * wobble
		var lean: Vector2 = bob["lean"]
		var vel: Vector2 = bob["vel"]
		vel += (push - STIFF * lean - DAMP * vel) * step
		lean += vel * step
		lean = lean.clampf(-MAX_LEAN, MAX_LEAN)
		bob["lean"] = lean
		bob["vel"] = vel
		var head: Node3D = bob["head"]
		head.rotation = Vector3(lean.x, 0.0, lean.y)


## The Room tab's controls for the bobbleheads (both Cruise rooms append them to get_controls()).
static func controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"heading": "Dashboard bobbleheads"},
		{"key": "r22_bobbles", "label": "Bobbleheads on the dashboard", "type": "check",
			"tooltip": "A little bobblehead of every presenter who is in the car stands on the dashboard and nods with the road. It shows the same picture as the presenter in the seat."},
		{"key": "r22_bobble_size", "label": "Bobblehead size", "min": 0.5, "max": 3.0, "step": 0.05, "format": "%d%%", "scale": 100.0,
			"tooltip": "How big the bobbleheads are. 100% = about 17 cm tall."},
		{"key": "r22_bobble_wobble", "label": "Wobble", "min": 0.0, "max": 3.0, "step": 0.05, "format": "%d%%", "scale": 100.0, "zero": "Standing still",
			"tooltip": "How much the heads nod while the car drives. 0% = they stand still. They also settle when the car is parked."},
	]
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var key := "r22_bobble_%d_" % n
		out.append_array([
			{"key": key + "x", "label": "Bobblehead %d: left / right" % n, "min": -0.8, "max": 0.8, "step": 0.01, "format": "%d cm", "scale": 100.0,
				"tooltip": "Where presenter %d's bobblehead stands across the dashboard, from the middle. Minus = toward the driver's side, plus = toward the passenger's side." % n},
			{"key": key + "z", "label": "Bobblehead %d: forward / back" % n, "min": -0.6, "max": 1.6, "step": 0.01, "format": "%d cm", "scale": 100.0,
				"tooltip": "Moves presenter %d's bobblehead toward the windscreen and out onto the hood (plus) or back toward the riders (minus). 0 = the middle of the dash top." % n},
			{"key": key + "y", "label": "Bobblehead %d: height" % n, "min": -0.3, "max": 0.6, "step": 0.01, "format": "%d cm", "scale": 100.0,
				"tooltip": "Lifts presenter %d's bobblehead above the dash top (or sinks it below, for the hood). 0 = standing on the dash." % n},
			{"key": key + "turn", "label": "Bobblehead %d: turn" % n, "min": -180.0, "max": 180.0, "step": 1.0, "format": "%d°",
				"tooltip": "Turns presenter %d's bobblehead on its base. 0° = facing forward like the riders (toward the Windshield camera); 180° = facing the riders." % n},
		])
	return out
