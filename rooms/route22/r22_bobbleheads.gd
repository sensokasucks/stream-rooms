extends Node3D
## Bobbleheads on the woody's dashboard (both Cruise rooms: the desert's route22_cruise_room.gd
## and route81_room.gd, which make one with setup() and call tick() every frame). Each is a
## little copy of one of the riders (presenters 1 to 4): a black base, a spring, and on top of
## the spring the rider's own picture (the presenter's picture material, shared, so it shows
## the same live feed, key and silhouette as the rider in the seat), which nods and sways on
## the spring as the car brakes, speeds up, takes the curves and hits bumps. (Sen, round 5.)
## Only riders who are on (presenter_<n>_on) get one.
##
## It is a child of the car's body (r22_car.gd get_body()), so it rides the body's own sway.
## The car's front is -Z; the dash pad's top is at DASH (car space).
##
## Settings (AppState.DEFAULTS, shared in a co-stream so every PC sees the same dashboard):
##   r22_bob_on      show them,
##   r22_bob_size    how big (1 = about 17 cm tall),
##   r22_bob_wobble  how much they bob (0 = stand still .. 3 = wildly),
##   r22_bob_<n>_x / _z / _turn   where bobblehead n stands along the dash (metres from its
##                   middle, + = the passenger side), how far forward or back (metres, + = towards
##                   the riders) and which way it faces (degrees; 0 = out through the windscreen,
##                   towards the Windshield camera; 180 = towards the riders).
## controls() lists the Room tab's controls for these; both Cruise rooms add them.

## Where the dash pad's top middle is in the car's space (the woody, models/make_woody.py
## "DashPad"), and how far the bobbleheads may be moved from it (sideways, forward/back).
const DASH := Vector3(0.0, 1.0, -0.76)
const REACH_X: float = 0.8
const REACH_Z: float = 0.3
## Height of a bobblehead at size 1, metres: the base, the spring, the picture.
const BASE_H: float = 0.012
const SPRING_H: float = 0.035
const PICTURE_H: float = 0.13
## How stiff the spring is (per second², for the tilt) and how quickly a swing dies down (per
## second). Low stiffness and damping = the long, loose wobble of a real bobblehead.
const STIFF: float = 55.0
const DAMP: float = 2.2
## Largest tilt, radians (the picture never lies flat).
const MAX_TILT: float = 0.7

var _room: Node                         # the room (its "Presenters" child is where the riders are)
var _bobs: Array[Dictionary] = []       # per rider: {"root", "pivot", "picture", "tilt", "spin"}
var _last_speed: float = 0.0
var _bump_in: float = 0.0
var _rng := RandomNumberGenerator.new()


## room: the Cruise room (RoomHost adds its "Presenters" after loading). body: the car's body.
func setup(room: Node, body: Node3D) -> void:
	_room = room
	name = "Bobbleheads"
	body.add_child(self)
	_rng.seed = 2222
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.05, 0.05, 0.055)
	base_mat.roughness = 0.4
	var spring_mat := StandardMaterial3D.new()
	spring_mat.albedo_color = Color(0.75, 0.76, 0.78)
	spring_mat.metallic = 0.9
	spring_mat.roughness = 0.3
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var root := Node3D.new()
		root.name = "Bobblehead%d" % n
		add_child(root)
		var base := MeshInstance3D.new()
		var puck := CylinderMesh.new()
		puck.top_radius = 0.028
		puck.bottom_radius = 0.032
		puck.height = BASE_H
		base.mesh = puck
		base.material_override = base_mat
		base.position = Vector3(0.0, BASE_H * 0.5, 0.0)
		root.add_child(base)
		# the spring: a thin coil of short rods
		var b := preload("res://rooms/route22/r22_geo.gd").Buf.new()
		var turns := 6.0
		var steps := 36
		for i in steps:
			var a0 := TAU * turns * float(i) / float(steps)
			var a1 := TAU * turns * float(i + 1) / float(steps)
			var p0 := Vector3(0.009 * cos(a0), BASE_H + SPRING_H * float(i) / float(steps), 0.009 * sin(a0))
			var p1 := Vector3(0.009 * cos(a1), BASE_H + SPRING_H * float(i + 1) / float(steps), 0.009 * sin(a1))
			b.rod(p0, p1, 0.0016, 3, Color.WHITE)
		var spring := MeshInstance3D.new()
		spring.mesh = b.to_mesh()
		spring.material_override = spring_mat
		root.add_child(spring)
		# the picture turns round the spring's top (its pivot)
		var pivot := Node3D.new()
		pivot.name = "Pivot"
		pivot.position = Vector3(0.0, BASE_H + SPRING_H, 0.0)
		root.add_child(pivot)
		var picture := MeshInstance3D.new()
		picture.name = "Picture"
		picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(picture)
		root.visible = false
		_bobs.append({"root": root, "pivot": pivot, "picture": picture, "tilt": Vector2.ZERO, "spin": Vector2.ZERO, "source": null})


