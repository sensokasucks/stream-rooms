class_name CameraRig
extends Camera3D
## Camera presets from the room's CAM_* markers, with smooth moves between them,
## plus free-look (hold right mouse, WASD / Q-E, Shift = faster).
## During a react pause it can jump to the room's "Reaction" preset and return after.
## The CameraRig node in core/main.tscn. main.gd hands it each new room (set_presets, set_room);
## the number keys arrive as EventBus.camera_preset_requested (hotkeys.gd).

## Seconds a smooth move between presets takes.
@export var move_time: float = 0.9
## Radians of turn per pixel of mouse movement while right-dragging.
@export var look_sensitivity: float = 0.0025
## Free-look flying speed in metres per second (Shift = 3x).
@export var move_speed: float = 2.5
## See-through: when a wall is between the camera and the inside of the room, the near clip
## plane moves to that wall's inner face, so you look into the room (a cutaway) instead of at
## the back of the wall. "Inside" = the room's camera markers; the walls get collision shapes
## on WALL_LAYER (only used for these rays).
const WALL_LAYER: int = 1 << 19
## Normal near clip distance in metres, used whenever the camera is inside the room.
const BASE_NEAR: float = 0.05
## Field of view limits in degrees (setting "camera_fov").
const FOV_MIN: float = 25.0
const FOV_MAX: float = 110.0

var _presets: Array[Transform3D] = []
var _labels: PackedStringArray = []
var _reaction_index: int = -1          # preset whose label contains "reaction" (-1 = none)
var _pre_react_transform: Transform3D  # where the camera was before the react pause moved it
var _pre_react_valid: bool = false
var _tween: Tween
var _yaw: float = 0.0                  # free-look angles in radians, kept in step by _sync_angles
var _pitch: float = 0.0
var _looking: bool = false
var _shake_left: float = 0.0           # seconds of shake left (of _shake_total)
var _shake_total: float = 0.0
var _shake_strength: float = 0.0
var _probes: Array[Vector3] = []       # points inside the room (camera markers)
var _last_inside: Variant = null       # last camera position that was inside the room


func _ready() -> void:
	EventBus.camera_preset_requested.connect(go_to_preset)
	EventBus.react_pause_changed.connect(_on_react_pause_changed)
	EventBus.camera_shake_requested.connect(shake)
	EventBus.setting_changed.connect(func(k: String, _v: Variant) -> void:
		if k == "camera_fov":
			fov = clampf(float(AppState.get_setting("camera_fov")), FOV_MIN, FOV_MAX))
	fov = clampf(float(AppState.get_setting("camera_fov")), FOV_MIN, FOV_MAX)
	near = BASE_NEAR


## Called by main when a room is ready: collision for its walls (see-through rays) and the
## points that count as "inside".
func set_room(room: Room) -> void:
	_probes.clear()
	_last_inside = null
	for m in room.get_camera_markers():
		_probes.append(m.global_position)
	# a trimesh collider per static mesh, so the see-through rays can find the walls
	for mi in room.get_static_meshes():
		# (already done: the room was loaded before)
		if mi.find_child("*_wall_col", false, false):
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = mi.name + "_wall_col"
		body.collision_layer = WALL_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)


# ── Public API ───────────────────────────────────────────────
## Called by main when a room is ready (parent wiring). markers / labels: the room's camera
## markers in order (key 1 = first). Jumps to the first preset.
func set_presets(markers: Array[Node3D], labels: PackedStringArray) -> void:
	_presets.clear()
	_labels = labels
	_reaction_index = -1
	for i in markers.size():
		_presets.append(markers[i].global_transform.orthonormalized())
		if labels[i].to_lower().contains("reaction"):
			_reaction_index = i
	_pre_react_valid = false
	if not _presets.is_empty():
		go_to_preset(0, false)


## Moves to preset `index` (0-based; out of range is ignored). Also EventBus.camera_preset_requested.
func go_to_preset(index: int, smooth: bool = true) -> void:
	if index < 0 or index >= _presets.size():
		return
	_move_to(_presets[index], smooth)


## A short shake (chat reaction). Uses the lens offset, so it never fights camera moves.
## From EventBus.camera_shake_requested (ReactionLayer). strength 0..2, seconds 0.05..3.
## Off when "reaction_camera_shake" is off or in photosensitive-safe mode (CLAUDE.md rule).
func shake(strength: float, seconds: float) -> void:
	if not bool(AppState.get_setting("reaction_camera_shake")) or bool(AppState.get_setting("photosensitive_safe")):
		return
	_shake_strength = clampf(strength, 0.0, 2.0) * 0.06
	_shake_total = clampf(seconds, 0.05, 3.0)
	_shake_left = _shake_total