## Called every frame by the room. speed = metres a second of the road, bend = the road's
## sideways curve ahead (r22_common.gdshaderinc: metres of shift per metre squared; the turn the
## car is in, near enough), delta = seconds.
func tick(delta: float, speed: float, bend: float) -> void:
	var on := bool(AppState.get_setting("r22_bob_on"))
	visible = on
	if not on or delta <= 0.0:
		_last_speed = speed
		return
	var size := clampf(float(AppState.get_setting("r22_bob_size")), 0.3, 3.0)
	var wobble := clampf(float(AppState.get_setting("r22_bob_wobble")), 0.0, 3.0)
	# What the car does to them, in the car's directions (x = sideways, y = along the car, + =
	# back towards the riders): speeding up throws the heads back, braking forward (m/s²); a
	# curve throws them outwards (the road ahead shifts by bend * d², so it turns towards +X at
	# 2 * bend radians a metre, and the push is the other way, speed² times that); bumps come
	# now and then, more often the faster the car goes, and kick them (radians a second).
	var accel := (speed - _last_speed) / delta
	_last_speed = speed
	var side := -2.0 * bend * speed * speed
	# (scaled so 3 m/s² of braking tips them about 0.15 rad and a brisk curve about 0.1)
	var push := Vector2(side * 9.0, accel * 2.5)
	var kick := Vector2.ZERO
	_bump_in -= delta
	if _bump_in <= 0.0 and speed > 1.0:
		_bump_in = _rng.randf_range(0.4, 2.2) * 14.0 / maxf(speed, 6.0)
		kick = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 1.0)) * clampf(speed / 25.0, 0.2, 1.0) * 1.6
	var stage := _room.get_node_or_null("Presenters") if _room else null
	for i in _bobs.size():
		var bob: Dictionary = _bobs[i]
		var n := i + 1
		var root := bob["root"] as Node3D
		var presenter: Node3D = stage.call("get_presenter", n) if stage else null
		var shows := presenter != null and presenter.visible
		root.visible = shows
		if not shows:
			continue
		_dress(bob, presenter)
		# where it stands and which way it faces
		var x := clampf(float(AppState.get_setting("r22_bob_%d_x" % n)), -REACH_X, REACH_X)
		var z := clampf(float(AppState.get_setting("r22_bob_%d_z" % n)), -REACH_Z, REACH_Z)
		var turn := deg_to_rad(float(AppState.get_setting("r22_bob_%d_turn" % n)))
		root.transform = Transform3D(Basis(Vector3.UP, turn + PI).scaled(Vector3.ONE * size), DASH + Vector3(x, 0.0, z))
		# the spring: tilt (x = sideways, y = forward/back) pulled back to upright, pushed by
		# the car (in the car's directions, turned into the bobblehead's own) and the bumps;
		# each one a little different, so they do not all nod in step
		var own := 0.85 + 0.3 * float(i) / 3.0
		var tilt: Vector2 = bob["tilt"]
		var spin: Vector2 = bob["spin"]
		# (Vector2.rotated by the yaw turns a car-space (x, z) into the bobblehead's own)
		var yaw := turn + PI
		spin += kick.rotated(yaw) * own * wobble
		spin += (push.rotated(yaw) * wobble - tilt * STIFF * own) * delta
		spin *= exp(-DAMP * delta)
		tilt += spin * delta
		tilt = tilt.limit_length(MAX_TILT)
		bob["tilt"] = tilt
		bob["spin"] = spin
		var pivot := bob["pivot"] as Node3D
		pivot.basis = Basis(Vector3.FORWARD, tilt.x) * Basis(Vector3.RIGHT, tilt.y)


## Gives a bobblehead the rider's picture: the same material as the picture in the seat (it
## follows the feed by itself), on a square of the same shape, standing on its bottom edge.
func _dress(bob: Dictionary, presenter: Node3D) -> void:
	var seat_picture: MeshInstance3D = presenter.call("get_picture")
	if seat_picture == null or bob["source"] == seat_picture:
		return
	bob["source"] = seat_picture
	var quad := QuadMesh.new()
	var shape := Vector2(1.0, 1.0)
	if seat_picture.mesh is QuadMesh:
		shape = (seat_picture.mesh as QuadMesh).size
	quad.size = Vector2(PICTURE_H * shape.x / maxf(shape.y, 0.01), PICTURE_H)
	var picture := bob["picture"] as MeshInstance3D
	picture.mesh = quad
	picture.material_override = seat_picture.material_override
	picture.position = Vector3(0.0, PICTURE_H * 0.5, 0.0)


## The Room tab's controls for the bobbleheads (both Cruise rooms add these to theirs).
static func controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"heading": "Bobbleheads"},
		{"key": "r22_bob_on", "label": "Bobbleheads on the dashboard", "type": "check",
			"tooltip": "Little copies of the riders on springs on the woody's dashboard, showing the same picture as each rider in the seat (only riders who are on). They nod and sway as the car speeds up, brakes, takes the curves and hits bumps."},
		{"key": "r22_bob_size", "label": "Size", "min": 0.3, "max": 3.0, "step": 0.05, "format": "%d%%", "scale": 100.0,
			"tooltip": "How big the bobbleheads are. 100% = about 17 cm tall, toy size."},
		{"key": "r22_bob_wobble", "label": "Wobble", "min": 0.0, "max": 3.0, "step": 0.05, "format": "%d%%", "scale": 100.0, "zero": "Still",
			"tooltip": "How much they bob about. 100% = a loose spring; 300% = wildly; 0 = they stand still."},
	]
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		out.append_array([
			{"key": "r22_bob_%d_x" % n, "label": "%d: sideways" % n, "min": -REACH_X, "max": REACH_X, "step": 0.01, "format": "%d cm", "scale": 100.0,
				"tooltip": "Where rider %d's bobblehead stands along the dashboard: centimetres from its middle, minus = the driver's side, plus = the passenger's." % n},
			{"key": "r22_bob_%d_z" % n, "label": "%d: forward / back" % n, "min": -REACH_Z, "max": REACH_Z, "step": 0.01, "format": "%d cm", "scale": 100.0,
				"tooltip": "Moves rider %d's bobblehead forward towards the windscreen (minus) or back towards the riders (plus), in centimetres." % n},
			{"key": "r22_bob_%d_turn" % n, "label": "%d: turn" % n, "min": -180.0, "max": 180.0, "step": 1.0, "format": "%d°",
				"tooltip": "Which way rider %d's bobblehead faces, in degrees. 0 = out through the windscreen (towards the Windshield camera); 180 = towards the riders." % n},
		])
	return out