# ── Input: free-look ─────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		if _looking:
			_kill_tween()
			_sync_angles()
			get_viewport().gui_release_focus()
	elif event is InputEventMouseButton and _looking and event.pressed and \
			event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# zoom: field of view while right-dragging
		var step := -3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3.0
		AppState.set_setting("camera_fov", clampf(float(AppState.get_setting("camera_fov")) + step, FOV_MIN, FOV_MAX))
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * look_sensitivity
		_pitch = clampf(_pitch - event.relative.y * look_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		rotation = Vector3(_pitch, _yaw, 0.0)


## Shake and see-through every frame, then WASD / Q-E flying (not while typing in a text box).
func _process(delta: float) -> void:
	_update_shake(delta)
	_update_near()
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_Q): input.y -= 1.0
	if Input.is_key_pressed(KEY_E): input.y += 1.0
	if input == Vector3.ZERO:
		return
	_kill_tween()
	_sync_angles()
	var speed := move_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	# forward / sideways move flat along the floor whatever the pitch; Q / E go straight down / up
	var flat := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.z)
	if flat.length() > 0.0:
		global_position += flat.normalized() * speed * delta
	global_position.y += input.y * speed * delta


# ── Private ──────────────────────────────────────────────────
## React pause (Space): go to the "Reaction" preset, and back to where we were when it ends.
## Needs the "react_camera" setting and a preset labelled with "reaction".
func _on_react_pause_changed(paused: bool) -> void:
	if not AppState.get_setting("react_camera") or _reaction_index < 0:
		return
	if paused:
		_pre_react_transform = global_transform
		_pre_react_valid = true
		go_to_preset(_reaction_index)
	elif _pre_react_valid:
		_pre_react_valid = false
		_move_to(_pre_react_transform, true)


## Jumps or glides (move_time, sine ease) to a transform. Free-look or flying cancels a glide.
func _move_to(target: Transform3D, smooth: bool) -> void:
	_kill_tween()
	if not smooth:
		global_transform = target
		_sync_angles()
		return
	var from := global_transform
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(t: float) -> void:
		global_transform = from.interpolate_with(target, t), 0.0, 1.0, move_time)
	_tween.tween_callback(_sync_angles)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


## Reads yaw / pitch back from the current transform, so free-look starts from where a preset
## move left the camera.
func _sync_angles() -> void:
	var fwd := -global_transform.basis.z
	_yaw = atan2(-fwd.x, -fwd.z)
	_pitch = asin(clampf(fwd.y, -1.0, 1.0))


## Behind a wall (no camera marker can see the camera): clip everything between the camera and
## the last spot it was inside the room, so you keep seeing what you saw from in there, just
## from further back (a cutaway). Without such a spot, cut to the first surface met on the way
## out from the marker most straight ahead.
func _update_near() -> void:
	if _probes.is_empty() or not bool(AppState.get_setting("camera_see_through")) or not is_inside_tree():
		near = BASE_NEAR
		return
	var space := get_world_3d().direct_space_state
	var cam := global_position
	var fwd := -global_transform.basis.z
	var best_hit: Variant = null
	var best_dot := -2.0
	for probe in _probes:
		if probe.distance_to(cam) < 0.3:
			_inside_at(cam)
			return
		# a ray from the marker to the camera; back faces count, since the wall is seen from inside
		var q := PhysicsRayQueryParameters3D.create(probe, cam, WALL_LAYER)
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_inside_at(cam)            # something inside the room can see us: we're inside
			return
		var ahead := (probe - cam).normalized().dot(fwd)
		if ahead > best_dot:
			best_dot = ahead
			best_hit = hit["position"]
	# every marker is blocked: clip just past the wall (2 cm), or further if needed to reach back to
	# the last spot inside the room
	var d := ((best_hit as Vector3) - cam).dot(fwd) + 0.02
	if _last_inside != null:
		d = maxf(d, ((_last_inside as Vector3) - cam).dot(fwd) - 0.1)
	near = clampf(d, BASE_NEAR, far * 0.5) if d > BASE_NEAR else BASE_NEAR


func _inside_at(p: Vector3) -> void:
	_last_inside = p
	near = BASE_NEAR


## Random lens offset that fades out linearly over the shake's length.
func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	var k := _shake_strength * (_shake_left / _shake_total)
	h_offset = randf_range(-k, k)
	v_offset = randf_range(-k, k)
